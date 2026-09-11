#!/usr/bin/env python3
"""gen_validation_fw.py -- builds firmware/validation.hex (slice 7g), the
end-to-end self-checking validation program for the RVBL-2 core.

Structure: one flat program, no external test harness needed to interpret
the outcome. Every RV32I/Zmmul/Xicrc feature under test computes a value,
compares it against an expected constant, and branches to a shared
`finish` tail on any mismatch -- carrying a distinct FAIL_ID identifying
which check failed. The success path carries PASS_CODE instead. `finish`
stores that code to both x1 and a fixed DMEM word, then executes ECALL
and self-loops forever (`jal x0, 0`) so the core never runs off the end
of the program once halt_o has been raised (halt_o is sticky, not a stop
signal -- control_unit.v:191-234 -- the FSM keeps fetching).

Run this script to regenerate firmware/validation.hex:
    python scripts/gen_validation_fw.py

It also self-verifies the program with scripts/rvbl2_sim.py (an
independent functional model) before writing the .hex file, and prints
the exact predicted cycle count (from the handoff table) plus the check
registry table for transcription into tb/system/tb_top_system.v's
comments and assertions.
"""

import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

from rvbl2_asm import Asm, u32, s32
from rvbl2_sim import Sim, CYCLE_COST

DMEM_BASE = 0x10010000
IMEM_BASE = 0x00400000

FAIL_MARK = 0xFA110000
PASS_CODE = 0x0000C0DE
STATUS_OFFSET = 0x100   # DMEM_BASE + this = status word address

asm = Asm(base_addr=IMEM_BASE)

CHECKS = []            # (id, name) in emission order, for the report/testbench
_next_id = [1]

# Scratch register pool reused freely across non-CRC checks (nothing needs
# to persist across check boundaries except x2=DMEM_BASE, kept fixed).
RA, RB, RD = 3, 4, 13     # generic operand/result registers
RE, RF = 14, 15          # extra scratch (DMEM word presets, poison values)
RM = 30                  # branch/jump "marker" register
RL = 31                  # loop counter
R_TMPADDR1, R_TMPADDR2 = 25, 26
R_BASE = 27
R_LINK = 16              # holds jal/jalr's own link result for those checks
R_IMEMPTR = 16


def check(name, actual_reg, expected_value):
    """Compare actual_reg against a literal expected value; branch to
    `finish` with a distinct FAIL_ID on mismatch. Uses x9 as scratch for
    the expected-value load -- safe because every check() call happens
    outside the CRC subroutine call window, which re-initializes x9
    (=s1) itself before ever reading it."""
    cid = _next_id[0]
    _next_id[0] += 1
    CHECKS.append((cid, name))
    tmp = 9 if actual_reg != 9 else 3  # avoid a degenerate self-compare
    ok = f"ck{cid}_ok"
    asm.li(tmp, expected_value, note=f"expected for check {cid} ({name})")
    asm.branch('beq', actual_reg, tmp, ok, comment=f"check {cid}: {name}")
    asm.li(1, FAIL_MARK | cid, note=f"FAIL_ID check {cid} ({name})")
    asm.jal(0, 'finish')
    asm.label(ok)
    return cid


def check_reg(name, actual_reg, expected_reg):
    """Same as check(), but the expected value is already in a register
    (used for jal/jalr link-value checks, whose expected value is a
    label's own address -- see la())."""
    cid = _next_id[0]
    _next_id[0] += 1
    CHECKS.append((cid, name))
    ok = f"ck{cid}_ok"
    asm.branch('beq', actual_reg, expected_reg, ok, comment=f"check {cid}: {name}")
    asm.li(1, FAIL_MARK | cid, note=f"FAIL_ID check {cid} ({name})")
    asm.jal(0, 'finish')
    asm.label(ok)
    return cid


# ===========================================================================
# Setup
# ===========================================================================
asm.li(2, DMEM_BASE, "DMEM_BASE pointer (permanent)")

