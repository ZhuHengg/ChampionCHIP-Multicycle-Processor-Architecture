// imm_extend.v — immediate extraction + sign extension per format

module imm_extend (
    input  wire [31:0] instr_i,
    input  wire [2:0]  imm_sel_i,
    output reg  [31:0] imm_o
);

    localparam [2:0] IMM_SEL_I = 3'b000; // I-type
    localparam [2:0] IMM_SEL_S = 3'b001; // S-type
    localparam [2:0] IMM_SEL_B = 3'b010; // B-type
    localparam [2:0] IMM_SEL_U = 3'b011; // U-type
    localparam [2:0] IMM_SEL_J = 3'b100; // J-type

    always @(*) begin
        imm_o = 32'b0; // default
        case (imm_sel_i)
            IMM_SEL_I: imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
            IMM_SEL_S: imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
            IMM_SEL_B: imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                                  instr_i[30:25], instr_i[11:8], 1'b0};
            IMM_SEL_U: imm_o = {instr_i[31:12], 12'b0};
            IMM_SEL_J: imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                                  instr_i[20], instr_i[30:21], 1'b0};
            default: imm_o = 32'b0;
        endcase
    end

endmodule
