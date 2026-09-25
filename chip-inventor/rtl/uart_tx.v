// 8-N-1 transmitter. start_i while busy is ignored; done_o stays high when idle.
module uart_tx #(parameter integer CLKS_PER_BIT = 174) (
    input wire clk_i, rst_i, start_i,
    input wire [7:0] data_i,
    output reg tx_o, busy_o, done_o
);
    localparam integer CW = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    reg [CW-1:0] count;
    reg [3:0] bit_index;
    reg [7:0] shift;
    always @(posedge clk_i) begin
        if (rst_i) begin
            tx_o <= 1; busy_o <= 0; done_o <= 1;
            count <= 0; bit_index <= 0; shift <= 0;
        end else if (!busy_o) begin
            if (start_i) begin
                shift <= data_i;
                tx_o <= 0; busy_o <= 1; done_o <= 0;
                count <= 0; bit_index <= 0;
            end
        end else if (count == CLKS_PER_BIT-1) begin
            count <= 0;
            if (bit_index < 8) begin
                tx_o <= shift[0]; shift <= {1'b0, shift[7:1]};
                bit_index <= bit_index + 1'b1;
            end else if (bit_index == 8) begin
                tx_o <= 1; bit_index <= 9;
            end else begin
                busy_o <= 0; done_o <= 1;
            end
        end else count <= count + 1'b1;
    end
endmodule