# ===========================================================================
# Group 1 -- R-type ALU: add, sub, and, or, xor, sll, srl, sra, slt, sltu
# ===========================================================================
asm.li(RA, 12); asm.li(RB, 5)
asm.r('add', RD, RA, RB); check('add 12+5', RD, 17)
asm.r('sub', RD, RA, RB); check('sub 12-5', RD, 7)
asm.r('and', RD, RA, RB); check('and 12&5', RD, 12 & 5)
asm.r('or',  RD, RA, RB); check('or 12|5',  RD, 12 | 5)
asm.r('xor', RD, RA, RB); check('xor 12^5', RD, 12 ^ 5)
asm.r('sll', RD, RA, RB); check('sll 12<<5', RD, (12 << 5) & 0xFFFFFFFF)

asm.li(RA, 0x80000000, "bit31 set -- srl/sra discriminator")
asm.li(RB, 4)
asm.r('srl', RD, RA, RB); check('srl 0x80000000>>4 (logical)', RD, 0x08000000)
asm.r('sra', RD, RA, RB); check('sra 0x80000000>>4 (arithmetic) -- TRAP if executes as srl', RD, 0xF8000000)

asm.li(RA, -1, "-1 -- slt/sltu discriminator")
asm.li(RB, 1)
asm.r('slt',  RD, RA, RB); check('slt -1<1 (signed true)', RD, 1)
asm.r('sltu', RD, RA, RB); check('sltu 0xFFFFFFFF<1 (unsigned false) -- disagrees with slt', RD, 0)

# ===========================================================================
# Group 2 -- I-type ALU: addi, andi, ori, xori, slli, srli, srai, slti, sltiu
# ===========================================================================
asm.li(RA, 10)
asm.i('addi', RD, RA, 5); check('addi 10+5', RD, 15)

asm.li(RA, 0xA)
asm.i('andi', RD, RA, 6); check('andi 0xA&6', RD, 0xA & 6)
asm.i('ori',  RD, RA, 6); check('ori 0xA|6',  RD, 0xA | 6)
asm.i('xori', RD, RA, 6); check('xori 0xA^6', RD, 0xA ^ 6)

asm.li(RA, 1)
asm.i('slli', RD, RA, 5); check('slli 1<<5', RD, 1 << 5)

asm.li(RA, 0x80000000, "bit31 set -- srli/srai discriminator")
asm.i('srli', RD, RA, 4); check('srli 0x80000000>>4 (logical)', RD, 0x08000000)
asm.i('srai', RD, RA, 4); check('srai 0x80000000>>4 (arithmetic) -- TRAP if executes as srli (instr bit 30, task warning)', RD, 0xF8000000)

asm.li(RA, -1, "-1 -- slti/sltiu discriminator")
asm.i('slti',  RD, RA, 1); check('slti -1<1 (signed true)', RD, 1)
asm.i('sltiu', RD, RA, 1); check('sltiu 0xFFFFFFFF<1 (unsigned false) -- disagrees with slti', RD, 0)

# ===========================================================================
# Group 3 -- loads (all 5 variants) and stores (all 3 widths), nonzero
# byte offsets, against DMEM. Table-12-style word (0xF4F3F2F1) plus two
# lane-write tests, all self-supplied via sw/sb/sh (no testbench backdoor
# available to a self-contained program).
# ===========================================================================
asm.li(RE, 0xF4F3F2F1, "Table-12-style word: bytes F1 F2 F3 F4 little-endian")
asm.store('sw', RE, 0x40, 2)
asm.load('lw', RD, 0x40, 2); check('lw @+0x40', RD, 0xF4F3F2F1)
asm.load('lb', RD, 0x40, 2); check('lb @+0x40 (sign-extend 0xF1)', RD, u32(s32(0xFFFFFFF1)))
asm.load('lbu', RD, 0x40, 2); check('lbu @+0x40', RD, 0x000000F1)
asm.load('lh', RD, 0x40, 2); check('lh @+0x40 (sign-extend 0xF2F1)', RD, u32(s32(0xFFFFF2F1)))
asm.load('lhu', RD, 0x40, 2); check('lhu @+0x40', RD, 0x0000F2F1)
asm.load('lb', RD, 0x42, 2, "nonzero byte offset within the word"); check('lb @+0x42 (sign-extend 0xF3)', RD, u32(s32(0xFFFFFFF3)))

