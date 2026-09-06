// fetch_registers.v — PC / old_pc / IR fetch-stage registers

`timescale 1ns / 1ps

module fetch_registers #(
    parameter PC_RESET_ADDR = 32'h00400000
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        pc_write_i,
    input  wire        ir_write_i,
    input  wire [31:0] pc_next_i,
    input  wire [31:0] mem_data_i,
    output reg  [31:0] pc_o,
    output reg  [31:0] old_pc_o,
    output reg  [31:0] ir_o
);

    always @(posedge clk_i) begin
        if (rst_i) begin
            pc_o     <= PC_RESET_ADDR;
            old_pc_o <= 32'b0;
            ir_o     <= 32'b0;
        end else begin
            if (pc_write_i) begin
                pc_o <= pc_next_i;
            end
            if (ir_write_i) begin
                old_pc_o <= pc_o; // pre-increment PC
                ir_o     <= mem_data_i;
            end
        end
    end

endmodule
