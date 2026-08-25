// tb_top_alu.v — slice 7c directed tests (regfile + ALU + result path)
//
// Verifies top.v against docs/TOP_BUILD_PLAN.md §3 trap 2 (RESULT_SRC_ALU
// must tap the alu_out REGISTER, not the live ALU) and the trap 1
// regression on AUIPC (ALU_SRC_A_PC must tap old_pc, not pc).
//
// Firmware: firmware/alu_test.hex. No RISC-V assembler was available in
// this environment (checked: riscv64-unknown-elf-as / riscv32-unknown-elf-as
// / riscv-none-elf-as all absent from PATH) — every encoding below is
// hand-derived from the RV32I field layout and cross-checked with an
// independent bit-math reimplementation (Node.js one-liner, not run through
// any assembler) before being written into firmware/alu_test.hex. Both
// derivations agreed; per CLAUDE.md step 6 that is stated here rather than
// silently assumed correct.
//
// ---------------------------------------------------------------------
// Field breakdown (imm/rs2/rs1/funct3/rd/opcode, +funct7 for R-type),
// cross-referenced against rtl/pkg/rvbl2_defines.vh and the RV32I spec's
// I-type/R-type/U-type layouts (CLAUDE.md step 1 — never take a bit
// pattern on trust):
//
//  [0] addi x1, x0, 5
//      I-type: imm=000000000101 rs1=00000 funct3=000 rd=00001 opcode=0010011
//      = (5<<20)|(0<<15)|(0<<12)|(1<<7)|0x13 = 0x00500093
//
//  [1] addi x2, x0, 3
//      I-type: imm=000000000011 rs1=00000 funct3=000 rd=00010 opcode=0010011
//      = (3<<20)|(0<<15)|(0<<12)|(2<<7)|0x13 = 0x00300113
//
//  [2] add x3, x1, x2   <-- TRAP 2 DETECTOR
//      R-type: funct7=0000000 rs2=00010 rs1=00001 funct3=000 rd=00011 opcode=0110011
//      = (0<<25)|(2<<20)|(1<<15)|(0<<12)|(3<<7)|0x33 = 0x002081B3
//      Correct: x3 = x1+x2 = 5+3 = 8. If RESULT_SRC_ALU taps the live ALU
//      instead of alu_out, WRITE_BACK's defaults (alu_src_a_o=RS1,
//      alu_src_b_o=RS2, alu_op_o=ALU_PASS_B) make the live ALU output
//      rs2_data = 3, so x3 would read 3, not 8.
//
//  [3] sub x4, x1, x2
//      R-type: funct7=0100000 rs2=00010 rs1=00001 funct3=000 rd=00100 opcode=0110011
//      = (0x20<<25)|(2<<20)|(1<<15)|(0<<12)|(4<<7)|0x33 = 0x40208233
//      x4 = x1-x2 = 5-3 = 2. Confirms funct7[5] SUB/ADD dispatch survives
//      integration (control_unit.v line ~499).
//
//  [4] and x5, x1, x2
//      R-type: funct7=0000000 rs2=00010 rs1=00001 funct3=111 rd=00101 opcode=0110011
//      = (2<<20)|(1<<15)|(7<<12)|(5<<7)|0x33 = 0x0020F2B3
//      x5 = 5 & 3 = 1.
//
//  [5] or x6, x1, x2
//      R-type: funct3=110 rd=00110
//      = (2<<20)|(1<<15)|(6<<12)|(6<<7)|0x33 = 0x0020E333
//      x6 = 5 | 3 = 7.
//
//  [6] xor x7, x1, x2
//      R-type: funct3=100 rd=00111
//      = (2<<20)|(1<<15)|(4<<12)|(7<<7)|0x33 = 0x0020C3B3
//      x7 = 5 ^ 3 = 6.
//
//  [7] sll x8, x1, x2
//      R-type: funct3=001 rd=01000
//      = (2<<20)|(1<<15)|(1<<12)|(8<<7)|0x33 = 0x00209433
//      x8 = 5 << (3 & 0x1F) = 5 << 3 = 40.
//
//  [8] lui x9, 0x12345
//      U-type: imm[31:12]=0x12345 rd=01001 opcode=0110111
//      = (0x12345<<12)|(9<<7)|0x37 = 0x123454B7
//      x9 = 0x12345000. Only instruction that exercises ALU_PASS_B in this
//      firmware (LUI's EXECUTE_ALU case: alu_src_b_o=IMM, alu_op_o=PASS_B).
//
//  [9] auipc x10, 0x0   <-- TRAP 1 REGRESSION
//      U-type: imm[31:12]=0x00000 rd=01010 opcode=0010111
//      = (0<<12)|(10<<7)|0x17 = 0x00000517
//      x10 = old_pc + imm = (address of this instruction) + 0.
//      This is instruction index 9 (0-based), so its address is
//      PC_RESET_ADDR + 9*4 = 0x00400000 + 0x24 = 0x00400024.
//      If mux_alu_a's PC arm taps live pc instead of old_pc, AUIPC's
//      EXECUTE_ALU cycle sees pc already advanced to the *next*
//      instruction's address (FETCH incremented it one cycle prior), so
//      x10 comes out 4 too high: 0x00400028.
// ---------------------------------------------------------------------

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

    // Debug trace — 7b's trace plus alu_out/mux_result, per task spec.
    always @(posedge clk_i) begin
        #1;
        $display("t=%0t state=%0d pc=%h ir=%h alu_out=%h mux_result=%h",
                  $time, dut.u_control_unit.state, dut.pc, dut.ir,
                  dut.alu_out, dut.mux_result);
    end

    // halt_o guard: no ECALL in this firmware (check 7).
    always @(*) begin
        if (!rst_i && halt_o !== 1'b0) begin
            $display("FAIL [halt_o guard] exp=0 got=%b, t=%0t", halt_o, $time);
            errors = errors + 1;
        end
    end

    // regs[0] guard: x0 must stay zero for the whole run (check 5).
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

    // Check 8: no register other than exp_rd changed this instruction.
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

        // ---------------------------------------------------------------
        // Walk all 10 instructions: FETCH -> DECODE -> EXECUTE_ALU ->
        // WRITE_BACK -> (next) FETCH, 4 cycles each (handoff Sec 2,
        // check 6).
        // ---------------------------------------------------------------
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

            // Register write-back check (check 1), after WRITE_BACK
            // retires, not during (task spec check 1/2/3/4).
            if (dut.u_regfile.regs[RD_IDX[i]] !== EXPECTED_VAL[i]) begin
                if (i == 2) begin
                    // Check 2: trap 2 detector, explicit message.
                    $display("FAIL [TRAP2: add x3,x1,x2] x3 exp=%0d got=%0d (got 3 => RESULT_SRC_ALU is tapping the live ALU/rs2_data instead of the alu_out register)",
                              EXPECTED_VAL[i], dut.u_regfile.regs[RD_IDX[i]]);
                end else if (i == 9) begin
                    // Check 3: trap 1 regression, explicit message.
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

        // Redundant explicit checks 2/3/4, spelled out per task spec even
        // though the loop above already covers them via EXPECTED_VAL.
        // Each increments errors independently so this block bites on its
        // own if the loop-body check above it is ever edited away.
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