asm.li(RE, 0xAABBCCDD, "sb lane1 preset word")
asm.store('sw', RE, 0x50, 2)
asm.li(RF, 0x77)
asm.store('sb', RF, 0x51, 2, "nonzero byte offset (lane 1)")
asm.load('lw', RD, 0x50, 2); check('sb lane1 readback', RD, 0xAABB77DD)

asm.li(RE, 0xAABBCCDD, "sh upper-half preset word")
asm.store('sw', RE, 0x60, 2)
asm.li(RF, 0x0345)
asm.store('sh', RF, 0x62, 2, "nonzero byte offset (upper half)")
asm.load('lw', RD, 0x60, 2); check('sh upper-half readback', RD, 0x0345CCDD)

# ===========================================================================
# Group 4 -- load from IMEM (guide §4.2): a literal data word embedded in
# the instruction stream, jumped over so it's never fetched as an
# instruction, read back with an ordinary lw.
# ===========================================================================
asm.jal(0, 'after_const', "skip over the embedded data word")
asm.label('const_word')
asm.word(0xCAFEF00D, "literal data word living inside IMEM")
asm.label('after_const')
asm.la(R_IMEMPTR, 'const_word')
asm.load('lw', RD, 0, R_IMEMPTR, "load from IMEM, not DMEM")
check('lw from IMEM', RD, 0xCAFEF00D)

# ===========================================================================
# Group 5 -- all six branches (beq/bne/blt/bge taken, bltu/bgeu
# not-taken -- blt/bltu and bge/bgeu share operand pairs that disagree,
# same discipline as slt/sltu above and 7d's blt/bltu pairing), plus a
# backward loop.
# ===========================================================================
asm.li(RA, 5); asm.li(RB, 5)
asm.li(RM, 0)
asm.branch('beq', RA, RB, 'beq_ok', comment="beq taken (5==5)")
asm.li(RM, 0xBAD1, "poison: only runs if beq wrongly NOT taken")
asm.label('beq_ok')
check('beq taken', RM, 0)

asm.li(RA, 5); asm.li(RB, 3)
asm.li(RM, 0)
asm.branch('bne', RA, RB, 'bne_ok', comment="bne taken (5!=3)")
asm.li(RM, 0xBAD2, "poison: only runs if bne wrongly NOT taken")
asm.label('bne_ok')
check('bne taken', RM, 0)

asm.li(RA, -1, "blt taken / bltu not-taken discriminator"); asm.li(RB, 1)
asm.li(RM, 0)
asm.branch('blt', RA, RB, 'blt_ok', comment="blt taken (-1<1 signed)")
asm.li(RM, 0xBAD3, "poison: only runs if blt wrongly NOT taken")
asm.label('blt_ok')
check('blt taken', RM, 0)

asm.branch('bltu', RA, RB, 'bltu_trap', comment="bltu should NOT be taken (0xFFFFFFFF<1 unsigned false) -- disagrees with blt")
asm.li(RM, 0)
asm.jal(0, 'bltu_after')
asm.label('bltu_trap')
asm.li(RM, 0xBAD4, "only reached if bltu wrongly taken")
asm.label('bltu_after')
check('bltu not-taken', RM, 0)

asm.li(RA, 1, "bge taken / bgeu not-taken discriminator"); asm.li(RB, -1)
asm.li(RM, 0)
asm.branch('bge', RA, RB, 'bge_ok', comment="bge taken (1>=-1 signed)")
asm.li(RM, 0xBAD5, "poison: only runs if bge wrongly NOT taken")
asm.label('bge_ok')
check('bge taken', RM, 0)

asm.branch('bgeu', RA, RB, 'bgeu_trap', comment="bgeu should NOT be taken (1>=0xFFFFFFFF unsigned false) -- disagrees with bge")
asm.li(RM, 0)
asm.jal(0, 'bgeu_after')
asm.label('bgeu_trap')
asm.li(RM, 0xBAD6, "only reached if bgeu wrongly taken")
asm.label('bgeu_after')
check('bgeu not-taken', RM, 0)

