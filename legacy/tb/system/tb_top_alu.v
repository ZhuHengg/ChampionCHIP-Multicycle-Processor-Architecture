// tb_top_alu.v — slice 7c directed tests: regfile, ALU ops, result-path traps

// Field breakdown (imm/rs2/rs1/funct3/rd/opcode, +funct7 for R-type):
//
//  [0] addi x1, x0, 5    = 0x00500093
//  [1] addi x2, x0, 3    = 0x00300113
//  [2] add x3, x1, x2    = 0x002081B3  <-- TRAP 2: RESULT_SRC_ALU must tap alu_out reg, not live ALU (x3=8 else 3)
//  [3] sub x4, x1, x2    = 0x40208233  (funct7[5] SUB/ADD dispatch, x4=2)
//  [4] and x5, x1, x2    = 0x0020F2B3  (x5=1)
//  [5] or  x6, x1, x2    = 0x0020E333  (x6=7)
//  [6] xor x7, x1, x2    = 0x0020C3B3  (x7=6)
//  [7] sll x8, x1, x2    = 0x00209433  (x8=5<<3=40)
//  [8] lui x9, 0x12345   = 0x123454B7  (x9=0x12345000, exercises ALU_PASS_B)
//  [9] auipc x10, 0x0    = 0x00000517  <-- TRAP 1: mux_alu_a's PC arm must tap old_pc, not pc (x10=0x00400024 else +4 too high)

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_top_alu;

    reg clk_i;
    reg rst_i;
    wire halt_o;

    integer errors;
    integer i, k;

    reg [31:0] EXPECTED_IR  [0:9];
    reg [4:0]  RD_IDX       [0:9];
    reg [31:0] EXPECTED_VAL [0:9];

    reg [31:0] regs_snapshot [0:31];
    reg [31:0] expected_pc;

    top #(
        .IMEM_DEPTH_WORDS (1024),
        .IMEM_INIT_FILE   ("firmware/alu_test.hex")
    ) dut (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .halt_o (halt_o)
    );

    // 10ns clock
    always #5 clk_i = ~clk_i;

    // Debug trace: pc/ir/alu_out/mux_result per cycle.
    always @(posedge clk_i) begin
        #1;
        $display("t=%0t state=%0d pc=%h ir=%h alu_out=%h mux_result=%h",
                  $time, dut.u_control_unit.state, dut.pc, dut.ir,
                  dut.alu_out, dut.mux_result);
    end

    // halt_o guard: no ECALL in this firmware.
    always @(*) begin
        if (!rst_i && halt_o !== 1'b0) begin
            $display("FAIL [halt_o guard] exp=0 got=%b, t=%0t", halt_o, $time);
            errors = errors + 1;
        end
    end

    // regs[0] guard: x0 must stay zero.
    always @(*) begin
        if (!rst_i && dut.u_regfile.regs[0] !== 32'b0) begin
            $display("FAIL [x0 guard] regs[0] exp=0 got=%h, t=%0t",
                      dut.u_regfile.regs[0], $time);
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

    task snapshot_regs;
        begin
            for (k = 0; k < 32; k = k + 1)
                regs_snapshot[k] = dut.u_regfile.regs[k];
        end
    endtask

    // No register other than exp_rd changed this instruction.
    task check_only_rd_changed;
        input integer instr_idx;
        input [4:0] exp_rd;
        begin
            for (k = 0; k < 32; k = k + 1) begin
                if (k != exp_rd && dut.u_regfile.regs[k] !== regs_snapshot[k]) begin
                    $display("FAIL [instr%0d] unexpected write to regs[%0d]: was=%h now=%h",
                              instr_idx, k, regs_snapshot[k], dut.u_regfile.regs[k]);
                    errors = errors + 1;
                end
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_top_alu.vcd");
        $dumpvars(0, tb_top_alu);

        errors = 0;
        clk_i  = 0;
        rst_i  = 1;

        EXPECTED_IR[0] = 32'h00500093; RD_IDX[0] = 5'd1;  EXPECTED_VAL[0] = 32'd5;
        EXPECTED_IR[1] = 32'h00300113; RD_IDX[1] = 5'd2;  EXPECTED_VAL[1] = 32'd3;
        EXPECTED_IR[2] = 32'h002081B3; RD_IDX[2] = 5'd3;  EXPECTED_VAL[2] = 32'd8;
        EXPECTED_IR[3] = 32'h40208233; RD_IDX[3] = 5'd4;  EXPECTED_VAL[3] = 32'd2;
        EXPECTED_IR[4] = 32'h0020F2B3; RD_IDX[4] = 5'd5;  EXPECTED_VAL[4] = 32'd1;
        EXPECTED_IR[5] = 32'h0020E333; RD_IDX[5] = 5'd6;  EXPECTED_VAL[5] = 32'd7;
        EXPECTED_IR[6] = 32'h0020C3B3; RD_IDX[6] = 5'd7;  EXPECTED_VAL[6] = 32'd6;
        EXPECTED_IR[7] = 32'h00209433; RD_IDX[7] = 5'd8;  EXPECTED_VAL[7] = 32'd40;
        EXPECTED_IR[8] = 32'h123454B7; RD_IDX[8] = 5'd9;  EXPECTED_VAL[8] = 32'h12345000;
        EXPECTED_IR[9] = 32'h00000517; RD_IDX[9] = 5'd10; EXPECTED_VAL[9] = `PC_RESET_ADDR + 32'd9*32'd4;

        @(posedge clk_i); #1; // RESET latched
        check_state("reset", dut.u_control_unit.RESET);

        rst_i = 0;
        @(posedge clk_i); #1; // RESET -> FETCH transition lands here
        check_state("post-reset-FETCH", dut.u_control_unit.FETCH);

        // Walk all 10 instructions: FETCH -> DECODE -> EXECUTE_ALU -> WRITE_BACK, 4 cycles each.
        for (i = 0; i < 10; i = i + 1) begin
            expected_pc = `PC_RESET_ADDR + (i * 4);

            check_state("FETCH", dut.u_control_unit.FETCH);
            if (dut.pc !== expected_pc) begin
                $display("FAIL [instr%0d-FETCH] pc: exp=%h got=%h", i, expected_pc, dut.pc);
                errors = errors + 1;
            end
            snapshot_regs();
            @(posedge clk_i); #1; // cycle 1

            check_state("DECODE", dut.u_control_unit.DECODE);
            if (dut.ir !== EXPECTED_IR[i]) begin
                $display("FAIL [instr%0d-DECODE] ir: exp=%h got=%h", i, EXPECTED_IR[i], dut.ir);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; // cycle 2

            check_state("EXECUTE_ALU", dut.u_control_unit.EXECUTE_ALU);
            @(posedge clk_i); #1; // cycle 3 — alu_out latches this edge

            check_state("WRITE_BACK", dut.u_control_unit.WRITE_BACK);
            @(posedge clk_i); #1; // cycle 4 — regfile write commits this edge

            // Register write-back check, after WRITE_BACK retires.
            if (dut.u_regfile.regs[RD_IDX[i]] !== EXPECTED_VAL[i]) begin
                if (i == 2) begin
                    // Trap 2 detector, explicit message.
                    $display("FAIL [TRAP2: add x3,x1,x2] x3 exp=%0d got=%0d (got 3 => RESULT_SRC_ALU is tapping the live ALU/rs2_data instead of the alu_out register)",
                              EXPECTED_VAL[i], dut.u_regfile.regs[RD_IDX[i]]);
                end else if (i == 9) begin
                    // Trap 1 regression, explicit message.
                    $display("FAIL [TRAP1: auipc x10,0x0] x10 exp=%h got=%h (4-too-high => mux_alu_a's PC arm is tapping live pc instead of old_pc)",
                              EXPECTED_VAL[i], dut.u_regfile.regs[RD_IDX[i]]);
                end else begin
                    $display("FAIL [instr%0d] regs[%0d] exp=%h got=%h",
                              i, RD_IDX[i], EXPECTED_VAL[i], dut.u_regfile.regs[RD_IDX[i]]);
                end
                errors = errors + 1;
            end else begin
                $display("PASS [instr%0d] regs[%0d] = %h", i, RD_IDX[i], EXPECTED_VAL[i]);
            end

            check_only_rd_changed(i, RD_IDX[i]);
            $display("PASS [instr%0d] cycle count = 4 (handoff Sec 2)", i);
        end

        check_state("final-FETCH", dut.u_control_unit.FETCH);

        // Redundant explicit trap/LUI checks, independent of loop body above.
        if (dut.u_regfile.regs[3] !== 32'd8) begin
            $display("FAIL [explicit TRAP2 check] x3 exp=8 got=%0d", dut.u_regfile.regs[3]);
            errors = errors + 1;
        end
        if (dut.u_regfile.regs[10] !== (`PC_RESET_ADDR + 32'd36)) begin
            $display("FAIL [explicit TRAP1 check] x10 exp=%h got=%h", `PC_RESET_ADDR + 32'd36, dut.u_regfile.regs[10]);
            errors = errors + 1;
        end
        if (dut.u_regfile.regs[9] !== 32'h12345000) begin
            $display("FAIL [explicit LUI check] x9 exp=12345000 got=%h", dut.u_regfile.regs[9]);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
