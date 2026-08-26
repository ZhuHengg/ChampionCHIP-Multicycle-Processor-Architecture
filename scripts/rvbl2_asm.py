#!/usr/bin/env python3
"""rvbl2_asm.py -- hand-written two-pass RV32I(+Zmmul/Xicrc) assembler for
the ChampionCHIP RVBL-2 core.

Why this exists: no riscv32/64-unknown-elf-as or riscv-none-elf-as is
available in this project's environment (checked repeatedly across slices
7c/7d/7e/7f/7g). Every firmware .hex file in firmware/ was produced by a
script descended from this one. It is committed here (rather than left in
a session scratchpad) so those .hex files can be regenerated and audited
by anyone working on the repo -- see scripts/README.md.

Encodings are transcribed directly from the RV32I field layouts (R/I/S/B/
U/J-type) and cross-checked against:
  - rtl/pkg/rvbl2_defines.vh       (opcodes, FUNCT7_MUL/FUNCT7_CRC,
                                     MULT_*/CRC_* funct3 assignments)
  - rtl/control_unit.v lines ~498-511 (ALU funct3/funct7[5] decode table
                                     -- authoritative for this core, used
                                     in preference to guessing from the
                                     generic RV32I spec since it's what
                                     the RTL actually implements)
  - rtl/datapath/branch_comparator.v (branch funct3 values -- RV32I
                                     standard, not guide-defined)
Nothing here is invented from memory; every opcode/funct3/funct7 literal
traces to one of the above.

Usage as a library:

    from rvbl2_asm import Asm
    a = Asm(base_addr=0x00400000)
    a.li(1, 6)
    a.li(2, 7)
    a.r('mul', 3, 1, 2)
    a.label('loop')
    a.i('addi', 4, 4, -1)
    a.branch('bne', 4, 0, 'loop')
    a.ecall()
    words = a.assemble()          # -> list of (addr, word, text, comment)
    a.write_hex('out.hex')
    labels = a.label_addr          # name -> address, for the caller to
                                    # compute expected link-register values
"""

def u32(x):
    return x & 0xFFFFFFFF

def s32(x):
    x = u32(x)
    return x - (1 << 32) if x & 0x80000000 else x

# ---------------------------------------------------------------------
# Opcodes -- rtl/pkg/rvbl2_defines.vh
# ---------------------------------------------------------------------
OPCODE_RTYPE  = 0b0110011
OPCODE_ITYPE  = 0b0010011
OPCODE_LOAD   = 0b0000011
OPCODE_STORE  = 0b0100011
OPCODE_BRANCH = 0b1100011
OPCODE_JAL    = 0b1101111
OPCODE_JALR   = 0b1100111
OPCODE_LUI    = 0b0110111
OPCODE_AUIPC  = 0b0010111
OPCODE_SYSTEM = 0b1110011

FUNCT7_MUL = 0b0000001
FUNCT7_CRC = 0b1000000
FUNCT12_ECALL = 0x000

# rtl/control_unit.v's ALU funct3 decode table (lines ~498-511): funct3
# alone selects the operation; funct7[5] (R-type) / instruction bit 30
# (I-type shifts only) disambiguates ADD/SUB and SRL/SRA. This is the
# *authoritative* mapping for this core -- transcribed from the RTL, not
# assumed from the generic RV32I spec.
ALU_F3 = {
    'add': 0b000, 'sub': 0b000,
    'sll': 0b001,
    'slt': 0b010,
    'sltu': 0b011,
    'xor': 0b100,
    'srl': 0b101, 'sra': 0b101,
    'or': 0b110,
    'and': 0b111,
}
ITYPE_F3 = {
    'addi': 0b000,
    'slli': 0b001,
    'slti': 0b010,
    'sltiu': 0b011,
    'xori': 0b100,
    'srli': 0b101, 'srai': 0b101,
    'ori': 0b110,
    'andi': 0b111,
}
LOAD_F3 = {'lb': 0b000, 'lh': 0b001, 'lw': 0b010, 'lbu': 0b100, 'lhu': 0b101}
STORE_F3 = {'sb': 0b000, 'sh': 0b001, 'sw': 0b010}
# rtl/datapath/branch_comparator.v -- RV32I standard funct3, not a
# rvbl2_defines.vh macro (branch_comparator.v's own header explains why).
BRANCH_F3 = {'beq': 0b000, 'bne': 0b001, 'blt': 0b100, 'bge': 0b101,
             'bltu': 0b110, 'bgeu': 0b111}
