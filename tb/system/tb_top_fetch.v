// tb_top_fetch.v — slice 7b directed tests (fetch path only)
//
// Verifies top.v against docs/TOP_BUILD_PLAN.md §2/§3 trap 1: pc/old_pc
// behave correctly across a run of pure addi instructions (no memory
// access, no branch, so mux_mem_addr/mux_pc_next's live arms stay
// inert and adr_src_o/halt_o should never move off their defaults).
//
// Firmware encodings (firmware/fetch_test.hex) verified against the
// RISC-V I-type layout (imm[11:0]|rs1|funct3|rd|opcode) by direct
// arithmetic before use, per CLAUDE.md step 6 — not taken on trust:
//   addi x1,x0,1 = (1<<20)|(1<<7)|0x13 = 0x00100093
//   addi x2,x0,2 = (2<<20)|(2<<7)|0x13 = 0x00200113
//   addi x3,x0,3 = (3<<20)|(3<<7)|0x13 = 0x00300193
//   addi x4,x0,4 = (4<<20)|(4<<7)|0x13 = 0x00400213

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_top_fetch;

    reg clk_i;
    reg rst_i;
    wire halt_o;

    integer errors;

    reg [31:0] EXPECTED_IR [0:3];

    top #(
        .IMEM_DEPTH_WORDS (1024),
        .IMEM_INIT_FILE   ("firmware/fetch_test.hex")
    ) dut (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .halt_o (halt_o)
    );

    // 10ns clock
    always #5 clk_i = ~clk_i;

    // Debug trace — on by default per task spec, this is where a wiring
    // mistake in slices 7c-7g is cheapest to see.
    always @(posedge clk_i) begin
        #1;
        $display("t=%0t state=%0d pc=%h old_pc=%h ir=%h",
                  $time, dut.u_control_unit.state, dut.pc, dut.old_pc, dut.ir);
    end

    // adr_src_o guard: no memory instruction in this firmware, so it
    // must never move off ADR_SRC_PC (check 7). Gated on !rst_i to
    // avoid the one-delta X period before the first posedge, same
    // rationale as tb_control_unit's adr_src_o guard.
    always @(*) begin
        if (!rst_i && dut.adr_src_o !== `ADR_SRC_PC) begin
            $display("FAIL [adr_src_o guard] exp=PC got=%b, t=%0t", dut.adr_src_o, $time);
            errors = errors + 1;
        end
    end

    // halt_o guard: no ECALL in this firmware (check 8).
    always @(*) begin
        if (!rst_i && halt_o !== 1'b0) begin
            $display("FAIL [halt_o guard] exp=0 got=%b, t=%0t", halt_o, $time);
            errors = errors + 1;
        end
    end

    task check_state;
        input [127:0] label;
        input [3:0]   exp_state;
        begin
            if (dut.u_control_unit.state !== exp_state) begin
                $display("FAIL [%0s] state: exp=%0d got=%0d", label, exp_state, dut.u_control_unit.state);
                errors = errors + 1;
            end
        end
    endtask

    integer i;
    reg [31:0] pc_snapshot, ir_snapshot, old_pc_snapshot;
    reg [31:0] expected_pc;

    initial begin
        $dumpfile("sim/tb_top_fetch.vcd");
        $dumpvars(0, tb_top_fetch);

        errors = 0;
        clk_i  = 0;
        rst_i  = 1;

        EXPECTED_IR[0] = 32'h00100093;
        EXPECTED_IR[1] = 32'h00200113;
        EXPECTED_IR[2] = 32'h00300193;
        EXPECTED_IR[3] = 32'h00400213;

        @(posedge clk_i); #1; // RESET latched
        check_state("reset", dut.u_control_unit.RESET);

        rst_i = 0;
        @(posedge clk_i); #1; // RESET -> FETCH transition lands here
        check_state("post-reset-FETCH", dut.u_control_unit.FETCH);

        // ---- Check 1: pc == PC_RESET_ADDR right after reset deasserts,
        // before any FETCH has completed and advanced it. ----
        if (dut.pc !== `PC_RESET_ADDR) begin
            $display("FAIL [reset] pc: exp=%h got=%h", `PC_RESET_ADDR, dut.pc);
            errors = errors + 1;
        end else begin
            $display("PASS [reset] pc = PC_RESET_ADDR");
        end

        // ---------------------------------------------------------------
        // Walk all 4 addi instructions: FETCH -> DECODE -> EXECUTE_ALU ->
        // WRITE_BACK -> (next) FETCH, 4 cycles each (handoff Sec 2).
        // ---------------------------------------------------------------
        for (i = 0; i < 4; i = i + 1) begin
            expected_pc = `PC_RESET_ADDR + (i * 4);

            // FETCH: currently-executing instruction's address is
            // `expected_pc` — the pre-increment pc (checks 1/4: reset
            // value for i=0, +4 progression for i>0).
            check_state("FETCH", dut.u_control_unit.FETCH);
            if (dut.pc !== expected_pc) begin
                $display("FAIL [instr%0d-FETCH] pc: exp=%h got=%h", i, expected_pc, dut.pc);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count_check(i, 1);

            // DECODE: ir/old_pc for the instruction just fetched are now
            // valid (checks 2/3 — old_pc == pc-4, the trap 1 assertion).
            check_state("DECODE", dut.u_control_unit.DECODE);
            if (dut.ir !== EXPECTED_IR[i]) begin
                $display("FAIL [instr%0d-DECODE] ir: exp=%h got=%h", i, EXPECTED_IR[i], dut.ir);
                errors = errors + 1;
            end
            if (dut.old_pc !== expected_pc) begin
                $display("FAIL [instr%0d-DECODE] old_pc: exp=%h got=%h", i, expected_pc, dut.old_pc);
                errors = errors + 1;
            end
            if (dut.pc !== (expected_pc + 32'd4)) begin
                $display("FAIL [instr%0d-DECODE] pc-4 != old_pc: pc=%h old_pc=%h", i, dut.pc, dut.old_pc);
                errors = errors + 1;
            end
            pc_snapshot     = dut.pc;
            ir_snapshot     = dut.ir;
            old_pc_snapshot = dut.old_pc;
            @(posedge clk_i); #1; cycle_count_check(i, 2);

            // EXECUTE_ALU: pc/ir/old_pc must be unchanged (checks 4/5).
            check_state("EXECUTE_ALU", dut.u_control_unit.EXECUTE_ALU);
            if (dut.pc !== pc_snapshot || dut.ir !== ir_snapshot || dut.old_pc !== old_pc_snapshot) begin
                $display("FAIL [instr%0d-EXECUTE_ALU] fetch regs moved: pc=%h ir=%h old_pc=%h",
                          i, dut.pc, dut.ir, dut.old_pc);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count_check(i, 3);

            // WRITE_BACK: still unchanged (checks 4/5).
            check_state("WRITE_BACK", dut.u_control_unit.WRITE_BACK);
            if (dut.pc !== pc_snapshot || dut.ir !== ir_snapshot || dut.old_pc !== old_pc_snapshot) begin
                $display("FAIL [instr%0d-WRITE_BACK] fetch regs moved: pc=%h ir=%h old_pc=%h",
                          i, dut.pc, dut.ir, dut.old_pc);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count_check(i, 4);
        end

        check_state("final-FETCH", dut.u_control_unit.FETCH);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d CHECK(S) FAILED", errors);

        $finish;
    end

    // Cycle-count bookkeeping (check 6): each addi is 4 cycles by
    // construction of the loop body above (one @(posedge) per FSM
    // state); this task just makes that count explicit in the log
    // rather than leaving it implicit.
    task cycle_count_check;
        input integer instr_idx;
        input integer cycle_num;
        begin
            if (cycle_num == 4)
                $display("PASS [instr%0d] cycle count = 4 (handoff Sec 2)", instr_idx);
        end
    endtask

endmodule
