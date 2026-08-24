/* crc_test.S — Xicrc validation vectors, supplied by the organisers.
 *
 * Three independent chains over the same 8 data bytes
 * (12 34 56 78 90 AB CD EF), fed 8 / 16 / 32 bits at a time.
 * All three must produce 0x1E82.
 *
 * Confirms: CRC-16/CCITT-FALSE, poly 0x1021, init 0xFFFF, no input or
 * output reflection, final XOR 0x0000, rs1 = data, rs2 = seed.
 * Verified against a reference implementation — all three chains give
 * 0x1E82. See docs/DATAPATH_BUILD_PLAN.md.
 *
 * Note the operand order in the assembly: `crcb s0, s1, s0` is
 * rd=s0, rs1=s1 (data), rs2=s0 (seed) — the running CRC is threaded
 * through rs2, not rs1. This is the reverse of the more common
 * convention and is easy to wire backwards.
 */

_rvbl2_crc_test:
    /* Expected result */
    li a7, 0x1E82

    /* CRC16 (8 bits) */
    li s0, 0xFFFF
    li s1, 0x12
    li s2, 0x34
    li s3, 0x56
    li s4, 0x78
    li s5, 0x90
    li s6, 0xAB
    li s7, 0xCD
    li s8, 0xEF
    crcb s0, s1, s0
    crcb s0, s2, s0
    crcb s0, s3, s0
    crcb s0, s4, s0
    crcb s0, s5, s0
    crcb s0, s6, s0
    crcb s0, s7, s0
    crcb s0, s8, s0

    /* If not equal, go to error handler */
    bne s0, a7, _error

    /* CRC16 (16 bits) */
    li t0, 0xFFFF
    li t1, 0x1234
    li t2, 0x5678
    li t3, 0x90AB
    li t4, 0xCDEF
    crch t0, t1, t0
    crch t0, t2, t0
    crch t0, t3, t0
    crch t0, t4, t0

    /* If not equal, go to error handler */
    bne t0, a7, _error

    /* CRC16 (32 bits) */
    li a0, 0xFFFF
    li a1, 0x12345678
    li a2, 0x90ABCDEF
    crcw a0, a1, a0
    crcw a0, a2, a0

    /* If not equal, go to error handler */
    bne a0, a7, _error

    ret
