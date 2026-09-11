// rvbl2_defines.vh — shared opcode/funct/op-code literals, include everywhere

`ifndef RVBL2_DEFINES_VH
`define RVBL2_DEFINES_VH

// Opcodes (IR[6:0])
`define OPCODE_RTYPE   7'b0110011  // ALU R-type, MUL, CRC — disambiguate via funct7
`define OPCODE_ITYPE   7'b0010011
`define OPCODE_LOAD    7'b0000011
`define OPCODE_STORE   7'b0100011
`define OPCODE_BRANCH  7'b1100011
`define OPCODE_JAL     7'b1101111
`define OPCODE_JALR    7'b1100111
`define OPCODE_LUI     7'b0110111
`define OPCODE_AUIPC   7'b0010111
`define OPCODE_SYSTEM  7'b1110011  // ECALL / EBREAK
`define OPCODE_FENCE   7'b0001111

// funct12 disambiguation for OPCODE_SYSTEM — IR[31:20]
`define FUNCT12_ECALL  12'h000
`define FUNCT12_EBREAK 12'h001

// funct7 disambiguation for OPCODE_RTYPE
// WARNING: category selection is an ELSE, not equality — SUB/SRA use
// funct7=0100000, a fourth value matching neither MUL nor CRC.
`define FUNCT7_MUL     7'b0000001
`define FUNCT7_CRC     7'b1000000
// No FUNCT7_ALU constant — ALU is "else", never an equality target.

// alu_op — Table 9
`define ALU_PASS_B     4'h0
`define ALU_ADD        4'h1
`define ALU_SUB        4'h2
`define ALU_AND        4'h3
`define ALU_OR         4'h4
`define ALU_XOR        4'h5
`define ALU_SLL        4'h6
`define ALU_SRL        4'h7
`define ALU_MRS        4'h8  // SRA
`define ALU_SLT        4'h9
`define ALU_SLTU       4'hA

// mult_op_o — Table 10, direct funct3 passthrough
`define MULT_MUL       4'h0
`define MULT_MULH      4'h1
`define MULT_MULHSU    4'h2
`define MULT_MULHU     4'h3

// crc_op_o — Table 11, direct funct3 passthrough
`define CRC_CRCB       4'h0
`define CRC_CRCH       4'h1
`define CRC_CRCW       4'h2

// Internal control signals
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

`define ADR_SRC_PC       1'b0
`define ADR_SRC_ALU      1'b1

// Memory map
`define PC_RESET_ADDR    32'h00400000
`define IMEM_BASE        32'h00400000
`define DMEM_BASE        32'h10010000

// op_size_o — [2:1]=size, [0]=sign; sign don't-care for stores
`define OP_SIZE_BYTE_S   3'b000
`define OP_SIZE_BYTE_U   3'b001
`define OP_SIZE_HALF_S   3'b010
`define OP_SIZE_HALF_U   3'b011
`define OP_SIZE_WORD     3'b100

// imm_sel_o
`define IMM_SEL_I        3'b000
`define IMM_SEL_S        3'b001
`define IMM_SEL_B        3'b010
`define IMM_SEL_U        3'b011
`define IMM_SEL_J        3'b100

`endif // RVBL2_DEFINES_VH
