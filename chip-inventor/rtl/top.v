module top (

  input wire clk_i,
  input wire rst_i,
  output wire halt_o,
  // Debug/observability outputs -- simulation-only, not part of the
  // guide/team-fixed interface. Needed because ChipInventor's canvas
  // compiler rejects hierarchical dot-refs into instance internals, so
  // testbench.v cannot read pc/regfile contents any other way.
  output wire [31:0] pc_dbg_o,
  output wire [31:0] x4_dbg_o

);

// Internal nets
wire pc_write_o;
wire ir_write_o;
wire [31:0] pc_next;
wire [31:0] decoder_data_o;
wire [31:0] pc;
wire [31:0] old_pc;
wire [31:0] ir;
wire [1:0] pc_src_o;
wire [31:0] alu_result;
wire [6:0] opcode;
wire [4:0] rd_addr;
wire [2:0] funct3;
wire [4:0] rs1_addr;
wire [4:0] rs2_addr;
wire [6:0] funct7;
wire [11:0] funct12;
wire [1:0] addr_lsb;
wire branch_taken;
wire reg_write_o;
wire [2:0] result_src_o;
wire alu_src_a_o;
wire [1:0] alu_src_b_o;
wire [3:0] alu_op_o;
wire [2:0] imm_sel_o;
wire [3:0] mult_op_o;
wire [3:0] crc_op_o;
wire mult_en_o;
wire crc_en_o;
wire we_o;
wire oe_o;
wire [3:0] bw_o;
wire [2:0] op_size_o;
wire adr_src_o;
wire [31:0] mux_result;
wire [31:0] rs1_data;
wire [31:0] rs2_data;
wire [31:0] imm;
wire [31:0] mux_alu_a_out;
wire [31:0] mux_alu_b_out;
wire not_adr_src_o;
wire [31:0] alu_out;
wire [31:0] mult_result;
wire [31:0] mult_result_r;
wire [31:0] crc_result;
wire [31:0] crc_result_r;
wire [31:0] lsu_core_data_i;
wire [31:0] lsu_mem_data_i;
wire is_result_src_mem;
wire [31:0] mem_result;
wire [31:0] mux_mem_addr;
wire [31:0] dmem_data_o;
wire [31:0] imem_data_o;
wire [31:0] decoder_address_o;
wire dmem_we_o;
wire dmem_oe_o;
wire imem_oe_o;
wire [3:0] dmem_bw_o;

//Instances of Modules
fetch_registers u_fetch_registers (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .pc_write_i (pc_write_o),
         .ir_write_i (ir_write_o),
         .pc_next_i (pc_next[31:0]),
         .mem_data_i (decoder_data_o[31:0]),
         .pc_o (pc[31:0]),
         .old_pc_o (old_pc[31:0]),
         .ir_o (ir[31:0])
     );

mux_pc_next u_mux_pc_next (
         .pc_src_i (pc_src_o[1:0]),
         .pc_i (pc[31:0]),
         .alu_result_i (alu_result[31:0]),
         .pc_next_o (pc_next[31:0])
     );

ir_splitter_eq26 u_ir_splitter (
         .instr_i (ir[31:0]),
         .opcode_o (opcode[6:0]),
         .rd_o (rd_addr[4:0]),
         .funct3_o (funct3[2:0]),
         .rs1_o (rs1_addr[4:0]),
         .rs2_o (rs2_addr[4:0]),
         .funct7_o (funct7[6:0]),
         .funct12_o (funct12[11:0])
     );

control_unit_eq26 u_control_unit (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .opcode_i (opcode[6:0]),
         .funct3_i (funct3[2:0]),
         .funct7_i (funct7[6:0]),
         .funct12_i (funct12[11:0]),
         .addr_lsb_i (addr_lsb[1:0]),
         .branch_taken_i (branch_taken),
         .pc_write_o (pc_write_o),
         .pc_src_o (pc_src_o[1:0]),
         .ir_write_o (ir_write_o),
         .reg_write_o (reg_write_o),
         .result_src_o (result_src_o[2:0]),
         .alu_src_a_o (alu_src_a_o),
         .alu_src_b_o (alu_src_b_o[1:0]),
         .alu_op_o (alu_op_o[3:0]),
         .imm_sel_o (imm_sel_o[2:0]),
         .mult_op_o (mult_op_o[3:0]),
         .crc_op_o (crc_op_o[3:0]),
         .mult_en_o (mult_en_o),
         .crc_en_o (crc_en_o),
         .we_o (we_o),
         .oe_o (oe_o),
         .bw_o (bw_o[3:0]),
         .op_size_o (op_size_o[2:0]),
         .adr_src_o (adr_src_o),
         .halt_o (halt_o)
     );

regfile_eq u_regfile (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .rs1_addr_i (rs1_addr[4:0]),
         .rs2_addr_i (rs2_addr[4:0]),
         .rd_addr_i (rd_addr[4:0]),
         .write_data_i (mux_result[31:0]),
         .reg_write_i (reg_write_o),
         .rs1_data_o (rs1_data[31:0]),
         .rs2_data_o (rs2_data[31:0]),
         .x4_dbg_o (x4_dbg_o[31:0])
     );

