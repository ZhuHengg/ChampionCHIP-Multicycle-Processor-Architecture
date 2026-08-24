// tb_imm_extend.v
// One directed test per format minimum, negative immediate for I/S/B/J,
// low-bit-zero assertion for B/J.

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_imm_extend;

    reg  [31:0] instr_i;
    reg  [2:0]  imm_sel_i;
    wire [31:0] imm_o;

    integer errors = 0;

    imm_extend dut (
        .instr_i(instr_i),
        .imm_sel_i(imm_sel_i),
        .imm_o(imm_o)
    );

    task check(input [127:0] name, input [31:0] expected);
        begin
            if (imm_o !== expected) begin
                $display("FAIL: %0s  instr=%h sel=%b got=%h exp=%h",
                          name, instr_i, imm_sel_i, imm_o, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s  instr=%h sel=%b -> imm=%h",
                          name, instr_i, imm_sel_i, imm_o);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_imm_extend.vcd");
        $dumpvars(0, tb_imm_extend);

        // I-type: addi x1,x2,-5  -> imm field [31:20] = -5 = 12'hFFB
        instr_i = {12'hFFB, 5'd2, 3'b000, 5'd1, `OPCODE_ITYPE};
        imm_sel_i = `IMM_SEL_I;
        #1; check("I-type negative", 32'hFFFFFFFB);

        // I-type positive: imm field = 12'h005
        instr_i = {12'h005, 5'd2, 3'b000, 5'd1, `OPCODE_ITYPE};
        imm_sel_i = `IMM_SEL_I;
        #1; check("I-type positive", 32'h00000005);

        // S-type: sw x2, -4(x1)  -> imm = -4 = 12'hFFC
        // imm[11:5]=instr[31:25]=7'b1111111, imm[4:0]=instr[11:7]=5'b11100
        instr_i = {7'b1111111, 5'd2, 5'd1, 3'b010, 5'b11100, `OPCODE_STORE};
        imm_sel_i = `IMM_SEL_S;
        #1; check("S-type negative (-4)", 32'hFFFFFFFC);

        // B-type: beq with imm = -8, verify implicit trailing zero and
        // bit7/bit31 swap vs S.
        // 13-bit signed imm = -8 = 13'b1_1_111111_1100_0 -> bits:
        // [12]=1 [11]=1 [10:5]=111111 [4:1]=1100
        instr_i = {1'b1, 6'b111111, 5'd2, 5'd1, 3'b000, 4'b1100, 1'b1, `OPCODE_BRANCH};
        imm_sel_i = `IMM_SEL_B;
        #1; check("B-type negative (-8)", 32'hFFFFFFF8);
        if (imm_o[0] !== 1'b0) begin
            $display("FAIL: B-type low bit not zero");
            errors = errors + 1;
        end

        // B-type positive: imm = +16 -> 13'b0_000000_1000_0
        // [12]=0 [10:5]=000000 [4:1]=1000 [11]=0
        instr_i = {1'b0, 6'b000000, 5'd2, 5'd1, 3'b000, 4'b1000, 1'b0, `OPCODE_BRANCH};
        imm_sel_i = `IMM_SEL_B;
        #1; check("B-type positive (+16)", 32'h00000010);

        // U-type: lui x1, 0xABCDE -> imm = {0xABCDE, 12'b0}
        instr_i = {20'hABCDE, 5'd1, `OPCODE_LUI};
        imm_sel_i = `IMM_SEL_U;
        #1; check("U-type", 32'hABCDE000);

        // J-type: jal x1, -4  (21-bit signed imm = -4)
        // 21-bit imm: [20]=1 [19:12]=11111111 [11]=1 [10:1]=1111111110
        // encode into instr: instr[31]=imm[20], instr[30:21]=imm[10:1],
        // instr[20]=imm[11], instr[19:12]=imm[19:12]
        instr_i = {1'b1, 10'b1111111110, 1'b1, 8'b11111111, 5'd1, `OPCODE_JAL};
        imm_sel_i = `IMM_SEL_J;
        #1; check("J-type negative (-4)", 32'hFFFFFFFC);
        if (imm_o[0] !== 1'b0) begin
            $display("FAIL: J-type low bit not zero");
            errors = errors + 1;
        end

        // J-type positive: imm = +2 -> 21-bit: [20]=0 [19:12]=0
        // [11]=0 [10:1]=0000000001
        instr_i = {1'b0, 10'b0000000001, 1'b0, 8'b00000000, 5'd1, `OPCODE_JAL};
        imm_sel_i = `IMM_SEL_J;
        #1; check("J-type positive (+2)", 32'h00000002);

        // default arm (no macro maps to 3'b101/110/111 — unreachable via
        // named selects, but exercise the default path directly)
        instr_i = 32'h0;
        imm_sel_i = 3'b111;
        #1; check("default arm", 32'h00000000);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
