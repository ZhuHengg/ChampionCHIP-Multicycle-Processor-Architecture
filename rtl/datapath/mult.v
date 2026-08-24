// mult.v
// Guide §3.1.2, Table 10. 32x32 -> 64-bit multiply, mux selects result half.
// Combinational, single cycle (handoff decision #1) — no MUL_WAIT state,
// no done handshake. Do not add one without an explicit area-tradeoff
// decision to do so.
//
// SYNTHESIS NOTE: full combinational 64-bit multiplier is the biggest area
// risk in the project (build plan §mult.v). Flag in OpenLane area report
// (report §5) once available; do not pre-optimize to an iterative version
// before measuring.

`include "pkg/rvbl2_defines.vh"

module mult (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  mult_op_i,
    output reg  [31:0] result_o
);

    // Each signedness combination extended to 64 bits independently before
    // multiplying — MULHSU is rs1 signed x rs2 unsigned, mixed extension.
    wire signed [63:0] p_ss = $signed(a_i) * $signed(b_i);                       // signed x signed
    wire signed [63:0] p_su = $signed({{32{a_i[31]}}, a_i}) * $signed({32'b0, b_i}); // signed x unsigned
    wire        [63:0] p_uu = a_i * b_i;                                         // unsigned x unsigned

    always @(*) begin
        result_o = 32'b0; // default
        case (mult_op_i)
            `MULT_MUL:    result_o = p_ss[31:0];  // low half identical regardless of signedness
            `MULT_MULH:   result_o = p_ss[63:32];
            `MULT_MULHSU: result_o = p_su[63:32];
            `MULT_MULHU:  result_o = p_uu[63:32];
            default:      result_o = 32'b0;
        endcase
    end

endmodule
