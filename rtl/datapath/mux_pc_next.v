// mux_pc_next.v — next-PC mux: PC+4 / branch-jal target / jalr target

`timescale 1ns / 1ps

module mux_pc_next (
    input  wire [1:0]  pc_src_i,
    input  wire [31:0] pc_i,
    input  wire [31:0] alu_result_i,
    output reg  [31:0] pc_next_o
);

    always @(*) begin
        case (pc_src_i)
            2'b00:   pc_next_o = pc_i + 32'd4;
            2'b01:   pc_next_o = alu_result_i;
            2'b10:   pc_next_o = {alu_result_i[31:1], 1'b0}; // jalr clears bit 0
            default: pc_next_o = pc_i + 32'd4;
        endcase
    end

endmodule
