module mux_alu_a (
    input  wire        alu_src_a_i,   // 0: RS1 data, 1: Old_PC
    input  wire [31:0] rs1_data_i,    // Data from RegFile rs1
    input  wire [31:0] old_pc_i,      // Saved PC from Old_PC register
    output wire [31:0] a_o            // Operand A into ALU
);

    assign a_o = alu_src_a_i ? old_pc_i : rs1_data_i;

endmodule