module imem (
    input  wire        clk_i,
    input  wire [31:0] addr_i,
    input  wire        oe_i,
    output reg  [31:0] data_o
);
    // Mock program for OpenLane synthesis-only test run (organiser feedback,
    // 2026-09-10): full validation firmware replaced by organiser's
    // 3-instruction mock (external/CCX_Malaysia_Edition_Firmware_Stage_2/
    // README.md) so the synthesized case block doesn't balloon cell count,
    // plus a 4th instruction (`add x4, x7, x0`) added here so the result
    // (expected x7 = 15) lands in x4 -- the only register with a debug
    // port wired out to testbench.v (x4_dbg_o). This is NOT the
    // functional-validation firmware -- that still runs in tb_top
    // simulation against the full imem content (see git history for the
    // 259-word table).
    always @(*) begin
        if (!oe_i) begin
            data_o = 32'h00000000;
        end else begin
            case (addr_i[9:0])
                10'd0: data_o = 32'h00A00293; // addi x5, x0, 10
                10'd1: data_o = 32'h00500313; // addi x6, x0, 5
                10'd2: data_o = 32'h006283B3; // add  x7, x5, x6
                10'd3: data_o = 32'h00038233; // add  x4, x7, x0  (debug-tap copy)
                default: data_o = 32'h00000013; // NOP (addi x0, x0, 0)
            endcase
        end
    end
endmodule