asm.li(RL, 3, "backward-loop counter")
asm.label('bwd_loop')
asm.i('addi', RL, RL, -1)
asm.branch('bne', RL, 0, 'bwd_loop', comment="genuine backward branch")
check('backward loop terminates at 0', RL, 0)

# ===========================================================================
# Group 6 -- jal / jalr, including link register value
# ===========================================================================
asm.li(RM, 0)
asm.jal(R_LINK, 'jal_target', comment="jal -- link should be addr(this)+4")
asm.label('jal_return_addr')
asm.li(RM, 0xBAD7, "poison: only runs if jal did not redirect PC")
asm.label('jal_target')
check('jal redirected PC', RM, 0)
asm.la(R_TMPADDR1, 'jal_return_addr')
check_reg('jal link value', R_LINK, R_TMPADDR1)

asm.la(R_BASE, 'jalr_target')
asm.li(RM, 0)
asm.jalr(R_LINK, R_BASE, 0, comment="jalr -- link should be addr(this)+4")
asm.label('jalr_return_addr')
asm.li(RM, 0xBAD8, "poison: only runs if jalr did not redirect PC")
asm.label('jalr_target')
check('jalr redirected PC', RM, 0)
asm.la(R_TMPADDR2, 'jalr_return_addr')
check_reg('jalr link value', R_LINK, R_TMPADDR2)

# ===========================================================================
# Group 7 -- lui / auipc
# ===========================================================================
asm.lui(RD, 0x12345)
check('lui 0x12345', RD, 0x12345000)

asm.label('auipc_here')
asm.auipc(RD, 0x1)
asm.la(RA, 'auipc_here')
asm.li(RB, 0x1000)
asm.r('add', RA, RA, RB)
check_reg('auipc addr+0x1000', RD, RA)

# ===========================================================================
# Group 8 -- all four Zmmul ops (golden values re-used from slice 7f's
# independently-verified vectors -- see tb/datapath/tb_mult.v)
# ===========================================================================
asm.li(RA, 0x80000000); asm.li(RB, 2)
asm.mul('mul', RD, RA, RB); check('mul 0x80000000*2 low', RD, 0x00000000)
asm.mul('mulh', RD, RA, RB); check('mulh 0x80000000*2 upper', RD, 0xFFFFFFFF)
asm.mul('mulhu', RD, RA, RB); check('mulhu 0x80000000*2 upper (disagrees with mulh)', RD, 0x00000001)
asm.li(RA, 0xFFFFFFFF); asm.li(RB, 1)
asm.mul('mulhsu', RD, RA, RB); check('mulhsu (-1 su 1)', RD, 0xFFFFFFFF)

# ===========================================================================
# Group 9 -- Xicrc, all three chains. firmware/crc_test.S's body,
# hand-assembled directly (organiser-supplied golden reference, not
# invented vectors) and called as a real subroutine (`call`/`ret` ==
# jal x1,label / jalr x0,0(x1) -- standard RV32I ra convention). Its three
# `bne ..., _error` guards are redirected to three distinct stub labels
# (crc_fail_b/h/w) instead of one shared handler, so a CRC failure
# identifies which chain broke.
#
# Register mapping is the standard RV32I calling convention (not
# invented): s0=x8 s1=x9 s2=x18 s3=x19 s4=x20 s5=x21 s6=x22 s7=x23 s8=x24
# t0=x5 t1=x6 t2=x7 t3=x28 t4=x29 a0=x10 a1=x11 a2=x12 a7=x17. These
# registers are treated as fully clobbered by the call (crc_test.S does
# not save/restore them) -- nothing outside this subroutine call uses
# them, before or after.
# ===========================================================================
S0,S1,S2,S3,S4,S5,S6,S7,S8 = 8,9,18,19,20,21,22,23,24
T0,T1,T2,T3,T4 = 5,6,7,28,29
A0,A1,A2,A7 = 10,11,12,17

asm.call('crc_test_start')
asm.jal(0, 'after_crc_test')