MULT_F3 = {'mul': 0b000, 'mulh': 0b001, 'mulhsu': 0b010, 'mulhu': 0b011}
CRC_F3  = {'crcb': 0b000, 'crch': 0b001, 'crcw': 0b010}


class Asm:
    def __init__(self, base_addr=0x00400000):
        self.base_addr = base_addr
        self._items = []          # list of dicts, pre-expansion
        self.label_addr = {}      # filled by assemble()

    # -- raw item append -------------------------------------------------
    def _emit(self, kind, text, comment="", **fields):
        self._items.append(dict(kind=kind, text=text, comment=comment, **fields))

    def label(self, name):
        self._items.append(dict(kind='label', name=name))

    def comment(self, text):
        self._items.append(dict(kind='comment', text=text))

    # -- concrete instruction builders -----------------------------------
    def r(self, mn, rd, rs1, rs2, comment=""):
        assert mn in ALU_F3, mn
        funct3 = ALU_F3[mn]
        funct7 = 0b0100000 if mn in ('sub', 'sra') else 0b0000000
        self._emit('rtype', f"{mn} x{rd},x{rs1},x{rs2}", comment,
                   rd=rd, rs1=rs1, rs2=rs2, funct3=funct3, funct7=funct7,
                   opcode=OPCODE_RTYPE)

    def i(self, mn, rd, rs1, imm, comment=""):
        assert mn in ITYPE_F3, mn
        funct3 = ITYPE_F3[mn]
        if mn in ('slli', 'srli', 'srai'):
            assert 0 <= imm <= 31, f"shift amount out of range: {imm}"
            imm12 = imm | (0x400 if mn == 'srai' else 0)  # bit 10 of imm = bit 30 of instr
        else:
            assert -2048 <= imm <= 2047, f"I-type imm out of range: {imm} ({mn})"
            imm12 = imm & 0xFFF
        self._emit('itype', f"{mn} x{rd},x{rs1},{imm}", comment,
                   rd=rd, rs1=rs1, funct3=funct3, imm12=imm12,
                   opcode=OPCODE_ITYPE)

    def addi(self, rd, rs1, imm, comment=""):
        self.i('addi', rd, rs1, imm, comment)

    def load(self, mn, rd, imm, rs1, comment=""):
        assert mn in LOAD_F3, mn
        assert -2048 <= imm <= 2047, f"load imm out of range: {imm}"
        self._emit('itype', f"{mn} x{rd},{imm}(x{rs1})", comment,
                   rd=rd, rs1=rs1, funct3=LOAD_F3[mn], imm12=imm & 0xFFF,
                   opcode=OPCODE_LOAD)

    def store(self, mn, rs2, imm, rs1, comment=""):
        assert mn in STORE_F3, mn
        assert -2048 <= imm <= 2047, f"store imm out of range: {imm}"
        self._emit('stype', f"{mn} x{rs2},{imm}(x{rs1})", comment,
                   rs1=rs1, rs2=rs2, funct3=STORE_F3[mn], imm=imm,
                   opcode=OPCODE_STORE)

    def lui(self, rd, imm20, comment=""):
        assert 0 <= imm20 <= 0xFFFFF
        self._emit('utype', f"lui x{rd},0x{imm20:x}", comment,
                   rd=rd, imm20=imm20, opcode=OPCODE_LUI)

    def auipc(self, rd, imm20, comment=""):
        assert 0 <= imm20 <= 0xFFFFF
        self._emit('utype', f"auipc x{rd},0x{imm20:x}", comment,
                   rd=rd, imm20=imm20, opcode=OPCODE_AUIPC)

    def branch(self, mn, rs1, rs2, label, comment=""):
        assert mn in BRANCH_F3, mn
        self._emit('btype', f"{mn} x{rs1},x{rs2},{label}", comment,
                   rs1=rs1, rs2=rs2, funct3=BRANCH_F3[mn], label=label)

    def jal(self, rd, label, comment=""):
        self._emit('jtype', f"jal x{rd},{label}", comment, rd=rd, label=label)

    def jalr(self, rd, rs1, imm, comment=""):
        assert -2048 <= imm <= 2047
        self._emit('itype', f"jalr x{rd},{imm}(x{rs1})", comment,
                   rd=rd, rs1=rs1, funct3=0, imm12=imm & 0xFFF,
                   opcode=OPCODE_JALR)

    def ecall(self, comment=""):
        self._emit('itype', "ecall", comment,
                   rd=0, rs1=0, funct3=0, imm12=FUNCT12_ECALL,
                   opcode=OPCODE_SYSTEM)

    def mul(self, mn, rd, rs1, rs2, comment=""):
        assert mn in MULT_F3, mn
        self._emit('rtype', f"{mn} x{rd},x{rs1},x{rs2}", comment,
                   rd=rd, rs1=rs1, rs2=rs2, funct3=MULT_F3[mn],
                   funct7=FUNCT7_MUL, opcode=OPCODE_RTYPE)

    def crc(self, mn, rd, rs1, rs2, comment=""):
        assert mn in CRC_F3, mn
        self._emit('rtype', f"{mn} x{rd},x{rs1},x{rs2}", comment,
                   rd=rd, rs1=rs1, rs2=rs2, funct3=CRC_F3[mn],
                   funct7=FUNCT7_CRC, opcode=OPCODE_RTYPE)

    # -- pseudo-ops --------------------------------------------------------
    def li(self, rd, value, note=""):
        """Standard RISC-V li expansion: lui(upper20)+addi(lower12,signed),
        or a bare addi if the value fits in 12 signed bits. When the
        lower 12 bits' bit 11 is set, addi's sign extension requires the
        upper half to be incremented by 1 first -- flagged as ADJUSTED in
        the comment when it happens (classic off-by-0x1000 source)."""
        value = u32(value)
        if -2048 <= s32(value) <= 2047:
            self.addi(rd, 0, s32(value), comment=f"li x{rd},0x{value:08x} {note}")
            return False
        lower12 = value & 0xFFF
        adjusted = False
        if lower12 & 0x800:
            lower12_signed = lower12 - 0x1000
            upper20 = ((value - lower12_signed) >> 12) & 0xFFFFF
            adjusted = True
        else:
            lower12_signed = lower12
            upper20 = (value >> 12) & 0xFFFFF
        self.lui(rd, upper20,
                 comment=f"li x{rd},0x{value:08x} upper {note}" +
                         (" [ADJUSTED +1 for bit11]" if adjusted else ""))
        if lower12_signed != 0:
            self.addi(rd, rd, lower12_signed, comment=f"li x{rd},0x{value:08x} lower {note}")
        return adjusted

    def call(self, label, comment=""):
        """jal x1,label -- x1 is the link register (RV32I ra convention)."""
        self.jal(1, label, comment=comment or f"call {label}")

    def ret(self, comment=""):
        """jalr x0,0(x1) -- standard RV32I ret pseudo-op expansion."""
        self.jalr(0, 1, 0, comment=comment or "ret")

    def la(self, rd, label, comment=""):
        """Load the absolute address of `label` into rd -- lui+addi pair
        whose immediates are resolved against label_addr in pass 2 (same
        upper/lower split as li(), sourced from a label instead of a
        literal). Lets a program reference its own layout (e.g. an
        embedded data word, or a jalr target) without the caller needing
        to precompute addresses by hand."""
        self._emit('utype_la', f"la x{rd},{label} (upper)", comment, rd=rd, label=label)
        self._emit('itype_la', f"la x{rd},{label} (lower)", comment, rd=rd, rs1=rd, label=label)

    def word(self, value, comment=""):
        """Emit one raw 32-bit word, untouched -- for embedding literal
        data inside IMEM (guide §4.2: IMEM holds constants read back via
        ordinary loads). Never fetch this address as an instruction --
        jump over it."""
        self._emit('raw', f".word 0x{u32(value):08x}", comment, value=u32(value))

    # -- assembly (two passes) --------------------------------------------
    def assemble(self):
        # Pass 1: assign addresses to concrete instructions, record labels.
        concrete = []
        addr = self.base_addr
        for it in self._items:
            if it['kind'] == 'label':
                self.label_addr[it['name']] = addr
            elif it['kind'] == 'comment':
                continue
            else:
                it['addr'] = addr
                concrete.append(it)
                addr += 4

        # Pass 2: encode, resolving label-relative branch/jal immediates.
        out = []
        for idx, it in enumerate(concrete):
            k = it['kind']
            if k == 'rtype':
                word = (it['funct7'] << 25) | (it['rs2'] << 20) | (it['rs1'] << 15) | \
                       (it['funct3'] << 12) | (it['rd'] << 7) | it['opcode']
            elif k == 'itype':
                word = (it['imm12'] << 20) | (it['rs1'] << 15) | (it['funct3'] << 12) | \
                       (it['rd'] << 7) | it['opcode']
            elif k == 'stype':
                imm = it['imm']
                imm12 = imm & 0xFFF
                word = (((imm12 >> 5) & 0x7F) << 25) | (it['rs2'] << 20) | (it['rs1'] << 15) | \
                       (it['funct3'] << 12) | ((imm12 & 0x1F) << 7) | it['opcode']
            elif k == 'utype':
                word = (it['imm20'] << 12) | (it['rd'] << 7) | it['opcode']
            elif k == 'utype_la':
                target = u32(self.label_addr[it['label']])
                lower12 = target & 0xFFF
                if lower12 & 0x800:
                    lower12_signed = lower12 - 0x1000
                    upper20 = ((target - lower12_signed) >> 12) & 0xFFFFF
                else:
                    lower12_signed = lower12
                    upper20 = (target >> 12) & 0xFFFFF
                it['_lower12_signed'] = lower12_signed  # stashed for the paired itype_la
                word = (upper20 << 12) | (it['rd'] << 7) | OPCODE_LUI
                it['comment'] = (it['comment'] + f" [addr=0x{target:08x}]").strip()
            elif k == 'itype_la':
                # Paired with the immediately preceding utype_la for the
                # same label -- reuses its lower12_signed split.
                lower12_signed = concrete[idx - 1]['_lower12_signed']
                imm12 = lower12_signed & 0xFFF
                word = (imm12 << 20) | (it['rs1'] << 15) | (0 << 12) | (it['rd'] << 7) | OPCODE_ITYPE
            elif k == 'raw':
                word = it['value']
            elif k == 'btype':
                target = self.label_addr[it['label']]
                imm = target - it['addr']
                assert imm % 2 == 0 and -4096 <= imm <= 4094, f"branch out of range: {imm}"
                imm13 = imm & 0x1FFF
                bit12 = (imm13 >> 12) & 1
                bit11 = (imm13 >> 11) & 1
                bits10_5 = (imm13 >> 5) & 0x3F
                bits4_1 = (imm13 >> 1) & 0xF
                word = (bit12 << 31) | (bits10_5 << 25) | (it['rs2'] << 20) | (it['rs1'] << 15) | \
                       (it['funct3'] << 12) | (bits4_1 << 8) | (bit11 << 7) | OPCODE_BRANCH
                it['comment'] = (it['comment'] + f" [target=0x{target:08x}]").strip()
            elif k == 'jtype':
                target = self.label_addr[it['label']]
                imm = target - it['addr']
                assert imm % 2 == 0 and -1048576 <= imm <= 1048574, f"jal out of range: {imm}"
                imm21 = imm & 0x1FFFFF
                bit20 = (imm21 >> 20) & 1
                bits10_1 = (imm21 >> 1) & 0x3FF
                bit11 = (imm21 >> 11) & 1
                bits19_12 = (imm21 >> 12) & 0xFF
                word = (bit20 << 31) | (bits10_1 << 21) | (bit11 << 20) | (bits19_12 << 12) | \
                       (it['rd'] << 7) | OPCODE_JAL
                it['comment'] = (it['comment'] + f" [target=0x{target:08x}]").strip()
            else:
                raise ValueError(k)
            out.append((it['addr'], u32(word), it['text'], it['comment']))
        self.words = out
        return out

    def write_hex(self, path):
        with open(path, 'w') as f:
            for addr, word, text, comment in self.words:
                f.write(f"{word:08x}\n")


if __name__ == '__main__':
    # Smoke test: a trivial labeled loop, printed, not written anywhere.
    a = Asm(0x00400000)
    a.li(1, 3, "counter")
    a.label('loop')
    a.i('addi', 1, 1, -1)
    a.branch('bne', 1, 0, 'loop')
    a.ecall()
    a.label('spin')
    a.jal(0, 'spin')
    for addr, word, text, comment in a.assemble():
        print(f"{addr:08x} {word:08x}  {text:<20s} {comment}")
