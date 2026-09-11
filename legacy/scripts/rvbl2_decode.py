#!/usr/bin/env python3
"""rvbl2_decode.py -- independent RV32I(+Zmmul/Xicrc) decoder for the
ChampionCHIP RVBL-2 core, used to round-trip verify everything
scripts/rvbl2_asm.py encodes.

Deliberately a SEPARATE bitfield-extraction code path from rvbl2_asm.py's
encoder -- an assembler that decodes its own output by re-running its own
encoder backwards would validate its own arithmetic, not catch a shared
mistake. This file re-derives every field independently from the RV32I
layouts.

For branch/jal words it also resolves the ABSOLUTE target address
(addr + immediate) so a caller can check the target lands on the intended
label -- a stronger check than confirming the mnemonic text alone, since
it catches a label mis-resolution that happens to still print correctly.

Usage as a library:

    from rvbl2_decode import decode
    text, target = decode(word, addr)   # target is None for non-branch/jal

Usage as a CLI:

    python rvbl2_decode.py firmware/validation.hex [base_addr_hex]
"""

import sys

def u32(x):
    return x & 0xFFFFFFFF

def sext(value, bits):
    mask = 1 << (bits - 1)
    value &= (1 << bits) - 1
    return (value ^ mask) - mask

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

ALU_F3_ADD_SUB = {(0b000, 0): 'add', (0b000, 1): 'sub',
                  (0b101, 0): 'srl', (0b101, 1): 'sra'}
ALU_F3_PLAIN = {0b001: 'sll', 0b010: 'slt', 0b011: 'sltu',
                0b100: 'xor', 0b110: 'or', 0b111: 'and'}
ITYPE_F3_SHIFT = {(0b001, 0): 'slli', (0b101, 0): 'srli', (0b101, 1): 'srai'}
ITYPE_F3_PLAIN = {0b000: 'addi', 0b010: 'slti', 0b011: 'sltiu',
                  0b100: 'xori', 0b110: 'ori', 0b111: 'andi'}
LOAD_F3 = {0b000: 'lb', 0b001: 'lh', 0b010: 'lw', 0b100: 'lbu', 0b101: 'lhu'}
STORE_F3 = {0b000: 'sb', 0b001: 'sh', 0b010: 'sw'}
BRANCH_F3 = {0b000: 'beq', 0b001: 'bne', 0b100: 'blt', 0b101: 'bge',
             0b110: 'bltu', 0b111: 'bgeu'}
MULT_F3 = {0b000: 'mul', 0b001: 'mulh', 0b010: 'mulhsu', 0b011: 'mulhu'}
CRC_F3  = {0b000: 'crcb', 0b001: 'crch', 0b010: 'crcw'}


def decode(word, addr=0):
    """Returns (text, target_addr_or_None)."""
    word = u32(word)
    opcode = word & 0x7F
    rd     = (word >> 7) & 0x1F
    funct3 = (word >> 12) & 0x7
    rs1    = (word >> 15) & 0x1F
    rs2    = (word >> 20) & 0x1F
    funct7 = (word >> 25) & 0x7F
    bit30  = (word >> 30) & 1

    if opcode == OPCODE_RTYPE:
        if funct7 == FUNCT7_MUL and funct3 in MULT_F3:
            return f"{MULT_F3[funct3]} x{rd},x{rs1},x{rs2}", None
        if funct7 == FUNCT7_CRC and funct3 in CRC_F3:
            return f"{CRC_F3[funct3]} x{rd},x{rs1},x{rs2}", None
        key = (funct3, funct7 >> 5 & 1)
        if key in ALU_F3_ADD_SUB:
            return f"{ALU_F3_ADD_SUB[key]} x{rd},x{rs1},x{rs2}", None
        if funct3 in ALU_F3_PLAIN:
            return f"{ALU_F3_PLAIN[funct3]} x{rd},x{rs1},x{rs2}", None
        return f"<rtype? funct7={funct7:07b} funct3={funct3:03b}>", None

    if opcode == OPCODE_ITYPE:
        imm = sext((word >> 20) & 0xFFF, 12)
        shamt = rs2  # bits [24:20], same position
        key = (funct3, bit30)
        if key in ITYPE_F3_SHIFT:
            return f"{ITYPE_F3_SHIFT[key]} x{rd},x{rs1},{shamt}", None
        if funct3 in ITYPE_F3_PLAIN:
            return f"{ITYPE_F3_PLAIN[funct3]} x{rd},x{rs1},{imm}", None
        return f"<itype? funct3={funct3:03b}>", None

    if opcode == OPCODE_LOAD:
        imm = sext((word >> 20) & 0xFFF, 12)
        mn = LOAD_F3.get(funct3, f"<load funct3={funct3:03b}>")
        return f"{mn} x{rd},{imm}(x{rs1})", None

    if opcode == OPCODE_STORE:
        imm = sext(((word >> 25) << 5) | ((word >> 7) & 0x1F), 12)
        mn = STORE_F3.get(funct3, f"<store funct3={funct3:03b}>")
        return f"{mn} x{rs2},{imm}(x{rs1})", None

    if opcode == OPCODE_LUI:
        imm20 = (word >> 12) & 0xFFFFF
        return f"lui x{rd},0x{imm20:x}", None

    if opcode == OPCODE_AUIPC:
        imm20 = (word >> 12) & 0xFFFFF
        return f"auipc x{rd},0x{imm20:x}", None

    if opcode == OPCODE_BRANCH:
        bit12 = (word >> 31) & 1
        bit11 = (word >> 7) & 1
        bits10_5 = (word >> 25) & 0x3F
        bits4_1 = (word >> 8) & 0xF
        imm = sext((bit12 << 12) | (bit11 << 11) | (bits10_5 << 5) | (bits4_1 << 1), 13)
        mn = BRANCH_F3.get(funct3, f"<branch funct3={funct3:03b}>")
        return f"{mn} x{rs1},x{rs2},{imm:+d}", addr + imm

    if opcode == OPCODE_JAL:
        bit20 = (word >> 31) & 1
        bits19_12 = (word >> 12) & 0xFF
        bit11 = (word >> 20) & 1
        bits10_1 = (word >> 21) & 0x3FF
        imm = sext((bit20 << 20) | (bits19_12 << 12) | (bit11 << 11) | (bits10_1 << 1), 21)
        return f"jal x{rd},{imm:+d}", addr + imm

    if opcode == OPCODE_JALR:
        imm = sext((word >> 20) & 0xFFF, 12)
        return f"jalr x{rd},{imm}(x{rs1})", None

    if opcode == OPCODE_SYSTEM:
        imm12 = (word >> 20) & 0xFFF
        if imm12 == 0x000:
            return "ecall", None
        if imm12 == 0x001:
            return "ebreak", None
        return f"<system imm={imm12:03x}>", None

    return f"<unknown opcode={opcode:07b}>", None


def decode_hex_file(path, base_addr=0x00400000):
    with open(path) as f:
        words = [int(line.strip(), 16) for line in f if line.strip()]
    out = []
    for i, w in enumerate(words):
        addr = base_addr + 4 * i
        text, target = decode(w, addr)
        out.append((addr, w, text, target))
    return out


if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'firmware/validation.hex'
    base = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x00400000
    for addr, w, text, target in decode_hex_file(path, base):
        tgt = f"  -> 0x{target:08x}" if target is not None else ""
        print(f"{addr:08x} {w:08x}  {text}{tgt}")
