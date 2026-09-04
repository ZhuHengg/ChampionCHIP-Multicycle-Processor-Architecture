// imem.v
// Guide §4.2. Instruction ROM at `IMEM_BASE (0x00400000). Read-only — no
// write port exists at all (guide §4.4: "EXCEPT IMEM memory, which cannot
// be written").
//
// Timing: read combinationally (async), NOT registered like DMEM. The
// FSM's FETCH state asserts oe_o and latches into IR in the SAME cycle
// (control_unit.v FETCH: pc_write_o=1, ir_write_o=1, oe_o=1, all in one
// state) — that only works if IMEM data is valid within the cycle.
// FLAG (per MEMORY_BUILD_PLAN.md): the guide itself never states IMEM's
// timing explicitly, unlike DMEM (guide §4.3, explicit "only completed
// after a clock cycle"). This is an assumption forced by the existing FSM
// design, not a literal guide statement. If wrong, FETCH needs a second
// cycle and the FSM changes — flagging per CLAUDE.md step 8/9, not
// silently guessing.
//
// Sizing: guide specifies 4 MB (Table 13). DEPTH_WORDS defaults to 1024
// words (4 kB) per MEMORY_BUILD_PLAN.md — a literal 4 MB ROM makes
// simulation slow and OpenLane area numbers meaningless. Real size can be
// set at top.v/OpenLane time via the parameter. Documented here so an
// evaluator comparing area against the 4 MB spec sees why the default is
// small.
//
// Also holds constants read via ordinary loads (guide §4.2 example:
// `lw` reading 0x00400100) — no special-casing needed, oe_i/addr_i work
// identically whether the access is a fetch or a load.

module imem #(
    parameter DEPTH_WORDS = 1024,
    parameter INIT_FILE   = ""
) (
    input  wire        clk_i,
    input  wire [31:0] addr_i,   // word address (bottom 2 bits already dropped by decoder)
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

    // Combinational (async) read — see timing note above. oe_i gates the
    // output; when negated, drive zero rather than X to keep downstream
    // sim clean (guide is silent on the disabled-read value).
    assign data_o = oe_i ? mem[index] : 32'b0;

endmodule
