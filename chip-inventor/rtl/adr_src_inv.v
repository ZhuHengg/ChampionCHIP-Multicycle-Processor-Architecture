// adr_src_inv.v
// Canvas-only glue block. top_structural.v (main rtl/) wires
// alu_out_reg.en_i to the inline expression !adr_src_o directly at the
// instance port; ChipInventor blocks only connect port-to-port with no
// inline-expression nets, so that inversion needs its own block here.
// Combinational, single gate -- not a new architectural signal, just
// the same logic top_structural.v computes inline, given a home.
module adr_src_inv (
    input  wire adr_src_i,
    output wire not_adr_src_o
);
    assign not_adr_src_o = !adr_src_i;
endmodule