asm.label('crc_test_start')
asm.li(A7, 0x1E82, "expected result, all three chains")
# crcb chain: 8x8-bit, seed 0xFFFF -- li 0xFFFF needs lui+addi w/ bit11
# adjustment (0xFFF's bit 11 is set); li 0x12/34/56/78/90/AB/CD/EF all
# fit a bare addi (<=2047).
asm.li(S0, 0xFFFF, "crcb seed")
asm.li(S1, 0x12); asm.li(S2, 0x34); asm.li(S3, 0x56); asm.li(S4, 0x78)
asm.li(S5, 0x90); asm.li(S6, 0xAB); asm.li(S7, 0xCD); asm.li(S8, 0xEF)
asm.crc('crcb', S0, S1, S0); asm.crc('crcb', S0, S2, S0)
asm.crc('crcb', S0, S3, S0); asm.crc('crcb', S0, S4, S0)
asm.crc('crcb', S0, S5, S0); asm.crc('crcb', S0, S6, S0)
asm.crc('crcb', S0, S7, S0); asm.crc('crcb', S0, S8, S0)
asm.branch('bne', S0, A7, 'crc_fail_b')

# crch chain: 4x16-bit -- li 0xFFFF (adjusted), 0x1234 (no adjust, lower12
# 0x234<0x800), 0x5678/0x90AB/0xCDEF (adjustment depends on each value's
# own bit 11 -- handled automatically by li(), flagged in its comment).
asm.li(T0, 0xFFFF, "crch seed")
asm.li(T1, 0x1234); asm.li(T2, 0x5678); asm.li(T3, 0x90AB); asm.li(T4, 0xCDEF)
asm.crc('crch', T0, T1, T0); asm.crc('crch', T0, T2, T0)
asm.crc('crch', T0, T3, T0); asm.crc('crch', T0, T4, T0)
asm.branch('bne', T0, A7, 'crc_fail_h')

# crcw chain: 2x32-bit.
asm.li(A0, 0xFFFF, "crcw seed")
asm.li(A1, 0x12345678); asm.li(A2, 0x90ABCDEF)
asm.crc('crcw', A0, A1, A0); asm.crc('crcw', A0, A2, A0)
asm.branch('bne', A0, A7, 'crc_fail_w')
asm.ret()

asm.label('crc_fail_b')
asm.li(1, FAIL_MARK | 0xB0, note="crcb chain mismatch")
asm.jal(0, 'finish')
asm.label('crc_fail_h')
asm.li(1, FAIL_MARK | 0xB1, note="crch chain mismatch")
asm.jal(0, 'finish')
asm.label('crc_fail_w')
asm.li(1, FAIL_MARK | 0xB2, note="crcw chain mismatch")
asm.jal(0, 'finish')
CHECKS.append(('B0/B1/B2', 'crcb/crch/crcw chain (subroutine, guards its own three chains)'))

asm.label('after_crc_test')

# ===========================================================================
# Success path + shared tail
# ===========================================================================
asm.li(1, PASS_CODE, note="all checks passed")
asm.jal(0, 'finish')

asm.label('finish')
asm.store('sw', 1, STATUS_OFFSET, 2, "status word: PASS_CODE or FAIL_MARK|id")
asm.ecall()
asm.label('self_loop')
asm.jal(0, 'self_loop', comment="halt_o is sticky, not a stop signal -- FSM keeps fetching, so loop forever")


