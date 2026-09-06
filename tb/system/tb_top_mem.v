// tb_top_mem.v — slice 7e directed load/store tests for top.v
//
// Program trace (symbolic listing):
//   0x400000 lui  x1,0x10010          x1 = 0x10010000 (DMEM_BASE)
//   0x400004 addi x2,x0,0x555         x2 = 0x555 (sw/lw round-trip value)
//   0x400008 sw   x2,4(x1)            mem[0x10010004] = 0x555
//   0x40000c lw   x3,4(x1)            x3 = 0x555 (round trip)
//   0x400010 addi x4,x0,0x99          x4 = 0x99  (sb store value)
//   0x400014 addi x5,x0,0x345         x5 = 0x345 (sh store value)
//   -- Table 12 golden bytes F1 F2 F3 F4 at DMEM_BASE -> 0xF4F3F2F1 LE
//   0x400018 lw   x6,0(x1)            x6  = 0xF4F3F2F1
//   0x40001c lb   x7,0(x1)            x7  = 0xFFFFFFF1 (sign-extend 0xF1)
//   0x400020 lbu  x8,0(x1)            x8  = 0x000000F1
//   0x400024 lh   x9,0(x1)            x9  = 0xFFFFF2F1 (sign-extend 0xF2F1)
//   0x400028 lhu  x10,0(x1)           x10 = 0x0000F2F1
//   0x40002c lb   x11,2(x1)           x11 = 0xFFFFFFF3 (MSB set)
//   0x400030 lbu  x12,2(x1)           x12 = 0x000000F3 (unsigned, same addr)
//   -- sb at every byte lane, each against its own preloaded word (0xAABBCCDD)
//   0x400034 sb x4,8(x1)  ; 0x400038 lw x13,8(x1)   word@8  lane0->0x99
//   0x40003c sb x4,13(x1) ; 0x400040 lw x14,12(x1)  word@12 lane1->0x99
//   0x400044 sb x4,18(x1) ; 0x400048 lw x15,16(x1)  word@16 lane2->0x99
//   0x40004c sb x4,23(x1) ; 0x400050 lw x16,20(x1)  word@20 lane3->0x99
//   -- sh at offsets 0 and 2 (low half / high half), each its own word
//   0x400054 sh x5,24(x1) ; 0x400058 lw x17,24(x1)  word@24 lo->0x0345
//   0x40005c sh x5,30(x1) ; 0x400060 lw x18,28(x1)  word@28 hi->0x0345
//   -- load from IMEM: read this program's own first instruction as data
//   0x400064 lui x19,0x00400          x19 = 0x00400000 (IMEM_BASE)
//   0x400068 lw  x20,0(x19)           x20 = 0x100100b7 (instr 0's word)

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_top_mem;

    reg clk_i;
    reg rst_i;
    wire halt_o;

    integer errors;
    integer i;

    localparam CYCLE_BUDGET = 500;
    integer cycle_count;

    top #(
        .IMEM_DEPTH_WORDS (1024),
        .IMEM_INIT_FILE   ("firmware/mem_test.hex")
    ) dut (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .halt_o (halt_o)
    );

    // 10ns clock
    always #5 clk_i = ~clk_i;

    // Debug trace: state/pc/ir plus mem-path signals
    always @(posedge clk_i) begin
        #1;
        $display("t=%0t state=%0d pc=%h ir=%h mux_mem_addr=%h op_size=%b bw=%b dmem_data_o=%h lsu_core_data_i=%h",
                  $time, dut.u_control_unit.state, dut.pc, dut.ir,
                  dut.mux_mem_addr, dut.op_size_o, dut.dmem_bw_o,
                  dut.dmem_data_o, dut.lsu_core_data_i);
    end

    // Watchdog (as in 7d): a mis-wired memory path can hang the FSM.
    always @(posedge clk_i) begin
        if (!rst_i) begin
            cycle_count = cycle_count + 1;
            if (cycle_count > CYCLE_BUDGET) begin
                $fatal(1, "WATCHDOG: exceeded %0d cycles without finishing", CYCLE_BUDGET);
            end
        end
    end

    // halt_o guard: no ECALL in this firmware (check 5).
    always @(*) begin
        if (!rst_i && halt_o !== 1'b0) begin
            $display("FAIL [halt_o guard] exp=0 got=%b, t=%0t", halt_o, $time);
            errors = errors + 1;
        end
    end

    // regs[0] guard (check 5).
    always @(*) begin
        if (!rst_i && dut.u_regfile.regs[0] !== 32'b0) begin
            $display("FAIL [x0 guard] regs[0] exp=0 got=%h, t=%0t",
                      dut.u_regfile.regs[0], $time);
            errors = errors + 1;
        end
    end

    // run_instr: runs one instruction FETCH-to-FETCH, counts cycles
    task run_instr;
        input [8*24-1:0] label;
        input [31:0]     exp_entry_pc;
        output [31:0]    landed_pc;
        output integer   cyc;
        begin
            if (dut.u_control_unit.state !== dut.u_control_unit.FETCH) begin
                $display("FAIL [%0s] expected FETCH at entry, got state=%0d pc=%h",
                          label, dut.u_control_unit.state, dut.pc);
                errors = errors + 1;
            end
            if (dut.pc !== exp_entry_pc) begin
                $display("FAIL [%0s] entry pc mismatch exp=%h got=%h", label, exp_entry_pc, dut.pc);
                errors = errors + 1;
            end
            cyc = 0;
            @(posedge clk_i); #1; cyc = cyc + 1;
            while (dut.u_control_unit.state !== dut.u_control_unit.FETCH) begin
                @(posedge clk_i); #1; cyc = cyc + 1;
            end
            landed_pc = dut.pc;
        end
    endtask

    task check_cyc;
        input [8*24-1:0] label;
        input integer     exp_cyc;
        input integer     got_cyc;
        begin
            if (got_cyc !== exp_cyc) begin
                $display("FAIL [%0s] cycle count exp=%0d got=%0d (handoff Sec 2: loads=6, stores=4, others=4)",
                          label, exp_cyc, got_cyc);
                errors = errors + 1;
            end
        end
    endtask

    // Check 7: no-x-propagation guard for load destinations
    task check_no_x;
        input [8*24-1:0] label;
        input [31:0]     val;
        begin
            if (^val === 1'bx) begin
                $display("FAIL [%0s] load result is X (unwired/undriven LSU port): got=%h", label, val);
                errors = errors + 1;
            end
        end
    endtask

    task check_reg;
        input [8*24-1:0] label;
        input integer     reg_idx;
        input [31:0]      exp_val;
        begin
            check_no_x(label, dut.u_regfile.regs[reg_idx]);
            if (dut.u_regfile.regs[reg_idx] !== exp_val) begin
                $display("FAIL [%0s] regs[%0d] exp=%h got=%h", label, reg_idx, exp_val, dut.u_regfile.regs[reg_idx]);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] regs[%0d] = %h", label, reg_idx, exp_val);
            end
        end
    endtask

    // 27 straight-line instructions; rd=-1 marks a store (no reg check)
    reg [31:0] EXP_PC  [0:26];
    integer    EXP_CYC [0:26];
    integer    EXP_RD  [0:26];
    reg [31:0] EXP_VAL [0:26];
    reg [8*24-1:0] STEP_LABEL [0:26];

    reg [31:0] landed;
    integer    cyc;
    reg [8*24-1:0] step_label;

    initial begin
        EXP_PC[0]=32'h00400000; EXP_CYC[0]=4; EXP_RD[0]=1;  EXP_VAL[0]=32'h10010000; STEP_LABEL[0]="lui_x1";
        EXP_PC[1]=32'h00400004; EXP_CYC[1]=4; EXP_RD[1]=2;  EXP_VAL[1]=32'h00000555; STEP_LABEL[1]="addi_x2";
        EXP_PC[2]=32'h00400008; EXP_CYC[2]=4; EXP_RD[2]=-1; EXP_VAL[2]=32'h0;        STEP_LABEL[2]="sw_roundtrip";
        EXP_PC[3]=32'h0040000c; EXP_CYC[3]=6; EXP_RD[3]=3;  EXP_VAL[3]=32'h00000555; STEP_LABEL[3]="lw_roundtrip";
        EXP_PC[4]=32'h00400010; EXP_CYC[4]=4; EXP_RD[4]=4;  EXP_VAL[4]=32'h00000099; STEP_LABEL[4]="addi_x4";
        EXP_PC[5]=32'h00400014; EXP_CYC[5]=4; EXP_RD[5]=5;  EXP_VAL[5]=32'h00000345; STEP_LABEL[5]="addi_x5";
        EXP_PC[6]=32'h00400018; EXP_CYC[6]=6; EXP_RD[6]=6;  EXP_VAL[6]=32'hF4F3F2F1; STEP_LABEL[6]="lw_table12";
        EXP_PC[7]=32'h0040001c; EXP_CYC[7]=6; EXP_RD[7]=7;  EXP_VAL[7]=32'hFFFFFFF1; STEP_LABEL[7]="lb_table12";
        EXP_PC[8]=32'h00400020; EXP_CYC[8]=6; EXP_RD[8]=8;  EXP_VAL[8]=32'h000000F1; STEP_LABEL[8]="lbu_table12";
        EXP_PC[9]=32'h00400024; EXP_CYC[9]=6; EXP_RD[9]=9;  EXP_VAL[9]=32'hFFFFF2F1; STEP_LABEL[9]="lh_table12";
        EXP_PC[10]=32'h00400028; EXP_CYC[10]=6; EXP_RD[10]=10; EXP_VAL[10]=32'h0000F2F1; STEP_LABEL[10]="lhu_table12";
        EXP_PC[11]=32'h0040002c; EXP_CYC[11]=6; EXP_RD[11]=11; EXP_VAL[11]=32'hFFFFFFF3; STEP_LABEL[11]="lb_off2_signext";
        EXP_PC[12]=32'h00400030; EXP_CYC[12]=6; EXP_RD[12]=12; EXP_VAL[12]=32'h000000F3; STEP_LABEL[12]="lbu_off2";
        EXP_PC[13]=32'h00400034; EXP_CYC[13]=4; EXP_RD[13]=-1; EXP_VAL[13]=32'h0;        STEP_LABEL[13]="sb_lane0";
        EXP_PC[14]=32'h00400038; EXP_CYC[14]=6; EXP_RD[14]=13; EXP_VAL[14]=32'hAABBCC99; STEP_LABEL[14]="lw_check_lane0";
        EXP_PC[15]=32'h0040003c; EXP_CYC[15]=4; EXP_RD[15]=-1; EXP_VAL[15]=32'h0;        STEP_LABEL[15]="sb_lane1";
        EXP_PC[16]=32'h00400040; EXP_CYC[16]=6; EXP_RD[16]=14; EXP_VAL[16]=32'hAABB99DD; STEP_LABEL[16]="lw_check_lane1";
        EXP_PC[17]=32'h00400044; EXP_CYC[17]=4; EXP_RD[17]=-1; EXP_VAL[17]=32'h0;        STEP_LABEL[17]="sb_lane2";
        EXP_PC[18]=32'h00400048; EXP_CYC[18]=6; EXP_RD[18]=15; EXP_VAL[18]=32'hAA99CCDD; STEP_LABEL[18]="lw_check_lane2";
        EXP_PC[19]=32'h0040004c; EXP_CYC[19]=4; EXP_RD[19]=-1; EXP_VAL[19]=32'h0;        STEP_LABEL[19]="sb_lane3";
        EXP_PC[20]=32'h00400050; EXP_CYC[20]=6; EXP_RD[20]=16; EXP_VAL[20]=32'h99BBCCDD; STEP_LABEL[20]="lw_check_lane3";
        EXP_PC[21]=32'h00400054; EXP_CYC[21]=4; EXP_RD[21]=-1; EXP_VAL[21]=32'h0;        STEP_LABEL[21]="sh_lo";
        EXP_PC[22]=32'h00400058; EXP_CYC[22]=6; EXP_RD[22]=17; EXP_VAL[22]=32'hAABB0345; STEP_LABEL[22]="lw_check_sh_lo";
        EXP_PC[23]=32'h0040005c; EXP_CYC[23]=4; EXP_RD[23]=-1; EXP_VAL[23]=32'h0;        STEP_LABEL[23]="sh_hi";
        EXP_PC[24]=32'h00400060; EXP_CYC[24]=6; EXP_RD[24]=18; EXP_VAL[24]=32'h0345CCDD; STEP_LABEL[24]="lw_check_sh_hi";
        EXP_PC[25]=32'h00400064; EXP_CYC[25]=4; EXP_RD[25]=19; EXP_VAL[25]=32'h00400000; STEP_LABEL[25]="lui_x19_imembase";
        EXP_PC[26]=32'h00400068; EXP_CYC[26]=6; EXP_RD[26]=20; EXP_VAL[26]=32'h100100b7; STEP_LABEL[26]="lw_from_imem";

        $dumpfile("sim/tb_top_mem.vcd");
        $dumpvars(0, tb_top_mem);

        errors = 0;
        cycle_count = 0;
        clk_i = 0;
        rst_i = 1;

        // Testbench-only backdoor DMEM preload (word N = DMEM_BASE + 4*N)
        dut.u_dmem.mem[0] = 32'hF4F3F2F1; // Table 12: bytes F1 F2 F3 F4
        dut.u_dmem.mem[2] = 32'hAABBCCDD; // word@8  (sb lane0 test)
        dut.u_dmem.mem[3] = 32'hAABBCCDD; // word@12 (sb lane1 test)
        dut.u_dmem.mem[4] = 32'hAABBCCDD; // word@16 (sb lane2 test)
        dut.u_dmem.mem[5] = 32'hAABBCCDD; // word@20 (sb lane3 test)
        dut.u_dmem.mem[6] = 32'hAABBCCDD; // word@24 (sh lo test)
        dut.u_dmem.mem[7] = 32'hAABBCCDD; // word@28 (sh hi test)

        @(posedge clk_i); #1; // RESET latched
        if (dut.u_control_unit.state !== dut.u_control_unit.RESET) begin
            $display("FAIL [reset] state exp=RESET got=%0d", dut.u_control_unit.state);
            errors = errors + 1;
        end

        rst_i = 0;
        @(posedge clk_i); #1; // RESET -> FETCH

        for (i = 0; i < 27; i = i + 1) begin
            step_label = STEP_LABEL[i];
            run_instr(step_label, EXP_PC[i], landed, cyc);
            check_cyc(step_label, EXP_CYC[i], cyc);
            if (EXP_RD[i] >= 0)
                check_reg(step_label, EXP_RD[i], EXP_VAL[i]);
        end

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
