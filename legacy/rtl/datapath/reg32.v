// reg32.v — generic 32-bit D-register, sync reset + enable

`timescale 1ns / 1ps

module reg32 #(
    parameter RESET_VALUE = 32'h00000000
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        en_i,
    input  wire [31:0] d_i,
    output reg  [31:0] q_o
);

    always @(posedge clk_i) begin
        if (rst_i) begin
            q_o <= RESET_VALUE;
        end else if (en_i) begin
            q_o <= d_i;
        end
    end

endmodule
