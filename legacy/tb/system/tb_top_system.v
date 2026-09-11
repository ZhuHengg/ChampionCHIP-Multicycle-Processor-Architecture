// tb_top_system.v — runs firmware/validation.hex full RV32I+Zmmul+Xicrc self-check; verifies halt_o cycle count and PASS_CODE in x1.

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_top_system;

    localparam PASS_CODE  = 32'h0000C0DE;
    localparam FAIL_MARK  = 32'hFA110000;
    localparam STATUS_IDX = 64; // (DMEM_BASE+0x100)/4 -- see gen_validation_fw.py

    reg clk_i;
    reg rst_i;
    wire halt_o;

    integer errors;
    integer i;
    integer cyc;
    localparam CYCLE_BUDGET = 2000; // predicted 980 + generous margin

    wire verbose;
    assign verbose = $test$plusargs("VERBOSE");

    top #(
        .IMEM_DEPTH_WORDS (1024),
        .IMEM_INIT_FILE   ("firmware/validation.hex")
    ) dut (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .halt_o (halt_o)
    );

    always #5 clk_i = ~clk_i;

    // per-cycle trace, +VERBOSE gated
    always @(posedge clk_i) begin
        #1;
        if (verbose)
            $display("t=%0t state=%0d pc=%h ir=%h halt_o=%b regs1=%h",
                      $time, dut.u_control_unit.state, dut.pc, dut.ir,
                      halt_o, dut.u_regfile.regs[1]);
    end

    // Check 3: no X instruction ever fetched (sampled at DECODE)
    always @(posedge clk_i) begin
        #1;
        if (!rst_i && dut.u_control_unit.state == dut.u_control_unit.DECODE) begin
            if (^dut.ir === 1'bx) begin
                $fatal(1, "FATAL [no-X fetch] ir is X during DECODE at t=%0t, ir=%h, pc=%h -- PC ran off the program",
                          $time, dut.ir, dut.pc);
            end
        end
    end

    // Check 4: no X ever written to the register file.
    always @(posedge clk_i) begin
        #1;
        if (!rst_i && dut.reg_write_o) begin
            if (^dut.mux_result === 1'bx) begin
                $display("FAIL [no-X write] mux_result is X at WRITE_BACK, t=%0t, pc=%h", $time, dut.pc);
                errors = errors + 1;
            end
        end
    end

    // Check 5: regs[0] stays 0 for the entire run.
    always @(*) begin
        if (!rst_i && dut.u_regfile.regs[0] !== 32'b0) begin
            $display("FAIL [x0 guard] regs[0] exp=0 got=%h, t=%0t", dut.u_regfile.regs[0], $time);
            errors = errors + 1;
        end
    end

    initial begin
        $dumpfile("sim/tb_top_system.vcd");
        $dumpvars(0, tb_top_system);

        errors = 0;
        clk_i = 0;
        rst_i = 1;

        @(posedge clk_i); #1; // RESET latched
        if (dut.u_control_unit.state !== dut.u_control_unit.RESET) begin
            $display("FAIL [reset] state exp=RESET got=%0d", dut.u_control_unit.state);
            errors = errors + 1;
        end
        if (halt_o !== 1'b0) begin
            $display("FAIL [halt_o] expected 0 immediately after reset, got %b", halt_o);
            errors = errors + 1;
        end

        rst_i = 0;
        @(posedge clk_i); #1; // RESET -> FETCH (instruction 0)

        // Checks 1/6/7: halt_o stays 0, cycle count, watchdog
        cyc = 0;
        while (!halt_o && cyc < CYCLE_BUDGET) begin
            @(posedge clk_i); #1;
            cyc = cyc + 1;
        end

        if (!halt_o) begin
            $fatal(1, "WATCHDOG [halt_o never asserted]: exceeded %0d cycles without ECALL retiring -- pc=%h state=%0d",
                      CYCLE_BUDGET, dut.pc, dut.u_control_unit.state);
        end

        $display("halt_o asserted after %0d cycles (predicted 980)", cyc);
        if (cyc !== 980) begin
            $display("FAIL [cycle count] exp=980 (see scripts/gen_validation_fw.py's simulator output) got=%0d", cyc);
            errors = errors + 1;
        end

        // Sticky check: halt_o stays 1 (status flag, not a stop signal)
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk_i); #1;
            if (halt_o !== 1'b1) begin
                $display("FAIL [halt_o sticky] dropped to %b, %0d cycles after first assertion", halt_o, i + 1);
                errors = errors + 1;
            end
        end

        // Check 2: firmware reached PASS_CODE (x1 and DMEM status word)
        if (dut.u_regfile.regs[1] !== PASS_CODE) begin
            $display("FAIL [firmware self-check] x1=%h -- expected PASS_CODE=%h",
                      dut.u_regfile.regs[1], PASS_CODE);
            if (dut.u_regfile.regs[1][31:16] === FAIL_MARK[31:16]) begin
                $display("  FAIL_ID = 0x%h -- see tb_top_system.v's check registry / scripts/gen_validation_fw.py's CHECKS list for which check this is",
                          dut.u_regfile.regs[1] & 32'h0000FFFF);
            end else begin
                $display("  x1 does not even carry the FAIL_MARK pattern (0x%h) -- firmware may not have reached `finish` at all",
                          FAIL_MARK);
            end
            errors = errors + 1;
        end else begin
            $display("PASS [firmware self-check] x1 = PASS_CODE (0x%h)", PASS_CODE);
        end

        if (dut.u_dmem.mem[STATUS_IDX] !== dut.u_regfile.regs[1]) begin
            $display("FAIL [status DMEM word] mem[%0d]=%h does not match x1=%h",
                      STATUS_IDX, dut.u_dmem.mem[STATUS_IDX], dut.u_regfile.regs[1]);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
