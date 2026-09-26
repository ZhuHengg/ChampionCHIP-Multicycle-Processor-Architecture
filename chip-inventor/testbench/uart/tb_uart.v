`timescale 1ns/1ps
module testbench;

    // ---- Clock and shared stimulus/decode signals ----------------------
    reg clk = 0;
    always #5 clk = ~clk;

    reg rst = 1, we = 0, oe = 0, rx = 1;
    reg [31:0] addr = 0, wr = 0;
    reg [3:0] bw = 15;
    wire [31:0] rd, urd;
    wire uwe, uoe, gwe, goe, dwe, doe, ioe, tx;

    // ---- Address decoder + UART DUT -------------------------------------
    address_decoder dec (
        .address_i(addr), .we_i(we), .oe_i(oe), .bw_i(bw),
        .dmem_data_i(32'h1234), .imem_data_i(32'h5678), .gpio_data_i(32'habcd),
        .uart_data_i(urd), .uart_we_o(uwe), .uart_oe_o(uoe),
        .gpio_we_o(gwe), .gpio_oe_o(goe),
        .dmem_we_o(dwe), .dmem_oe_o(doe), .imem_oe_o(ioe),
        .data_o(rd)
    );

    uart #(.CLK_HZ(1843200)) dut (
        .clk_i(clk), .rst_i(rst), .addr_i(addr),
        .we_i(uwe), .oe_i(uoe), .bw_i(bw), .data_i(wr), .data_o(urd),
        .rx_i(rx), .tx_o(tx)
    );

    // ---- Tasks ------------------------------------------------------------
    task write_reg(input [31:0] a, input [31:0] v);
        begin
            @(negedge clk);
            addr = a;
            wr = v;
            we = 1;
            oe = 0;
            #1;
            if (!uwe || gwe || dwe) $fatal(1, "decode write");
            @(negedge clk);
            we = 0;
        end
    endtask

    task check(input [31:0] a, input [31:0] v);
        begin
            @(negedge clk);
            addr = a;
            oe = 1;
            we = 0;
            @(posedge clk); #1;
            if (rd !== v) $fatal(1, "read %h got %h expected %h", a, rd, v);
            @(negedge clk);
            oe = 0;
        end
    endtask

    task send_byte(input [7:0] b);
        integer i;
        begin
            @(negedge clk);
            rx = 0;
            repeat (16) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];
                repeat (16) @(negedge clk);
            end
            rx = 1;
            repeat (16) @(negedge clk);
        end
    endtask

    task expect_tx(input [7:0] b);
        integer i;
        begin
            @(negedge tx); #80;
            if (tx !== 0) $fatal(1, "start");
            for (i = 0; i < 8; i = i + 1) begin
                #160;
                if (tx !== b[i]) $fatal(1, "TX bit %0d", i);
            end
            #160;
            if (tx !== 1) $fatal(1, "stop");
            #81;
            if (!dut.txdone) $fatal(1, "done before/after stop");
        end
    endtask

    // ---- Test sequence ------------------------------------------------------
    initial begin
        repeat (3) @(negedge clk);
        rst = 0;

        // Reset state: CONTROL = TXDONE only, RXDATA = 0.
        check(32'hf1000008, 4);
        check(32'hf1000004, 0);

        // TXDATA write/readback; only byte lane 0 is writable.
        write_reg(32'hf1000000, 32'hffffffa5);
        check(32'hf1000003, 165);
        bw = 14;
        write_reg(32'hf1000000, 0);
        bw = 15;
        check(32'hf1000000, 165);

        // Full duplex: send 0x3C in while TX shifts out 0xA5.
        // Also probe that a write during the shift doesn't corrupt/restart it.
        fork
            expect_tx(8'ha5);
            send_byte(8'h3c);
            begin
                write_reg(32'hf1000008, 1);
                check(32'hf1000008, 0);
                write_reg(32'hf1000000, 8'hff); // in-flight shift register must retain A5
                write_reg(32'hf1000008, 1);      // busy trigger must not restart TX
            end
        join

        // After both finish: TXDONE+RXDONE set, RXDATA = 0x3C.
        check(32'hf1000008, 6);
        check(32'hf1000004, 60);

        // RXDONE clears on write-0; RXDATA holds until overwritten.
        write_reg(32'hf1000004, 0);
        check(32'hf1000004, 60);

        // Clear RXDONE via CONTROL write, then send TX 0xFF.
        write_reg(32'hf1000008, 0);
        check(32'hf1000008, 4);
        fork
            expect_tx(8'hff);
            write_reg(32'hf1000008, 1);
        join

        // Receive 0x00 then 0xFF back to back; RXDATA holds the latest byte.
        send_byte(0);
        send_byte(255);
        check(32'hf1000004, 255);
        check(32'hf1000008, 6);

        // Reserved offset and address alias must not select UART.
        @(negedge clk);
        addr = 32'hf100000c;
        we = 1;
        oe = 1;
        #1;
        if (uwe || uoe || rd !== 0) $fatal(1, "reserved offset");
        addr = 32'hf1000010;
        #1;
        if (uwe || uoe || rd !== 0) $fatal(1, "alias");

        // Reset clears everything: TX idles high, RXDATA = 0.
        @(negedge clk);
        we = 0;
        oe = 0;
        rst = 1;
        @(posedge clk); #1;
        if (tx !== 1 || urd !== 0) $fatal(1, "reset");

        $display("ALL TESTS PASSED: UART full duplex, timing, registers and decode");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "timeout");
    end

endmodule
