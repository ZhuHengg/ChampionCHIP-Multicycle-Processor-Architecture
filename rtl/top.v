// top.v — datapath, wires control_unit to memories/ALU/regfile/mult/crc/lsu

// ---------------------------------------------------------------------
// Multiplexer select lines & constants (from rvbl2_defines.vh)
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

`define PC_RESET_ADDR    32'h00400000
`define IMEM_BASE        32'h00400000
`define DMEM_BASE        32'h10010000

// IMEM_INIT_FILE defaults to validation firmware, not "" — an
// uninitialized imem gets constant-folded away by synthesis.
module top #(
    parameter IMEM_DEPTH_WORDS = 1024,
    parameter DMEM_DEPTH_WORDS = 2048,
    parameter IMEM_INIT_FILE   = "firmware/validation.hex"
) (
    input  wire clk_i,
    input  wire rst_i,
    output wire halt_o
);

    // Fetch-stage registers
    reg [31:0] pc;
    reg [31:0] old_pc;
    reg [31:0] ir;

    // Registered ALU output — frozen during MEM_ACCESS_*
    reg [31:0] alu_out;

    // Captured load result, held through WRITE_BACK
    reg [31:0] mem_result;

    // Captured MUL/CRC result, held through WRITE_BACK
    reg [31:0] mult_result_r;
    reg [31:0] crc_result_r;

    // Control unit <-> datapath wiring
    wire        pc_write_o;
    wire [1:0]  pc_src_o;
    wire        ir_write_o;
    wire        reg_write_o;
    wire [2:0]  result_src_o;
    wire        alu_src_a_o;
    wire [1:0]  alu_src_b_o;
    wire [3:0]  alu_op_o;
    wire [2:0]  imm_sel_o;
    wire [3:0]  mult_op_o;
    wire [3:0]  crc_op_o;
    wire        mult_en_o;
    wire        crc_en_o;
    wire        we_o;
    wire        oe_o;
    wire [3:0]  bw_o;
    wire        adr_src_o;

    // Memory-path nets
    wire [29:0] decoder_address_o;
    wire [31:0] decoder_data_o;
    wire        imem_oe_o;
    wire [31:0] imem_data_o;

    // Regfile / ALU / immediate-extender nets
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] imm;
    wire [31:0] alu_result; // live ALU output, not for RESULT_SRC_ALU
    wire        branch_taken;

    // Live mult/crc outputs — captured into result registers, not tapped directly
    wire [31:0] mult_result;
    wire [31:0] crc_result;

    // DMEM / LSU nets
    wire [31:0] dmem_data_o;
    wire        dmem_we_o;
    wire        dmem_oe_o;
    wire [3:0]  dmem_bw_o;
    wire [2:0]  op_size_o;
    wire [31:0] lsu_core_data_i;
    wire [31:0] lsu_mem_data_i;

    // mux_pc_next
    reg [31:0] mux_pc_next;
    always @(*) begin
        mux_pc_next = pc + 32'd4; // default
        case (pc_src_o)
            `PC_SRC_PLUS4:  mux_pc_next = pc + 32'd4;
            `PC_SRC_TARGET: mux_pc_next = alu_result;
            `PC_SRC_JALR:   mux_pc_next = {alu_result[31:1], 1'b0}; // clear bit 0
            default:        mux_pc_next = pc + 32'd4;
        endcase
    end

    // mux_mem_addr
    reg [31:0] mux_mem_addr;
    always @(*) begin
        mux_mem_addr = pc; // default
        case (adr_src_o)
            `ADR_SRC_PC:  mux_mem_addr = pc;
            `ADR_SRC_ALU: mux_mem_addr = alu_out;
            default:      mux_mem_addr = pc;
        endcase
    end

    // mux_alu_a / mux_alu_b
    reg [31:0] mux_alu_a;
    always @(*) begin
        mux_alu_a = rs1_data; // default
        case (alu_src_a_o)
            `ALU_SRC_A_RS1: mux_alu_a = rs1_data;
            `ALU_SRC_A_PC:  mux_alu_a = old_pc;
            default:        mux_alu_a = rs1_data;
        endcase
    end

    reg [31:0] mux_alu_b;
    always @(*) begin
        mux_alu_b = rs2_data; // default
        case (alu_src_b_o)
            `ALU_SRC_B_RS2:    mux_alu_b = rs2_data;
            `ALU_SRC_B_IMM:    mux_alu_b = imm;
            `ALU_SRC_B_CONST4: mux_alu_b = 32'd4;
            default:           mux_alu_b = rs2_data;
        endcase
    end

    // mux_result — write-back data mux
    reg [31:0] mux_result;
    always @(*) begin
        mux_result = alu_out; // default
        case (result_src_o)
            `RESULT_SRC_ALU: mux_result = alu_out;
            `RESULT_SRC_MUL: mux_result = mult_result_r;
            `RESULT_SRC_CRC: mux_result = crc_result_r;
            `RESULT_SRC_MEM: mux_result = mem_result;
            `RESULT_SRC_PC4: mux_result = old_pc + 32'd4;
            default:         mux_result = alu_out;
        endcase
    end

    // Fetch-stage register file — sync reset
    always @(posedge clk_i) begin
        if (rst_i) begin
            pc     <= `PC_RESET_ADDR;
            old_pc <= 32'b0;
            ir     <= 32'b0;
        end else begin
            if (pc_write_o)
                pc <= mux_pc_next;
            if (ir_write_o) begin
                old_pc <= pc;
                ir     <= decoder_data_o;
            end
        end
    end

    // alu_out register — loads every cycle except while memory path owns address
    always @(posedge clk_i) begin
        if (rst_i)
            alu_out <= 32'b0;
        else if (!adr_src_o)
            alu_out <= alu_result;
    end

    // mem_result register
    always @(posedge clk_i) begin
        if (rst_i)
            mem_result <= 32'b0;
        else if (result_src_o == `RESULT_SRC_MEM)
            mem_result <= lsu_core_data_i;
    end

    // mult_result_r / crc_result_r registers
    always @(posedge clk_i) begin
        if (rst_i)
            mult_result_r <= 32'b0;
        else if (mult_en_o)
            mult_result_r <= mult_result;
    end

    always @(posedge clk_i) begin
        if (rst_i)
            crc_result_r <= 32'b0;
        else if (crc_en_o)
            crc_result_r <= crc_result;
    end

    // Module instances
    control_unit u_control_unit (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .opcode_i       (ir[6:0]),
        .funct3_i       (ir[14:12]),
        .funct7_i       (ir[31:25]),
        .funct12_i      (ir[31:20]),
        .addr_lsb_i     (alu_out[1:0]),
        .branch_taken_i (branch_taken),
        .pc_write_o     (pc_write_o),
        .pc_src_o       (pc_src_o),
        .ir_write_o     (ir_write_o),
        .reg_write_o    (reg_write_o),
        .result_src_o   (result_src_o),
        .alu_src_a_o    (alu_src_a_o),
        .alu_src_b_o    (alu_src_b_o),
        .alu_op_o       (alu_op_o),
        .imm_sel_o      (imm_sel_o),
        .mult_op_o      (mult_op_o),
        .crc_op_o       (crc_op_o),
        .mult_en_o      (mult_en_o),
        .crc_en_o       (crc_en_o),
        .we_o           (we_o),
        .oe_o           (oe_o),
        .bw_o           (bw_o),
        .op_size_o      (op_size_o),
        .adr_src_o      (adr_src_o),
        .halt_o         (halt_o)
    );

    address_decoder u_addr_decoder (
        .address_i    (mux_mem_addr),
        .we_i         (we_o),
        .oe_i         (oe_o),
        .bw_i         (bw_o),
        .dmem_data_i  (dmem_data_o),
        .imem_data_i  (imem_data_o),
        .address_o    (decoder_address_o),
        .dmem_we_o    (dmem_we_o),
        .dmem_oe_o    (dmem_oe_o),
        .imem_oe_o    (imem_oe_o),
        .bw_o         (dmem_bw_o),
        .data_o       (decoder_data_o)
    );

    imem #(
        .DEPTH_WORDS (IMEM_DEPTH_WORDS),
        .INIT_FILE   (IMEM_INIT_FILE)
    ) u_imem (
        .clk_i  (clk_i),
        .addr_i ({2'b00, decoder_address_o}),
        .oe_i   (imem_oe_o),
        .data_o (imem_data_o)
    );

    regfile u_regfile (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .rs1_addr_i   (ir[19:15]),
        .rs2_addr_i   (ir[24:20]),
        .rd_addr_i    (ir[11:7]),
        .write_data_i (mux_result),
        .reg_write_i  (reg_write_o),
        .rs1_data_o   (rs1_data),
        .rs2_data_o   (rs2_data)
    );

    alu u_alu (
        .a_i      (mux_alu_a),
        .b_i      (mux_alu_b),
        .alu_op_i (alu_op_o),
        .result_o (alu_result)
    );

    imm_extend u_imm_extend (
        .instr_i   (ir),
        .imm_sel_i (imm_sel_o),
        .imm_o     (imm)
    );

    branch_comparator u_branch_comparator (
        .rs1_i          (rs1_data),
        .rs2_i          (rs2_data),
        .funct3_i       (ir[14:12]),
        .branch_taken_o (branch_taken)
    );

    // Combinational, single-cycle
    mult u_mult (
        .a_i       (rs1_data),
        .b_i       (rs2_data),
        .mult_op_i (mult_op_o),
        .result_o  (mult_result)
    );

    // Combinational — a_i is data, b_i is running CRC seed
    crc u_crc (
        .a_i      (rs1_data),
        .b_i      (rs2_data),
        .crc_op_i (crc_op_o),
        .result_o (crc_result)
    );

    dmem #(
        .DEPTH_WORDS (DMEM_DEPTH_WORDS)
    ) u_dmem (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .addr_i ({2'b00, decoder_address_o}),
        .we_i   (dmem_we_o),
        .oe_i   (dmem_oe_o),
        .bw_i   (dmem_bw_o),
        .data_i (lsu_mem_data_i),
        .data_o (dmem_data_o)
    );

    // LSU port names are from the core's perspective (guide Figure 2)
    lsu u_lsu (
        .core_data_o    (rs2_data),
        .core_address_o (alu_out),
        .op_size_o      (op_size_o),
        .mem_data_o     (decoder_data_o),
        .core_data_i    (lsu_core_data_i),
        .mem_data_i     (lsu_mem_data_i)
    );

endmodule
