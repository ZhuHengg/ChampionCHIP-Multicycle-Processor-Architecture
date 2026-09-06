// tb_imem.v — golden vectors from guide Table 14, oe_i gating, out-of-range read

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

        // index = addr_i[9:0], word addressing
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

        // uninitialized word (only 65 of 1024 loaded) -> X expected
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
