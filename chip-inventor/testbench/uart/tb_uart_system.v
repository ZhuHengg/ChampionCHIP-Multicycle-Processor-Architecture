`timescale 1ns/1ps
module tb_uart_system;
reg clk=0;always #5 clk=~clk;
reg rst=1,rx=1;wire tx;wire [31:0] x4;
top #(.CLK_HZ(1843200)) dut(.clk_i(clk),.rst_i(rst),.rx_i(rx),.tx_o(tx),.x4_dbg_o(x4));
integer i;reg [7:0] b=8'h96;
initial begin
repeat(3) @(negedge clk);rst=0;
repeat(40) @(negedge clk);
rx=0;repeat(16) @(negedge clk);
for(i=0;i<8;i=i+1)begin rx=b[i];repeat(16) @(negedge clk);end
rx=1;
@(negedge tx);#80;if(tx!==0)$fatal(1,"start");
for(i=0;i<8;i=i+1)begin #160;if(tx!==b[i])$fatal(1,"echo bit %0d",i);end
#160;if(tx!==1)$fatal(1,"stop");
repeat(200) @(negedge clk);
if(x4!==32'h55)$fatal(1,"CPU status %h",x4);
$display("ALL TESTS PASSED: CPU UART echo using lw/sw");$finish;
end
initial begin #100000;$fatal(1,"CPU UART timeout");end
endmodule
