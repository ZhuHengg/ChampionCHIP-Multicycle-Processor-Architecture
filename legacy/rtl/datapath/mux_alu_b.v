// mux_alu_b.v — ALU operand B mux (rs2 / imm / const4)

module mux_alu_b (
    input  wire [1:0]  alu_src_b_i,
    input  wire [31:0] rs2_data_i,
    input  wire [31:0] imm_i,
    output reg  [31:0] b_o
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
