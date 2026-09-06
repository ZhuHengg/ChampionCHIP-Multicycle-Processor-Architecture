// control_unit.v — FSM, per HANDOFF_control_unit.md

// ---------------------------------------------------------------------
// Opcodes (IR[6:0])
// ---------------------------------------------------------------------
`define OPCODE_RTYPE   7'b0110011  // ALU R-type, MUL, CRC
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
// funct12 / funct7 disambiguation
// ---------------------------------------------------------------------
`define FUNCT12_ECALL  12'h000
`define FUNCT12_EBREAK 12'h001
`define FUNCT7_MUL     7'b0000001
`define FUNCT7_CRC     7'b1000000

// ---------------------------------------------------------------------
// alu_op — Table 9
// ---------------------------------------------------------------------
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

// ---------------------------------------------------------------------
// mult_op_o (Table 10) & crc_op_o (Table 11)
// ---------------------------------------------------------------------
`define MULT_MUL       4'h0
`define MULT_MULH      4'h1
`define MULT_MULHSU    4'h2
`define MULT_MULHU     4'h3

`define CRC_CRCB       4'h0
`define CRC_CRCH       4'h1
`define CRC_CRCW       4'h2

// ---------------------------------------------------------------------
// Multiplexer select lines
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

`define ADR_SRC_PC       1'b0
`define ADR_SRC_ALU      1'b1

// ---------------------------------------------------------------------
// Memory Map (Table 13)
// ---------------------------------------------------------------------
`define PC_RESET_ADDR    32'h00400000
`define IMEM_BASE        32'h00400000
`define DMEM_BASE        32'h10010000

// ---------------------------------------------------------------------
// op_size_o & imm_sel_o
// ---------------------------------------------------------------------
`define OP_SIZE_BYTE_S   3'b000
`define OP_SIZE_BYTE_U   3'b001
`define OP_SIZE_HALF_S   3'b010
`define OP_SIZE_HALF_U   3'b011
`define OP_SIZE_WORD     3'b100

