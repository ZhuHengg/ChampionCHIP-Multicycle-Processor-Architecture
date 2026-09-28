/*
 * Grid-aware EV charging-station controller -- ChampionCHIP RVBL-2 Stage 3.
 * Spec: docs/STAGE3_STRATEGY.md SS7.3-7.8. Golden model:
 * chip-inventor/testbench/app/golden.py -- this firmware must match it exactly.
 *
 * Constraints (spec SS4): no .data/.bss/stack/DMEM (sp is never initialised,
 * physical DMEM is 32 bytes), so all state lives in registers. No ecall/ebreak
 * (they halt the core), no CSRs, no division. Leaf subroutines only.
 *
 * Register map:
 *   tp/x4  application state (0 IDLE 1 CONNECTED 2 CHARGING 3 GRID_HOLD 4 FAULT)
 *   s0     GPIO base      s1     UART base     s2  CRC chain seed
 *   s3     energy         s4     frames        s5  flags
 *   s6     consecutive bad frames              s7  hold count
 *   s8     restart delay  s9     frame byte index
 *   s10    apply_pins scratch (state before the pass)
 *   s11    apply_pins saved return address
 *   a4     running CRC of the frame payload   a5 V   a6 I   a7 F
 *   gp     CRC field of the frame being received
 *   t6     poll_uart saved return address (on_frame clobbers ra)
 *   t0-t5, a0-a3 scratch (never live across a jal)
 *
 * Clobbers, so a caller can tell what survives a call: set_state t1-t2/tp;
 * uart_tx_byte t0; send_record a0-a3/t3; enter_fault adds t4; on_frame adds t5.
 *
 * Calling convention (no stack): apply_pins saves ra in s11, enter_fault in
 * t4, send_record in t3. set_state and uart_tx_byte are leaves. Anything a
 * caller needs across a jal lives in s*, never a* or t*.
 */

    /* GPIO (spec SS4: base 0xF0000000, 1 = output) */
    .equ GPIO_BASE,        0xF0000000
    .equ GPIO_DATAOUT,     0x0
    .equ GPIO_DATAIN,      0x4
    .equ GPIO_DATADIR,     0x8
    .equ DATADIR_VALUE,    0xF0          /* P7-4 out, P3-0 in */

    /* UART (spec SS4: base 0xF1000000) */
    .equ UART_BASE,        0xF1000000
    .equ UART_TXDATA,      0x0
    .equ UART_RXDATA,      0x4
    .equ UART_CONTROL,     0x8
    .equ UART_TRANSMIT,    0x1
    .equ UART_RXDONE,      0x2
    .equ UART_TXDONE,      0x4

    /* Application states */
    .equ ST_IDLE,          0
    .equ ST_CONNECTED,     1
    .equ ST_CHARGING,      2
    .equ ST_GRID_HOLD,     3
    .equ ST_FAULT,         4

    /* DATAOUT per state (spec SS7.6) */
    .equ OUT_IDLE,         0x00
    .equ OUT_CONNECTED,    0x20
    .equ OUT_CHARGING,     0x30
    .equ OUT_GRID_HOLD,    0x60
    .equ OUT_FAULT,        0x80

    /* STATUS cause flags (spec SS7.6) */
    .equ F_ESTOP,          0x08
    .equ F_CP_ERROR,       0x10
    .equ F_OVERCURRENT,    0x20
    .equ F_CRC_LOST,       0x40
    .equ F_GRID_HOLD,      0x80

    .equ SAFETY_TRIP,      0x08          /* DATAIN bit 3 */
    .equ CRC_INIT,         0xFFFF

    /* Grid limits (spec SS7.6; placeholders, not grid-code values) */
    .equ F_LOW,            4950          /* 49.50 Hz */
    .equ V_SAG,            2070          /* 207.0 V */
    .equ I_MAX,            320           /* 32.0 A; over-current when I > I_MAX */
    .equ HOLD_BASE,        2             /* minimum healthy frames before restart */

/*
 * Xicrc (handoff SS7-8): opcode 0110011 = 0x33, funct7 1000000 = 0x40,
 * funct3 000 crcb / 001 crch / 010 crcw. rs1 = data, rs2 = seed, result in rd.
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
    li   s0, GPIO_BASE
    li   s1, UART_BASE
    li   t0, DATADIR_VALUE
    sw   t0, GPIO_DATADIR(s0)
    sw   zero, GPIO_DATAOUT(s0)
    mv   tp, zero                    /* state = IDLE */
    li   s2, CRC_INIT
    mv   s3, zero                    /* energy */
    mv   s4, zero                    /* frames */
    mv   s5, zero                    /* flags */
    mv   s6, zero                    /* consecutive bad */
    mv   s7, zero                    /* hold count */
    mv   s8, zero                    /* restart delay */
    mv   s9, zero                    /* frame byte index */

