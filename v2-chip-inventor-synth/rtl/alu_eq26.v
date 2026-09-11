module alu_eq26 (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  alu_op_i,
    output reg  [31:0] result_o
);
    // ALU Operation Codes (Table 9)
    localparam [3:0] ALU_PASS_B = 4'h0;
    localparam [3:0] ALU_ADD    = 4'h1;
    localparam [3:0] ALU_SUB    = 4'h2;
    localparam [3:0] ALU_AND    = 4'h3;
    localparam [3:0] ALU_OR     = 4'h4;
    localparam [3:0] ALU_XOR    = 4'h5;
    localparam [3:0] ALU_SLL    = 4'h6;
    localparam [3:0] ALU_SRL    = 4'h7;
    localparam [3:0] ALU_MRS    = 4'h8; // SRA (arithmetic shift right)
    localparam [3:0] ALU_SLT    = 4'h9; // Set Less Than (signed)
    localparam [3:0] ALU_SLTU   = 4'hA; // Set Less Than Unsigned
    always @(*) begin
        result_o = 32'b0; // default value
        case (alu_op_i)
            ALU_PASS_B: result_o = b_i;
            ALU_ADD:    result_o = a_i + b_i;
            ALU_SUB:    result_o = a_i - b_i;
            ALU_AND:    result_o = a_i & b_i;
            ALU_OR:     result_o = a_i | b_i;
            ALU_XOR:    result_o = a_i ^ b_i;
            ALU_SLL:    result_o = a_i << b_i[4:0];
            ALU_SRL:    result_o = a_i >> b_i[4:0];
            ALU_MRS:    result_o = $signed(a_i) >>> b_i[4:0];
            ALU_SLT:    result_o = ($signed(a_i) < $signed(b_i)) ? 32'd1 : 32'd0;
            ALU_SLTU:   result_o = (a_i < b_i) ? 32'd1 : 32'd0;
            default:    result_o = 32'b0;
        endcase
    end
endmodule