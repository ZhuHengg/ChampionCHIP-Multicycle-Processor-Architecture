// testbench.v -- runs the organiser-supplied Stage 2 validation firmware
// (baked into this canvas's imem block -- see hdl.v's imem module header)
// against the ChipInventor wiring of the full multicycle core.
//
// Same pass/fail contract as the main repo's tb/system/tb_top_organiser.v:
// firmware self-loops (`j .`) when done, x4==0 -> PASS, x4==0xFFFFFFFF -> FAIL.
//
// ChipInventor's canvas compiler rejects hierarchical dot-refs into
// instance internals (dut.pc, dut.u_control_unit.state, dut.u_regfile.regs[4]
// all fail elaboration there even though local iverilog accepts them) --
// block instances are opaque outside their own declared ports. So `top`
// (hdl.v) and `regfile_eq` (hdl.v) were each given a debug-only output
// port -- pc_dbg_o and x4_dbg_o -- purely for this testbench to observe
// state through, and this testbench uses only top-level ports.
//
// CYCLE COUNT, not self-loop detection: the organiser firmware contains a
// real backward loop (copy_loop, 3 iterations) before its terminal `j .`,
// so a generic "PC revisited an earlier address" detector cannot tell
// that loop apart from the terminal one without also tracking iteration
// counts. The main repo's rtl/top.v (same firmware, same FSM design) was
// run against tb/system/tb_top_organiser.v and independently confirmed to
// settle at the terminal self-loop (pc=0x004003ec) after exactly 979
// cycles -- see that testbench for the state-based (FSM state ==
// DECODE/FETCH) detection this canvas cannot replicate. This testbench
// reuses that already-verified cycle count directly: run exactly
// EXPECTED_CYCLES, then read x4_dbg_o once settled.

module testbench();

reg  clk_i = 0;
reg  rst_i = 1;
wire halt_o;
wire [31:0] pc_dbg_o;
wire [31:0] x4_dbg_o;

integer errors;
integer i;
localparam EXPECTED_CYCLES = 979; // confirmed against rtl/top.v + tb/system/tb_top_organiser.v
localparam SETTLE_MARGIN   = 20;  // extra cycles run past EXPECTED_CYCLES before sampling x4
localparam EXPECTED_PC     = 32'h004003ec;

top ai45 (
    .clk_i     (clk_i),
    .rst_i     (rst_i),
    .halt_o    (halt_o),
    .pc_dbg_o  (pc_dbg_o),
    .x4_dbg_o  (x4_dbg_o)
);

always #5 clk_i = ~clk_i;

initial begin
    $dumpfile("testbench.vcd");
    $dumpvars(0, testbench);

    errors = 0;

    @(posedge clk_i); #1; // RESET latched

    rst_i = 0;
    @(posedge clk_i); #1; // RESET -> FETCH (instruction 0)

    if (pc_dbg_o !== 32'h00400000) begin
        $display("FAIL [entry pc] exp=00400000 got=%h", pc_dbg_o);
        errors = errors + 1;
    end

    for (i = 0; i < EXPECTED_CYCLES + SETTLE_MARGIN - 1; i = i + 1)
        @(posedge clk_i);
    #1;

    $display("t=%0t: pc=%h x4=%h (after %0d cycles)",
              $time, pc_dbg_o, x4_dbg_o, EXPECTED_CYCLES + SETTLE_MARGIN);

    if (pc_dbg_o !== EXPECTED_PC) begin
        $display("FAIL [terminal pc] exp=%h got=%h -- program has not settled at the expected self-loop address",
                  EXPECTED_PC, pc_dbg_o);
        errors = errors + 1;
    end

    // x4 == 0 -> PASS, x4 == 0xFFFFFFFF -> FAIL (organiser spec)
    if (x4_dbg_o === 32'h00000000) begin
        $display("PASS [organiser firmware self-check] x4 = 0x00000000 (PASS)");
    end else if (x4_dbg_o === 32'hFFFFFFFF) begin
        $display("FAIL [organiser firmware self-check] x4 = 0xFFFFFFFF (FAIL) -- pc=%h", pc_dbg_o);
        errors = errors + 1;
    end else begin
        $display("FAIL [organiser firmware self-check] x4 = %h -- neither PASS (0) nor FAIL (0xFFFFFFFF)",
                  x4_dbg_o);
        errors = errors + 1;
    end

    if (errors == 0)
        $display("ALL TESTS PASSED");
    else
        $display("%0d CHECK(S) FAILED", errors);

    $finish;
end

endmodule
