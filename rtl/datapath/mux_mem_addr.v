// =============================================================================
// Module: mux_mem_addr
// Description: 2-to-1 Memory Address Multiplexer. Selects whether the memory
//              system accesses PC (during Fetch) or ALU_Out (during Load/Store).
// =============================================================================

module mux_mem_addr (
    input  wire        adr_src_i,     // 0: PC, 1: ALU_Out
    input  wire [31:0] pc_i,          // Current PC address (Fetch)
    input  wire [31:0] alu_out_i,     // Calculated memory address (Load/Store)
    output wire [31:0] address_o      // Address sent to address_decoder
);

    assign address_o = adr_src_i ? alu_out_i : pc_i;

endmodule
