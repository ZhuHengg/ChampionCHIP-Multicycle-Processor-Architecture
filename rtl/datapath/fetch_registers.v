// =============================================================================
// Module: fetch_registers
// Description: Fetch-Stage Pipeline Registers for ChipInventor.
//              Encapsulates PC, Old_PC, and IR registers into a single clean block
//              with synchronous reset and respective clock enables (pc_write_i, ir_write_i).
// =============================================================================

`timescale 1ns / 1ps

module fetch_registers #(
    parameter PC_RESET_ADDR = 32'h00400000
) (
    input  wire        clk_i,
    input  wire        rst_i,

    // Controls from Control Unit
    input  wire        pc_write_i,      // From control_unit.pc_write_o
    input  wire        ir_write_i,      // From control_unit.ir_write_o

    // Data inputs
    input  wire [31:0] pc_next_i,       // From mux_pc_next.pc_next_o
    input  wire [31:0] mem_data_i,      // Instruction data from memory (decoder_data_o)

    // Register outputs
    output reg  [31:0] pc_o,            // Current PC -> to mux_mem_addr, PC+4 adder
    output reg  [31:0] old_pc_o,        // Saved Old PC -> to mux_alu_a, mux_result
    output reg  [31:0] ir_o             // Instruction Register -> to ir_splitter, imm_extend
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
                old_pc_o <= pc_o;        // Captures pre-increment PC during FETCH
                ir_o     <= mem_data_i;  // Latches fetched instruction during FETCH
            end
        end
    end

endmodule
