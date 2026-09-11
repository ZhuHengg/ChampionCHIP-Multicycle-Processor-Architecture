#!/usr/bin/env python3
"""rvbl2_sim.py -- small reference functional simulator for the RVBL-2
instruction set (RV32I + Zmmul + Xicrc), used at firmware-authoring time
to verify a self-checking program's logic and derive the exact predicted
cycle count from the handoff doc's per-instruction-type table, BEFORE
ever touching iverilog.

This is a design-time verification tool, not part of the RTL or the
testbench's pass/fail authority -- its semantics are re-derived from the
same sources rvbl2_asm.py cites (rtl/control_unit.v's ALU decode table,
rtl/datapath/branch_comparator.v's funct3 table, rtl/datapath/lsu.v's
load-extension/store-positioning logic, rtl/datapath/mult.v/crc.v's
arithmetic), not copied from the RTL. Cross-check both independently
before trusting either exclusively.

Memory model: DMEM is a flat byte array indexed by (address - DMEM_BASE).
Valid as long as every DMEM access in the simulated program stays within
DMEM_BASE .. DMEM_BASE+DEPTH-1 (true for this project's firmware -- see
rtl/memory/dmem.v's header for the real hardware's index-aliasing
behavior, which coincides with this simple model for DMEM_BASE-relative
addresses because DMEM_BASE's own word address happens to have its low
IDX_W bits all zero).

Cycle costs (docs/HANDOFF_control_unit_ALL_STAGES.md §Slices 1-6, the
authoritative table -- NOT re-derived from guesswork):
    R-type ALU=4, I-type ALU=4, load=6, store=4, branch=3 (taken or not --
    it never reaches WRITE_BACK either way), JAL=4, JALR=4, LUI=4,
    AUIPC=4, MUL=4, CRC=4, ECALL/EBREAK/FENCE=3.
"""

from rvbl2_decode import u32, sext, OPCODE_RTYPE, OPCODE_ITYPE, \
    OPCODE_LOAD, OPCODE_STORE, OPCODE_BRANCH, OPCODE_JAL, OPCODE_JALR, \
    OPCODE_LUI, OPCODE_AUIPC, OPCODE_SYSTEM, FUNCT7_MUL, FUNCT7_CRC

DMEM_BASE = 0x10010000
DMEM_DEPTH = 2048 * 4  # bytes, matches dmem.v's default DEPTH_WORDS=2048

CYCLE_COST = {
    'rtype': 4, 'itype_alu': 4, 'load': 6, 'store': 4, 'branch': 3,
    'jal': 4, 'jalr': 4, 'lui': 4, 'auipc': 4, 'mul': 4, 'crc': 4,
    'ecall': 3,
}


def s32(x):
    x = u32(x)
    return x - (1 << 32) if x & 0x80000000 else x


