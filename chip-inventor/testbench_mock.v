// testbench_mock.v -- verifies the 4-instruction OpenLane synth-mock now
// baked into hdl.v's imem block (organiser feedback, 2026-09-10), NOT the
// full validation firmware. See testbench.v for that (separate, full-
// firmware) test -- it is stale against the current mocked hdl.v and
// must not be run against it (EXPECTED_CYCLES/EXPECTED_PC there assume
// the 259-word firmware).
//
// Mock program (rtl/imem.v / hdl.v, word addresses 0-3):
//   addi x5, x0, 10
//   addi x6, x0, 5
//   add  x7, x5, x6      -- x7 = 15 (organiser's worked example)
//   add  x4, x7, x0      -- copies x7 into x4, the only register with a
//                           debug port wired to top level (x4_dbg_o)
// default: NOP thereafter (no self-loop -- mock never halts).
//
// Cycle count: R-type/I-type ALU = 4 cycles each (fetch, decode, execute,
// write back) per docs/HANDOFF_control_unit.md line 51. 4 instructions x
// 4 cycles = 16 cycles to retire the add into x4. No terminal PC check --
// unlike the full firmware, this mock has no `j .` self-loop, so PC keeps
// advancing through NOPs forever; only x4's settled value is meaningful.

module testbench_mock();

reg  clk_i = 0;
reg  rst_i = 1;
wire halt_o;
wire [31:0] pc_dbg_o;
wire [31:0] x4_dbg_o;

integer errors;
integer i;
localparam INSTR_CYCLES  = 4;  // R/I-type ALU, HANDOFF_control_unit.md L51
localparam NUM_INSTRS    = 4;
localparam SETTLE_MARGIN = 10; // extra cycles past retirement before sampling
localparam EXPECTED_X4   = 32'd15; // x7 = 10 + 5, copied into x4

top ai45 (
    .clk_i     (clk_i),
    .rst_i     (rst_i),
    .halt_o    (halt_o),
    .pc_dbg_o  (pc_dbg_o),
    .x4_dbg_o  (x4_dbg_o)
);

always #5 clk_i = ~clk_i;

initial begin
    $dumpfile("testbench_mock.vcd");
    $dumpvars(0, testbench_mock);

    errors = 0;

    @(posedge clk_i); #1; // RESET latched

    rst_i = 0;
    @(posedge clk_i); #1; // RESET -> FETCH (instruction 0)

    if (pc_dbg_o !== 32'h00400000) begin
        $display("FAIL [entry pc] exp=00400000 got=%h", pc_dbg_o);
        errors = errors + 1;
    end

    for (i = 0; i < (INSTR_CYCLES * NUM_INSTRS) + SETTLE_MARGIN - 1; i = i + 1)
        @(posedge clk_i);
    #1;

    $display("t=%0t: pc=%h x4=%h (after %0d cycles)",
              $time, pc_dbg_o, x4_dbg_o, (INSTR_CYCLES * NUM_INSTRS) + SETTLE_MARGIN);

    if (x4_dbg_o === EXPECTED_X4) begin
        $display("PASS [mock ALU chain] x4 = %0d (expected %0d)", x4_dbg_o, EXPECTED_X4);
    end else begin
        $display("FAIL [mock ALU chain] x4 = %0d (expected %0d) -- pc=%h",
                  x4_dbg_o, EXPECTED_X4, pc_dbg_o);
        errors = errors + 1;
    end

    if (errors == 0)
        $display("ALL TESTS PASSED");
    else
        $display("%0d CHECK(S) FAILED", errors);

    $finish;
end

endmodule
