// tb_crc.v
// Golden vectors: firmware/crc_test.S three chains (crcb/crch/crcw), all
// converging on 0x1E82. Plus width-masking and default-arm checks.
// See docs/DATAPATH_BUILD_PLAN.md crc.v section.

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_crc;

    reg  [31:0] a_i, b_i;
    reg  [3:0]  crc_op_i;
    wire [31:0] result_o;

    integer errors = 0;

    crc dut (
        .a_i(a_i),
        .b_i(b_i),
        .crc_op_i(crc_op_i),
        .result_o(result_o)
    );

    task check(input [127:0] name, input [31:0] expected);
        begin
            if (result_o !== expected) begin
                $display("FAIL: %0s  a=%h b=%h op=%h got=%h exp=%h",
                          name, a_i, b_i, crc_op_i, result_o, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s  a=%h b=%h op=%h -> %h",
                          name, a_i, b_i, crc_op_i, result_o);
            end
        end
    endtask

    // runs one crc call and feeds result_o back into b_i (seed) for chaining
    task step(input [127:0] name, input [3:0] op, input [31:0] data);
        begin
            crc_op_i = op;
            a_i      = data;
            #1;
            $display("  %0s: data=%h seed=%h -> %h", name, data, b_i, result_o);
            b_i = result_o[15:0];
        end
    endtask

    initial begin
        $dumpfile("sim/tb_crc.vcd");
        $dumpvars(0, tb_crc);

        // ---- crcb chain: 8 x 8-bit, seed 0xFFFF, expect 0x1E82 ----
        b_i = 32'h0000FFFF;
        step("crcb 12", `CRC_CRCB, 32'h00000012);
        step("crcb 34", `CRC_CRCB, 32'h00000034);
        step("crcb 56", `CRC_CRCB, 32'h00000056);
        step("crcb 78", `CRC_CRCB, 32'h00000078);
        step("crcb 90", `CRC_CRCB, 32'h00000090);
        step("crcb AB", `CRC_CRCB, 32'h000000AB);
        step("crcb CD", `CRC_CRCB, 32'h000000CD);
        crc_op_i = `CRC_CRCB; a_i = 32'h000000EF; #1;
        check("crcb chain final", 32'h00001E82);

        // ---- crch chain: 4 x 16-bit, seed 0xFFFF, expect 0x1E82 ----
        b_i = 32'h0000FFFF;
        step("crch 1234", `CRC_CRCH, 32'h00001234);
        step("crch 5678", `CRC_CRCH, 32'h00005678);
        step("crch 90AB", `CRC_CRCH, 32'h000090AB);
        crc_op_i = `CRC_CRCH; a_i = 32'h0000CDEF; #1;
        check("crch chain final", 32'h00001E82);

        // ---- crcw chain: 2 x 32-bit, seed 0xFFFF, expect 0x1E82 ----
        b_i = 32'h0000FFFF;
        step("crcw 12345678", `CRC_CRCW, 32'h12345678);
        crc_op_i = `CRC_CRCW; a_i = 32'h90ABCDEF; #1;
        check("crcw chain final", 32'h00001E82);

        // ---- width masking: crcb only consumes a_i[7:0] ----
        a_i = 32'hFFFFFF41; b_i = 32'h0000FFFF; crc_op_i = `CRC_CRCB; #1;
        begin : mask8
            reg [31:0] r1;
            r1 = result_o;
            a_i = 32'h00000041; b_i = 32'h0000FFFF; crc_op_i = `CRC_CRCB; #1;
            if (result_o !== r1) begin
                $display("FAIL: crcb width mask  a=0xFFFFFF41 -> %h, a=0x41 -> %h (should match)", r1, result_o);
                errors = errors + 1;
            end else
                $display("PASS: crcb width mask  both a values -> %h", result_o);
        end

        // width masking: crch only consumes a_i[15:0]
        a_i = 32'hFFFF1234; b_i = 32'h0000FFFF; crc_op_i = `CRC_CRCH; #1;
        begin : mask16
            reg [31:0] r1;
            r1 = result_o;
            a_i = 32'h00001234; b_i = 32'h0000FFFF; crc_op_i = `CRC_CRCH; #1;
            if (result_o !== r1) begin
                $display("FAIL: crch width mask  a=0xFFFF1234 -> %h, a=0x1234 -> %h (should match)", r1, result_o);
                errors = errors + 1;
            end else
                $display("PASS: crch width mask  both a values -> %h", result_o);
        end

        // upper bits of result always zero
        a_i = 32'h12345678; b_i = 32'h0000FFFF; crc_op_i = `CRC_CRCW; #1;
        if (result_o[31:16] !== 16'b0) begin
            $display("FAIL: result_o[31:16] not zero: %h", result_o);
            errors = errors + 1;
        end else
            $display("PASS: result_o[31:16] == 0");

        // default/unused crc_op
        a_i = 32'hDEADBEEF; b_i = 32'hCAFEBABE; crc_op_i = 4'hF; #1;
        check("illegal crc_op default", 32'b0);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