/*
 * Main loop: apply the pilot/safety rules until the state is stable, then
 * check for one received byte. Inputs are levels, polled continuously, so an
 * -i may arrive before or after any -t.
 */
main_loop:
    jal  ra, apply_pins
    jal  ra, poll_uart
    j    main_loop

/*
 * apply_pins -- re-apply the pilot/safety rules until the state stops
 * changing, so CP = C straight from IDLE walks IDLE -> CONNECTED -> CHARGING
 * in one pass (spec SS7.6).
 */
apply_pins:
    mv   s11, ra                     /* no stack: keep the return address here */
ap_again:
    lw   t0, GPIO_DATAIN(s0)
    andi a1, t0, 0x07                /* a1 = CP code */
    andi a2, t0, SAFETY_TRIP         /* a2 = safety trip */
    mv   s10, tp                     /* state before this pass (survives calls) */

    li   t0, ST_FAULT
    beq  tp, t0, ap_fault

    bnez a2, ap_estop                /* safety first, in every state but FAULT */
    li   t0, 4
    bge  a1, t0, ap_cp_error         /* CP >= 4: E, F, or invalid 6/7 */

    li   t0, ST_IDLE
    beq  tp, t0, ap_idle
    li   t0, ST_CONNECTED
    beq  tp, t0, ap_connected
    j    ap_session                  /* CHARGING or GRID_HOLD */

ap_fault:
    /* Latched: only safety clear AND CP = A releases it, and sends no record. */
    bnez a2, ap_done
    bnez a1, ap_done
    li   a0, ST_IDLE
    jal  ra, set_state
    j    ap_check

ap_estop:
    li   t0, F_ESTOP
    or   s5, s5, t0
    jal  ra, enter_fault
    j    ap_check

ap_cp_error:
    li   t0, F_CP_ERROR
    or   s5, s5, t0
    jal  ra, enter_fault
    j    ap_check

ap_idle:
    /* CP = B, C or D starts a session and clears the counters. */
    beqz a1, ap_done
    mv   s3, zero
    mv   s4, zero
    mv   s5, zero
    li   a0, ST_CONNECTED
    jal  ra, set_state
    j    ap_check

ap_connected:
    li   t0, 2
    beq  a1, t0, ap_conn_charge
    beqz a1, ap_unplug               /* CP = A ends the session */
    j    ap_done                     /* B or D: stay (D refused, no ventilation) */
ap_conn_charge:
    li   a0, ST_CHARGING
    jal  ra, set_state
    j    ap_check

ap_session:
    /* CHARGING or GRID_HOLD. */
    beqz a1, ap_unplug
    li   t0, 2
    beq  a1, t0, ap_done             /* still C: keep charging/holding */
    li   a0, ST_CONNECTED            /* B or D drops back to CONNECTED */
    jal  ra, set_state
    j    ap_check

ap_unplug:
    /* Outputs go safe before the record is sent (spec SS7.6). */
    li   a0, ST_IDLE
    jal  ra, set_state
    li   a0, ST_IDLE
    jal  ra, send_record
    j    ap_check

ap_check:
    bne  tp, s10, ap_again           /* state moved: re-apply the rules */
ap_done:
    mv   ra, s11
    ret

/*
 * enter_fault -- latch FAULT and send the record (spec SS7.6). Flags must
 * already be set by the caller.
 */
enter_fault:
    mv   t4, ra
    li   a0, ST_FAULT
    jal  ra, set_state
    li   a0, ST_FAULT
    jal  ra, send_record
    mv   ra, t4
    ret

/* set_state -- a0 = new state; writes tp and DATAOUT. */
set_state:
    mv   tp, a0
    li   t1, ST_IDLE
    beq  a0, t1, ss_idle
    li   t1, ST_CONNECTED
    beq  a0, t1, ss_connected
    li   t1, ST_CHARGING
    beq  a0, t1, ss_charging
    li   t1, ST_GRID_HOLD
    beq  a0, t1, ss_hold
    li   t2, OUT_FAULT
    j    ss_write
