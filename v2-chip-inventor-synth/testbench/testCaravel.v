 entrou module top ( ---( 
 module 
  --- 
  
   input wire clk_i, ---inputwireclk_i, 
 clk_i 
   input wire rst_i, ---inputwirerst_i, 
 rst_i 
   output wire halt_o, ---outputwirehalt_o, 
 halt_o 
   output wire [31:0] 31, ---outputwire[31:0] 
 31 
   output wire [31:0] 31 ---outputwire[31:0] 
 31 
  --- 
  
 ); --- 
 ); 
  --- 
  
 //Internal Wires --- 
 //Internal 
  wire [1:0] w_1; ---[1:0]w_1; 
  
  wire [31:0] w_2; ---[31:0]w_2; 
  
  wire [31:0] w_3; ---[31:0]w_3; 
  
  wire [31:0] w_4; ---[31:0]w_4; 
  
  wire w_5; ---w_5; 
  
  wire [31:0] w_7; ---[31:0]w_7; 
  
  wire [31:0] w_8; ---[31:0]w_8; 
  
  wire [31:0] w_9; ---[31:0]w_9; 
  
  wire [6:0] w_10; ---[6:0]w_10; 
  
  wire [4:0] w_11; ---[4:0]w_11; 
  
  wire [2:0] w_12; ---[2:0]w_12; 
  
  wire [4:0] w_14; ---[4:0]w_14; 
  
  wire [4:0] w_15; ---[4:0]w_15; 
  
  wire [6:0] w_16; ---[6:0]w_16; 
  
  wire [11:0] w_17; ---[11:0]w_17; 
  
  wire [2:0] w_19; ---[2:0]w_19; 
  
  wire [31:0] w_20; ---[31:0]w_20; 
  
  wire w_21; ---w_21; 
  
  wire [31:0] w_22; ---[31:0]w_22; 
  
  wire [31:0] w_23; ---[31:0]w_23; 
  
  wire [31:0] w_24; ---[31:0]w_24; 
  
  wire [1:0] w_25; ---[1:0]w_25; 
  
  wire [31:0] w_26; ---[31:0]w_26; 
  
  wire [31:0] w_27; ---[31:0]w_27; 
  
  wire [3:0] w_28; ---[3:0]w_28; 
  
  wire [31:0] w_30; ---[31:0]w_30; 
  
  wire [1:0] w_33; ---[1:0]w_33; 
  
  wire [3:0] w_36; ---[3:0]w_36; 
  
  wire [31:0] w_37; ---[31:0]w_37; 
  
  wire [3:0] w_40; ---[3:0]w_40; 
  
  wire [31:0] w_41; ---[31:0]w_41; 
  
  wire w_42; ---w_42; 
  
  wire [31:0] w_43; ---[31:0]w_43; 
  
  wire w_44; ---w_44; 
  
  wire [31:0] w_45; ---[31:0]w_45; 
  
  wire [31:0] w_46; ---[31:0]w_46; 
  
  wire w_47; ---w_47; 
  
  wire [31:0] w_48; ---[31:0]w_48; 
  
  wire w_50; ---w_50; 
  
  wire w_51; ---w_51; 
  
  wire [3:0] w_52; ---[3:0]w_52; 
  
  wire [31:0] w_53; ---[31:0]w_53; 
  
  wire [31:0] w_54; ---[31:0]w_54; 
  
  wire [2:0] w_56; ---[2:0]w_56; 
  
  wire [31:0] w_57; ---[31:0]w_57; 
  
  wire [31:0] w_58; ---[31:0]w_58; 
  
  wire [2:0] w_59; ---[2:0]w_59; 
  
  wire [31:0] w_60; ---[31:0]w_60; 
  
  wire [31:0] w_62; ---[31:0]w_62; 
  
  wire w_63; ---w_63; 
  
  wire w_64; ---w_64; 
  
  wire w_65; ---w_65; 
  
  wire w_66; ---w_66; 
  
  wire w_70; ---w_70; 
  
  wire w_71; ---w_71; 
  
  wire [3:0] w_72; ---[3:0]w_72; 
  
  --- 
  
 //Interface Assigns --- 
 //Interface 
 assign [31:0] pg_dbg_o = w_2; ---pg_dbg_o=w_2; 
 w_2;assign 
  --- 
  
 //Instances of Modules ---Modules 
 //Instances 
 mux_pc_next blk3807_12 ( ---( 
 mux_pc_next 
          .pc_src_i (w_1), --- 
  
          .pc_i (w_2), --- 
  
          .alu_result_i (w_3), --- 
  
          .pc_next_o (w_4) --- 
  
      ); --- 
  
  --- 
  
 mux_mem_addr blk3808_14 ( ---( 
 mux_mem_addr 
          .adr_src_i (w_5), --- 
  
          .pc_i (w_2), --- 
  
          .alu_out_i (w_7), --- 
  
          .address_o (w_8) --- 
  
      ); --- 
  
  --- 
  
 ir_splitter_eq26 blk3781_15 ( ---( 
 ir_splitter_eq26 
          .instr_i (w_9), --- 
  
          .opcode_o (w_10), --- 
  
          .rd_o (w_11), --- 
  
          .funct3_o (w_12), --- 
  
          .rs1_o (w_14), --- 
  
          .rs2_o (w_15), --- 
  
          .funct7_o (w_16), --- 
  
          .funct12_o (w_17) --- 
  
      ); --- 
  
  --- 
  
 imm_extend_eq26 blk3556_17 ( ---( 
 imm_extend_eq26 
          .instr_i (w_9), --- 
  
          .imm_sel_i (w_19), --- 
  
          .imm_o (w_20) --- 
  
      ); --- 
  
  --- 
  
 mux_alu_a blk3795_18 ( ---( 
 mux_alu_a 
          .alu_src_a_i (w_21), --- 
  
          .rs1_data_i (w_22), --- 
  
          .old_pc_i (w_23), --- 
  
          .a_o (w_24) --- 
  
      ); --- 
  
  --- 
  
 mux_alu_b blk3796_19 ( ---( 
 mux_alu_b 
          .imm_i (w_20), --- 
  
          .alu_src_b_i (w_25), --- 
  
          .rs2_data_i (w_26), --- 
  
          .b_o (w_27) --- 
  
      ); --- 
  
  --- 
  
 alu_eq26 blk3550_20 ( ---( 
 alu_eq26 
          .result_o (w_3), --- 
  
          .a_i (w_24), --- 
  
          .b_i (w_27), --- 
  
          .alu_op_i (w_28) --- 
  
      ); --- 
  
  --- 
  
 alu_out_reg #(.RESET_VALUE(32'h00000000)) blk3811_21 ( ---blk3811_21( 
 alu_out_reg 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .en_i (1'b1), --- 
  
          .alu_out_o (w_7), --- 
  
          .alu_result_i (w_3), --- 
  
          .addr_lsb_o (w_33) --- 
  
      ); --- 
  
  --- 
  
 mult_eq26 blk3557_22 ( ---( 
 mult_eq26 
          .a_i (w_22), --- 
  
          .b_i (w_26), --- 
  
          .mult_op_i (w_36), --- 
  
          .result_o (w_37) --- 
  
      ); --- 
  
  --- 
  
 crc_eq26 #(.POLY(16'h1021), .XOR_OUT(16'h0000)) blk3553_23 ( ---.XOR_OUT(16'h0000))blk3553_23( 
 (crc_eq26 
          .a_i (w_22), --- 
  
          .b_i (w_26), --- 
  
          .crc_op_i (w_40), --- 
  
          .result_o (w_41) --- 
  
      ); --- 
  
  --- 
  
 reg32_dff_eq26 #(.RESET_VALUE(32'h00000000)) blk3722_24 ( ---blk3722_24( 
 reg32_dff_eq26 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .d_i (w_37), --- 
  
          .en_i (w_42), --- 
  
          .q_o (w_43) --- 
  
      ); --- 
  
  --- 
  
 reg32_dff_eq26 #(.RESET_VALUE(32'h00000000)) blk3722_25 ( ---blk3722_25( 
 reg32_dff_eq26 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .d_i (w_41), --- 
  
          .en_i (w_44), --- 
  
          .q_o (w_45) --- 
  
      ); --- 
  
  --- 
  
 imem blk3564_28 ( ---( 
 imem 
          .clk_i (clk_i), --- 
  
          .addr_i (w_46), --- 
  
          .oe_i (w_47), --- 
  
          .data_o (w_48) --- 
  
      ); --- 
  
  --- 
  
 dmem_eq26 #(.DEPTH_WORDS(2048)) blk3565_29 ( ---blk3565_29( 
 dmem_eq26 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .addr_i (w_46), --- 
  
          .we_i (w_50), --- 
  
          .oe_i (w_51), --- 
  
          .bw_i (w_52), --- 
  
          .data_i (w_53), --- 
  
          .data_o (w_54) --- 
  
      ); --- 
  
  --- 
  
 lsu_eq26 blk3562_30 ( ---( 
 lsu_eq26 
          .core_address_o (w_7), --- 
  
          .mem_data_i (w_53), --- 
  
          .core_data_o (w_26), --- 
  
          .op_size_o (w_56), --- 
  
          .mem_data_o (w_57), --- 
  
          .core_data_i (w_58) --- 
  
      ); --- 
  
  --- 
  
 mux_result blk3724_31 ( ---( 
 mux_result 
          .alu_out_i (w_7), --- 
  
          .mult_result_i (w_43), --- 
  
          .crc_result_i (w_45), --- 
  
          .result_src_i (w_59), --- 
  
          .mem_result_i (w_60), --- 
  
          .old_pc_i (w_23), --- 
  
          .result_o (w_62) --- 
  
      ); --- 
  
  --- 
  
 reg32_dff_eq26 #(.RESET_VALUE(32'h00000000)) blk3722_32 ( ---blk3722_32( 
 reg32_dff_eq26 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .en_i (1'b1), --- 
  
          .d_i (w_58), --- 
  
          .q_o (w_60) --- 
  
      ); --- 
  
  --- 
  
 branch_comparator_eq26 blk3552_34 ( ---( 
 branch_comparator_eq26 
          .funct3_i (w_12), --- 
  
          .branch_taken_o (w_63) --- 
  
      ); --- 
  
  --- 
  
 regfile_eq blk3560_44 ( ---( 
 regfile_eq 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .x4_dbg_o ([31:0] x4_dbg_o), --- 
  
          .rd_addr_i (w_11), --- 
  
          .rs1_addr_i (w_14), --- 
  
          .rs2_addr_i (w_15), --- 
  
          .rs1_data_o (w_22), --- 
  
          .rs2_data_o (w_26), --- 
  
          .write_data_i (w_62), --- 
  
          .reg_write_i (w_64) --- 
  
      ); --- 
  
  --- 
  
 fetch_registers #(.PC_RESET_ADDR(32'h00400000)) blk3804_45 ( ---blk3804_45( 
 fetch_registers 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .pc_o (w_2), --- 
  
          .pc_next_i (w_4), --- 
  
          .ir_o (w_9), --- 
  
          .old_pc_o (w_23), --- 
  
          .pc_write_i (w_65), --- 
  
          .ir_write_i (w_66), --- 
  
          .mem_data_i (w_57) --- 
  
      ); --- 
  
  --- 
  
 control_unit_eq26 blk3567_46 ( ---( 
 control_unit_eq26 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .halt_o (halt_o), --- 
  
          .pc_src_o (w_1), --- 
  
          .adr_src_o (w_5), --- 
  
          .opcode_i (w_10), --- 
  
          .funct3_i (w_12), --- 
  
          .funct7_i (w_16), --- 
  
          .funct12_i (w_17), --- 
  
          .imm_sel_o (w_19), --- 
  
          .alu_src_a_o (w_21), --- 
  
          .alu_src_b_o (w_25), --- 
  
          .alu_op_o (w_28), --- 
  
          .addr_lsb_i (w_33), --- 
  
          .mult_op_o (w_36), --- 
  
          .crc_op_o (w_40), --- 
  
          .mult_en_o (w_42), --- 
  
          .crc_en_o (w_44), --- 
  
          .op_size_o (w_56), --- 
  
          .result_src_o (w_59), --- 
  
          .branch_taken_i (w_63), --- 
  
          .reg_write_o (w_64), --- 
  
          .pc_write_o (w_65), --- 
  
          .ir_write_o (w_66), --- 
  
          .we_o (w_70), --- 
  
          .oe_o (w_71), --- 
  
          .bw_o (w_72) --- 
  
      ); --- 
  
  --- 
  
 address_decoder blk3566_47 ( ---( 
 address_decoder 
          .address_i (w_8), --- 
  
          .address_o (w_46), --- 
  
          .imem_oe_o (w_47), --- 
  
          .imem_data_i (w_48), --- 
  
          .dmem_we_o (w_50), --- 
  
          .dmem_oe_o (w_51), --- 
  
          .bw_o (w_52), --- 
  
          .dmem_data_i (w_54), --- 
  
          .data_o (w_57), --- 
  
          .we_i (w_70), --- 
  
          .oe_i (w_71), --- 
  
          .bw_i (w_72) --- 
  
      ); --- 
  
  --- 
  
  --- 
  
 endmodule --- 
 endmodule 
  --- 
  
