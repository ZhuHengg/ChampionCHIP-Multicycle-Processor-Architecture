`timescale 1ns/1ps
module testbench;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    tri [7:0] pins;
    // External inputs on pins 4-7; CPU program drives only pins 0-3.
    assign pins[7:4]=4'ha;
    // Pad model: tri-state lives outside the chip.
    wire [7:0] pins_o, pins_oe;
    genvar p;
    generate for (p=0;p<8;p=p+1) begin : pad
        assign pins[p] = pins_oe[p] ? pins_o[p] : 1'bz;
    end endgenerate
    wire [31:0] pc, x4;
    wire halt;
    top dut (.clk_i(clk), .rst_i(rst), .pins_i(pins), .pins_o(pins_o), .pins_oe_o(pins_oe),
        .halt_o(halt), .pc_dbg_o(pc), .x4_dbg_o(x4));

    // Select this test's program in imem (0 = Stage 2, the default).
    // IMEM_INST is imem's instance name in the top: blk3564_70 on the
    // ChipInventor canvas; run_tests.py overrides it for hdl.v/rtl/top.v.
`ifndef IMEM_INST
`define IMEM_INST blk3564_70
`endif
    defparam dut.`IMEM_INST.FIRMWARE = 1;
    initial begin
        $dumpfile("testbench.vcd"); $dumpvars(0,testbench);
        repeat(2) @(negedge clk); rst=0;
        repeat(300) @(negedge clk);
        if (x4 !== 32'h55) $fatal(1,"CPU GPIO program failed: x4=%h pc=%h",x4,pc);
        if (pins !== 8'ha5) $fatal(1,"CPU GPIO outputs incorrect: %h",pins);
        $display("ALL TESTS PASSED: CPU GPIO lw/sw program"); $finish;
    end
endmodule
