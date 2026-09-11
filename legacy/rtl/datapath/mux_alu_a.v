// mux_alu_a.v — ALU operand A mux (rs1 / old_pc)

module mux_alu_a (
    input  wire        alu_src_a_i,
    input  wire [31:0] rs1_data_i,
    input  wire [31:0] old_pc_i,
    output wire [31:0] a_o
);

    assign a_o = alu_src_a_i ? old_pc_i : rs1_data_i;

endmodule
