// imm_extend.v
// Guide §3.1.5. Extracts immediate per format, sign-extends to 32 bits.
module imm_extend_eq26(
    input  wire [31:0] instr_i,
    input  wire [2:0]  imm_sel_i,
    output reg  [31:0] imm_o
);
    // Immediate Format Selectors
    localparam [2:0] IMM_SEL_I = 3'b000; // I-type (ALU imm, loads, JALR)
    localparam [2:0] IMM_SEL_S = 3'b001; // S-type (stores)
    localparam [2:0] IMM_SEL_B = 3'b010; // B-type (branches)
    localparam [2:0] IMM_SEL_U = 3'b011; // U-type (LUI, AUIPC)
    localparam [2:0] IMM_SEL_J = 3'b100; // J-type (JAL)
    always @(*) begin
        imm_o = 32'b0; // default
        case (imm_sel_i)
            // I-type: instr[31:20], sign-extended
            IMM_SEL_I: imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
            // S-type: {instr[31:25], instr[11:7]}, sign-extended
            IMM_SEL_S: imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
            // B-type: {instr[31], instr[7], instr[30:25], instr[11:8], 0},
            // sign-extended. Implicit trailing zero (2-byte aligned).
            IMM_SEL_B: imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                                  instr_i[30:25], instr_i[11:8], 1'b0};
            // U-type: {instr[31:12], 12'b0} — no sign extension needed,
            // immediate occupies the upper bits directly.
            IMM_SEL_U: imm_o = {instr_i[31:12], 12'b0};
            // J-type: {instr[31], instr[19:12], instr[20], instr[30:21], 0},
            // sign-extended. Implicit trailing zero.
            IMM_SEL_J: imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                                  instr_i[20], instr_i[30:21], 1'b0};
            default: imm_o = 32'b0;
        endcase
    end
endmodule