// tb_dmem.v
// Directed tests per docs/MEMORY_BUILD_PLAN.md dmem.v section. Golden
// data layout from guide Table 12: 0xF1/F2/F3/F4 at DMEM word 0
// (absolute 0x10010000-0x10010003), i.e. word = 0xF4F3F2F1.
//
// Critical: proves the REGISTERED-READ timing, not just values — data
// must NOT be valid in the address-presentation cycle, and IS valid the
// next cycle. A combinational implementation would also pass a
// values-only test, which defeats the point (per build plan).

`timescale 1ns/1ps

module tb_dmem;

    reg         clk, rst;
    reg  [31:0] addr;
    reg         we, oe;
    reg  [3:0]  bw;
    reg  [31:0] data_in;
    wire [31:0] data_out;

    integer errors;

    dmem #(.DEPTH_WORDS(2048)) dut (
        .clk_i(clk),
        .rst_i(rst),
        .addr_i(addr),
        .we_i(we),
        .oe_i(oe),
        .bw_i(bw),
        .data_i(data_in),
        .data_o(data_out)
    );

    always #5 clk = ~clk;

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
        $dumpfile("sim/tb_dmem.vcd");
        $dumpvars(0, tb_dmem);

        clk = 0; rst = 1; errors = 0;
        addr = 0; we = 0; oe = 0; bw = 4'b0000; data_in = 0;

        @(posedge clk); #1;
        rst = 0;

        // --- Write the golden word: 0xF4F3F2F1 at word index 0 ---
        addr = 32'd0;
        data_in = 32'hF4F3F2F1;
        bw = 4'b1111;
        we = 1'b1;
        @(posedge clk); #1;
        we = 1'b0;
        bw = 4'b0000;

        // --- Timing proof: present address, check data_o NOT valid this
        // cycle (still previous/reset value), then valid next cycle ---
        data_in = 32'hDEAD_BEEF; // ensure data_o isn't accidentally right by coincidence
        addr = 32'd0;
        oe = 1'b1;
        #1; // still within the address-presentation cycle, before the edge
        check32("data_o NOT valid in address cycle", data_out, 32'h0); // reset value, unchanged
        @(posedge clk); #1;
        check32("data_o valid the cycle AFTER address", data_out, 32'hF4F3F2F1);
        oe = 1'b0;

        // --- Full word readback (values only, timing already proven) ---
        addr = 32'd0; oe = 1'b1;
        @(posedge clk); #1;
        check32("full word readback", data_out, 32'hF4F3F2F1);
        oe = 1'b0;

        // --- Byte-write: overwrite only byte 0 (bw=0001), others untouched ---
        addr = 32'd0;
        data_in = 32'h0000_00AA;
        bw = 4'b0001;
        we = 1'b1;
        @(posedge clk); #1;
        we = 1'b0; bw = 4'b0000;
        oe = 1'b1;
        @(posedge clk); #1;
        check32("byte0 write, others untouched", data_out, 32'hF4F3F2AA);
        oe = 1'b0;

        // --- Byte-write: byte 1 only ---
        addr = 32'd0;
        data_in = 32'h0000_BB00;
        bw = 4'b0010;
        we = 1'b1;
        @(posedge clk); #1;
        we = 1'b0; bw = 4'b0000;
        oe = 1'b1;
        @(posedge clk); #1;
        check32("byte1 write, others untouched", data_out, 32'hF4F3BBAA);
        oe = 1'b0;

        // --- Byte-write: byte 2 only ---
        addr = 32'd0;
        data_in = 32'h00CC_0000;
        bw = 4'b0100;
        we = 1'b1;
        @(posedge clk); #1;
        we = 1'b0; bw = 4'b0000;
        oe = 1'b1;
        @(posedge clk); #1;
        check32("byte2 write, others untouched", data_out, 32'hF4CCBBAA);
        oe = 1'b0;

        // --- Byte-write: byte 3 only ---
        addr = 32'd0;
        data_in = 32'hDD00_0000;
        bw = 4'b1000;
        we = 1'b1;
        @(posedge clk); #1;
        we = 1'b0; bw = 4'b0000;
        oe = 1'b1;
        @(posedge clk); #1;
        check32("byte3 write, others untouched", data_out, 32'hDDCCBBAA);
        oe = 1'b0;

        // --- Restore golden word at word 0 for downstream LSU tests ---
        addr = 32'd0;
        data_in = 32'hF4F3F2F1;
        bw = 4'b1111;
        we = 1'b1;
        @(posedge clk); #1;
        we = 1'b0; bw = 4'b0000;

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
