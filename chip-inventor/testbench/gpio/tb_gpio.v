`timescale 1ns/1ps
module testbench;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, we = 0, oe = 0;
    reg [31:0] addr = 0, wr = 0;
    reg [3:0] bw = 4'hf;
    wire [31:0] rd, gpio_rd, word_addr;
    wire gwe, goe, dwe, doe, ioe;
    wire [3:0] dbw;
    tri [7:0] pins;
    wire [7:0] pins_o, pins_oe;
    reg [7:0] ext_en = 0, ext_data = 0;
    integer i;
    reg [7:0] mask;
    genvar p;
    generate for (p=0; p<8; p=p+1) begin : external_pins
        assign pins[p] = ext_en[p] ? ext_data[p] : 1'bz;
        // Pad model: tri-state lives outside the GPIO block.
        assign pins[p] = pins_oe[p] ? pins_o[p] : 1'bz;
    end endgenerate
    address_decoder decoder (
        .address_i(addr), .we_i(we), .oe_i(oe), .bw_i(bw),
        .dmem_data_i(32'h12345678), .imem_data_i(32'h87654321),
        .uart_data_i(32'h13579bdf), .gpio_data_i(gpio_rd), .address_o(word_addr),
        .dmem_we_o(dwe), .dmem_oe_o(doe), .imem_oe_o(ioe),
        .gpio_we_o(gwe), .gpio_oe_o(goe), .bw_o(dbw), .data_o(rd)
    );
    gpio dut (.clk_i(clk), .rst_i(rst), .addr_i(addr),
        .we_i(gwe), .oe_i(goe), .bw_i(bw), .data_i(wr),
        .data_o(gpio_rd), .pins_i(pins), .pins_o(pins_o), .pins_oe_o(pins_oe));

    task write_reg;
        input [31:0] a, value;
        input [3:0] lanes;
        begin
            @(negedge clk); addr=a; wr=value; bw=lanes; we=1; oe=0;
            #1;
            if (!gwe || dwe || doe || ioe) $fatal(1,"GPIO write decoding");
            @(negedge clk); we=0;
        end
    endtask
    task read_reg;
        input [31:0] a, expected;
        begin
            @(negedge clk); addr=a; oe=1; we=0;
            #1;
            if (!goe || dwe || doe || ioe) $fatal(1,"GPIO read decoding");
            @(posedge clk); #1;
            if (rd !== expected) $fatal(1,"read %h expected %h got %h",a,expected,rd);
            @(negedge clk); oe=0;
        end
    endtask
    initial begin
        $dumpfile("gpio.vcd"); $dumpvars(0,testbench);
        repeat(2) @(negedge clk);
        if (pins !== 8'hzz || gpio_rd !== 0) $fatal(1,"reset");
        rst=0;
        read_reg(32'hf0000000,0);
        read_reg(32'hf0000008,0);
        ext_en=8'hff; ext_data=8'ha5;
        repeat(2) @(negedge clk);
        read_reg(32'hf0000004,32'ha5);
        write_reg(32'hf0000004,0,4'hf);
        read_reg(32'hf0000004,32'ha5); // read-only
        write_reg(32'hf0000000,32'hffffff05,4'hf);
        read_reg(32'hf0000000,5); // reserved bits zero
        write_reg(32'hf0000008,15,4'hf);
        ext_en=8'hf0;
        if (pins !== 8'ha5) $fatal(1,"four inputs/four outputs");
        ext_data=8'h50;
        repeat(2) @(negedge clk);
        read_reg(32'hf0000004,32'h55); // output bits hold prior sample 5
        write_reg(32'hf0000000,10,4'hf);
        if (pins !== 8'h5a) $fatal(1,"output update");
        read_reg(32'hf0000004,32'h55); // no output feedback
        write_reg(32'hf0000000,0,4'he);
        read_reg(32'hf0000000,10); // upper-byte write has no effect
        write_reg(32'hf0000008,0,4'h0);
        read_reg(32'hf0000008,15); // disabled byte lanes
        // Low address bits ignored at the register bus boundary.
        write_reg(32'hf0000003,6,4'hf);
        read_reg(32'hf0000001,6);
        // Demonstrate registered reads, then retention while disabled.
        @(negedge clk); addr=32'hf0000008; oe=1;
        #1; if (rd !== 6) $fatal(1,"read changed before clock");
        @(posedge clk); #1; if (rd !== 15) $fatal(1,"registered read");
        @(negedge clk); oe=0; addr=32'hf0000000;
        @(posedge clk); #1; if (gpio_rd !== 15) $fatal(1,"read hold");
        ext_en=0;
        // Exercise every direction bit independently, high and low.
        for (i=0;i<8;i=i+1) begin
            mask=8'b1 << i;
            write_reg(32'hf0000008,{24'b0,mask},4'hf);
            write_reg(32'hf0000000,255,4'hf);
            if (pins[i] !== 1'b1) $fatal(1,"pin %0d high",i);
            write_reg(32'hf0000000,0,4'hf);
            if (pins[i] !== 1'b0) $fatal(1,"pin %0d low",i);
            write_reg(32'hf0000008,0,4'hf);
            if (pins !== 8'hzz) $fatal(1,"pin release");
        end
        @(negedge clk); addr=32'hf000000c; oe=1; we=1;
        #1; if (gwe || goe || dwe || doe || ioe || rd !== 0) $fatal(1,"reserved offset");
        addr=32'hf0000010; #1;
        if (gwe || goe || rd !== 0) $fatal(1,"GPIO alias");
        addr=32'hf1000000; #1;
        if (gwe || goe || rd !== 32'h13579bdf) $fatal(1,"UART must not select GPIO");
        addr=32'h10010000; #1;
        if (!dwe || !doe || gwe || goe || rd !== 32'h12345678) $fatal(1,"DMEM regression");
        addr=32'h00400000; #1;
        if (!ioe || gwe || goe || dwe || rd !== 32'h87654321) $fatal(1,"IMEM regression");
        @(negedge clk); we=0; oe=0;
        write_reg(32'hf0000008,255,4'hf);
        @(negedge clk); rst=1;
        @(posedge clk); #1;
        if (pins !== 8'hzz || gpio_rd !== 0) $fatal(1,"reset after use");
        $display("ALL TESTS PASSED: GPIO and address decoder"); $finish;
    end
endmodule
