// rvbl2_defines.vh
// Single source of truth for every opcode/funct/op-code literal used across
// the project. `include this in every module that switches on an opcode,
// alu_op, mult_op_o, crc_op_o, result_src, pc_src, or alu_src value.
//
// DO NOT hardcode any of these numbers directly in control_unit.v, alu.v,
// mult.v, crc.v, or anywhere else. If a value here is wrong, fixing it once
// here fixes it everywhere — hardcoding it in five places means five
// separate bugs when someone fixes only one.
//
// Source: HANDOFF_control_unit.md sections 5 and 6, verified against the
// Stage 2 Block Guide Tables 7–11.

`ifndef RVBL2_DEFINES_VH
`define RVBL2_DEFINES_VH

// ---------------------------------------------------------------------
// Opcodes (IR[6:0]) — handoff doc §5
// ---------------------------------------------------------------------
`define OPCODE_RTYPE   7'b0110011  // ALU R-type, MUL (Zmmul), CRC (Xicrc) — disambiguate via funct7
`define OPCODE_ITYPE   7'b0010011  // ALU I-type
`define OPCODE_LOAD    7'b0000011
`define OPCODE_STORE   7'b0100011
`define OPCODE_BRANCH  7'b1100011
`define OPCODE_JAL     7'b1101111
`define OPCODE_JALR    7'b1100111
`define OPCODE_LUI     7'b0110111
`define OPCODE_AUIPC   7'b0010111
`define OPCODE_SYSTEM  7'b1110011  // ECALL / EBREAK
`define OPCODE_FENCE   7'b0001111

// ---------------------------------------------------------------------
// funct12 disambiguation for OPCODE_SYSTEM — IR[31:20]
// ---------------------------------------------------------------------
// ECALL and EBREAK share opcode 1110011 AND funct3 000. The only field
// that separates them is IR[31:20]. funct7 (IR[31:25]) is NOT enough:
// both have funct7 = 0000000 and differ solely in IR[20].
//
// Cross-referenced against the RISC-V Unprivileged ISA spec, Chapter 2
// (Environment Call and Breakpoints) — not from memory.
//
//   ECALL  = 0x00000073  → IR[31:20] = 12'h000
//   EBREAK = 0x00100073  → IR[31:20] = 12'h001
//
// Both also require rs1 = 0, funct3 = 0, rd = 0. The CU checks funct3
// and funct12 only; rs1/rd are datapath address fields it never sees.
`define FUNCT12_ECALL  12'h000
`define FUNCT12_EBREAK 12'h001

// ---------------------------------------------------------------------
// funct7 disambiguation for OPCODE_RTYPE — handoff doc §5
// ---------------------------------------------------------------------
// WARNING: category selection is an ELSE, not a three-way equality
// check. SUB and SRA use funct7=0100000 — a fourth value that matches
// neither FUNCT7_MUL nor FUNCT7_CRC. Correct logic:
//     if      (funct7 == `FUNCT7_MUL) ...  // Zmmul
//     else if (funct7 == `FUNCT7_CRC) ...  // Xicrc
//     else                             ...  // R-type ALU (covers
//                                            // 0000000 AND 0100000 AND
//                                            // anything else)
`define FUNCT7_MUL     7'b0000001  // Zmmul — exact match required
`define FUNCT7_CRC     7'b1000000  // Xicrc — exact match required
// No FUNCT7_ALU constant on purpose — ALU is "else", never an equality
// target.

