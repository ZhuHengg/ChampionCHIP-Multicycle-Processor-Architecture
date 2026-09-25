// Stage 3 Part 1 section 2: word offsets 0 TXDATA, 1 RXDATA, 2 CONTROL.
// Registered reads match GPIO/DMEM. Only byte lane zero is writable.
// Choices where guide is silent: TXDONE resets high; busy starts are ignored;
// newest received byte wins on overrun; reception wins over software flag clear.
module uart #(
    parameter integer CLK_HZ = 20000000,
    parameter integer BAUD = 115200
) (
    input wire clk_i, rst_i,
    input wire [1:0] addr_i,
    input wire we_i, oe_i,
    input wire [3:0] bw_i,
    input wire [31:0] data_i,
    output reg [31:0] data_o,
    input wire rx_i,
    output wire tx_o
);
    // Round to nearest whole clock. Supported configurations need >= 4 clocks/bit.
    localparam integer CLKS_PER_BIT = (CLK_HZ + BAUD/2) / BAUD;
    reg [7:0] txdata, rxdata;
    reg transmit, rxdone;
    wire txbusy, txdone, rxvalid;
    wire [7:0] received;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) transmitter (
        .clk_i(clk_i), .rst_i(rst_i), .start_i(transmit), .data_i(txdata),
        .tx_o(tx_o), .busy_o(txbusy), .done_o(txdone)
    );
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) receiver (
        .clk_i(clk_i), .rst_i(rst_i), .rx_i(rx_i),
        .data_o(received), .valid_o(rxvalid)
    );
    always @(posedge clk_i) begin
        if (rst_i) begin
            txdata <= 0; rxdata <= 0; transmit <= 0; rxdone <= 0;
        end else begin
            transmit <= 0;
            if (we_i && bw_i[0]) begin
                case (addr_i)
                    0: txdata <= data_i[7:0];
                    2: begin
                        transmit <= data_i[0] && !txbusy && !transmit;
                        rxdone <= data_i[1];
                    end
                    default: begin end
                endcase
            end
            if (rxvalid) begin rxdata <= received; rxdone <= 1; end
        end
    end
    always @(posedge clk_i) begin
        if (rst_i) data_o <= 0;
        else if (oe_i) begin
            case (addr_i)
                0: data_o <= {24'b0, txdata};
                1: data_o <= {24'b0, rxdata};
                2: data_o <= {29'b0, (txdone && !transmit), rxdone, 1'b0};
                default: data_o <= 0;
            endcase
        end
    end
endmodule