ss_idle:
    li   t2, OUT_IDLE
    j    ss_write
ss_connected:
    li   t2, OUT_CONNECTED
    j    ss_write
ss_charging:
    li   t2, OUT_CHARGING
    j    ss_write
ss_hold:
    li   t2, OUT_GRID_HOLD
ss_write:
    sw   t2, GPIO_DATAOUT(s0)
    ret

/*
 * send_record -- one 8-byte session record (spec SS7.5):
 *   ENERGY u32 LE | STATUS (state|flags) | FRAMES | CRC-16 over bytes 0-5.
 * a0 = the state being entered. Clobbers a0-a3, t0-t5.
 */
send_record:
    mv   t3, ra
    or   a1, a0, s5                  /* STATUS byte */
    li   a2, CRC_INIT                /* running CRC */

    srli a3, s3, 0                   /* byte 0: energy[7:0] */
    andi a0, a3, 0xFF
    crcb a2, a0, a2
    jal  ra, uart_tx_byte
    srli a3, s3, 8
    andi a0, a3, 0xFF
    crcb a2, a0, a2
    jal  ra, uart_tx_byte
    srli a3, s3, 16
    andi a0, a3, 0xFF
    crcb a2, a0, a2
    jal  ra, uart_tx_byte
    srli a3, s3, 24
    andi a0, a3, 0xFF
    crcb a2, a0, a2
    jal  ra, uart_tx_byte

    andi a0, a1, 0xFF                /* byte 4: STATUS */
    crcb a2, a0, a2
    jal  ra, uart_tx_byte
    andi a0, s4, 0xFF                /* byte 5: FRAMES */
    crcb a2, a0, a2
    jal  ra, uart_tx_byte

    andi a0, a2, 0xFF                /* bytes 6-7: CRC, little-endian */
    jal  ra, uart_tx_byte
    srli a0, a2, 8
    andi a0, a0, 0xFF
    jal  ra, uart_tx_byte

    mv   ra, t3
    ret

/* uart_tx_byte -- a0 = byte. Read-modify-write on CONTROL so RXDONE survives. */
uart_tx_byte:
tx_wait:
    lw   t0, UART_CONTROL(s1)
    andi t0, t0, UART_TXDONE
    beqz t0, tx_wait
    sw   a0, UART_TXDATA(s1)
    lw   t0, UART_CONTROL(s1)
    ori  t0, t0, UART_TRANSMIT
    sw   t0, UART_CONTROL(s1)
    ret

/*
 * poll_uart -- one non-blocking check for a received byte. Bytes are framed by
 * count from reset (spec SS7.6): no resync byte, the emulator always sends
 * whole frames. The payload CRC is folded in byte by byte as bytes arrive, so
 * the 8th byte only needs a compare -- that keeps end-of-frame work inside one
 * byte time (1740 cycles) even with no gap between frames.
 */
poll_uart:
    mv   t6, ra                      /* on_frame clobbers ra */
    lw   t0, UART_CONTROL(s1)
    andi t0, t0, UART_RXDONE
    beqz t0, pu_done
    sw   zero, UART_CONTROL(s1)      /* clear RXDONE before reading */
    lw   t1, UART_RXDATA(s1)
    andi t1, t1, 0xFF

    /* Bytes 0-5 are payload and feed the CRC; 6-7 are the CRC field. */
    li   t2, 6
    bge  s9, t2, pu_crc_field

    beqz s9, pu_seed                 /* byte 0 seeds from the chain */
    j    pu_fold
pu_seed:
    mv   a4, s2                      /* running CRC <- chain seed */
pu_fold:
    crcb a4, t1, a4

    /* Little-endian: V = bytes 0-1, I = 2-3, F = 4-5. */
    li   t2, 0
    beq  s9, t2, pu_v_lo
    li   t2, 1
    beq  s9, t2, pu_v_hi
    li   t2, 2
    beq  s9, t2, pu_i_lo
    li   t2, 3
    beq  s9, t2, pu_i_hi
    li   t2, 4
    beq  s9, t2, pu_f_lo
    j    pu_f_hi
pu_v_lo:
    mv   a5, t1
    j    pu_advance
pu_v_hi:
    slli t2, t1, 8
    or   a5, a5, t2
    j    pu_advance
pu_i_lo:
    mv   a6, t1
    j    pu_advance
