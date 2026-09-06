// branch_comparator.v — rs1/rs2 branch condition compare

module branch_comparator (
    input  wire [31:0] rs1_i,
    input  wire [31:0] rs2_i,
    input  wire [2:0]  funct3_i,
    output reg  branch_taken_o
);

    // RV32I standard branch funct3 encodings
    localparam FUNCT3_BEQ  = 3'b000;
    localparam FUNCT3_BNE  = 3'b001;
    localparam FUNCT3_BLT  = 3'b100;
    localparam FUNCT3_BGE  = 3'b101;
    localparam FUNCT3_BLTU = 3'b110;
    localparam FUNCT3_BGEU = 3'b111;

    always @(*) begin
        branch_taken_o = 1'b0; // default
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
