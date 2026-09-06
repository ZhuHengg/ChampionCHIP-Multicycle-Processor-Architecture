// address_decoder.v — routes core mem requests to IMEM/DMEM, muxes read data back
// No store-data port: bypasses decoder, wired LSU->DMEM directly at top.v (guide Fig 3).
// Unmapped address: returns zero, no bus error (guide silent on behavior).

module address_decoder (
    input  wire [31:0] address_i,
    input  wire        we_i,
    input  wire        oe_i,
    input  wire [3:0]  bw_i,

    input  wire [31:0] dmem_data_i,
    input  wire [31:0] imem_data_i,

    output wire [31:0] address_o,     // word address (zero-extended)
    output wire        dmem_we_o,
    output wire        dmem_oe_o,
    output wire        imem_oe_o,
    output wire [3:0]  bw_o,
    output reg  [31:0] data_o
);

    localparam [31:0] IMEM_BASE = 32'h0040_0000;
    localparam [31:0] DMEM_BASE = 32'h1001_0000;

    localparam [31:0] IMEM_LOW  = IMEM_BASE;
    localparam [31:0] IMEM_HIGH = IMEM_BASE + 32'h0040_0000 - 1; // +4MB
    localparam [31:0] DMEM_LOW  = DMEM_BASE;
    localparam [31:0] DMEM_HIGH = DMEM_BASE + 32'h0000_2000 - 1; // +8kB

    wire is_imem = (address_i >= IMEM_LOW) && (address_i <= IMEM_HIGH);
    wire is_dmem = (address_i >= DMEM_LOW) && (address_i <= DMEM_HIGH);

    assign address_o = {2'b00, address_i[31:2]};

    assign dmem_we_o = we_i && is_dmem;
    assign dmem_oe_o = oe_i && is_dmem;
    assign imem_oe_o = oe_i && is_imem;
    assign bw_o      = is_dmem ? bw_i : 4'b0000;

    always @(*) begin
        data_o = 32'b0; // default: unmapped address
        if (is_dmem)
            data_o = dmem_data_i;
        else if (is_imem)
            data_o = imem_data_i;
    end

endmodule
