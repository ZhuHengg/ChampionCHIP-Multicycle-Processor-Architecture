// imem.v — instruction ROM at IMEM_BASE, combinational read, no write port

module imem #(
    parameter DEPTH_WORDS = 1024,
    parameter INIT_FILE   = ""
) (
    input  wire        clk_i,
    input  wire [31:0] addr_i,
    input  wire        oe_i,
    output wire [31:0] data_o
);

    localparam IDX_W = $clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];

    wire [IDX_W-1:0] index = addr_i[IDX_W-1:0];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // Combinational read — matches FETCH asserting oe_o and latching IR same cycle
    assign data_o = oe_i ? mem[index] : 32'b0;

endmodule
