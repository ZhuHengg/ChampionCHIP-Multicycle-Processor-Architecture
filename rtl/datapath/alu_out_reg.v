// alu_out_reg.v — ALU output register + addr_lsb tap

`timescale 1ns / 1ps

module alu_out_reg #(
    parameter RESET_VALUE = 32'h00000000
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        en_i,
    input  wire [31:0] alu_result_i,
    output reg  [31:0] alu_out_o,
    output wire [1:0]  addr_lsb_o
);

    always @(posedge clk_i) begin
        if (rst_i) begin
            alu_out_o <= RESET_VALUE;
        end else if (en_i) begin
            alu_out_o <= alu_result_i;
        end
    end

    assign addr_lsb_o = alu_out_o[1:0];

endmodule
