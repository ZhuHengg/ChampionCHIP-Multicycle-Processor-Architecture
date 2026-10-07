`timescale 1ns/1ps
module testbench;
    reg clk=0, rst=1, we=0, oe=1;
    reg [31:0] addr=32'hf2000000;
    reg [3:0] bw=4'hf;
    wire timer_we, timer_oe;
    wire [31:0] timer_data, data;
    always #25 clk=~clk;
    meter_timer dut (.clk_i(clk), .rst_i(rst), .we_i(timer_we), .addr_i(addr),
                     .oe_i(timer_oe), .data_o(timer_data));
    address_decoder decode (
        .address_i(addr), .we_i(we), .oe_i(oe), .bw_i(bw),
        .dmem_data_i(32'h11), .imem_data_i(32'h22),
        .gpio_data_i(32'h33), .uart_data_i(32'h44),
        .timer_data_i(timer_data), .timer_we_o(timer_we),
        .timer_oe_o(timer_oe), .data_o(data)
    );
    initial begin
        repeat(3) @(negedge clk);
        rst=0;
        repeat(19999) @(negedge clk);
        if (dut.age_ms !== 0) $fatal(1,"timer advanced before 1 ms");
        @(negedge clk);
        if (dut.age_ms !== 1) $fatal(1,"20,000 clocks must equal 1 ms");
        @(negedge clk);
        if (data !== 1) $fatal(1,"registered MMIO read incorrect");
        bw=1; we=1;
        @(negedge clk);
        if (dut.age_ms !== 1) $fatal(1,"byte store refreshed word-only timer");
        bw=15; addr=32'hf2000008;
        @(negedge clk);
        if (data !== 0 || dut.age_ms !== 1) $fatal(1,"unmapped address affected timer");
        addr=32'hf2000004;
        @(negedge clk);
        if (dut.rx_age_ms !== 0 || dut.age_ms !== 1) $fatal(1,"RX refresh affected meter timer");
        addr=32'hf2000000;
        @(negedge clk); we=0;
        if (dut.age_ms !== 0 || dut.ticks !== 0) $fatal(1,"refresh must reset age and divider");
        repeat(19999) @(negedge clk);
        if (dut.age_ms !== 0) $fatal(1,"refresh interval too short");
        @(negedge clk);
        if (dut.age_ms !== 1) $fatal(1,"refresh interval too long");
        // Deposit near saturation to test the boundary without a 49-day run.
        dut.age_ms=32'hfffffffe; dut.ticks=19999;
        @(negedge clk);
        if (dut.age_ms !== 32'hffffffff) $fatal(1,"saturation boundary");
        repeat(20000) @(negedge clk);
        if (dut.age_ms !== 32'hffffffff) $fatal(1,"timer wrapped and became fresh");
        rst=1;
        @(negedge clk);
        if (dut.age_ms !== 0 || dut.ticks !== 0 || data !== 0) $fatal(1,"reset failed");
        rst=0; addr=32'hf2000004;
        repeat(20001) @(negedge clk);
        if (data !== 1 || dut.age_ms !== 1) $fatal(1,"RX timer read/divider failed");
        we=1;
        @(negedge clk); we=0;
        @(negedge clk);
        if (data !== 0 || dut.age_ms !== 1) $fatal(1,"RX refresh not independent");
        $display("PASS meter timer: real clock divider, MMIO, refresh, saturation, reset");
        $finish;
    end
endmodule
