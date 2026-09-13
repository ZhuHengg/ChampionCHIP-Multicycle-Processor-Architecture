module reg32_dff_eq26 #(
    parameter RESET_VALUE = 32'h00000000
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        en_i,       // Enable: 1 = load d_i, 0 = hold current value
    input  wire [31:0] d_i,        // Data input (D)
    output reg  [31:0] q_o         // Data output (Q)
);

    always @(posedge clk_i) begin
        if (rst_i) begin
            q_o <= RESET_VALUE;
        end else if (en_i) begin
            q_o <= d_i;
        end
    end

endmodule
// Generic D flip-flop register.