// ---------------------------------------------------------------------
// alu_op — Table 9. Requires real decode (funct3 + funct7[5]), NOT a
// passthrough — RV32I's standard funct3 numbering doesn't match these.
// ---------------------------------------------------------------------
`define ALU_PASS_B     4'h0
`define ALU_ADD        4'h1
`define ALU_SUB        4'h2
`define ALU_AND        4'h3
`define ALU_OR         4'h4
`define ALU_XOR        4'h5
`define ALU_SLL        4'h6
`define ALU_SRL        4'h7
`define ALU_MRS        4'h8  // arithmetic shift right (SRA)
`define ALU_SLT        4'h9
`define ALU_SLTU       4'hA

// ---------------------------------------------------------------------
// mult_op_o — Table 10. DIRECT PASSTHROUGH of funct3 (zero-extended).
// mult_op_o = {2'b00, funct3}. Do not build a lookup table for this.
// Port width decided 4 bits (matches alu_op_o) — handoff §7 item 7.
// ---------------------------------------------------------------------
`define MULT_MUL       4'h0
`define MULT_MULH      4'h1
`define MULT_MULHSU    4'h2
`define MULT_MULHU     4'h3

// ---------------------------------------------------------------------
// crc_op_o — Table 11. DIRECT PASSTHROUGH of funct3 (zero-extended).
// crc_op_o = {2'b00, funct3}. Do not build a lookup table for this.
// Port width decided 4 bits (matches alu_op_o) — handoff §7 item 7.
// ---------------------------------------------------------------------
`define CRC_CRCB       4'h0
`define CRC_CRCH       4'h1
`define CRC_CRCW       4'h2

// ---------------------------------------------------------------------
// Internal control signals — invented by us, NOT in the guide.
// See HANDOFF_control_unit.md §3 for full rationale.
// ---------------------------------------------------------------------
`define RESULT_SRC_ALU   3'b000
`define RESULT_SRC_MUL   3'b001
`define RESULT_SRC_CRC   3'b010
`define RESULT_SRC_MEM   3'b011
`define RESULT_SRC_PC4   3'b100

`define PC_SRC_PLUS4     2'b00
`define PC_SRC_TARGET    2'b01
`define PC_SRC_JALR      2'b10

`define ALU_SRC_A_RS1    1'b0
`define ALU_SRC_A_PC     1'b1

`define ALU_SRC_B_RS2    2'b00
`define ALU_SRC_B_IMM    2'b01
`define ALU_SRC_B_CONST4 2'b10

// ---------------------------------------------------------------------
// Memory map — guide Table 13
// ---------------------------------------------------------------------
`define PC_RESET_ADDR    32'h00400000  // IMEM base
`define IMEM_BASE        32'h00400000
`define DMEM_BASE        32'h10010000

// ---------------------------------------------------------------------
// op_size_o — decided (handoff §3, §7 item 9). [2:1]=size, [0]=sign.
// Sign bit is don't-care for stores (stores never extend).
// ---------------------------------------------------------------------
`define OP_SIZE_BYTE_S   3'b000  // lb / sb
`define OP_SIZE_BYTE_U   3'b001  // lbu
`define OP_SIZE_HALF_S   3'b010  // lh / sh
`define OP_SIZE_HALF_U   3'b011  // lhu
`define OP_SIZE_WORD     3'b100  // lw / sw

// ---------------------------------------------------------------------
// imm_sel_o — decided (handoff §3, §7 item 10). Fully internal
// invention, no external spec to check against.
// ---------------------------------------------------------------------
`define IMM_SEL_I        3'b000  // I-type ALU, JALR, loads
`define IMM_SEL_S        3'b001  // stores
`define IMM_SEL_B        3'b010  // branches
`define IMM_SEL_U        3'b011  // LUI, AUIPC
`define IMM_SEL_J        3'b100  // JAL

// ---------------------------------------------------------------------
// STILL OPEN — do not invent values for these, ask first.
// See HANDOFF_control_unit.md §8.
// ---------------------------------------------------------------------
// Illegal-opcode handling policy — undecided.
// ECALL behavior — partially resolved 2026-08-25: ECALL now raises a
//   sticky halt_o status flag (see control_unit.v). Execution semantics
//   are unchanged (still a no-op, PC still advances). What remains open
//   is whether the validation firmware expects the core to actually
//   STOP on ECALL rather than just flag it — that needs the firmware.
// x0 write protection — belongs in regfile, not here; not FSM-blocking.

`endif // RVBL2_DEFINES_VH