# ===========================================================================
# Assemble, self-verify, report.
# ===========================================================================
def main():
    words_full = asm.assemble()

    print(f"; {len(words_full)} words assembled")

    # ---- round-trip check (independent decoder) -----------------------
    from rvbl2_decode import decode as _decode
    mismatches = 0
    for addr, word, text, comment in words_full:
        dtext, target = _decode(word, addr)
        # .word entries are raw data, never meant to decode as an instruction
        if text.startswith('.word'):
            continue
        # la() expands to a real lui+addi pair -- the decoder correctly
        # reports those mnemonics, not the pseudo-op name 'la'. Checked
        # instead via the comment's [addr=...] tag (upper half) and via
        # the functional simulator actually using the resulting register
        # value end-to-end (jal/jalr link checks, IMEM load, auipc check).
        if text.startswith('la '):
            if '(upper)' in text:
                if dtext.split()[0] != 'lui':
                    print(f"MISMATCH @ {addr:08x}: la upper half did not decode as lui: {dtext!r}")
                    mismatches += 1
            else:
                if dtext.split()[0] != 'addi':
                    print(f"MISMATCH @ {addr:08x}: la lower half did not decode as addi: {dtext!r}")
                    mismatches += 1
            continue
        # normalize: decoder renders branch/jal targets as offsets, asm as
        # label names -- compare resolved target addresses instead when present
        if target is not None:
            # extract intended target from comment's "[target=0x...]" tag
            if '[target=' in comment:
                intended = int(comment.split('[target=')[1].split(']')[0], 16)
                if intended != target:
                    print(f"MISMATCH @ {addr:08x}: asm intended 0x{intended:08x}, decoder resolved 0x{target:08x}")
                    mismatches += 1
            continue
        mn_asm = text.split()[0]
        mn_dec = dtext.split()[0]
        if mn_asm != mn_dec:
            print(f"MISMATCH @ {addr:08x}: asm={text!r} decoder={dtext!r}")
            mismatches += 1
    print("ROUND-TRIP:", "ALL MATCH" if mismatches == 0 else f"{mismatches} MISMATCHES")
    assert mismatches == 0, "round-trip verification failed -- fix before writing .hex"

    # ---- write the .hex immediately after round-trip verification, BEFORE
    # the functional pass/fail check below -- so a deliberately-mutated
    # firmware (wrong expected constant, missing ECALL, etc.) still gets
    # written out for RTL testing instead of silently keeping the last
    # good file on disk if the simulator flags it as failing.
    out_path = os.path.join(os.path.dirname(__file__), '..', 'firmware', 'validation.hex')
    asm.write_hex(out_path)
    print(f"\nwrote {out_path}, {len(words_full)} words, "
          f"last addr = 0x{words_full[-1][0]:08x}")

    # ---- functional self-check (independent simulator) -----------------
    sim_failed = False
    words = [w for _, w, _, _ in words_full]
    sim = Sim(words, IMEM_BASE)
    sim.run()
    status_addr = DMEM_BASE + STATUS_OFFSET
    status_dmem = sim._dmem_read_word(status_addr)
    x1 = sim.regs[1]
    print(f"\nSIMULATION: x1=0x{x1:08x}  dmem[status]=0x{status_dmem:08x}  "
          f"regs[0]={sim.regs[0]}  cycles={sim.cycles}  instrs_executed={len(sim.trace)}")
    if x1 == PASS_CODE and status_dmem == PASS_CODE:
        print("SIMULATION RESULT: PASS_CODE reached on both x1 and DMEM status word.")
    else:
        print(f"SIMULATION RESULT: FAILED -- x1=0x{x1:08x} (expected 0x{PASS_CODE:08x}) -- "
              f".hex was still written above (e.g. for deliberate mutation testing)")
        sim_failed = True
    assert sim.regs[0] == 0, "x0 corrupted in simulation (should be structurally impossible)"

    # ---- predicted cycle count, by category ----------------------------
    from collections import Counter
    cat_counts = Counter(kind for _, _, kind in sim.trace)
    print("\nPredicted cycle count by category (handoff §Slices 1-6 table):")
    total = 0
    for kind, n in sorted(cat_counts.items()):
        cost = CYCLE_COST[kind]
        print(f"  {kind:10s} x{n:3d} instrs x {cost} cycles = {n*cost}")
        total += n * cost
    print(f"  {'TOTAL':10s}                    = {total} cycles")
    assert total == sim.cycles

    # ---- check registry (for the testbench's documentation/report) -----
    print(f"\n{len(CHECKS)} checks registered:")
    for cid, name in CHECKS:
        print(f"  [{cid}] {name}")

    print(f"PASS_CODE = 0x{PASS_CODE:08x}   FAIL_MARK = 0x{FAIL_MARK:08x}   "
          f"STATUS_ADDR = 0x{status_addr:08x}")
    print(f"PREDICTED_CYCLES = {total}")

    if sim_failed:
        sys.exit(1)


if __name__ == '__main__':
    main()