`define IMM_SEL_I        3'b000
`define IMM_SEL_S        3'b001
`define IMM_SEL_B        3'b010
`define IMM_SEL_U        3'b011
`define IMM_SEL_J        3'b100

module control_unit (
    input  wire        clk_i,
    input  wire        rst_i,

    // Decode fields
    input  wire [6:0]  opcode_i,      // IR[6:0]
    input  wire [2:0]  funct3_i,      // IR[14:12]
    input  wire [6:0]  funct7_i,      // IR[31:25]
    input  wire [11:0] funct12_i,     // IR[31:20], ECALL/EBREAK disambiguation

    // Effective-address low bits, for bw_o
    input  wire [1:0]  addr_lsb_i,

    // Branch comparator result
    input  wire        branch_taken_i,

    // Datapath control
    output reg         pc_write_o,
    output reg  [1:0]  pc_src_o,
    output reg         ir_write_o,
    output reg         reg_write_o,
    output reg  [2:0]  result_src_o,
    output reg         alu_src_a_o,
    output reg  [1:0]  alu_src_b_o,
    output reg  [3:0]  alu_op_o,
    output reg  [2:0]  imm_sel_o,
    output reg  [3:0]  mult_op_o,
    output reg  [3:0]  crc_op_o,
    output reg         mult_en_o,
    output reg         crc_en_o,

    // Memory interface
    output reg         we_o,
    output reg         oe_o,
    output reg  [3:0]  bw_o,
    output reg  [2:0]  op_size_o,
    output reg         adr_src_o,     // mem address mux select

    // Sticky ECALL status
    output reg         halt_o
);

    // State encoding
    localparam [3:0] RESET             = 4'd0;
    localparam [3:0] FETCH             = 4'd1;
    localparam [3:0] DECODE            = 4'd2;
    localparam [3:0] EXECUTE_ALU       = 4'd3;
    localparam [3:0] WRITE_BACK        = 4'd4;
    localparam [3:0] MEM_ADDR          = 4'd5;
    localparam [3:0] MEM_ACCESS_ADDR   = 4'd6;
    localparam [3:0] MEM_ACCESS_DATA   = 4'd7;
    localparam [3:0] MEM_ACCESS_STORE  = 4'd8;

    reg [3:0] state, next_state;

    // Tracks which state fed WRITE_BACK, for result_src_o
    reg [3:0] prev_state;

    // State register — sync reset
    always @(posedge clk_i) begin
        if (rst_i) begin
            state      <= RESET;
            prev_state <= RESET;
        end else begin
            prev_state <= state;
            state      <= next_state;
        end
    end

    // halt_o — sticky ECALL flag, observability only, does not stop core
    wire is_ecall = (opcode_i  == `OPCODE_SYSTEM) &&
                    (funct3_i  == 3'b000)         &&
                    (funct12_i == `FUNCT12_ECALL);

    always @(posedge clk_i) begin
        if (rst_i) begin
            halt_o <= 1'b0;
        end else if ((state == EXECUTE_ALU) && is_ecall) begin
            halt_o <= 1'b1;
        end
    end

    // Illegal-opcode detection — silent no-op policy
    wire opcode_legal = (opcode_i == `OPCODE_RTYPE)  ||
                        (opcode_i == `OPCODE_ITYPE)  ||
                        (opcode_i == `OPCODE_LOAD)   ||
                        (opcode_i == `OPCODE_STORE)  ||
                        (opcode_i == `OPCODE_BRANCH) ||
                        (opcode_i == `OPCODE_JAL)    ||
                        (opcode_i == `OPCODE_JALR)   ||
                        (opcode_i == `OPCODE_LUI)    ||
                        (opcode_i == `OPCODE_AUIPC)  ||
                        (opcode_i == `OPCODE_SYSTEM) ||
                        (opcode_i == `OPCODE_FENCE);

    // Next-state logic
    always @(*) begin
        next_state = state; // default: hold
        case (state)
            RESET:  next_state = FETCH;
            FETCH:  next_state = DECODE;

            DECODE: begin
                if (opcode_i == `OPCODE_LOAD || opcode_i == `OPCODE_STORE)
                    next_state = MEM_ADDR;
                else
                    next_state = EXECUTE_ALU;
            end

            EXECUTE_ALU: begin
                // Branch/system/fence/illegal skip WRITE_BACK
                if (opcode_i == `OPCODE_BRANCH ||
                    opcode_i == `OPCODE_SYSTEM ||
                    opcode_i == `OPCODE_FENCE  ||
                    !opcode_legal)
                    next_state = FETCH;
                else
                    next_state = WRITE_BACK;
            end

            WRITE_BACK:  next_state = FETCH;

            MEM_ADDR: begin
                if (opcode_i == `OPCODE_STORE)
                    next_state = MEM_ACCESS_STORE;
                else
                    next_state = MEM_ACCESS_ADDR;
            end

            MEM_ACCESS_ADDR: next_state = MEM_ACCESS_DATA;
            MEM_ACCESS_DATA: next_state = WRITE_BACK;
            MEM_ACCESS_STORE: next_state = FETCH; // store skips WRITE_BACK

            default: next_state = RESET;
        endcase
    end

    // funct3 -> op_size_o lookup
    reg [2:0] op_size_lookup;
    always @(*) begin
        case (funct3_i)
            3'b000:  op_size_lookup = `OP_SIZE_BYTE_S; // lb / sb
            3'b001:  op_size_lookup = `OP_SIZE_HALF_S; // lh / sh
            3'b010:  op_size_lookup = `OP_SIZE_WORD;   // lw / sw
            3'b100:  op_size_lookup = `OP_SIZE_BYTE_U; // lbu
            3'b101:  op_size_lookup = `OP_SIZE_HALF_U; // lhu
            default: op_size_lookup = `OP_SIZE_WORD;
        endcase
    end

    // bw_o formula
    reg [3:0] bw_lookup;
    always @(*) begin
        case (op_size_lookup[2:1])
            2'b10: bw_lookup = 4'b1111; // word
            2'b01: bw_lookup = addr_lsb_i[1] ? 4'b1100 : 4'b0011; // half
            2'b00: bw_lookup = 4'b0001 << addr_lsb_i; // byte
            default: bw_lookup = 4'b1111;
        endcase
    end

    // Output logic
    always @(*) begin
        // Defaults
        pc_write_o   = 1'b0;
        pc_src_o     = `PC_SRC_PLUS4;
        ir_write_o   = 1'b0;
        reg_write_o  = 1'b0;
        result_src_o = `RESULT_SRC_ALU;
        alu_src_a_o  = `ALU_SRC_A_RS1;
        alu_src_b_o  = `ALU_SRC_B_RS2;
        alu_op_o     = `ALU_PASS_B;
        imm_sel_o    = `IMM_SEL_I;
        mult_op_o      = 4'h0;
        crc_op_o       = 4'h0;
        mult_en_o    = 1'b0;
        crc_en_o     = 1'b0;
        we_o         = 1'b0;
        oe_o         = 1'b0;
        bw_o         = 4'b0000;
        op_size_o    = `OP_SIZE_WORD;
        adr_src_o    = `ADR_SRC_PC;

        case (state)
            RESET: begin
                // all defaults
            end

            FETCH: begin
                pc_write_o = 1'b1;
                ir_write_o = 1'b1;
                oe_o       = 1'b1;
            end

            DECODE: begin
                // imm_sel_o per opcode
                if (opcode_i == `OPCODE_LOAD)
                    imm_sel_o = `IMM_SEL_I;
                else if (opcode_i == `OPCODE_STORE)
                    imm_sel_o = `IMM_SEL_S;
                else if (opcode_i == `OPCODE_BRANCH)
                    imm_sel_o = `IMM_SEL_B;
                else if (opcode_i == `OPCODE_JAL)
                    imm_sel_o = `IMM_SEL_J;
                else if (opcode_i == `OPCODE_JALR)
                    imm_sel_o = `IMM_SEL_I;
                else if (opcode_i == `OPCODE_LUI || opcode_i == `OPCODE_AUIPC)
                    imm_sel_o = `IMM_SEL_U;
                else if (opcode_i == `OPCODE_ITYPE)
                    imm_sel_o = `IMM_SEL_I;
                else
                    imm_sel_o = `IMM_SEL_I;
            end

            EXECUTE_ALU: begin
                if (opcode_i == `OPCODE_BRANCH) begin
                    // Branch — pc_write_o follows comparator
                    pc_write_o   = branch_taken_i;
                    pc_src_o     = `PC_SRC_TARGET;
                    alu_src_a_o  = `ALU_SRC_A_PC;
                    alu_src_b_o  = `ALU_SRC_B_IMM;
                    alu_op_o     = `ALU_ADD;
                    imm_sel_o    = `IMM_SEL_B;
                end else if (opcode_i == `OPCODE_JAL) begin
                    pc_write_o   = 1'b1;
                    pc_src_o     = `PC_SRC_TARGET;
                    alu_src_a_o  = `ALU_SRC_A_PC;
                    alu_src_b_o  = `ALU_SRC_B_IMM;
                    alu_op_o     = `ALU_ADD;
                    imm_sel_o    = `IMM_SEL_J;
                    result_src_o = `RESULT_SRC_PC4;
                end else if (opcode_i == `OPCODE_JALR) begin
                    // Target = rs1 + imm, not PC + imm
                    pc_write_o   = 1'b1;
                    pc_src_o     = `PC_SRC_JALR;
                    alu_src_a_o  = `ALU_SRC_A_RS1;
                    alu_src_b_o  = `ALU_SRC_B_IMM;
                    alu_op_o     = `ALU_ADD;
                    imm_sel_o    = `IMM_SEL_I;
                    result_src_o = `RESULT_SRC_PC4;
                end else if (opcode_i == `OPCODE_LUI) begin
                    // Only user of ALU_PASS_B
                    alu_src_b_o = `ALU_SRC_B_IMM;
                    alu_op_o    = `ALU_PASS_B;
                    imm_sel_o   = `IMM_SEL_U;
                end else if (opcode_i == `OPCODE_AUIPC) begin
                    alu_src_a_o = `ALU_SRC_A_PC;
                    alu_src_b_o = `ALU_SRC_B_IMM;
                    alu_op_o    = `ALU_ADD;
                    imm_sel_o   = `IMM_SEL_U;
                end else if (opcode_i == `OPCODE_SYSTEM || opcode_i == `OPCODE_FENCE) begin
                    // ECALL/EBREAK/FENCE no-op
                end else if (opcode_i == `OPCODE_RTYPE && funct7_i == `FUNCT7_MUL) begin
                    // Zmmul — combinational, single-cycle
                    mult_en_o    = 1'b1;
                    mult_op_o      = {2'b00, funct3_i};
                    result_src_o = `RESULT_SRC_MUL;
                end else if (opcode_i == `OPCODE_RTYPE && funct7_i == `FUNCT7_CRC) begin
                    // Xicrc
                    crc_en_o     = 1'b1;
                    crc_op_o       = {2'b00, funct3_i};
                    result_src_o = `RESULT_SRC_CRC;
                end else begin
                    // R-type / I-type ALU
                    if (opcode_i == `OPCODE_ITYPE) begin
                        alu_src_b_o = `ALU_SRC_B_IMM;
                        imm_sel_o   = `IMM_SEL_I;
                    end

                    // alu_op decode
                    case (funct3_i)
                        3'b000: alu_op_o = (opcode_i != `OPCODE_ITYPE && funct7_i[5]) ? `ALU_SUB : `ALU_ADD;
                        3'b001: alu_op_o = `ALU_SLL;
                        3'b010: alu_op_o = `ALU_SLT;
                        3'b011: alu_op_o = `ALU_SLTU;
                        3'b100: alu_op_o = `ALU_XOR;
                        3'b101: alu_op_o = funct7_i[5] ? `ALU_MRS : `ALU_SRL;
                        3'b110: alu_op_o = `ALU_OR;
                        3'b111: alu_op_o = `ALU_AND;
                        default: alu_op_o = `ALU_ADD;
                    endcase
                end
            end

            MEM_ADDR: begin
                // Effective address = rs1 + imm
                alu_src_a_o = `ALU_SRC_A_RS1;
                alu_src_b_o = `ALU_SRC_B_IMM;
                alu_op_o    = `ALU_ADD;
                imm_sel_o   = (opcode_i == `OPCODE_STORE) ? `IMM_SEL_S : `IMM_SEL_I;
                op_size_o   = op_size_lookup;
                bw_o        = bw_lookup;
            end

            MEM_ACCESS_ADDR: begin
                // Load sub-cycle 1: present address
                oe_o      = 1'b1;
                op_size_o = op_size_lookup;
                adr_src_o = `ADR_SRC_ALU;
            end

            MEM_ACCESS_DATA: begin
                // Load sub-cycle 2: read data valid
                result_src_o = `RESULT_SRC_MEM;
                op_size_o    = op_size_lookup;
                oe_o         = 1'b1;
                adr_src_o    = `ADR_SRC_ALU;
            end

            MEM_ACCESS_STORE: begin
                // Store: commit, then FETCH
                we_o      = 1'b1;
                op_size_o = op_size_lookup;
                bw_o      = bw_lookup;
                adr_src_o = `ADR_SRC_ALU;
            end

            WRITE_BACK: begin
                reg_write_o = 1'b1;
                // result_src_o depends on path taken to get here
                if (prev_state == MEM_ACCESS_DATA) begin
                    result_src_o = `RESULT_SRC_MEM;
                    op_size_o    = op_size_lookup;
                end
                else if (prev_state == EXECUTE_ALU &&
                         (opcode_i == `OPCODE_JAL || opcode_i == `OPCODE_JALR))
                    result_src_o = `RESULT_SRC_PC4;
                else if (prev_state == EXECUTE_ALU && opcode_i == `OPCODE_RTYPE &&
                         funct7_i == `FUNCT7_MUL)
                    result_src_o = `RESULT_SRC_MUL;
                else if (prev_state == EXECUTE_ALU && opcode_i == `OPCODE_RTYPE &&
                         funct7_i == `FUNCT7_CRC)
                    result_src_o = `RESULT_SRC_CRC;
                else
                    result_src_o = `RESULT_SRC_ALU;
            end

            default: begin
                // all defaults
            end
        endcase

        // Halt override — ECALL stops the core, both pc_write_o and
        // ir_write_o must be gated or FETCH re-executes ECALL forever
        if (halt_o) begin
            pc_write_o = 1'b0;
            ir_write_o = 1'b0;
        end
    end

endmodule
