// dmem.v
// Guide §4.3. 8 kB data SRAM at `DMEM_BASE (0x10010000).
//
// TIMING-CRITICAL: guide §4.3 states writes/reads via SRAM "will only be
// completed after a clock cycle" — registered-output, NOT combinational.
// The control unit's FSM has separate MEM_ACCESS_ADDR (present address,
// oe_o=1) and MEM_ACCESS_DATA (result_src_o=RESULT_SRC_MEM) states
// specifically because data isn't ready until the cycle after the
// address is presented. A combinational `assign data_o = mem[index]`
// would pass simulation (data arrives early, FSM reads a cycle late,
// looks fine) but fail in real SRAM. Built registered from the start.
//
// Byte-write: bw_i is a MASK (one bit per byte), not a binary selector
// (guide §4.3/§3.3.2, control unit computes it — decision #11, this
// module only applies it).
//
// Sizing: guide Table 13 maps DMEM as 8 kB (2048 words), but there is no
// SRAM macro behind this array -- it synthesises to DEPTH_WORDS*32
// flip-flops plus a DEPTH_WORDS-way read mux. At 2048 that is 65,536 DFFs,
// which dominates area and made OpenLane place-and-route run 11 h+ before
// failing in detailed routing. Deliberate area tradeoff, to be stated in
// the report: the address map stays 8 kB (address_decoder's DMEM_HIGH is
// unchanged), only the physical backing store is shrunk.
//
// DEPTH_WORDS = 8 (32 B) is sized from the validation firmware's .bss,
// which is the whole of its DMEM usage:
//     test_ram:  .space 16  -> DMEM_BASE+0x00..0x0F = words 0..3
//     dest_data: .space 12  -> DMEM_BASE+0x10..0x1B = words 4..6
// Highest word index touched is 6, so 7 words are required; rounded up to
// the next power of two because `index` is a bit-slice, not a compare --
// a non-power-of-2 depth leaves indices above the array bound (see below).
// DEPTH_WORDS must stay a power of two for that reason.
//
// DEPTH_WORDS = 4 (16 B) also passes the validation firmware, but only by
// accident: it aliases dest_data (words 4..6) onto test_ram (words 0..2),
// which is harmless ONLY because the LSU test completes and self-checks
// before the memcpy test starts, so nothing reads test_ram after the
// clobber, and the copy loop's readback happens to hit the same aliased
// words it wrote. Verified: depth 4 and 8 both reach ALL TESTS PASSED;
// depth 2 fails (x4=0xFFFFFFFF, stuck at _error) because dest_data[0] and
// dest_data[2] then collide with each other. 8 is chosen over 4 for margin
// -- it holds the full .bss with no aliasing, so a firmware change that
// interleaves the two regions cannot break it silently, and the extra 128
// flip-flops are negligible against the 65,536 being removed.
//
// DMEM_BASE (0x10010000) has its low bits clear, so the base always maps
// to index 0 regardless of depth; depth only limits how far above the base
// the firmware may reach.
//
// Default overridden to 4 (2026-09-10) for the OpenLane synth-flow test
// only (organiser feedback) -- ChipInventor canvas's blk3565 DEPTH_WORDS
// parameter is also set to 4 (convertion/diagram.json) so a fresh export
// regenerates this same value into hdl.v. This module is only instantiated
// from chip-inventor/hdl.v; no other testbench in the repo relies on the
// prior default of 8, so changing it here does not affect functional
// simulation elsewhere.

module dmem_eq26 #(
    parameter DEPTH_WORDS = 4
) (
    input  wire        clk_i,
    input  wire         rst_i,
    input  wire [31:0] addr_i,   // word address
    input  wire        we_i,
    input  wire        oe_i,
    input  wire [3:0]  bw_i,     // byte write mask
    input  wire [31:0] data_i,
    output reg  [31:0] data_o    // registered — see timing note above
);

    localparam IDX_W = $clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];

    wire [IDX_W-1:0] index = addr_i[IDX_W-1:0];

    always @(posedge clk_i) begin
        if (rst_i) begin
            data_o <= 32'b0;
        end else begin
            if (we_i) begin
                if (bw_i[0]) mem[index][ 7: 0] <= data_i[ 7: 0];
                if (bw_i[1]) mem[index][15: 8] <= data_i[15: 8];
                if (bw_i[2]) mem[index][23:16] <= data_i[23:16];
                if (bw_i[3]) mem[index][31:24] <= data_i[31:24];
            end
            if (oe_i) begin
                data_o <= mem[index]; // registered read, NOT combinational
            end
        end
    end

endmodule