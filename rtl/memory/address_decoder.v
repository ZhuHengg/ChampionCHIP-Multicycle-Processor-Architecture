// address_decoder.v
// Guide §4.4, Figure 3. Routes core memory requests to IMEM or DMEM
// based on address, and muxes the read data back to the core.
//
// - address_o: bottom 2 bits dropped (guide: "ignoring the bottom two
//   bits, alignment at 4 bytes") — both memories are word-addressed.
// - we_o -> DMEM only. IMEM has no write path at all (guide §4.4:
//   "EXCEPT IMEM memory, which cannot be written").
// - oe_o -> both devices.
// - bw_o -> DMEM only (guide: "sends the Byte Write signal ... ONLY to
//   the DMEM memory").
//
// Address ranges (guide Table 13):
//   IMEM: `IMEM_BASE (0x00400000) + 4 MB
//   DMEM: `DMEM_BASE (0x10010000) + 8 kB
//
// Unmapped addresses: guide is silent on behavior. Returns zero, asserts
// nothing — no bus-error mechanism invented. Flagged per CLAUDE.md step
// 8/MEMORY_BUILD_PLAN.md.
//
// FLAG: MEMORY_BUILD_PLAN.md's port table lists a core_data_i input
// (store data heading out) but no corresponding output toward DMEM/IMEM,
// and guide Figure 3 draws the decoder with only address/we/oe/bw
// arrows — no data path through it at all. Read literally, store data
// (LSU's mem_data_i) must wire directly from LSU to DMEM at top.v,
// bypassing the decoder entirely. Omitted that port here rather than
// wiring a dead input with no destination; flagging rather than
// silently guessing a route the guide never draws.

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

    // Memory Map Base Addresses (Guide Table 13)
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
        data_o = 32'b0; // default: unmapped address, guide silent (see header note)
        if (is_dmem)
            data_o = dmem_data_i;
        else if (is_imem)
            data_o = imem_data_i;
    end

endmodule
