module alu_out_reg #(
    parameter RESET_VALUE = 32'h00000000
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        en_i,           // Enable: 1 = load alu_result_i, 0 = hold
    input  wire [31:0] alu_result_i,   // From alu.result_o
    output reg  [31:0] alu_out_o,      // Registered 32-bit ALU output
    output wire [1:0]  addr_lsb_o      // Direct tap of alu_out_o[1:0] -> to CU.addr_lsb_i
);

    always @(posedge clk_i) begin
        if (rst_i) begin
            alu_out_o <= RESET_VALUE;
        end else if (en_i) begin
            alu_out_o <= alu_result_i;
        end
    end

    // Direct extraction of lowest 2 bits for the Control Unit byte-write mask
    assign addr_lsb_o = alu_out_o[1:0];

endmodule