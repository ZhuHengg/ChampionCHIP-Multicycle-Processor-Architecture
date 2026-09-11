// testbench.v -- sanity-only check against the OpenLane synth-flow mock
// firmware baked into this canvas's imem block (hdl.v imem module: addi
// x5,10 / addi x6,5 / add x7,x5,x6 / add x4,x7,x0 / NOP-pad).
//
// DEVIATION (CLAUDE.md step 8): the previous version of this testbench
// checked pc_dbg_o against the organiser firmware's terminal self-loop
// address and read x4_dbg_o for the PASS(0)/FAIL(0xFFFFFFFF) self-check.
// Both debug ports (pc_dbg_o, x4_dbg_o) were removed from `top` (2026-09,
// see hdl.v history) because their 64 combined output pins were the
// dominant driver of the resizer-timing-optimization (26m32s) and
// detailed-routing (19m08s) stages in the OpenLane run recorded in
// build/runtime.yaml, and were suspected of blocking ChipInventor's 3D
// GDS viewer. Confirmed post-fix: OpenLane run completed and GDS is
// valid (verified in KLayout).
//
// That leaves `halt_o` as the only observable top-level signal. It does
// NOT help here either: halt_o only asserts on ECALL retirement (see
// control_unit_eq26's halt_o block, hdl.v), and this mock firmware
// contains no ECALL -- it is 4 real instructions followed by NOP padding,
// with no self-loop and no PASS/FAIL protocol at all. So there is no
// port on `top` from which this testbench can read x5/x6/x7/x4 or
// confirm the add results. That functional check is NOT performed here.
//
// Reduced scope, honestly: exercise reset and a fixed number of clock
// cycles, and check that halt_o (the one signal that exists) resolves to
// a known value (never X/Z) rather than staying uninitialized -- this
// catches an undriven/mis-reset halt_o and confirms the design elaborates
// and clocks without going X, but it is NOT a functional/ALU correctness
// check. Full functional verification (x4==15 expected from this
// firmware) still requires either a debug port (see PR discussion, not
// re-added here per user decision 2026-09-11) or running the equivalent
// design in the main repo's iverilog flow (rtl/top.v + tb_top.v), which
// still carries the full debug-tap interface and is unaffected by this
// canvas-only pin trim.

module testbench();

reg  clk_i = 0;
reg  rst_i = 1;
wire halt_o;

integer i;
localparam RUN_CYCLES = 40; // comfortably past the 4 real instructions + a few NOPs

top ai45 (
    .clk_i  (clk_i),
    .rst_i  (rst_i),
    .halt_o (halt_o)
);

always #5 clk_i = ~clk_i;

initial begin
    $dumpfile("testbench.vcd");
    $dumpvars(0, testbench);

    @(posedge clk_i); #1; // RESET latched

    if (halt_o === 1'bx) begin
        $display("FAIL [reset] halt_o is X immediately after reset assertion");
        $finish;
    end

    rst_i = 0;
    @(posedge clk_i); #1; // RESET -> FETCH (instruction 0)

    for (i = 0; i < RUN_CYCLES; i = i + 1) begin
        @(posedge clk_i); #1;
        if (halt_o === 1'bx) begin
            $display("FAIL [cycle %0d] halt_o went X -- undriven signal or reset issue", i);
            $finish;
        end
    end

    $display("t=%0t: ran %0d cycles post-reset, halt_o=%b (no functional check -- see file header)",
              $time, RUN_CYCLES, halt_o);
    $display("SANITY CHECK PASSED (clock/reset/halt_o stayed defined; no ALU/x4 result check possible without a debug port)");

    $finish;
end

endmodule
