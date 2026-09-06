// ir_splitter.v — instruction field splitter

module ir_splitter (
    input  wire [31:0] instr_i,
    output wire [6:0]  opcode_o,
    output wire [4:0]  rd_o,
    output wire [2:0]  funct3_o,
    output wire [4:0]  rs1_o,
    output wire [4:0]  rs2_o,
    output wire [6:0]  funct7_o,
    output wire [11:0] funct12_o
);

    assign opcode_o  = instr_i[6:0];
    assign rd_o      = instr_i[11:7];
    assign funct3_o  = instr_i[14:12];
    assign rs1_o     = instr_i[19:15];
    assign rs2_o     = instr_i[24:20];
    assign funct7_o  = instr_i[31:25];
    assign funct12_o = instr_i[31:20];

endmodule
