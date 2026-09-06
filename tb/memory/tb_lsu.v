// tb_lsu.v — golden load/store vectors, guide Table 12 word 0xF4F3F2F1.
// lb @ +2: guide's rule vs worked example disagree, see lsu.v header; tested here.

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_lsu;

    reg  [31:0] core_data_o;
    reg  [31:0] core_address_o;
    reg  [2:0]  op_size_o;
    reg  [31:0] mem_data_o;

    wire [31:0] core_data_i;
    wire [31:0] mem_data_i;

    integer errors;

    localparam [31:0] GOLDEN_WORD = 32'hF4F3F2F1; // guide Table 12

    lsu dut (
        .core_data_o(core_data_o),
        .core_address_o(core_address_o),
        .op_size_o(op_size_o),
        .mem_data_o(mem_data_o),
        .core_data_i(core_data_i),
        .mem_data_i(mem_data_i)
    );

    task check32(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got=%h exp=%h", name, got, exp);
                errors = errors + 1;
            end else begin
                $display("PASS %0s: got=%h", name, got);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_lsu.vcd");
        $dumpvars(0, tb_lsu);

        errors = 0;
        mem_data_o = GOLDEN_WORD;

        // ---------------- Load vectors: Table 12 ----------------

        // lbu @ 0x10010000 -> 0x000000F1
        core_address_o = 32'h10010000; op_size_o = `OP_SIZE_BYTE_U; #1;
        check32("lbu @ +0", core_data_i, 32'h000000F1);

        // lb @ 0x10010000 -> 0xFFFFFFF1
        core_address_o = 32'h10010000; op_size_o = `OP_SIZE_BYTE_S; #1;
        check32("lb @ +0", core_data_i, 32'hFFFFFFF1);

        // lhu @ 0x10010000 -> 0x0000F2F1
        core_address_o = 32'h10010000; op_size_o = `OP_SIZE_HALF_U; #1;
        check32("lhu @ +0", core_data_i, 32'h0000F2F1);

        // lh @ 0x10010000 -> 0xFFFFF2F1
        core_address_o = 32'h10010000; op_size_o = `OP_SIZE_HALF_S; #1;
        check32("lh @ +0", core_data_i, 32'hFFFFF2F1);

        // lw @ 0x10010000 -> 0xF4F3F2F1
        core_address_o = 32'h10010000; op_size_o = `OP_SIZE_WORD; #1;
        check32("lw @ +0", core_data_i, GOLDEN_WORD);

        // lb @ 0x10010002 -> general sign-extension rule (see lsu.v header)
        core_address_o = 32'h10010002; op_size_o = `OP_SIZE_BYTE_S; #1;
        check32("lb @ +2 (sign-extension rule)", core_data_i, 32'hFFFFFFF3);

        // lbu @ 0x10010002 -> 0x000000F3 (unsigned, unambiguous either way)
        core_address_o = 32'h10010002; op_size_o = `OP_SIZE_BYTE_U; #1;
        check32("lbu @ +2 (unambiguous)", core_data_i, 32'h000000F3);

        // ---------------- Store: guide §3.3.2 example ----------------
        // Write 0x12 to 0x10010002 (byte lane 2) -> mem_data_i = 0x00120000
        core_data_o = 32'h00000012;
        core_address_o = 32'h10010002;
        op_size_o = `OP_SIZE_BYTE_S; // sign bit don't-care for stores
        #1;
        check32("sb positioning @ lane2 (guide example)", mem_data_i, 32'h00120000);

        // sb @ lane 0
        core_data_o = 32'h000000AB; core_address_o = 32'h10010000; op_size_o = `OP_SIZE_BYTE_S; #1;
        check32("sb positioning @ lane0", mem_data_i, 32'h000000AB);

        // sb @ lane 1
        core_data_o = 32'h000000AB; core_address_o = 32'h10010001; op_size_o = `OP_SIZE_BYTE_S; #1;
        check32("sb positioning @ lane1", mem_data_i, 32'h0000AB00);

        // sb @ lane 3
        core_data_o = 32'h000000AB; core_address_o = 32'h10010003; op_size_o = `OP_SIZE_BYTE_S; #1;
        check32("sb positioning @ lane3", mem_data_i, 32'hAB000000);

        // sh @ lower half (addr[1]=0)
        core_data_o = 32'h0000BEEF; core_address_o = 32'h10010000; op_size_o = `OP_SIZE_HALF_S; #1;
        check32("sh positioning @ lower half", mem_data_i, 32'h0000BEEF);

        // sh @ upper half (addr[1]=1)
        core_data_o = 32'h0000BEEF; core_address_o = 32'h10010002; op_size_o = `OP_SIZE_HALF_S; #1;
        check32("sh positioning @ upper half", mem_data_i, 32'hBEEF0000);

        // sw
        core_data_o = 32'hCAFEBABE; core_address_o = 32'h10010000; op_size_o = `OP_SIZE_WORD; #1;
        check32("sw positioning (whole word)", mem_data_i, 32'hCAFEBABE);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
