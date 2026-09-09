// tb_control_unit.v — directed FSM/control-signal tests, all instruction classes

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_control_unit;

    reg        clk_i;
    reg        rst_i;
    reg [6:0]  opcode_i;
    reg [2:0]  funct3_i;
    reg [6:0]  funct7_i;
    reg [11:0] funct12_i;
    reg [1:0]  addr_lsb_i;
    reg        branch_taken_i;

    wire        pc_write_o;
    wire [1:0]  pc_src_o;
    wire        ir_write_o;
    wire        reg_write_o;
    wire [2:0]  result_src_o;
    wire        alu_src_a_o;
    wire [1:0]  alu_src_b_o;
    wire [3:0]  alu_op_o;
    wire [2:0]  imm_sel_o;
    wire        we_o;
    wire        oe_o;
    wire [3:0]  bw_o;
    wire [2:0]  op_size_o;
    wire        adr_src_o;
    wire [3:0]  mult_op_o;
    wire [3:0]  crc_op_o;
    wire        mult_en_o;
    wire        crc_en_o;
    wire        halt_o;

    integer errors;
    integer halt_errors;   // post-ECALL halt check (handoff §8)
    integer h;             // loop index for the same
    integer ill_errors;    // illegal-opcode silent-no-op check (handoff §8)
    integer k;             // loop index for the same

    // we_o guard: must be 0 outside MEM_ACCESS_STORE, checked every cycle
    always @(*) begin
        if (we_o && dut.state !== dut.MEM_ACCESS_STORE) begin
            $display("FAIL [we_o guard] we_o asserted outside MEM_ACCESS_STORE, state=%0d", dut.state);
            errors = errors + 1;
        end
    end

    // halt_o guard: must never assert before ECALL retires (ecall_seen arms it)
    reg ecall_seen;
    always @(*) begin
        if (halt_o && !ecall_seen) begin
            $display("FAIL [halt_o guard] halt_o asserted with no ECALL retired, state=%0d", dut.state);
            errors = errors + 1;
        end
    end

    // adr_src_o guard: ALU in the 3 memory-access states, PC elsewhere
    always @(*) begin
        // gated on !rst_i: x !== 0/1 reads true during reset delta, not a real defect
        if (!rst_i) begin
            if (dut.state === dut.MEM_ACCESS_ADDR ||
                dut.state === dut.MEM_ACCESS_DATA ||
                dut.state === dut.MEM_ACCESS_STORE) begin
                if (adr_src_o !== `ADR_SRC_ALU) begin
                    $display("FAIL [adr_src_o guard] exp=ALU got=%b, state=%0d", adr_src_o, dut.state);
                    errors = errors + 1;
                end
            end else begin
                if (adr_src_o !== `ADR_SRC_PC) begin
                    $display("FAIL [adr_src_o guard] exp=PC got=%b, state=%0d", adr_src_o, dut.state);
                    errors = errors + 1;
                end
            end
        end
    end

    control_unit dut (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .opcode_i     (opcode_i),
        .funct3_i     (funct3_i),
        .funct7_i     (funct7_i),
        .funct12_i    (funct12_i),
        .addr_lsb_i     (addr_lsb_i),
        .branch_taken_i (branch_taken_i),
        .pc_write_o   (pc_write_o),
        .pc_src_o     (pc_src_o),
        .ir_write_o   (ir_write_o),
        .reg_write_o  (reg_write_o),
        .result_src_o (result_src_o),
        .alu_src_a_o  (alu_src_a_o),
        .alu_src_b_o  (alu_src_b_o),
        .alu_op_o     (alu_op_o),
        .imm_sel_o    (imm_sel_o),
        .mult_op_o      (mult_op_o),
        .crc_op_o       (crc_op_o),
        .mult_en_o    (mult_en_o),
        .crc_en_o     (crc_en_o),
        .we_o         (we_o),
        .oe_o         (oe_o),
        .bw_o         (bw_o),
        .op_size_o    (op_size_o),
        .adr_src_o    (adr_src_o),
        .halt_o       (halt_o)
    );

    // 10ns clock
    always #5 clk_i = ~clk_i;

    // Checker task
    task check_state;
        input [127:0] label;
        input [3:0]   exp_state;
        input         exp_pc_write, exp_ir_write, exp_reg_write;
        input [1:0]   exp_pc_src;
        input [2:0]   exp_result_src;
        input         exp_alu_src_a;
        input [1:0]   exp_alu_src_b;
        input [3:0]   exp_alu_op;
        input         exp_we, exp_oe;
        begin
            if (dut.state !== exp_state) begin
                $display("FAIL [%0s] state: exp=%0d got=%0d", label, exp_state, dut.state);
                errors = errors + 1;
            end
            if (pc_write_o !== exp_pc_write) begin
                $display("FAIL [%0s] pc_write_o: exp=%b got=%b", label, exp_pc_write, pc_write_o);
                errors = errors + 1;
            end
            if (pc_src_o !== exp_pc_src) begin
                $display("FAIL [%0s] pc_src_o: exp=%b got=%b", label, exp_pc_src, pc_src_o);
                errors = errors + 1;
            end
            if (ir_write_o !== exp_ir_write) begin
                $display("FAIL [%0s] ir_write_o: exp=%b got=%b", label, exp_ir_write, ir_write_o);
                errors = errors + 1;
            end
            if (reg_write_o !== exp_reg_write) begin
                $display("FAIL [%0s] reg_write_o: exp=%b got=%b", label, exp_reg_write, reg_write_o);
                errors = errors + 1;
            end
            if (result_src_o !== exp_result_src) begin
                $display("FAIL [%0s] result_src_o: exp=%b got=%b", label, exp_result_src, result_src_o);
                errors = errors + 1;
            end
            if (alu_src_a_o !== exp_alu_src_a) begin
                $display("FAIL [%0s] alu_src_a_o: exp=%b got=%b", label, exp_alu_src_a, alu_src_a_o);
                errors = errors + 1;
            end
            if (alu_src_b_o !== exp_alu_src_b) begin
                $display("FAIL [%0s] alu_src_b_o: exp=%b got=%b", label, exp_alu_src_b, alu_src_b_o);
                errors = errors + 1;
            end
            if (alu_op_o !== exp_alu_op) begin
                $display("FAIL [%0s] alu_op_o: exp=%h got=%h", label, exp_alu_op, alu_op_o);
                errors = errors + 1;
            end
            if (we_o !== exp_we) begin
                $display("FAIL [%0s] we_o: exp=%b got=%b", label, exp_we, we_o);
                errors = errors + 1;
            end
            if (oe_o !== exp_oe) begin
                $display("FAIL [%0s] oe_o: exp=%b got=%b", label, exp_oe, oe_o);
                errors = errors + 1;
            end
        end
    endtask

    // R-type/base loop: FETCH->DECODE->EXECUTE_ALU->WRITE_BACK->FETCH, 4 cycles
    task run_instruction;
        input [127:0] label;
        input [3:0]   exp_alu_op;
        integer cycle_count;
        begin
            // Assumes we enter this task with dut.state == FETCH already
            cycle_count = 0;

            // FETCH
            check_state({label,"-FETCH"}, 4'd1, 1'b1,1'b1,1'b0, `PC_SRC_PLUS4,
                         `RESULT_SRC_ALU, `ALU_SRC_A_RS1, `ALU_SRC_B_RS2, `ALU_PASS_B, 1'b0,1'b1);
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // DECODE
            check_state({label,"-DECODE"}, 4'd2, 1'b0,1'b0,1'b0, `PC_SRC_PLUS4,
                         `RESULT_SRC_ALU, `ALU_SRC_A_RS1, `ALU_SRC_B_RS2, `ALU_PASS_B, 1'b0,1'b0);
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // EXECUTE_ALU
            check_state({label,"-EXECUTE_ALU"}, 4'd3, 1'b0,1'b0,1'b0, `PC_SRC_PLUS4,
                         `RESULT_SRC_ALU, `ALU_SRC_A_RS1, `ALU_SRC_B_RS2, exp_alu_op, 1'b0,1'b0);
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // WRITE_BACK
            check_state({label,"-WRITE_BACK"}, 4'd4, 1'b0,1'b0,1'b1, `PC_SRC_PLUS4,
                         `RESULT_SRC_ALU, `ALU_SRC_A_RS1, `ALU_SRC_B_RS2, `ALU_PASS_B, 1'b0,1'b0);
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // back to FETCH
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] did not return to FETCH: got=%0d", label, dut.state);
                errors = errors + 1;
            end

            if (cycle_count !== 4) begin
                $display("FAIL [%0s] cycle count: exp=4 got=%0d", label, cycle_count);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] cycle count = 4 (handoff Sec 2)", label);
            end
        end
    endtask

    // Load: FETCH->DECODE->MEM_ADDR->MEM_ACCESS_ADDR->MEM_ACCESS_DATA->WRITE_BACK, 6 cycles
    task run_load;
        input [127:0] label;
        input [2:0]   exp_op_size;
        input [3:0]   exp_bw;
        integer cycle_count;
        begin
            cycle_count = 0;

            // FETCH
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] expected FETCH, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // DECODE
            if (dut.state !== 4'd2) begin
                $display("FAIL [%0s] expected DECODE, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (imm_sel_o !== `IMM_SEL_I) begin
                $display("FAIL [%0s-DECODE] imm_sel_o: exp=%b got=%b", label, `IMM_SEL_I, imm_sel_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // MEM_ADDR
            if (dut.state !== 4'd5) begin
                $display("FAIL [%0s] expected MEM_ADDR, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (alu_op_o !== `ALU_ADD) begin
                $display("FAIL [%0s-MEM_ADDR] alu_op_o: exp=ADD got=%h", label, alu_op_o);
                errors = errors + 1;
            end
            if (op_size_o !== exp_op_size) begin
                $display("FAIL [%0s-MEM_ADDR] op_size_o: exp=%b got=%b", label, exp_op_size, op_size_o);
                errors = errors + 1;
            end
            if (bw_o !== exp_bw) begin
                $display("FAIL [%0s-MEM_ADDR] bw_o: exp=%b got=%b", label, exp_bw, bw_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // MEM_ACCESS_ADDR
            if (dut.state !== 4'd6) begin
                $display("FAIL [%0s] expected MEM_ACCESS_ADDR, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (oe_o !== 1'b1) begin
                $display("FAIL [%0s-MEM_ACCESS_ADDR] oe_o: exp=1 got=%b", label, oe_o);
                errors = errors + 1;
            end
            if (op_size_o !== exp_op_size) begin
                $display("FAIL [%0s-MEM_ACCESS_ADDR] op_size_o: exp=%b got=%b", label, exp_op_size, op_size_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // MEM_ACCESS_DATA
            if (dut.state !== 4'd7) begin
                $display("FAIL [%0s] expected MEM_ACCESS_DATA, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (result_src_o !== `RESULT_SRC_MEM) begin
                $display("FAIL [%0s-MEM_ACCESS_DATA] result_src_o: exp=MEM got=%b", label, result_src_o);
                errors = errors + 1;
            end
            // op_size_o must stay driven here, not fall back to WORD default
            if (op_size_o !== exp_op_size) begin
                $display("FAIL [%0s-MEM_ACCESS_DATA] op_size_o: exp=%b got=%b", label, exp_op_size, op_size_o);
                errors = errors + 1;
            end
            // oe_o must be re-asserted here — imem.v drops output when oe_i low
            if (oe_o !== 1'b1) begin
                $display("FAIL [%0s-MEM_ACCESS_DATA] oe_o: exp=1 got=%b", label, oe_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // WRITE_BACK
            if (dut.state !== 4'd4) begin
                $display("FAIL [%0s] expected WRITE_BACK, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (reg_write_o !== 1'b1) begin
                $display("FAIL [%0s-WRITE_BACK] reg_write_o: exp=1 got=%b", label, reg_write_o);
                errors = errors + 1;
            end
            if (result_src_o !== `RESULT_SRC_MEM) begin
                $display("FAIL [%0s-WRITE_BACK] result_src_o: exp=MEM got=%b", label, result_src_o);
                errors = errors + 1;
            end
            // op_size_o must still be driven here too (commit state)
            if (op_size_o !== exp_op_size) begin
                $display("FAIL [%0s-WRITE_BACK] op_size_o: exp=%b got=%b", label, exp_op_size, op_size_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] did not return to FETCH: got=%0d", label, dut.state);
                errors = errors + 1;
            end

            if (cycle_count !== 6) begin
                $display("FAIL [%0s] cycle count: exp=6 got=%0d", label, cycle_count);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] cycle count = 6 (handoff Sec 2)", label);
            end
        end
    endtask

    // Store: FETCH->DECODE->MEM_ADDR->MEM_ACCESS_STORE->FETCH, no WRITE_BACK
    task run_store;
        input [127:0] label;
        input [2:0]   exp_op_size;
        input [3:0]   exp_bw;
        integer cycle_count;
        begin
            cycle_count = 0;

            // FETCH
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] expected FETCH, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // DECODE
            if (dut.state !== 4'd2) begin
                $display("FAIL [%0s] expected DECODE, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (imm_sel_o !== `IMM_SEL_S) begin
                $display("FAIL [%0s-DECODE] imm_sel_o: exp=%b got=%b", label, `IMM_SEL_S, imm_sel_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // MEM_ADDR
            if (dut.state !== 4'd5) begin
                $display("FAIL [%0s] expected MEM_ADDR, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (we_o !== 1'b0) begin
                $display("FAIL [%0s-MEM_ADDR] we_o: exp=0 got=%b", label, we_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // MEM_ACCESS_STORE
            if (dut.state !== 4'd8) begin
                $display("FAIL [%0s] expected MEM_ACCESS_STORE, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (we_o !== 1'b1) begin
                $display("FAIL [%0s-MEM_ACCESS_STORE] we_o: exp=1 got=%b", label, we_o);
                errors = errors + 1;
            end
            if (op_size_o !== exp_op_size) begin
                $display("FAIL [%0s-MEM_ACCESS_STORE] op_size_o: exp=%b got=%b", label, exp_op_size, op_size_o);
                errors = errors + 1;
            end
            if (bw_o !== exp_bw) begin
                $display("FAIL [%0s-MEM_ACCESS_STORE] bw_o: exp=%b got=%b", label, exp_bw, bw_o);
                errors = errors + 1;
            end
            if (reg_write_o !== 1'b0) begin
                $display("FAIL [%0s-MEM_ACCESS_STORE] reg_write_o: exp=0 got=%b", label, reg_write_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // back to FETCH, no WRITE_BACK
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] did not return to FETCH: got=%0d", label, dut.state);
                errors = errors + 1;
            end

            // store is 4 cycles; handoff's "5 cycles" was a doc-only inconsistency
            if (cycle_count !== 4) begin
                $display("FAIL [%0s] cycle count: exp=4 got=%0d", label, cycle_count);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] cycle count = 4 (handoff Sec 2, corrected)", label);
            end
        end
    endtask

    // Branch: FETCH->DECODE->EXECUTE_ALU->FETCH, 3 cycles, pc_write_o follows branch_taken_i
    task run_branch;
        input [127:0] label;
        input         taken;
        integer cycle_count;
        begin
            cycle_count = 0;
            branch_taken_i = taken;

            // FETCH
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] expected FETCH, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // DECODE
            if (dut.state !== 4'd2) begin
                $display("FAIL [%0s] expected DECODE, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (imm_sel_o !== `IMM_SEL_B) begin
                $display("FAIL [%0s-DECODE] imm_sel_o: exp=%b got=%b", label, `IMM_SEL_B, imm_sel_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // EXECUTE_ALU (branch case)
            if (dut.state !== 4'd3) begin
                $display("FAIL [%0s] expected EXECUTE_ALU, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (pc_write_o !== taken) begin
                $display("FAIL [%0s-EXECUTE] pc_write_o: exp=%b (branch_taken_i) got=%b", label, taken, pc_write_o);
                errors = errors + 1;
            end
            if (pc_src_o !== `PC_SRC_TARGET) begin
                $display("FAIL [%0s-EXECUTE] pc_src_o: exp=TARGET got=%b", label, pc_src_o);
                errors = errors + 1;
            end
            if (alu_src_a_o !== `ALU_SRC_A_PC) begin
                $display("FAIL [%0s-EXECUTE] alu_src_a_o: exp=PC got=%b", label, alu_src_a_o);
                errors = errors + 1;
            end
            if (reg_write_o !== 1'b0) begin
                $display("FAIL [%0s-EXECUTE] reg_write_o: exp=0 got=%b", label, reg_write_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // back to FETCH, no WRITE_BACK
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] did not return to FETCH: got=%0d", label, dut.state);
                errors = errors + 1;
            end

            if (cycle_count !== 3) begin
                $display("FAIL [%0s] cycle count: exp=3 got=%0d", label, cycle_count);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] cycle count = 3 (handoff Sec 2)", label);
            end
        end
    endtask

    // JAL/JALR: FETCH->DECODE->EXECUTE_ALU->WRITE_BACK->FETCH, is_jalr selects check variant
    task run_jump;
        input [127:0] label;
        input         is_jalr;
        integer cycle_count;
        begin
            cycle_count = 0;

            // FETCH
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] expected FETCH, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // DECODE
            if (dut.state !== 4'd2) begin
                $display("FAIL [%0s] expected DECODE, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (is_jalr) begin
                if (imm_sel_o !== `IMM_SEL_I) begin
                    $display("FAIL [%0s-DECODE] imm_sel_o: exp=I got=%b", label, imm_sel_o);
                    errors = errors + 1;
                end
            end else begin
                if (imm_sel_o !== `IMM_SEL_J) begin
                    $display("FAIL [%0s-DECODE] imm_sel_o: exp=J got=%b", label, imm_sel_o);
                    errors = errors + 1;
                end
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // EXECUTE_ALU
            if (dut.state !== 4'd3) begin
                $display("FAIL [%0s] expected EXECUTE_ALU, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (pc_write_o !== 1'b1) begin
                $display("FAIL [%0s-EXECUTE] pc_write_o: exp=1 got=%b", label, pc_write_o);
                errors = errors + 1;
            end
            if (result_src_o !== `RESULT_SRC_PC4) begin
                $display("FAIL [%0s-EXECUTE] result_src_o: exp=PC4 got=%b", label, result_src_o);
                errors = errors + 1;
            end
            if (is_jalr) begin
                if (pc_src_o !== `PC_SRC_JALR) begin
                    $display("FAIL [%0s-EXECUTE] pc_src_o: exp=JALR got=%b", label, pc_src_o);
                    errors = errors + 1;
                end
                if (alu_src_a_o !== `ALU_SRC_A_RS1) begin
                    $display("FAIL [%0s-EXECUTE] alu_src_a_o: exp=RS1 got=%b", label, alu_src_a_o);
                    errors = errors + 1;
                end
            end else begin
                if (pc_src_o !== `PC_SRC_TARGET) begin
                    $display("FAIL [%0s-EXECUTE] pc_src_o: exp=TARGET got=%b", label, pc_src_o);
                    errors = errors + 1;
                end
                if (alu_src_a_o !== `ALU_SRC_A_PC) begin
                    $display("FAIL [%0s-EXECUTE] alu_src_a_o: exp=PC got=%b", label, alu_src_a_o);
                    errors = errors + 1;
                end
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // WRITE_BACK
            if (dut.state !== 4'd4) begin
                $display("FAIL [%0s] expected WRITE_BACK, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (reg_write_o !== 1'b1) begin
                $display("FAIL [%0s-WRITE_BACK] reg_write_o: exp=1 got=%b", label, reg_write_o);
                errors = errors + 1;
            end
            if (result_src_o !== `RESULT_SRC_PC4) begin
                $display("FAIL [%0s-WRITE_BACK] result_src_o: exp=PC4 got=%b", label, result_src_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] did not return to FETCH: got=%0d", label, dut.state);
                errors = errors + 1;
            end

            if (cycle_count !== 4) begin
                $display("FAIL [%0s] cycle count: exp=4 got=%0d", label, cycle_count);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] cycle count = 4 (handoff Sec 2)", label);
            end
        end
    endtask

    // MUL/CRC: FETCH->DECODE->EXECUTE_ALU->WRITE_BACK->FETCH, mult_op_o/crc_op_o = funct3 passthrough
    task run_mulcrc;
        input [127:0] label;
        input         is_crc;
        integer cycle_count;
        begin
            cycle_count = 0;

            // FETCH
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] expected FETCH, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // DECODE
            if (dut.state !== 4'd2) begin
                $display("FAIL [%0s] expected DECODE, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // EXECUTE_ALU
            if (dut.state !== 4'd3) begin
                $display("FAIL [%0s] expected EXECUTE_ALU, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (is_crc) begin
                if (crc_en_o !== 1'b1) begin
                    $display("FAIL [%0s-EXECUTE] crc_en_o: exp=1 got=%b", label, crc_en_o);
                    errors = errors + 1;
                end
                if (mult_en_o !== 1'b0) begin
                    $display("FAIL [%0s-EXECUTE] mult_en_o: exp=0 got=%b", label, mult_en_o);
                    errors = errors + 1;
                end
                if (crc_op_o !== {1'b0, funct3_i}) begin
                    $display("FAIL [%0s-EXECUTE] crc_op_o: exp=%h got=%h", label, {1'b0, funct3_i}, crc_op_o);
                    errors = errors + 1;
                end
                if (result_src_o !== `RESULT_SRC_CRC) begin
                    $display("FAIL [%0s-EXECUTE] result_src_o: exp=CRC got=%b", label, result_src_o);
                    errors = errors + 1;
                end
            end else begin
                if (mult_en_o !== 1'b1) begin
                    $display("FAIL [%0s-EXECUTE] mult_en_o: exp=1 got=%b", label, mult_en_o);
                    errors = errors + 1;
                end
                if (crc_en_o !== 1'b0) begin
                    $display("FAIL [%0s-EXECUTE] crc_en_o: exp=0 got=%b", label, crc_en_o);
                    errors = errors + 1;
                end
                if (mult_op_o !== {1'b0, funct3_i}) begin
                    $display("FAIL [%0s-EXECUTE] mult_op_o: exp=%h got=%h", label, {1'b0, funct3_i}, mult_op_o);
                    errors = errors + 1;
                end
                if (result_src_o !== `RESULT_SRC_MUL) begin
                    $display("FAIL [%0s-EXECUTE] result_src_o: exp=MUL got=%b", label, result_src_o);
                    errors = errors + 1;
                end
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // WRITE_BACK
            if (dut.state !== 4'd4) begin
                $display("FAIL [%0s] expected WRITE_BACK, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (reg_write_o !== 1'b1) begin
                $display("FAIL [%0s-WRITE_BACK] reg_write_o: exp=1 got=%b", label, reg_write_o);
                errors = errors + 1;
            end
            if (is_crc) begin
                if (result_src_o !== `RESULT_SRC_CRC) begin
                    $display("FAIL [%0s-WRITE_BACK] result_src_o: exp=CRC got=%b", label, result_src_o);
                    errors = errors + 1;
                end
            end else begin
                if (result_src_o !== `RESULT_SRC_MUL) begin
                    $display("FAIL [%0s-WRITE_BACK] result_src_o: exp=MUL got=%b", label, result_src_o);
                    errors = errors + 1;
                end
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] did not return to FETCH: got=%0d", label, dut.state);
                errors = errors + 1;
            end

            if (cycle_count !== 4) begin
                $display("FAIL [%0s] cycle count: exp=4 got=%0d", label, cycle_count);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] cycle count = 4 (handoff Sec 2)", label);
            end
        end
    endtask

    // LUI/AUIPC: FETCH->DECODE->EXECUTE_ALU->WRITE_BACK->FETCH, is_auipc selects check variant
    task run_lui_auipc;
        input [127:0] label;
        input         is_auipc;
        integer cycle_count;
        begin
            cycle_count = 0;

            // FETCH
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] expected FETCH, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // DECODE
            if (dut.state !== 4'd2) begin
                $display("FAIL [%0s] expected DECODE, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (imm_sel_o !== `IMM_SEL_U) begin
                $display("FAIL [%0s-DECODE] imm_sel_o: exp=U got=%b", label, imm_sel_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // EXECUTE_ALU
            if (dut.state !== 4'd3) begin
                $display("FAIL [%0s] expected EXECUTE_ALU, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (alu_src_b_o !== `ALU_SRC_B_IMM) begin
                $display("FAIL [%0s-EXECUTE] alu_src_b_o: exp=IMM got=%b", label, alu_src_b_o);
                errors = errors + 1;
            end
            if (is_auipc) begin
                if (alu_op_o !== `ALU_ADD) begin
                    $display("FAIL [%0s-EXECUTE] alu_op_o: exp=ADD got=%h", label, alu_op_o);
                    errors = errors + 1;
                end
                if (alu_src_a_o !== `ALU_SRC_A_PC) begin
                    $display("FAIL [%0s-EXECUTE] alu_src_a_o: exp=PC got=%b", label, alu_src_a_o);
                    errors = errors + 1;
                end
            end else begin
                if (alu_op_o !== `ALU_PASS_B) begin
                    $display("FAIL [%0s-EXECUTE] alu_op_o: exp=PASS_B got=%h", label, alu_op_o);
                    errors = errors + 1;
                end
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // WRITE_BACK
            if (dut.state !== 4'd4) begin
                $display("FAIL [%0s] expected WRITE_BACK, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (reg_write_o !== 1'b1) begin
                $display("FAIL [%0s-WRITE_BACK] reg_write_o: exp=1 got=%b", label, reg_write_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] did not return to FETCH: got=%0d", label, dut.state);
                errors = errors + 1;
            end

            if (cycle_count !== 4) begin
                $display("FAIL [%0s] cycle count: exp=4 got=%0d", label, cycle_count);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] cycle count = 4 (handoff Sec 2)", label);
            end
        end
    endtask

    // System no-op (ECALL/EBREAK/FENCE): FETCH->DECODE->EXECUTE_ALU->FETCH, 3 cycles
    task run_system_nop;
        input [127:0] label;
        input         exp_halt;   // halt_o expected once the instruction retires
        integer cycle_count;
        reg     halt_at_entry;
        begin
            cycle_count   = 0;
            halt_at_entry = halt_o;  // sticky flags may already be set

            // FETCH
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] expected FETCH, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // DECODE
            if (dut.state !== 4'd2) begin
                $display("FAIL [%0s] expected DECODE, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            // halt_o latches at end of EXECUTE_ALU, must not move during DECODE
            if (halt_o !== halt_at_entry) begin
                $display("FAIL [%0s-DECODE] halt_o changed before retire: entry=%b got=%b",
                         label, halt_at_entry, halt_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // EXECUTE_ALU (no-op)
            if (dut.state !== 4'd3) begin
                $display("FAIL [%0s] expected EXECUTE_ALU, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (halt_o !== halt_at_entry) begin
                $display("FAIL [%0s-EXECUTE] halt_o changed before retire: entry=%b got=%b",
                         label, halt_at_entry, halt_o);
                errors = errors + 1;
            end
            if (reg_write_o !== 1'b0) begin
                $display("FAIL [%0s-EXECUTE] reg_write_o: exp=0 got=%b", label, reg_write_o);
                errors = errors + 1;
            end
            if (we_o !== 1'b0) begin
                $display("FAIL [%0s-EXECUTE] we_o: exp=0 got=%b", label, we_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // back to FETCH, no WRITE_BACK
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] did not return to FETCH: got=%0d", label, dut.state);
                errors = errors + 1;
            end

            if (cycle_count !== 3) begin
                $display("FAIL [%0s] cycle count: exp=3 got=%0d", label, cycle_count);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] cycle count = 3 (handoff Sec 2)", label);
            end

            // halt_o now that the instruction has retired.
            if (halt_o !== exp_halt) begin
                $display("FAIL [%0s] halt_o after retire: exp=%b got=%b", label, exp_halt, halt_o);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] halt_o = %b after retire", label, exp_halt);
            end
        end
    endtask

    // I-type ALU: same as run_instruction but alu_src_b_o=IMM, imm_sel_o=I
    task run_itype;
        input [127:0] label;
        input [3:0]   exp_alu_op;
        integer cycle_count;
        begin
            cycle_count = 0;

            // FETCH
            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] expected FETCH, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // DECODE
            if (dut.state !== 4'd2) begin
                $display("FAIL [%0s] expected DECODE, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (imm_sel_o !== `IMM_SEL_I) begin
                $display("FAIL [%0s-DECODE] imm_sel_o: exp=I got=%b", label, imm_sel_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // EXECUTE_ALU
            if (dut.state !== 4'd3) begin
                $display("FAIL [%0s] expected EXECUTE_ALU, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (alu_src_b_o !== `ALU_SRC_B_IMM) begin
                $display("FAIL [%0s-EXECUTE] alu_src_b_o: exp=IMM got=%b", label, alu_src_b_o);
                errors = errors + 1;
            end
            if (alu_op_o !== exp_alu_op) begin
                $display("FAIL [%0s-EXECUTE] alu_op_o: exp=%h got=%h", label, exp_alu_op, alu_op_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            // WRITE_BACK
            if (dut.state !== 4'd4) begin
                $display("FAIL [%0s] expected WRITE_BACK, got=%0d", label, dut.state);
                errors = errors + 1;
            end
            if (reg_write_o !== 1'b1) begin
                $display("FAIL [%0s-WRITE_BACK] reg_write_o: exp=1 got=%b", label, reg_write_o);
                errors = errors + 1;
            end
            if (result_src_o !== `RESULT_SRC_ALU) begin
                $display("FAIL [%0s-WRITE_BACK] result_src_o: exp=ALU got=%b", label, result_src_o);
                errors = errors + 1;
            end
            @(posedge clk_i); #1; cycle_count = cycle_count + 1;

            if (dut.state !== 4'd1) begin
                $display("FAIL [%0s] did not return to FETCH: got=%0d", label, dut.state);
                errors = errors + 1;
            end

            if (cycle_count !== 4) begin
                $display("FAIL [%0s] cycle count: exp=4 got=%0d", label, cycle_count);
                errors = errors + 1;
            end else begin
                $display("PASS [%0s] cycle count = 4 (handoff Sec 2)", label);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_control_unit.vcd");
        $dumpvars(0, tb_control_unit);

        errors = 0;
        clk_i = 0;
        rst_i = 1;
        opcode_i = `OPCODE_RTYPE;
        funct3_i = 3'b000;
        funct7_i = 7'b0000000;
        // default EBREAK not ECALL, so no unrelated test latches halt_o by accident
        funct12_i = `FUNCT12_EBREAK;
        addr_lsb_i = 2'b00;
        branch_taken_i = 1'b0;
        ecall_seen = 1'b0;

        @(posedge clk_i); #1;
        if (dut.state !== 4'd0) begin
            $display("FAIL [reset] state: exp=RESET(0) got=%0d", dut.state);
            errors = errors + 1;
        end
        if (halt_o !== 1'b0) begin
            $display("FAIL [reset] halt_o: exp=0 got=%b", halt_o);
            errors = errors + 1;
        end else begin
            $display("PASS [reset] halt_o = 0 out of reset");
        end
        rst_i = 0;
        @(posedge clk_i); #1; // RESET -> FETCH transition lands here

        // ---- Test 1: add x5, x6, x7 (funct3=000, funct7=0000000) ----
        opcode_i = `OPCODE_RTYPE;
        funct3_i = 3'b000;
        funct7_i = 7'b0000000;
        run_instruction("ADD", `ALU_ADD);

        // ---- Test 2: sub x5, x6, x7 -- funct7[5] ADD/SUB disambiguation ----
        opcode_i = `OPCODE_RTYPE;
        funct3_i = 3'b000;
        funct7_i = 7'b0100000;
        run_instruction("SUB", `ALU_SUB);

        // ---- Test 3: srl x5, x6, x7 (funct3=101, funct7=0000000) ----
        opcode_i = `OPCODE_RTYPE;
        funct3_i = 3'b101;
        funct7_i = 7'b0000000;
        run_instruction("SRL", `ALU_SRL);

        // ---- Test 4: sra x5, x6, x7 -- same trap as SUB, different funct3 ----
        opcode_i = `OPCODE_RTYPE;
        funct3_i = 3'b101;
        funct7_i = 7'b0100000;
        run_instruction("SRA", `ALU_MRS);

        // ---- Remaining R-type ops: full 10/10 coverage ----
        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b001; funct7_i = 7'b0000000;
        run_instruction("SLL", `ALU_SLL);

        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b010; funct7_i = 7'b0000000;
        run_instruction("SLT", `ALU_SLT);

        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b011; funct7_i = 7'b0000000;
        run_instruction("SLTU", `ALU_SLTU);

        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b100; funct7_i = 7'b0000000;
        run_instruction("XOR", `ALU_XOR);

        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b110; funct7_i = 7'b0000000;
        run_instruction("OR", `ALU_OR);

        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b111; funct7_i = 7'b0000000;
        run_instruction("AND", `ALU_AND);

        // Load/store: vectors from handoff Table 12 (DMEM 0xF1/F2/F3/F4 @ 0x10010000)

        // ---- lbu x5, 0(x6) @ 0x10010000 -> op_size=BYTE_U, addr[1:0]=00 -> bw=0001
        opcode_i = `OPCODE_LOAD; funct3_i = 3'b100; addr_lsb_i = 2'b00;
        run_load("LBU", `OP_SIZE_BYTE_U, 4'b0001);

        // ---- lb x5, 0(x6) @ 0x10010000 -> op_size=BYTE_S, addr[1:0]=00 -> bw=0001
        opcode_i = `OPCODE_LOAD; funct3_i = 3'b000; addr_lsb_i = 2'b00;
        run_load("LB", `OP_SIZE_BYTE_S, 4'b0001);

        // ---- lhu x5, 0(x6) @ 0x10010000 -> op_size=HALF_U, addr[1]=0 -> bw=0011
        opcode_i = `OPCODE_LOAD; funct3_i = 3'b101; addr_lsb_i = 2'b00;
        run_load("LHU", `OP_SIZE_HALF_U, 4'b0011);

        // ---- lh x5, 0(x6) @ 0x10010000 -> op_size=HALF_S, addr[1]=0 -> bw=0011
        opcode_i = `OPCODE_LOAD; funct3_i = 3'b001; addr_lsb_i = 2'b00;
        run_load("LH", `OP_SIZE_HALF_S, 4'b0011);

        // ---- lw x5, 0(x6) @ 0x10010000 -> op_size=WORD -> bw=1111
        opcode_i = `OPCODE_LOAD; funct3_i = 3'b010; addr_lsb_i = 2'b00;
        run_load("LW", `OP_SIZE_WORD, 4'b1111);

        // ---- lb x5, 2(x6) @ 0x10010002 -> byte repositioning, addr[1:0]=10 -> bw=0100
        opcode_i = `OPCODE_LOAD; funct3_i = 3'b000; addr_lsb_i = 2'b10;
        run_load("LB_OFS2", `OP_SIZE_BYTE_S, 4'b0100);

        // ---- sb x5, 0(x6) @ 0x10010000 -> op_size=BYTE_S (sign don't-care), bw=0001
        opcode_i = `OPCODE_STORE; funct3_i = 3'b000; addr_lsb_i = 2'b00;
        run_store("SB", `OP_SIZE_BYTE_S, 4'b0001);

        // ---- sh x5, 0(x6) @ 0x10010000 -> op_size=HALF_S, addr[1]=0 -> bw=0011
        opcode_i = `OPCODE_STORE; funct3_i = 3'b001; addr_lsb_i = 2'b00;
        run_store("SH", `OP_SIZE_HALF_S, 4'b0011);

        // ---- sw x5, 0(x6) @ 0x10010000 -> op_size=WORD -> bw=1111
        opcode_i = `OPCODE_STORE; funct3_i = 3'b010; addr_lsb_i = 2'b00;
        run_store("SW", `OP_SIZE_WORD, 4'b1111);

        // Branch/jump: control unit doesn't decode branch funct3 (comparator's job);
        // all 6 branches loop through to guard against future funct3 dependency
        opcode_i = `OPCODE_BRANCH; funct3_i = 3'b000; // beq
        run_branch("BEQ_NOTTAKEN", 1'b0);
        run_branch("BEQ_TAKEN", 1'b1);

        opcode_i = `OPCODE_BRANCH; funct3_i = 3'b001; // bne
        run_branch("BNE_NOTTAKEN", 1'b0);
        run_branch("BNE_TAKEN", 1'b1);

        opcode_i = `OPCODE_BRANCH; funct3_i = 3'b100; // blt
        run_branch("BLT_NOTTAKEN", 1'b0);
        run_branch("BLT_TAKEN", 1'b1);

        opcode_i = `OPCODE_BRANCH; funct3_i = 3'b101; // bge
        run_branch("BGE_NOTTAKEN", 1'b0);
        run_branch("BGE_TAKEN", 1'b1);

        opcode_i = `OPCODE_BRANCH; funct3_i = 3'b110; // bltu
        run_branch("BLTU_NOTTAKEN", 1'b0);
        run_branch("BLTU_TAKEN", 1'b1);

        opcode_i = `OPCODE_BRANCH; funct3_i = 3'b111; // bgeu
        run_branch("BGEU_NOTTAKEN", 1'b0);
        run_branch("BGEU_TAKEN", 1'b1);

        branch_taken_i = 1'b0; // restore default, not used by JAL/JALR

        opcode_i = `OPCODE_JAL;
        run_jump("JAL", 1'b0);

        opcode_i = `OPCODE_JALR;
        run_jump("JALR", 1'b1);

        // MUL/CRC: both OPCODE_RTYPE, disambiguated by funct7; SUB/SRA regression follows
        opcode_i = `OPCODE_RTYPE; funct7_i = `FUNCT7_MUL; funct3_i = 3'b000; // mul
        run_mulcrc("MUL", 1'b0);

        opcode_i = `OPCODE_RTYPE; funct7_i = `FUNCT7_MUL; funct3_i = 3'b001; // mulh
        run_mulcrc("MULH", 1'b0);

        opcode_i = `OPCODE_RTYPE; funct7_i = `FUNCT7_MUL; funct3_i = 3'b010; // mulhsu
        run_mulcrc("MULHSU", 1'b0);

        opcode_i = `OPCODE_RTYPE; funct7_i = `FUNCT7_MUL; funct3_i = 3'b011; // mulhu
        run_mulcrc("MULHU", 1'b0);

        opcode_i = `OPCODE_RTYPE; funct7_i = `FUNCT7_CRC; funct3_i = 3'b000; // crcb
        run_mulcrc("CRCB", 1'b1);

        opcode_i = `OPCODE_RTYPE; funct7_i = `FUNCT7_CRC; funct3_i = 3'b001; // crch
        run_mulcrc("CRCH", 1'b1);

        opcode_i = `OPCODE_RTYPE; funct7_i = `FUNCT7_CRC; funct3_i = 3'b010; // crcw
        run_mulcrc("CRCW", 1'b1);

        // ---- Regression: SUB/SRA must not misroute into MUL/CRC branches ----
        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b000; funct7_i = 7'b0100000;
        run_instruction("SUB_REGRESSION", `ALU_SUB);

        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b101; funct7_i = 7'b0100000;
        run_instruction("SRA_REGRESSION", `ALU_MRS);

        // LUI / AUIPC / system no-ops
        opcode_i = `OPCODE_LUI;
        run_lui_auipc("LUI", 1'b0);

        opcode_i = `OPCODE_AUIPC;
        run_lui_auipc("AUIPC", 1'b1);

        // EBREAK must NOT halt (only ECALL does) -- real test of funct12 decode
        opcode_i = `OPCODE_SYSTEM; funct3_i = 3'b000; funct12_i = `FUNCT12_EBREAK;
        run_system_nop("EBREAK", 1'b0);

        // FENCE: different opcode, shares the same no-op arm
        opcode_i = `OPCODE_FENCE;
        run_system_nop("FENCE", 1'b0);

        // I-type ALU: 9 ops (no SUBI); ADDI must NOT consult bit30 unlike SRAI/SRLI
        opcode_i = `OPCODE_ITYPE; funct3_i = 3'b000; funct7_i = 7'b0000000; // addi
        run_itype("ADDI", `ALU_ADD);

        opcode_i = `OPCODE_ITYPE; funct3_i = 3'b000; funct7_i = 7'b0100000; // addi w/ bit30=1 -- must NOT decode as SUB
        run_itype("ADDI_BIT30_TRAP", `ALU_ADD);

        opcode_i = `OPCODE_ITYPE; funct3_i = 3'b010; funct7_i = 7'b0000000; // slti
        run_itype("SLTI", `ALU_SLT);

        opcode_i = `OPCODE_ITYPE; funct3_i = 3'b011; funct7_i = 7'b0000000; // sltiu
        run_itype("SLTIU", `ALU_SLTU);

        opcode_i = `OPCODE_ITYPE; funct3_i = 3'b100; funct7_i = 7'b0000000; // xori
        run_itype("XORI", `ALU_XOR);

        opcode_i = `OPCODE_ITYPE; funct3_i = 3'b110; funct7_i = 7'b0000000; // ori
        run_itype("ORI", `ALU_OR);

        opcode_i = `OPCODE_ITYPE; funct3_i = 3'b111; funct7_i = 7'b0000000; // andi
        run_itype("ANDI", `ALU_AND);

        opcode_i = `OPCODE_ITYPE; funct3_i = 3'b001; funct7_i = 7'b0000000; // slli
        run_itype("SLLI", `ALU_SLL);

        opcode_i = `OPCODE_ITYPE; funct3_i = 3'b101; funct7_i = 7'b0000000; // srli, bit30=0
        run_itype("SRLI", `ALU_SRL);

        opcode_i = `OPCODE_ITYPE; funct3_i = 3'b101; funct7_i = 7'b0100000; // srai, bit30=1
        run_itype("SRAI", `ALU_MRS);

        // ---- Regression: I-type ADDI fix must not break R-type's SUB path ----
        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b000; funct7_i = 7'b0000000;
        run_instruction("ADD_REGRESSION2", `ALU_ADD);

        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b000; funct7_i = 7'b0100000;
        run_instruction("SUB_REGRESSION2", `ALU_SUB);

        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b101; funct7_i = 7'b0100000;
        run_instruction("SRA_REGRESSION2", `ALU_MRS);

        // Illegal opcode: silent no-op (handoff §8). Runs before ECALL block
        // since halt_o is sticky. custom-0 (0001011) is unimplemented but real.
        opcode_i = 7'b0001011; funct3_i = 3'b000; funct7_i = 7'b0000000;
        funct12_i = `FUNCT12_EBREAK;
        ill_errors = 0;

        // FETCH
        if (dut.state !== 4'd1) begin
            $display("FAIL [ILLEGAL] not at FETCH on entry: state=%0d", dut.state);
            ill_errors = ill_errors + 1;
        end
        for (k = 0; k < 3; k = k + 1) begin
            if (reg_write_o !== 1'b0) begin
                $display("FAIL [ILLEGAL] reg_write_o asserted: cycle=%0d state=%0d", k, dut.state);
                ill_errors = ill_errors + 1;
            end
            if (we_o !== 1'b0) begin
                $display("FAIL [ILLEGAL] we_o asserted: cycle=%0d state=%0d", k, dut.state);
                ill_errors = ill_errors + 1;
            end
            if (dut.state === 4'd4) begin
                $display("FAIL [ILLEGAL] reached WRITE_BACK: cycle=%0d", k);
                ill_errors = ill_errors + 1;
            end
            @(posedge clk_i); #1;
        end
        // After 3 cycles it must be back at FETCH, never having written.
        if (dut.state !== 4'd1) begin
            $display("FAIL [ILLEGAL] did not return to FETCH in 3 cycles: state=%0d", dut.state);
            ill_errors = ill_errors + 1;
        end
        if (ill_errors == 0) begin
            $display("PASS [ILLEGAL] silent no-op: 3 cycles, no reg_write_o, no we_o (handoff Sec 8)");
        end else begin
            errors = errors + ill_errors;
        end

        // ECALL / halt_o: deliberately LAST since halt_o is sticky

        // ---- halt_o still 0 after a full run of non-ECALL work ----
        if (halt_o !== 1'b0) begin
            $display("FAIL [pre-ECALL] halt_o: exp=0 got=%b", halt_o);
            errors = errors + 1;
        end else begin
            $display("PASS [pre-ECALL] halt_o still 0 after all prior instructions");
        end

        // ---- ECALL: same as EBREAK except funct12, only halt_o differs ----
        ecall_seen = 1'b1;   // arm the guard
        opcode_i = `OPCODE_SYSTEM; funct3_i = 3'b000; funct12_i = `FUNCT12_ECALL;
        run_system_nop("ECALL", 1'b1);

        // ---- Halted: core must be STOPPED, not merely flagged (handoff §8) ----
        opcode_i = `OPCODE_RTYPE; funct3_i = 3'b000; funct7_i = 7'b0000000;
        funct12_i = `FUNCT12_EBREAK;
        halt_errors = 0;
        for (h = 0; h < 12; h = h + 1) begin
            if (pc_write_o !== 1'b0) begin
                $display("FAIL [halted] pc_write_o asserted after ECALL: cycle=%0d state=%0d",
                         h, dut.state);
                halt_errors = halt_errors + 1;
            end
            if (ir_write_o !== 1'b0) begin
                $display("FAIL [halted] ir_write_o asserted after ECALL: cycle=%0d state=%0d",
                         h, dut.state);
                halt_errors = halt_errors + 1;
            end
            if (halt_o !== 1'b1) begin
                $display("FAIL [sticky] halt_o cleared after ECALL: cycle=%0d got=%b", h, halt_o);
                halt_errors = halt_errors + 1;
            end
            @(posedge clk_i); #1;
        end
        if (halt_errors == 0) begin
            $display("PASS [halted] pc_write_o/ir_write_o held 0 and halt_o held 1 for 12 cycles");
        end else begin
            errors = errors + halt_errors;
        end

        // ---- Reset clears it ----
        rst_i = 1;
        @(posedge clk_i); #1;
        if (halt_o !== 1'b0) begin
            $display("FAIL [halt reset] halt_o not cleared by reset: got=%b", halt_o);
            errors = errors + 1;
        end else begin
            $display("PASS [halt reset] halt_o cleared by reset");
        end
        ecall_seen = 1'b0;   // disarm: nothing may re-assert halt_o now
        rst_i = 0;
        @(posedge clk_i); #1;

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d CHECK(S) FAILED", errors);

        $finish;
    end

endmodule
