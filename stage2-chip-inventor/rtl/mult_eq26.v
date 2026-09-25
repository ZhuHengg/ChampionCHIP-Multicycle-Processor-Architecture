// 32x32 combinational multiplier.
module mult_eq26(
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  mult_op_i,
    output reg  [31:0] result_o
);

    // Multiplier Operation Codes (Table 10)
    localparam [3:0] MULT_MUL    = 4'h0;
    localparam [3:0] MULT_MULH   = 4'h1;
    localparam [3:0] MULT_MULHSU = 4'h2;
    localparam [3:0] MULT_MULHU  = 4'h3;

    wire signed [63:0] p_ss = $signed(a_i) * $signed(b_i);                       // signed x signed
    wire signed [63:0] p_su = $signed({{32{a_i[31]}}, a_i}) * $signed({32'b0, b_i}); // signed x unsigned
    wire        [63:0] p_uu = a_i * b_i;                                         // unsigned x unsigned

    always @(*) begin
        result_o = 32'b0; // default
        case (mult_op_i)
            MULT_MUL:    result_o = p_ss[31:0];  // low half identical regardless of signedness
            MULT_MULH:   result_o = p_ss[63:32];
            MULT_MULHSU: result_o = p_su[63:32];
            MULT_MULHU:  result_o = p_uu[63:32];
            default:      result_o = 32'b0;
        endcase
    end

endmodule