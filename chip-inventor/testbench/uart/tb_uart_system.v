`timescale 1ns/1ps
// CPU UART echo: firmware (run_tests.py) waits for RXDONE, reads RXDATA,
// writes it to TXDATA, pulses TRANSMIT, waits TXDONE, then sets x4 = 0x55.
// Real timing: 20 MHz clock, CLK_HZ default, 174 clocks per bit. No top
// parameter override, so this runs unchanged against the ChipInventor top.
module testbench;
    reg clk = 0;
    always #25 clk = ~clk;                 // 20 MHz, matches config.json

    localparam integer BIT = 174;          // 20 MHz / 115200 baud

    reg rst = 1, rx = 1;
    wire tx;
    wire [31:0] x4, pc;
    top dut (.clk_i(clk), .rst_i(rst), .rx_i(rx), .tx_o(tx),
             .pins_i(8'h00), .x4_dbg_o(x4), .pc_dbg_o(pc));

    // Select this test's program in imem (0 = Stage 2, the default).
    // IMEM_INST is imem's instance name in the top: blk3564_70 on the
    // ChipInventor canvas; run_tests.py overrides it for hdl.v/rtl/top.v.
`ifndef IMEM_INST
`define IMEM_INST blk3564_70
`endif
    defparam dut.`IMEM_INST.FIRMWARE = 2;

    integer i, j;                          // i: receiver, j: sender
    reg [7:0] b = 8'h96;

    // Host drives one byte on rx while the chip echoes it on tx.
    initial begin
        $dumpfile("testbench.vcd");
        $dumpvars(0, testbench);
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (40) @(negedge clk);
        rx = 0;                             // start bit
        repeat (BIT) @(negedge clk);
        for (j = 0; j < 8; j = j + 1) begin // data, LSB first
            rx = b[j];
            repeat (BIT) @(negedge clk);
        end
        rx = 1;                             // stop bit, then idle
    end

    // Sample the echoed byte at the middle of each bit.
    initial begin
        @(negedge rst);
        @(negedge tx);
        repeat (BIT / 2) @(posedge clk);
        if (tx !== 0) $fatal(1, "start");
        for (i = 0; i < 8; i = i + 1) begin
            repeat (BIT) @(posedge clk);
            if (tx !== b[i]) $fatal(1, "echo bit %0d", i);
        end
        repeat (BIT) @(posedge clk);
        if (tx !== 1) $fatal(1, "stop");
        repeat (200) @(negedge clk);
        if (x4 !== 32'h55) $fatal(1, "CPU status %h", x4);
        $display("ALL TESTS PASSED: CPU UART echo using lw/sw");
        $finish;
    end

    initial begin
        #2_000_000;                         // 40k cycles
        $fatal(1, "CPU UART timeout");
    end
endmodule
