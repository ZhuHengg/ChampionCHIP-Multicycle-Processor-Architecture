// tb_top_organiser.v — runs organiser-supplied Stage 2 validation firmware against this core

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_top_organiser;

    localparam PC_ENTRY = 32'h00400000;

    reg clk_i;
    reg rst_i;
    wire halt_o;

    integer errors;
    integer cyc;
    localparam CYCLE_BUDGET = 2000;

    reg  [31:0] pc_prev;
    reg         pc_prev_valid;
    integer     stuck_count;
    localparam  STUCK_THRESHOLD = 4; // consecutive identical FETCH-PC samples

    wire verbose;
    assign verbose = $test$plusargs("VERBOSE");

    top #(
        .IMEM_DEPTH_WORDS (1024),
        .IMEM_INIT_FILE   ("firmware/organiser_validation.hex")
    ) dut (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .halt_o (halt_o)
    );

    always #5 clk_i = ~clk_i;

    always @(posedge clk_i) begin
        #1;
        if (verbose)
            $display("t=%0t state=%0d pc=%h ir=%h x4=%h",
                      $time, dut.u_control_unit.state, dut.pc, dut.ir,
                      dut.u_regfile.regs[4]);
    end

    // No-X-fetch guard, same discipline as tb_top_system.v.
    always @(posedge clk_i) begin
        #1;
        if (!rst_i && dut.u_control_unit.state == dut.u_control_unit.DECODE) begin
            if (^dut.ir === 1'bx) begin
                $fatal(1, "FATAL [no-X fetch] ir is X during DECODE at t=%0t, ir=%h, pc=%h -- PC ran off the program",
                          $time, dut.ir, dut.pc);
            end
        end
    end

    // regs[0] guard.
    always @(*) begin
        if (!rst_i && dut.u_regfile.regs[0] !== 32'b0) begin
            $display("FAIL [x0 guard] regs[0] exp=0 got=%h, t=%0t", dut.u_regfile.regs[0], $time);
            errors = errors + 1;
        end
    end

    initial begin
        $dumpfile("sim/tb_top_organiser.vcd");
        $dumpvars(0, tb_top_organiser);

        errors = 0;
        clk_i = 0;
        rst_i = 1;
        pc_prev_valid = 0;
        stuck_count = 0;

        @(posedge clk_i); #1; // RESET latched
        if (dut.u_control_unit.state !== dut.u_control_unit.RESET) begin
            $display("FAIL [reset] state exp=RESET got=%0d", dut.u_control_unit.state);
            errors = errors + 1;
        end

        rst_i = 0;
        @(posedge clk_i); #1; // RESET -> FETCH (instruction 0)

        if (dut.pc !== PC_ENTRY) begin
            $display("FAIL [entry pc] exp=%h got=%h", PC_ENTRY, dut.pc);
            errors = errors + 1;
        end

        // detect self-loop (`j .`) termination via repeated FETCH-PC
        cyc = 0;
        while (stuck_count < STUCK_THRESHOLD && cyc < CYCLE_BUDGET) begin
            @(posedge clk_i); #1;
            cyc = cyc + 1;
            if (dut.u_control_unit.state == dut.u_control_unit.FETCH) begin
                if (pc_prev_valid && dut.pc === pc_prev)
                    stuck_count = stuck_count + 1;
                else
                    stuck_count = 0;
                pc_prev = dut.pc;
                pc_prev_valid = 1;
            end
        end

        if (stuck_count < STUCK_THRESHOLD) begin
            $fatal(1, "WATCHDOG [self-loop never reached]: exceeded %0d cycles without PC settling -- pc=%h state=%0d",
                      CYCLE_BUDGET, dut.pc, dut.u_control_unit.state);
        end

        $display("self-loop detected at pc=%h after %0d cycles", dut.pc, cyc);

        // x4 == 0 -> PASS, x4 == 0xFFFFFFFF -> FAIL (organiser spec)
        if (dut.u_regfile.regs[4] === 32'h00000000) begin
            $display("PASS [organiser firmware self-check] x4 = 0x00000000 (PASS)");
        end else if (dut.u_regfile.regs[4] === 32'hFFFFFFFF) begin
            $display("FAIL [organiser firmware self-check] x4 = 0xFFFFFFFF (FAIL) -- pc=%h", dut.pc);
            errors = errors + 1;
        end else begin
            $display("FAIL [organiser firmware self-check] x4 = %h -- neither PASS (0) nor FAIL (0xFFFFFFFF); self-loop pc=%h does not match all_good (0x004003EC) or _error (0x004003F4)",
                      dut.u_regfile.regs[4], dut.pc);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
