// Independent elapsed-ms counters: +0 valid meter age, +4 RX inter-byte age.
// A word write refreshes only the selected counter and its divider.
// Saturation prevents an unattended meter from becoming fresh after wraparound.
module meter_timer #(parameter integer CLK_HZ = 20000000) (
    input wire clk_i, rst_i, we_i, oe_i,
    input wire [31:0] addr_i,
    output reg [31:0] data_o
);
    localparam integer TICKS_PER_MS = (CLK_HZ < 1000) ? 1 : CLK_HZ / 1000;
    localparam integer CW = (TICKS_PER_MS > 1) ? $clog2(TICKS_PER_MS) : 1;
    reg [CW-1:0] ticks;
    reg [31:0] age_ms;
    reg [CW-1:0] rx_ticks;
    reg [31:0] rx_age_ms;
    always @(posedge clk_i) begin
        if (rst_i || (we_i && !addr_i[2])) begin
            ticks <= 0;
            age_ms <= 0;
        end else if (ticks == TICKS_PER_MS - 1) begin
            ticks <= 0;
            if (age_ms != 32'hffffffff) age_ms <= age_ms + 1'b1;
        end else ticks <= ticks + 1'b1;
        if (rst_i || (we_i && addr_i[2])) begin
            rx_ticks <= 0;
            rx_age_ms <= 0;
        end else if (rx_ticks == TICKS_PER_MS - 1) begin
            rx_ticks <= 0;
            if (rx_age_ms != 32'hffffffff) rx_age_ms <= rx_age_ms + 1'b1;
        end else rx_ticks <= rx_ticks + 1'b1;
        if (rst_i) data_o <= 0;
        else if (oe_i) data_o <= addr_i[2] ? rx_age_ms : age_ms;
    end
endmodule
