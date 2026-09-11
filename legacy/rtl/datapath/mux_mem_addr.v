// mux_mem_addr.v — memory address mux (pc / alu_out)

module mux_mem_addr (
    input  wire        adr_src_i,
    input  wire [31:0] pc_i,
    input  wire [31:0] alu_out_i,
    output wire [31:0] address_o
);

    assign address_o = adr_src_i ? alu_out_i : pc_i;

endmodule
