// =============================================================================
// Module: mux_alu_b
// Description: 3-to-1 ALU Operand B Multiplexer. Selects between Register rs2,
//              Immediate (imm), and Constant 4 (for PC+4 incrementing).
// =============================================================================

module mux_alu_b (
    input  wire [1:0]  alu_src_b_i,   // 2'b00: RS2, 2'b01: Immediate, 2'b10: Constant 4
    input  wire [31:0] rs2_data_i,    // Data from RegFile rs2
    input  wire [31:0] imm_i,         // Extended immediate from imm_extend
    output reg  [31:0] b_o            // Operand B into ALU
);

    always @(*) begin
        case (alu_src_b_i)
            2'b00:   b_o = rs2_data_i;
            2'b01:   b_o = imm_i;
            2'b10:   b_o = 32'd4;
            default: b_o = rs2_data_i;
        endcase
    end

endmodule
