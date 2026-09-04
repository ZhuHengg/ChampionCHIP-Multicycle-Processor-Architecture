// =============================================================================
// Module: top_structural
// Description: Pure structural top-level module for ChampionCHIP multicycle core.
//              Matches the ChipInventor block-diagram schematic 1-to-1.
//              Contains ZERO behavioral always blocks — purely connects module instances!
// =============================================================================

`include "pkg/rvbl2_defines.vh"

module top_structural #(
    parameter IMEM_DEPTH_WORDS = 1024,
    parameter DMEM_DEPTH_WORDS = 2048,
    parameter IMEM_INIT_FILE   = "firmware/validation.hex"
) (
    input  wire clk_i,
    input  wire rst_i,
    output wire halt_o
);

    // =========================================================================
    // 1. Interconnect Wires
    // =========================================================================

    // Fetch-stage register outputs
    wire [31:0] pc;
    wire [31:0] old_pc;
    wire [31:0] ir;
    wire [31:0] pc_next;

    // IR Splitter outputs
    wire [6:0]  opcode;
    wire [4:0]  rd_addr;
    wire [2:0]  funct3;
    wire [4:0]  rs1_addr;
    wire [4:0]  rs2_addr;
    wire [6:0]  funct7;
    wire [11:0] funct12;

    // Control Unit outputs
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
    wire [2:0]  op_size_o;
    wire        adr_src_o;

    // Datapath & Execution wires
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] imm;
    wire        branch_taken;
    wire [31:0] mux_alu_a_out;
    wire [31:0] mux_alu_b_out;
    wire [31:0] alu_result;
    wire [31:0] alu_out;
    wire [1:0]  addr_lsb;
    wire [31:0] mult_result;
    wire [31:0] mult_result_r;
    wire [31:0] crc_result;
    wire [31:0] crc_result_r;
    wire [31:0] mux_result;

    // Memory & LSU wires
    wire [31:0] mux_mem_addr;
    wire [31:0] decoder_address_o;
    wire [31:0] decoder_data_o;
    wire        imem_oe_o;
    wire [31:0] imem_data_o;
    wire        dmem_we_o;
    wire        dmem_oe_o;
    wire [3:0]  dmem_bw_o;
    wire [31:0] dmem_data_o;
    wire [31:0] lsu_core_data_i;
    wire [31:0] lsu_mem_data_i;
    wire [31:0] mem_result;

    // =========================================================================
    // 2. Module Instances (Pure Wiring)
    // =========================================================================

    // --- Fetch Registers (PC, Old_PC, IR) ---
    fetch_registers #(
        .PC_RESET_ADDR (`PC_RESET_ADDR)
    ) u_fetch_registers (
        .clk_i      (clk_i),
        .rst_i      (rst_i),
        .pc_write_i (pc_write_o),
        .ir_write_i (ir_write_o),
        .pc_next_i  (pc_next),
        .mem_data_i (decoder_data_o),
        .pc_o       (pc),
        .old_pc_o   (old_pc),
        .ir_o       (ir)
    );

    // --- Next PC Multiplexer ---
    mux_pc_next u_mux_pc_next (
        .pc_src_i     (pc_src_o),
        .pc_i         (pc),
        .alu_result_i (alu_result),
        .pc_next_o    (pc_next)
    );

    // --- Instruction Field Splitter ---
    ir_splitter u_ir_splitter (
        .instr_i   (ir),
        .opcode_o  (opcode),
        .rd_o      (rd_addr),
        .funct3_o  (funct3),
        .rs1_o     (rs1_addr),
        .rs2_o     (rs2_addr),
        .funct7_o  (funct7),
        .funct12_o (funct12)
    );

    // --- Control Unit ---
    control_unit u_control_unit (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .opcode_i       (opcode),
        .funct3_i       (funct3),
        .funct7_i       (funct7),
        .funct12_i      (funct12),
        .addr_lsb_i     (addr_lsb),
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

    // --- Register File (32 GPRs) ---
    regfile u_regfile (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .rs1_addr_i   (rs1_addr),
        .rs2_addr_i   (rs2_addr),
        .rd_addr_i    (rd_addr),
        .write_data_i (mux_result),
        .reg_write_i  (reg_write_o),
        .rs1_data_o   (rs1_data),
        .rs2_data_o   (rs2_data)
    );

    // --- Immediate Extender ---
    imm_extend u_imm_extend (
        .instr_i   (ir),
        .imm_sel_i (imm_sel_o),
        .imm_o     (imm)
    );

    // --- Branch Condition Comparator ---
    branch_comparator u_branch_comparator (
        .rs1_i          (rs1_data),
        .rs2_i          (rs2_data),
        .funct3_i       (funct3),
        .branch_taken_o (branch_taken)
    );

    // --- ALU Input A Multiplexer ---
    mux_alu_a u_mux_alu_a (
        .alu_src_a_i (alu_src_a_o),
        .rs1_data_i  (rs1_data),
        .old_pc_i    (old_pc),
        .a_o         (mux_alu_a_out)
    );

    // --- ALU Input B Multiplexer ---
    mux_alu_b u_mux_alu_b (
        .alu_src_b_i (alu_src_b_o),
        .rs2_data_i  (rs2_data),
        .imm_i       (imm),
        .b_o         (mux_alu_b_out)
    );

    // --- Arithmetic Logic Unit (ALU) ---
    alu u_alu (
        .a_i      (mux_alu_a_out),
        .b_i      (mux_alu_b_out),
        .alu_op_i (alu_op_o),
        .result_o (alu_result)
    );

    // --- ALU Output Register (with built-in 2-bit addr_lsb tap) ---
    alu_out_reg u_alu_out_reg (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .en_i         (!adr_src_o),
        .alu_result_i (alu_result),
        .alu_out_o    (alu_out),
        .addr_lsb_o   (addr_lsb)
    );

    // --- Multiplier Accelerator & Capture Register ---
    mult u_mult (
        .a_i       (rs1_data),
        .b_i       (rs2_data),
        .mult_op_i (mult_op_o),
        .result_o  (mult_result)
    );

    reg32 u_reg_mult_result (
        .clk_i (clk_i),
        .rst_i (rst_i),
        .en_i  (mult_en_o),
        .d_i   (mult_result),
        .q_o   (mult_result_r)
    );

    // --- CRC Accelerator & Capture Register ---
    crc u_crc (
        .a_i      (rs1_data),
        .b_i      (rs2_data),
        .crc_op_i (crc_op_o),
        .result_o (crc_result)
    );

    reg32 u_reg_crc_result (
        .clk_i (clk_i),
        .rst_i (rst_i),
        .en_i  (crc_en_o),
        .d_i   (crc_result),
        .q_o   (crc_result_r)
    );

    // --- Load/Store Unit (LSU) & Mem Result Register ---
    lsu u_lsu (
        .core_data_o    (rs2_data),
        .core_address_o (alu_out),
        .op_size_o      (op_size_o),
        .mem_data_o     (decoder_data_o),
        .core_data_i    (lsu_core_data_i),
        .mem_data_i     (lsu_mem_data_i)
    );

    reg32 u_reg_mem_result (
        .clk_i (clk_i),
        .rst_i (rst_i),
        .en_i  (result_src_o == `RESULT_SRC_MEM),
        .d_i   (lsu_core_data_i),
        .q_o   (mem_result)
    );

    // --- Write-Back Result Multiplexer ---
    mux_result u_mux_result (
        .result_src_i  (result_src_o),
        .alu_out_i     (alu_out),
        .mult_result_i (mult_result_r),
        .crc_result_i  (crc_result_r),
        .mem_result_i  (mem_result),
        .old_pc_i      (old_pc),
        .result_o      (mux_result)
    );

    // --- Memory Address Multiplexer ---
    mux_mem_addr u_mux_mem_addr (
        .adr_src_i (adr_src_o),
        .pc_i      (pc),
        .alu_out_i (alu_out),
        .address_o (mux_mem_addr)
    );

    // --- Address Decoder ---
    address_decoder u_addr_decoder (
        .address_i   (mux_mem_addr),
        .we_i        (we_o),
        .oe_i        (oe_o),
        .bw_i        (bw_o),
        .dmem_data_i (dmem_data_o),
        .imem_data_i (imem_data_o),
        .address_o   (decoder_address_o),
        .dmem_we_o   (dmem_we_o),
        .dmem_oe_o   (dmem_oe_o),
        .imem_oe_o   (imem_oe_o),
        .bw_o        (dmem_bw_o),
        .data_o      (decoder_data_o)
    );

    // --- Instruction Memory (IMEM) ---
    imem #(
        .DEPTH_WORDS (IMEM_DEPTH_WORDS),
        .INIT_FILE   (IMEM_INIT_FILE)
    ) u_imem (
        .clk_i  (clk_i),
        .addr_i (decoder_address_o),
        .oe_i   (imem_oe_o),
        .data_o (imem_data_o)
    );

    // --- Data Memory (DMEM) ---
    dmem #(
        .DEPTH_WORDS (DMEM_DEPTH_WORDS)
    ) u_dmem (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .addr_i (decoder_address_o),
        .we_i   (dmem_we_o),
        .oe_i   (dmem_oe_o),
        .bw_i   (dmem_bw_o),
        .data_i (lsu_mem_data_i),
        .data_o (dmem_data_o)
    );

endmodule
