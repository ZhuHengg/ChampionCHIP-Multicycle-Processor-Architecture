// alu.v — combinational ALU

`include "pkg/rvbl2_defines.vh"

module alu (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  alu_op_i,
    output reg  [31:0] result_o
);

    always @(*) begin
        result_o = 32'b0; // default
        case (alu_op_i)
            `ALU_PASS_B: result_o = b_i;
            `ALU_ADD:    result_o = a_i + b_i;
            `ALU_SUB:    result_o = a_i - b_i;
            `ALU_AND:    result_o = a_i & b_i;
            `ALU_OR:     result_o = a_i | b_i;
            `ALU_XOR:    result_o = a_i ^ b_i;
            `ALU_SLL:    result_o = a_i << b_i[4:0];
            `ALU_SRL:    result_o = a_i >> b_i[4:0];
            `ALU_MRS:    result_o = $signed(a_i) >>> b_i[4:0]; // arithmetic shift right
            `ALU_SLT:    result_o = ($signed(a_i) < $signed(b_i)) ? 32'd1 : 32'd0;
            `ALU_SLTU:   result_o = (a_i < b_i) ? 32'd1 : 32'd0;
            default:     result_o = 32'b0;
        endcase
    end

endmodule
