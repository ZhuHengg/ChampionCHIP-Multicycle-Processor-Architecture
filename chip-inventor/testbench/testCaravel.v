 entrou module top ( ---( 
 module 
  --- 
  
   input wire clk_i, ---inputwireclk_i, 
 clk_i 
   input wire rst_i, ---inputwirerst_i, 
 rst_i 
   output wire halt_o ---outputwirehalt_o 
 halt_o 
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
  
  wire w_6; ---w_6; 
  
  wire [31:0] w_7; ---[31:0]w_7; 
  
  wire [31:0] w_9; ---[31:0]w_9; 
  
  wire [31:0] w_11; ---[31:0]w_11; 
  
  wire w_13; ---w_13; 
  
  wire [31:0] w_14; ---[31:0]w_14; 
  
  wire [31:0] w_15; ---[31:0]w_15; 
  
  wire [6:0] w_16; ---[6:0]w_16; 
  
  wire [4:0] w_17; ---[4:0]w_17; 
  
  wire [2:0] w_18; ---[2:0]w_18; 
  
  wire [4:0] w_20; ---[4:0]w_20; 
  
  wire [4:0] w_21; ---[4:0]w_21; 
  
  wire [6:0] w_22; ---[6:0]w_22; 
  
  wire [11:0] w_23; ---[11:0]w_23; 
  
  wire [2:0] w_24; ---[2:0]w_24; 
  
  wire [31:0] w_25; ---[31:0]w_25; 
  
  wire w_26; ---w_26; 
  
  wire [31:0] w_27; ---[31:0]w_27; 
  
  wire [31:0] w_28; ---[31:0]w_28; 
  
  wire [1:0] w_29; ---[1:0]w_29; 
  
  wire [31:0] w_30; ---[31:0]w_30; 
  
  wire [31:0] w_31; ---[31:0]w_31; 
  
  wire [3:0] w_32; ---[3:0]w_32; 
  
  wire [31:0] w_34; ---[31:0]w_34; 
  
  wire [1:0] w_37; ---[1:0]w_37; 
  
  wire [3:0] w_40; ---[3:0]w_40; 
  
  wire [31:0] w_41; ---[31:0]w_41; 
  
  wire [3:0] w_44; ---[3:0]w_44; 
  
  wire [31:0] w_45; ---[31:0]w_45; 
  
  wire w_46; ---w_46; 
  
  wire [31:0] w_47; ---[31:0]w_47; 
  
  wire w_48; ---w_48; 
  
  wire [31:0] w_49; ---[31:0]w_49; 
  
  wire w_50; ---w_50; 
  
  wire w_51; ---w_51; 
  
  wire [3:0] w_52; ---[3:0]w_52; 
  
  wire [31:0] w_53; ---[31:0]w_53; 
  
  wire [31:0] w_54; ---[31:0]w_54; 
  
  wire [31:0] w_55; ---[31:0]w_55; 
  
  wire w_57; ---w_57; 
  
  wire w_58; ---w_58; 
  
  wire w_59; ---w_59; 
  
  wire [3:0] w_60; ---[3:0]w_60; 
  
  wire [31:0] w_62; ---[31:0]w_62; 
  
  wire [2:0] w_64; ---[2:0]w_64; 
  
  wire [31:0] w_65; ---[31:0]w_65; 
  
  wire [2:0] w_66; ---[2:0]w_66; 
  
  wire [31:0] w_67; ---[31:0]w_67; 
  
  wire [31:0] w_68; ---[31:0]w_68; 
  
  wire w_69; ---w_69; 
  
  wire w_70; ---w_70; 
  
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
  
 fetch_registers #(.PC_RESET_ADDR(32'h00400000)) blk3804_13 ( ---blk3804_13( 
 fetch_registers 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .pc_o (w_2), --- 
  
          .pc_next_i (w_4), --- 
  
          .pc_write_i (w_5), --- 
  
          .ir_write_i (w_6), --- 
  
          .mem_data_i (w_7), --- 
  
          .old_pc_o (w_9), --- 
  
          .ir_o (w_11) --- 
  
      ); --- 
  
  --- 
  
 mux_mem_addr blk3808_14 ( ---( 
 mux_mem_addr 
          .pc_i (w_2), --- 
  
          .adr_src_i (w_13), --- 
  
          .alu_out_i (w_14), --- 
  
          .address_o (w_15) --- 
  
      ); --- 
  
  --- 
  
 ir_splitter_eq26 blk3781_15 ( ---( 
 ir_splitter_eq26 
          .instr_i (w_11), --- 
  
          .opcode_o (w_16), --- 
  
          .rd_o (w_17), --- 
  
          .funct3_o (w_18), --- 
  
          .rs1_o (w_20), --- 
  
          .rs2_o (w_21), --- 
  
          .funct7_o (w_22), --- 
  
          .funct12_o (w_23) --- 
  
      ); --- 
  
  --- 
  
 imm_extend_eq26 blk3556_17 ( ---( 
 imm_extend_eq26 
          .instr_i (w_11), --- 
  
          .imm_sel_i (w_24), --- 
  
          .imm_o (w_25) --- 
  
      ); --- 
  
  --- 
  
 mux_alu_a blk3795_18 ( ---( 
 mux_alu_a 
          .old_pc_i (w_9), --- 
  
          .alu_src_a_i (w_26), --- 
  
          .rs1_data_i (w_27), --- 
  
          .a_o (w_28) --- 
  
      ); --- 
  
  --- 
  
 mux_alu_b blk3796_19 ( ---( 
 mux_alu_b 
          .imm_i (w_25), --- 
  
          .alu_src_b_i (w_29), --- 
  
          .rs2_data_i (w_30), --- 
  
          .b_o (w_31) --- 
  
      ); --- 
  
  --- 
  
 alu_eq26 blk3550_20 ( ---( 
 alu_eq26 
          .result_o (w_3), --- 
  
          .a_i (w_28), --- 
  
          .b_i (w_31), --- 
  
          .alu_op_i (w_32) --- 
  
      ); --- 
  
  --- 
  
 alu_out_reg #(.RESET_VALUE(32'h00000000)) blk3811_21 ( ---blk3811_21( 
 alu_out_reg 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .en_i (1'b1), --- 
  
          .alu_out_o (w_14), --- 
  
          .alu_result_i (w_3), --- 
  
          .addr_lsb_o (w_37) --- 
  
      ); --- 
  
  --- 
  
 mult_eq26 blk3557_22 ( ---( 
 mult_eq26 
          .a_i (w_27), --- 
  
          .b_i (w_30), --- 
  
          .mult_op_i (w_40), --- 
  
          .result_o (w_41) --- 
  
      ); --- 
  
  --- 
  
 crc_eq26 #(.POLY(16'h1021), .XOR_OUT(16'h0000)) blk3553_23 ( ---.XOR_OUT(16'h0000))blk3553_23( 
 (crc_eq26 
          .a_i (w_27), --- 
  
          .b_i (w_30), --- 
  
          .crc_op_i (w_44), --- 
  
          .result_o (w_45) --- 
  
      ); --- 
  
  --- 
  
 reg32_dff_eq26 #(.RESET_VALUE(32'h00000000)) blk3722_24 ( ---blk3722_24( 
 reg32_dff_eq26 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .d_i (w_41), --- 
  
          .en_i (w_46), --- 
  
          .q_o (w_47) --- 
  
      ); --- 
  
  --- 
  
 reg32_dff_eq26 #(.RESET_VALUE(32'h00000000)) blk3722_25 ( ---blk3722_25( 
 reg32_dff_eq26 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .d_i (w_45), --- 
  
          .en_i (w_48), --- 
  
          .q_o (w_49) --- 
  
      ); --- 
  
  --- 
  
 address_decoder blk3566_26 ( ---( 
 address_decoder 
          .data_o (w_7), --- 
  
          .address_i (w_15), --- 
  
          .we_i (w_50), --- 
  
          .oe_i (w_51), --- 
  
          .bw_i (w_52), --- 
  
          .dmem_data_i (w_53), --- 
  
          .imem_data_i (w_54), --- 
  
          .address_o (w_55), --- 
  
          .dmem_we_o (w_57), --- 
  
          .dmem_oe_o (w_58), --- 
  
          .imem_oe_o (w_59), --- 
  
          .bw_o (w_60) --- 
  
      ); --- 
  
  --- 
  
 imem blk3564_28 ( ---( 
 imem 
          .clk_i (clk_i), --- 
  
          .data_o (w_54), --- 
  
          .addr_i (w_55), --- 
  
          .oe_i (w_59) --- 
  
      ); --- 
  
  --- 
  
 dmem_eq26 #(.DEPTH_WORDS(2048)) blk3565_29 ( ---blk3565_29( 
 dmem_eq26 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .data_o (w_53), --- 
  
          .addr_i (w_55), --- 
  
          .we_i (w_57), --- 
  
          .oe_i (w_58), --- 
  
          .bw_i (w_60), --- 
  
          .data_i (w_62) --- 
  
      ); --- 
  
  --- 
  
 lsu_eq26 blk3562_30 ( ---( 
 lsu_eq26 
          .core_address_o (w_14), --- 
  
          .mem_data_o (w_7), --- 
  
          .mem_data_i (w_62), --- 
  
          .core_data_o (w_30), --- 
  
          .op_size_o (w_64), --- 
  
          .core_data_i (w_65) --- 
  
      ); --- 
  
  --- 
  
 mux_result blk3724_31 ( ---( 
 mux_result 
          .old_pc_i (w_9), --- 
  
          .alu_out_i (w_14), --- 
  
          .mult_result_i (w_47), --- 
  
          .crc_result_i (w_49), --- 
  
          .result_src_i (w_66), --- 
  
          .mem_result_i (w_67), --- 
  
          .result_o (w_68) --- 
  
      ); --- 
  
  --- 
  
 reg32_dff_eq26 #(.RESET_VALUE(32'h00000000)) blk3722_32 ( ---blk3722_32( 
 reg32_dff_eq26 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .en_i (1'b1), --- 
  
          .d_i (w_65), --- 
  
          .q_o (w_67) --- 
  
      ); --- 
  
  --- 
  
 control_unit_eq26 blk3567_33 ( ---( 
 control_unit_eq26 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .halt_o (halt_o), --- 
  
          .pc_src_o (w_1), --- 
  
          .pc_write_o (w_5), --- 
  
          .ir_write_o (w_6), --- 
  
          .adr_src_o (w_13), --- 
  
          .opcode_i (w_16), --- 
  
          .funct3_i (w_18), --- 
  
          .funct7_i (w_22), --- 
  
          .funct12_i (w_23), --- 
  
          .imm_sel_o (w_24), --- 
  
          .alu_src_a_o (w_26), --- 
  
          .alu_src_b_o (w_29), --- 
  
          .alu_op_o (w_32), --- 
  
          .addr_lsb_i (w_37), --- 
  
          .mult_op_o (w_40), --- 
  
          .crc_op_o (w_44), --- 
  
          .mult_en_o (w_46), --- 
  
          .crc_en_o (w_48), --- 
  
          .we_o (w_50), --- 
  
          .oe_o (w_51), --- 
  
          .bw_o (w_52), --- 
  
          .op_size_o (w_64), --- 
  
          .result_src_o (w_66), --- 
  
          .branch_taken_i (w_69), --- 
  
          .reg_write_o (w_70) --- 
  
      ); --- 
  
  --- 
  
 branch_comparator_eq26 blk3552_34 ( ---( 
 branch_comparator_eq26 
          .funct3_i (w_18), --- 
  
          .branch_taken_o (w_69) --- 
  
      ); --- 
  
  --- 
  
 regfile_eq blk3560_40 ( ---( 
 regfile_eq 
          .clk_i (clk_i), --- 
  
          .rst_i (rst_i), --- 
  
          .rd_addr_i (w_17), --- 
  
          .rs1_addr_i (w_20), --- 
  
          .rs2_addr_i (w_21), --- 
  
          .rs1_data_o (w_27), --- 
  
          .rs2_data_o (w_30), --- 
  
          .write_data_i (w_68), --- 
  
          .reg_write_i (w_70) --- 
  
      ); --- 
  
  --- 
  
  --- 
  
 endmodule --- 
 endmodule 
  --- 
  