assign pc_dbg_o = pc[31:0];

imm_extend_eq26 u_imm_extend (
         .instr_i (ir[31:0]),
         .imm_sel_i (imm_sel_o[2:0]),
         .imm_o (imm[31:0])
     );

branch_comparator_eq26 u_branch_comparator (
         .rs1_i (rs1_data[31:0]),
         .rs2_i (rs2_data[31:0]),
         .funct3_i (funct3[2:0]),
         .branch_taken_o (branch_taken)
     );

mux_alu_a u_mux_alu_a (
         .alu_src_a_i (alu_src_a_o),
         .rs1_data_i (rs1_data[31:0]),
         .old_pc_i (old_pc[31:0]),
         .a_o (mux_alu_a_out[31:0])
     );

mux_alu_b u_mux_alu_b (
         .alu_src_b_i (alu_src_b_o[1:0]),
         .rs2_data_i (rs2_data[31:0]),
         .imm_i (imm[31:0]),
         .b_o (mux_alu_b_out[31:0])
     );

alu_eq26 u_alu (
         .a_i (mux_alu_a_out[31:0]),
         .b_i (mux_alu_b_out[31:0]),
         .alu_op_i (alu_op_o[3:0]),
         .result_o (alu_result[31:0])
     );

alu_out_reg u_alu_out_reg (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (not_adr_src_o),
         .alu_result_i (alu_result[31:0]),
         .alu_out_o (alu_out[31:0]),
         .addr_lsb_o (addr_lsb[1:0])
     );

adr_src_inv u_adr_src_inv (
         .adr_src_i (adr_src_o),
         .not_adr_src_o (not_adr_src_o)
     );

mult_eq26 u_mult (
         .a_i (rs1_data[31:0]),
         .b_i (rs2_data[31:0]),
         .mult_op_i (mult_op_o[3:0]),
         .result_o (mult_result[31:0])
     );

reg32_dff_eq26 u_reg_mult_result (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (mult_en_o),
         .d_i (mult_result[31:0]),
         .q_o (mult_result_r[31:0])
     );

crc_eq26 u_crc (
         .a_i (rs1_data[31:0]),
         .b_i (rs2_data[31:0]),
         .crc_op_i (crc_op_o[3:0]),
         .result_o (crc_result[31:0])
     );

reg32_dff_eq26 u_reg_crc_result (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (crc_en_o),
         .d_i (crc_result[31:0]),
         .q_o (crc_result_r[31:0])
     );

lsu_eq26 u_lsu (
         .core_data_o (rs2_data[31:0]),
         .core_address_o (alu_out[31:0]),
         .op_size_o (op_size_o[2:0]),
         .mem_data_o (decoder_data_o[31:0]),
         .core_data_i (lsu_core_data_i[31:0]),
         .mem_data_i (lsu_mem_data_i[31:0])
     );

reg32_dff_eq26 u_reg_mem_result (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (is_result_src_mem),
         .d_i (lsu_core_data_i[31:0]),
         .q_o (mem_result[31:0])
     );

result_src_mem_eq u_result_src_mem_eq (
         .result_src_i (result_src_o[2:0]),
         .is_result_src_mem_o (is_result_src_mem)
     );

mux_result u_mux_result (
         .result_src_i (result_src_o[2:0]),
         .alu_out_i (alu_out[31:0]),
         .mult_result_i (mult_result_r[31:0]),
         .crc_result_i (crc_result_r[31:0]),
         .mem_result_i (mem_result[31:0]),
         .old_pc_i (old_pc[31:0]),
         .result_o (mux_result[31:0])
     );

mux_mem_addr u_mux_mem_addr (
         .adr_src_i (adr_src_o),
         .pc_i (pc[31:0]),
         .alu_out_i (alu_out[31:0]),
         .address_o (mux_mem_addr[31:0])
     );

address_decoder u_addr_decoder (
         .address_i (mux_mem_addr[31:0]),
         .we_i (we_o),
         .oe_i (oe_o),
         .bw_i (bw_o[3:0]),
         .dmem_data_i (dmem_data_o[31:0]),
         .imem_data_i (imem_data_o[31:0]),
         .address_o (decoder_address_o[29:0]),
         .dmem_we_o (dmem_we_o),
         .dmem_oe_o (dmem_oe_o),
         .imem_oe_o (imem_oe_o),
         .bw_o (dmem_bw_o[3:0]),
         .data_o (decoder_data_o[31:0])
     );

imem u_imem (
         .clk_i (clk_i),
         .addr_i (decoder_address_o[31:0]),
         .oe_i (imem_oe_o),
         .data_o (imem_data_o[31:0])
     );

dmem_eq26 #(
    .DEPTH_WORDS (2048)
) u_dmem (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .addr_i (decoder_address_o[31:0]),
         .we_i (dmem_we_o),
         .oe_i (dmem_oe_o),
         .bw_i (dmem_bw_o[3:0]),
         .data_i (lsu_mem_data_i[31:0]),
         .data_o (dmem_data_o[31:0])
     );


endmodule
