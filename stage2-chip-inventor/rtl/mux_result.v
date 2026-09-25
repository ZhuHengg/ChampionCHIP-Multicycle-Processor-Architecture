module mux_result (
    input  wire [2:0]  result_src_i,   // Select code from Control Unit (result_src_o)
    input  wire [31:0] alu_out_i,      // ALU registered result (3'b000)
    input  wire [31:0] mult_result_i,  // Multiplier registered result (3'b001)
    input  wire [31:0] crc_result_i,   // CRC registered result (3'b010)
    input  wire [31:0] mem_result_i,   // Memory loaded result from LSU (3'b011)
    input  wire [31:0] old_pc_i,       // Old PC for JAL/JALR return address (3'b100 -> Old_PC + 4)
    output reg  [31:0] result_o        // Selected 32-bit data to regfile.write_data_i
);

    localparam [2:0] RESULT_SRC_ALU = 3'b000;
    localparam [2:0] RESULT_SRC_MUL = 3'b001;
    localparam [2:0] RESULT_SRC_CRC = 3'b010;
    localparam [2:0] RESULT_SRC_MEM = 3'b011;
    localparam [2:0] RESULT_SRC_PC4 = 3'b100;

    always @(*) begin
        case (result_src_i)
            RESULT_SRC_ALU: result_o = alu_out_i;
            RESULT_SRC_MUL: result_o = mult_result_i;
            RESULT_SRC_CRC: result_o = crc_result_i;
            RESULT_SRC_MEM: result_o = mem_result_i;
            RESULT_SRC_PC4: result_o = old_pc_i + 32'd4;
            default:        result_o = alu_out_i;
        endcase
    end

endmodule