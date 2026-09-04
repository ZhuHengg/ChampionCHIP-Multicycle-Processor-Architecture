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
// Sizing: DEPTH_WORDS defaults to 2048 words = 8 kB, the guide's real
// size (guide is already small enough not to need shrinking for sim).

module dmem #(
    parameter DEPTH_WORDS = 2048
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
