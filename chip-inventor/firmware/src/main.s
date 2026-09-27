/*
 * Grid-aware EV charging-station controller -- ChampionCHIP RVBL-2 Stage 3.
 *
 * Application firmware for our multicycle RV32I + Zmmul + Xicrc core.
 * Spec: docs/STAGE3_STRATEGY.md SS7.3-7.8 (pin map, meter frame, session
 * record, application FSM, constants).
 *
 * Built with the organiser's Firmware-Builder (vendored in ../), so this file
 * drops into RVBL-Firmware-Builder/src/main.s unchanged.
 *
 * STATUS: Task 1 stub -- encoding smoke test only. The application FSM lands
 * in Tasks 5-7.
 *
 * Constraints this file must respect (spec SS4, handoff SS2):
 *   - No .data/.bss/stack/DMEM use: sp is never initialised and physical DMEM
 *     is 32 bytes. All state lives in registers.
 *   - No ecall/ebreak (they halt the core), no CSRs, no division.
 *   - Leaf subroutines only (jal ra / ret, never nested).
 *   - tp (x4) mirrors the application state code at all times; x4_dbg_o
 *     exposes it to the testbench.
 */

    /* ---- GPIO (spec SS4: base 0xF0000000, 1 = output) ---- */
    .equ GPIO_BASE,        0xF0000000
    .equ GPIO_DATAOUT,     0x0
    .equ GPIO_DATAIN,      0x4
    .equ GPIO_DATADIR,     0x8

    /* ---- UART (spec SS4: base 0xF1000000, 115200 8-N-1) ---- */
    .equ UART_BASE,        0xF1000000
    .equ UART_TXDATA,      0x0
    .equ UART_RXDATA,      0x4
    .equ UART_CONTROL,     0x8
    .equ UART_TRANSMIT,    0x1
    .equ UART_RXDONE,      0x2
    .equ UART_TXDONE,      0x4

/*
 * Xicrc custom instructions (handoff SS7-8, cross-checked against
 * docs/HANDOFF_control_unit.md lines 209-283):
 *   opcode 0110011 = 0x33, funct7 1000000 = 0x40,
 *   funct3 000 crcb / 001 crch / 010 crcw.
 * Operand roles: rs1 = data, rs2 = seed / running CRC, result in rd.
 * The stock assembler does not know these mnemonics, so encode with .insn.
 */
    .macro crcb rd, rs1, rs2
    .insn r 0x33, 0x0, 0x40, \rd, \rs1, \rs2
    .endm

    .macro crch rd, rs1, rs2
    .insn r 0x33, 0x1, 0x40, \rd, \rs1, \rs2
    .endm

    .macro crcw rd, rs1, rs2
    .insn r 0x33, 0x2, 0x40, \rd, \rs1, \rs2
    .endm

    .section .start, "ax"
    .global _start

_start:
    /* Task 1 encoding smoke test: these two words are checked in firmware.dmp
     * against the repo assembler (legacy/scripts/rvbl2_asm.py):
     *   crcb s0, s1, s0 -> 0x80848433
     *   mul  a0, a1, a2 -> 0x02c58533
     */
    crcb s0, s1, s0
    mul  a0, a1, a2

1:  j 1b