pu_i_hi:
    slli t2, t1, 8
    or   a6, a6, t2
    j    pu_advance
pu_f_lo:
    mv   a7, t1
    j    pu_advance
pu_f_hi:
    slli t2, t1, 8
    or   a7, a7, t2
    j    pu_advance

pu_crc_field:
    li   t2, 6
    bne  s9, t2, pu_crc_hi
    mv   gp, t1                      /* CRC field low byte */
    j    pu_advance
pu_crc_hi:
    slli t2, t1, 8
    or   gp, gp, t2                  /* CRC field complete: run the rules */
    jal  ra, on_frame
    mv   s9, zero
    mv   ra, t6
    ret

pu_advance:
    addi s9, s9, 1
pu_done:
    mv   ra, t6
    ret

/*
 * on_frame -- frame rules 1-3 of spec SS7.6, on the 8th byte.
 *   1. valid = (running CRC == CRC field); seed <- CRC field, always.
 *   2. invalid -> bad + 1; at 2, outside FAULT -> FAULT with the CRC-lost flag.
 *   3. valid -> bad <- 0, then act per state.
 * The bad counter is updated in every state, including FAULT; only the FAULT
 * transition is skipped when already faulted (matching golden._on_frame).
 */
on_frame:
    mv   t5, ra
    mv   a2, zero                    /* a2 = valid */
    bne  a4, gp, of_seed
    li   a2, 1
of_seed:
    mv   s2, gp                      /* rule 1: chain advances either way */

    bnez a2, of_valid

    addi s6, s6, 1                   /* rule 2 */
    li   t0, 2
    blt  s6, t0, of_done
    li   t0, ST_FAULT
    beq  tp, t0, of_done             /* already faulted: no second record */
    li   t0, F_CRC_LOST
    or   s5, s5, t0
    jal  ra, enter_fault
    j    of_done

of_valid:
    mv   s6, zero                    /* rule 3 */
    li   t0, ST_CHARGING
    beq  tp, t0, of_charging
    li   t0, ST_GRID_HOLD
    beq  tp, t0, of_hold
    j    of_done                     /* other states: chain update only */

of_charging:
    li   t0, I_MAX
    bgt  a6, t0, of_overcurrent
    /* Grid health: F >= F_LOW and V >= V_SAG (spec SS7.6). */
    li   t0, F_LOW
    blt  a7, t0, of_grid_hold
    li   t0, V_SAG
    blt  a5, t0, of_grid_hold
    mul  t0, a5, a6
    add  s3, s3, t0                  /* energy wraps mod 2^32 naturally */
    li   t0, 255
    beq  s4, t0, of_done             /* FRAMES saturates */
    addi s4, s4, 1
    j    of_done

of_overcurrent:
    li   t0, F_OVERCURRENT
    or   s5, s5, t0
    jal  ra, enter_fault
    j    of_done

/*
 * Entering GRID_HOLD: wait HOLD_BASE + (hash & 7) healthy frames, where hash
 * is the CRC-16 of the four CHARGER_ID bytes seeded with THIS frame's CRC
 * field (spec SS7.6). Different chargers and different events therefore
 * restart on different frames, so a fleet does not rebound in lockstep.
 */
of_grid_hold:
    li   t0, F_GRID_HOLD
    or   s5, s5, t0
    li   t0, 0x01                    /* CHARGER_ID 0x4D590001 as bytes 01 00 59 4D */
    crcb t1, t0, gp
    li   t0, 0x00
    crcb t1, t0, t1
    li   t0, 0x59
    crcb t1, t0, t1
    li   t0, 0x4D
    crcb t1, t0, t1
    andi t1, t1, 7
    addi s8, t1, HOLD_BASE           /* restart delay */
    mv   s7, zero                    /* hold count */
    li   a0, ST_GRID_HOLD
    jal  ra, set_state
    j    of_done

of_hold:
    /* Healthy frame -> count up; at the delay, resume charging (this frame is
     * not billed). Unhealthy -> start the count again. Over-current is ignored
     * here because the contactor is already open. */
    li   t0, F_LOW
    blt  a7, t0, of_hold_reset
    li   t0, V_SAG
    blt  a5, t0, of_hold_reset
    addi s7, s7, 1
    blt  s7, s8, of_done
    li   a0, ST_CHARGING
    jal  ra, set_state
    j    of_done

of_hold_reset:
    mv   s7, zero
    j    of_done

of_done:
    mv   ra, t5
    ret
