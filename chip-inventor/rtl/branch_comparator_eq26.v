// branch_comparator.v
// Guide §3.1.6. Compares rs1/rs2 per funct3, drives branch_taken_o which
// arrives at the control unit as branch_taken_i.
//
// Combinational only: values in, value out, no clock, no state.

module branch_comparator_eq26(
    input  wire [31:0] rs1_i,
    input  wire [31:0] rs2_i,
    input  wire [2:0]  funct3_i,
    output reg  branch_taken_o
);

    // funct3 encodings are RV32I standard branch funct3 values (RISC-V
    // spec, not guide-defined — no macro exists for these in
    // rvbl2_defines.vh, so literals here are the spec encoding itself).
    localparam FUNCT3_BEQ  = 3'b000;
    localparam FUNCT3_BNE  = 3'b001;
    localparam FUNCT3_BLT  = 3'b100;
    localparam FUNCT3_BGE  = 3'b101;
    localparam FUNCT3_BLTU = 3'b110;
    localparam FUNCT3_BGEU = 3'b111;

    always @(*) begin
        branch_taken_o = 1'b0; // default: not taken (covers 010/011 unused)
        case (funct3_i)
            FUNCT3_BEQ:  branch_taken_o = (rs1_i == rs2_i);
            FUNCT3_BNE:  branch_taken_o = (rs1_i != rs2_i);
            FUNCT3_BLT:  branch_taken_o = ($signed(rs1_i) <  $signed(rs2_i));
            FUNCT3_BGE:  branch_taken_o = ($signed(rs1_i) >= $signed(rs2_i));
            FUNCT3_BLTU: branch_taken_o = (rs1_i <  rs2_i);
            FUNCT3_BGEU: branch_taken_o = (rs1_i >= rs2_i);
            default:     branch_taken_o = 1'b0;
        endcase
    end

endmodule