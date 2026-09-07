// result_src_mem_eq.v
// Canvas-only glue block. top_structural.v (main rtl/) wires
// reg_mem_result.en_i to the inline expression
// (result_src_o == `RESULT_SRC_MEM) directly at the instance port;
// ChipInventor blocks only connect port-to-port with no inline-
// expression nets, so that comparison needs its own block here.
// RESULT_SRC_MEM = 3'b011 (Table in control_unit_eq26.v). Combinational,
// single comparison -- not a new architectural signal, just the same
// logic top_structural.v computes inline, given a home.
module result_src_mem_eq (
    input  wire [2:0] result_src_i,
    output wire       is_result_src_mem_o
);
    localparam [2:0] RESULT_SRC_MEM = 3'b011;
    assign is_result_src_mem_o = (result_src_i == RESULT_SRC_MEM);
endmodule
