// =============================================================================
// Module: mux_pc_next
// Description: 3-to-1 PC Next Multiplexer for ChipInventor.
//              Selects the next Program Counter value:
//                2'b00: PC + 4 (computes pc_i + 4 internally, no external adder needed!)
//                2'b01: Branch / JAL target (from live alu.result_o)
//                2'b10: JALR target (from live alu.result_o with bit 0 cleared)
// =============================================================================

`timescale 1ns / 1ps

module mux_pc_next (
    input  wire [1:0]  pc_src_i,      // 2'b00: PC+4, 2'b01: Target, 2'b10: JALR target (from CU)
    input  wire [31:0] pc_i,          // Current PC from fetch_registers (adds +4 internally)
    input  wire [31:0] alu_result_i,  // Live ALU result from alu.result_o
    output reg  [31:0] pc_next_o      // Next PC value -> to fetch_registers.pc_next_i
);

    always @(*) begin
        case (pc_src_i)
            2'b00:   pc_next_o = pc_i + 32'd4;
            2'b01:   pc_next_o = alu_result_i;
            2'b10:   pc_next_o = {alu_result_i[31:1], 1'b0}; // RISC-V JALR clears bit 0
            default: pc_next_o = pc_i + 32'd4;
        endcase
    end

endmodule
