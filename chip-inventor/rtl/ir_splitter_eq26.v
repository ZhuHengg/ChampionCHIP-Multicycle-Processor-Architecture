module ir_splitter_eq26(
    input  wire [31:0] instr_i,      // 32-bit instruction from IR register (q_o of reg32)
    output wire [6:0]  opcode_o,     // instr_i[6:0]   -> to control_unit.opcode_i
    output wire [4:0]  rd_o,         // instr_i[11:7]  -> to regfile.rd_addr_i
    output wire [2:0]  funct3_o,     // instr_i[14:12] -> to control_unit & branch_comparator
    output wire [4:0]  rs1_o,        // instr_i[19:15] -> to regfile.rs1_addr_i
    output wire [4:0]  rs2_o,        // instr_i[24:20] -> to regfile.rs2_addr_i
    output wire [6:0]  funct7_o,     // instr_i[31:25] -> to control_unit.funct7_i
    output wire [11:0] funct12_o     // instr_i[31:20] -> to control_unit.funct12_i
);
    assign opcode_o  = instr_i[6:0];
    assign rd_o      = instr_i[11:7];
    assign funct3_o  = instr_i[14:12];
    assign rs1_o     = instr_i[19:15];
    assign rs2_o     = instr_i[24:20];
    assign funct7_o  = instr_i[31:25];
    assign funct12_o = instr_i[31:20];
endmodule