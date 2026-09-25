`timescale 1ns/1ps
module tb_gpio_system;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    tri [7:0] pins;
    // External inputs on pins 4-7; CPU program drives only pins 0-3.
    assign pins[7:4]=4'ha;
    wire [31:0] pc, x4;
    wire halt;
    top dut (.clk_i(clk), .rst_i(rst), .pins_io(pins),
        .halt_o(halt), .pc_dbg_o(pc), .x4_dbg_o(x4));
    initial begin
        $dumpfile("gpio_system.vcd"); $dumpvars(0,tb_gpio_system);
        repeat(2) @(negedge clk); rst=0;
        repeat(300) @(negedge clk);
        if (x4 !== 32'h55) $fatal(1,"CPU GPIO program failed: x4=%h pc=%h",x4,pc);
        if (pins !== 8'ha5) $fatal(1,"CPU GPIO outputs incorrect: %h",pins);
        $display("ALL TESTS PASSED: CPU GPIO lw/sw program"); $finish;
    end
endmodule
