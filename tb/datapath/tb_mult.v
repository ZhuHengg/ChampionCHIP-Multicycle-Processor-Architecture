// tb_mult.v — all 4 MULT ops, sign combos, MULHSU trap, 0xFFFFFFFF^2 stress

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_mult;

    reg  [31:0] a_i, b_i;
    reg  [3:0]  mult_op_i;
    wire [31:0] result_o;

    integer errors = 0;

    mult dut (
        .a_i(a_i),
        .b_i(b_i),
        .mult_op_i(mult_op_i),
        .result_o(result_o)
    );

    task check(input [127:0] name, input [31:0] expected);
        begin
            if (result_o !== expected) begin
                $display("FAIL: %0s  a=%h b=%h op=%h got=%h exp=%h",
                          name, a_i, b_i, mult_op_i, result_o, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s  a=%h b=%h op=%h -> %h",
                          name, a_i, b_i, mult_op_i, result_o);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_mult.vcd");
        $dumpvars(0, tb_mult);

        // MUL: 6 * 7 = 42
        a_i = 32'd6; b_i = 32'd7;
        mult_op_i = `MULT_MUL; #1; check("MUL 6*7", 32'd42);

        // MUL negative * positive: -6 * 7 = -42
        a_i = -32'sd6; b_i = 32'd7;
        mult_op_i = `MULT_MUL; #1; check("MUL -6*7", -32'sd42);

        // MULH: negative * negative, check upper half
        // (-2) * (-3) = 6 -> upper 32 bits of 64-bit signed product = 0
        a_i = -32'sd2; b_i = -32'sd3;
        mult_op_i = `MULT_MULH; #1; check("MULH (-2)*(-3) upper=0", 32'h00000000);

        // MULH: large negative * large positive to get nonzero upper half
        // a = 0x80000000 (-2147483648), b = 0x00000002 (2)
        // product = -4294967296 = 0xFFFFFFFF00000000 (64-bit two's complement)
        a_i = 32'h80000000; b_i = 32'h00000002;
        mult_op_i = `MULT_MULH; #1; check("MULH large neg*pos upper", 32'hFFFFFFFF);

        // MULHU: unsigned * unsigned, 0xFFFFFFFF * 0xFFFFFFFF
        // = 0xFFFFFFFE00000001 -> upper = 0xFFFFFFFE
        a_i = 32'hFFFFFFFF; b_i = 32'hFFFFFFFF;
        mult_op_i = `MULT_MULHU; #1; check("MULHU 0xFFFFFFFF^2 upper", 32'hFFFFFFFE);

        // Same operands, MUL low half: unsigned*unsigned low32 = 0x00000001
        mult_op_i = `MULT_MUL; #1; check("MUL 0xFFFFFFFF^2 low", 32'h00000001);

        // Same operands, signed interpretation: (-1)*(-1) = 1
        // MULH upper half should be 0 (product fits in low 32 as +1)
        mult_op_i = `MULT_MULH; #1; check("MULH (-1)*(-1) upper=0", 32'h00000000);

        // MULHSU trap: rs1 signed = -1 (0xFFFFFFFF), rs2 unsigned = 1
        // signed*unsigned = -1 * 1 = -1 -> 64-bit = 0xFFFFFFFFFFFFFFFF
        // upper = 0xFFFFFFFF
        a_i = 32'hFFFFFFFF; b_i = 32'h00000001;
        mult_op_i = `MULT_MULHSU; #1; check("MULHSU trap (-1 su 1)", 32'hFFFFFFFF);

        // MULHSU: rs1 signed = -1, rs2 unsigned = 0xFFFFFFFF (large unsigned)
        // -1 * 4294967295 = -4294967295 = 0xFFFFFFFF00000001 (64-bit)
        // upper = 0xFFFFFFFF
        a_i = 32'hFFFFFFFF; b_i = 32'hFFFFFFFF;
        mult_op_i = `MULT_MULHSU; #1; check("MULHSU (-1 su 0xFFFFFFFF)", 32'hFFFFFFFF);

        // MULHSU sanity: rs1 positive small, rs2 unsigned small — same as
        // signed*signed in this range, catches gross sign-extension bugs
        a_i = 32'd3; b_i = 32'd4;
        mult_op_i = `MULT_MULHSU; #1; check("MULHSU small positive upper=0", 32'h00000000);
        mult_op_i = `MULT_MUL;    #1; check("MUL small positive low", 32'd12);

        // illegal mult_op -> default
        mult_op_i = 4'hF; #1; check("illegal op default", 32'b0);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
