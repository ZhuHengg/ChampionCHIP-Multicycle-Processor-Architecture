// tb_imem.v
// Directed tests per docs/MEMORY_BUILD_PLAN.md imem.v section, using
// guide Table 14's own worked example as golden data:
//  0x00400000 -> 0x00842283
//  0x00400004 -> 0xf0000437
//  0x00400100 -> 0x0000000A  (constant read via ordinary load address)
//  read outside loaded range does not produce X in a way that breaks sim

`timescale 1ns/1ps

module tb_imem;

    reg  [31:0] addr;
    reg         oe;
    wire [31:0] data;

    integer errors;

    imem #(.DEPTH_WORDS(1024), .INIT_FILE("firmware/tb_imem_test.hex")) dut (
        .clk_i(1'b0),
        .addr_i(addr),
        .oe_i(oe),
        .data_o(data)
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
        $dumpfile("sim/tb_imem.vcd");
        $dumpvars(0, tb_imem);

        errors = 0;
        oe = 1'b1;

        // Word addressing: index = addr_i[9:0] (low bits), so use word
        // index directly (decoder normally strips base + bottom 2 bits;
        // imem itself just indexes by the low bits of addr_i).
        addr = 32'd0; #1;
        check32("word 0 (0x00400000)", data, 32'h00842283);

        addr = 32'd1; #1;
        check32("word 1 (0x00400004)", data, 32'hf0000437);

        addr = 32'd64; #1; // 0x00400100 / 4 = 64
        check32("word 64 (0x00400100 constant)", data, 32'h0000000a);

        // oe_i negated -> output forced to zero, not X
        oe = 1'b0; #1;
        check32("oe_i deasserted -> 0, not X", data, 32'h0);
        oe = 1'b1;

        // Address beyond initialized program but within DEPTH_WORDS:
        // uninitialized memory in iverilog reads as X. Confirm oe_i=0
        // path (already proven above) is the safe way to avoid X
        // propagating; a direct read of an uninitialized word is expected
        // to be X here since $readmemh only wrote 65 of 1024 words.
        addr = 32'd200; #1;
        if (^data === 1'bx)
            $display("INFO word 200 uninitialized -> X (expected, not in loaded range)");
        else
            $display("INFO word 200 uninitialized -> %h", data);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
