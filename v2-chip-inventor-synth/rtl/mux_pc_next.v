module mux_pc_next (
    input  wire [1:0]  pc_src_i,      // From control_unit.pc_src_o[1:0]
    input  wire [31:0] pc_i,          // From fetch_registers.pc_o (adds +4 internally!)
    input  wire [31:0] alu_result_i,  // From alu.result_o (Live branch/jump target)
    output reg  [31:0] pc_next_o      // To fetch_registers.pc_next_i
);
    always @(*) begin
        case (pc_src_i)
            2'b00:   pc_next_o = pc_i + 32'd4;                 // PC + 4 computed inside!
            2'b01:   pc_next_o = alu_result_i;                 // Branch / JAL target
            2'b10:   pc_next_o = {alu_result_i[31:1], 1'b0};   // JALR target (clears bit 0)
            default: pc_next_o = pc_i + 32'd4;
        endcase
    end
endmodule