class Sim:
    def __init__(self, words, base_addr):
        self.mem = {addr: w for addr, w in
                     zip(range(base_addr, base_addr + 4 * len(words), 4), words)}
        self.base_addr = base_addr
        self.regs = [0] * 32
        self.dmem = bytearray(DMEM_DEPTH)
        self.pc = base_addr
        self.cycles = 0
        self.trace = []
        self.halted = False

    def _reg(self, i):
        return 0 if i == 0 else self.regs[i]

    def _setreg(self, i, v):
        if i != 0:
            self.regs[i] = u32(v)

    def _dmem_read_word(self, addr):
        off = addr - DMEM_BASE
        b = self.dmem[off:off + 4]
        return b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)

    def _mem_read_word(self, addr):
        """Routes to IMEM or DMEM by address range, mirroring
        rtl/memory/address_decoder.v -- a plain `lw` can target either
        (guide §4.2: IMEM also holds constants read via ordinary loads)."""
        if DMEM_BASE <= addr < DMEM_BASE + DMEM_DEPTH:
            return self._dmem_read_word(addr)
        return self.mem.get(addr, 0)  # IMEM: word actually emitted, or 0

    def _dmem_write_bytes(self, addr, byte_sel, size_bits, value):
        # size_bits: 0=byte,1=half,2=word (matches op_size_o[2:1] coding)
        off = (addr - DMEM_BASE) & ~0x3  # word-aligned base of the lane
        if size_bits == 2:
            for k in range(4):
                self.dmem[off + k] = (value >> (8 * k)) & 0xFF
        elif size_bits == 1:
            base = off + (2 if byte_sel & 0b10 else 0)
            self.dmem[base] = value & 0xFF
            self.dmem[base + 1] = (value >> 8) & 0xFF
        else:
            self.dmem[off + byte_sel] = value & 0xFF

    def run(self, max_steps=200000):
        while not self.halted:
            if len(self.trace) > max_steps:
                raise RuntimeError(f"simulator exceeded {max_steps} steps -- runaway PC? pc=0x{self.pc:08x}")
            word = self.mem.get(self.pc)
            if word is None:
                raise RuntimeError(f"fetch from unmapped address 0x{self.pc:08x} (ran off the program)")
            self._step(word)

    def _step(self, word):
        opcode = word & 0x7F
        rd = (word >> 7) & 0x1F
        funct3 = (word >> 12) & 0x7
        rs1 = (word >> 15) & 0x1F
        rs2 = (word >> 20) & 0x1F
        funct7 = (word >> 25) & 0x7F
        bit30 = (word >> 30) & 1
        pc = self.pc
        next_pc = pc + 4
        kind = None

        if opcode == OPCODE_RTYPE:
            a, b = self._reg(rs1), self._reg(rs2)
            if funct7 == FUNCT7_MUL:
                kind = 'mul'
                self._setreg(rd, self._mul(funct3, a, b))
            elif funct7 == FUNCT7_CRC:
                kind = 'crc'
                self._setreg(rd, self._crc(funct3, a, b))
            else:
                kind = 'rtype'
                self._setreg(rd, self._alu(funct3, bit30 if funct7 else 0, a, b, is_itype=False))

        elif opcode == OPCODE_ITYPE:
            imm = sext((word >> 20) & 0xFFF, 12)
            a = self._reg(rs1)
            kind = 'itype_alu'
            if funct3 in (0b001, 0b101):  # slli/srli/srai: imm[4:0]=shamt
                self._setreg(rd, self._alu(funct3, bit30, a, imm & 0x1F, is_itype=True))
            else:
                self._setreg(rd, self._alu(funct3, 0, a, imm, is_itype=True))

        elif opcode == OPCODE_LOAD:
            kind = 'load'
            imm = sext((word >> 20) & 0xFFF, 12)
            addr = u32(self._reg(rs1) + imm)
            byte_sel = addr & 0x3
            wordval = self._mem_read_word(addr & ~0x3)
            byte = (wordval >> (8 * byte_sel)) & 0xFF
            half = (wordval >> (16 if byte_sel & 0b10 else 0)) & 0xFFFF
            if funct3 == 0b000:   val = sext(byte, 8)          # lb
            elif funct3 == 0b100: val = byte                    # lbu
            elif funct3 == 0b001: val = sext(half, 16)          # lh
            elif funct3 == 0b101: val = half                    # lhu
            elif funct3 == 0b010: val = wordval                 # lw
            else: raise ValueError(f"bad load funct3 {funct3:03b}")
            self._setreg(rd, val)

        elif opcode == OPCODE_STORE:
            kind = 'store'
            imm = sext(((word >> 25) << 5) | ((word >> 7) & 0x1F), 12)
            addr = u32(self._reg(rs1) + imm)
            byte_sel = addr & 0x3
            data = self._reg(rs2)
            if funct3 == 0b000:   self._dmem_write_bytes(addr, byte_sel, 0, data)   # sb
            elif funct3 == 0b001: self._dmem_write_bytes(addr, byte_sel, 1, data)   # sh
            elif funct3 == 0b010: self._dmem_write_bytes(addr, byte_sel, 2, data)   # sw
            else: raise ValueError(f"bad store funct3 {funct3:03b}")

        elif opcode == OPCODE_LUI:
            kind = 'lui'
            imm20 = (word >> 12) & 0xFFFFF
            self._setreg(rd, u32(imm20 << 12))

        elif opcode == OPCODE_AUIPC:
            kind = 'auipc'
            imm20 = (word >> 12) & 0xFFFFF
            self._setreg(rd, u32(pc + (imm20 << 12)))

        elif opcode == OPCODE_BRANCH:
            kind = 'branch'
            bit12 = (word >> 31) & 1
            bit11 = (word >> 7) & 1
            bits10_5 = (word >> 25) & 0x3F
            bits4_1 = (word >> 8) & 0xF
            imm = sext((bit12 << 12) | (bit11 << 11) | (bits10_5 << 5) | (bits4_1 << 1), 13)
            a, b = self._reg(rs1), self._reg(rs2)
            taken = {0b000: a == b, 0b001: a != b,
                     0b100: s32(a) < s32(b), 0b101: s32(a) >= s32(b),
                     0b110: a < b, 0b111: a >= b}[funct3]
            if taken:
                next_pc = u32(pc + imm)

        elif opcode == OPCODE_JAL:
            kind = 'jal'
            bit20 = (word >> 31) & 1
            bits19_12 = (word >> 12) & 0xFF
            bit11 = (word >> 20) & 1
            bits10_1 = (word >> 21) & 0x3FF
            imm = sext((bit20 << 20) | (bits19_12 << 12) | (bit11 << 11) | (bits10_1 << 1), 21)
            self._setreg(rd, u32(pc + 4))
            next_pc = u32(pc + imm)

        elif opcode == OPCODE_JALR:
            kind = 'jalr'
            imm = sext((word >> 20) & 0xFFF, 12)
            target = u32(self._reg(rs1) + imm) & ~1
            self._setreg(rd, u32(pc + 4))
            next_pc = target

        elif opcode == OPCODE_SYSTEM:
            kind = 'ecall'
            self.halted = True  # stop the simulator right after ECALL retires

        else:
            raise RuntimeError(f"unknown opcode 0b{opcode:07b} at 0x{pc:08x} (word=0x{word:08x})")

        self.cycles += CYCLE_COST[kind]
        self.trace.append((pc, word, kind))
        self.pc = next_pc

    def _alu(self, funct3, sub_or_sra_bit, a, b, is_itype):
        a, b = u32(a), u32(b)
        if funct3 == 0b000:
            if (not is_itype) and sub_or_sra_bit:
                return u32(a - b)
            return u32(a + b)
        if funct3 == 0b001: return u32(a << (b & 0x1F))
        if funct3 == 0b010: return 1 if s32(a) < s32(b) else 0
        if funct3 == 0b011: return 1 if a < b else 0
        if funct3 == 0b100: return u32(a ^ b)
        if funct3 == 0b101:
            if sub_or_sra_bit:
                return u32(s32(a) >> (b & 0x1F))  # arithmetic (Python >> on negative is arithmetic)
            return u32(a >> (b & 0x1F))
        if funct3 == 0b110: return u32(a | b)
        if funct3 == 0b111: return u32(a & b)
        raise ValueError(funct3)

    def _mul(self, funct3, a, b):
        sa, sb, ua, ub = s32(a), s32(b), u32(a), u32(b)
        if funct3 == 0b000: return u32(sa * sb)
        if funct3 == 0b001: return u32((sa * sb) >> 32)
        if funct3 == 0b010: return u32((sa * ub) >> 32)
        if funct3 == 0b011: return u32((ua * ub) >> 32)
        raise ValueError(funct3)

    def _crc(self, funct3, a, b):
        nbits = {0b000: 8, 0b001: 16, 0b010: 32}[funct3]
        data = u32(a) & ((1 << nbits) - 1)
        crc = u32(b) & 0xFFFF
        for i in range(nbits - 1, -1, -1):
            bit_in = (data >> i) & 1
            msb = (crc >> 15) & 1
            crc = (crc << 1) & 0xFFFF
            if msb ^ bit_in:
                crc ^= 0x1021
        return crc
