// ChipInventor canvas upload for the UART block: uart + uart_tx + uart_rx in one
// file, uart first so the canvas takes its ports. Copy of rtl/uart.v, rtl/uart_tx.v,
// rtl/uart_rx.v - edit those sources, then regenerate this file. Do not compile
// together with rtl/ (duplicate modules).

// Stage 3 Part 1 section 2: word offsets 0 TXDATA, 1 RXDATA, 2 CONTROL.
// Registered reads match GPIO/DMEM. Only byte lane zero is writable.
// addr_i takes the whole address bus so the ChipInventor canvas can wire it
// bus-to-bus; the register select is taken from addr_i[3:2] here.
// Choices where guide is silent: TXDONE resets high; busy starts are ignored;
// newest received byte wins on overrun; reception wins over software flag clear.
module uart #(
    parameter integer CLK_HZ = 20000000,
    parameter integer BAUD = 115200
) (
    input wire clk_i, rst_i,
    input wire [31:0] addr_i,
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
    wire [1:0] reg_sel = addr_i[3:2]; // word offset; bits [1:0] ignored per guide 2.1
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
                case (reg_sel)
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
            case (reg_sel)
                0: data_o <= {24'b0, txdata};
                1: data_o <= {24'b0, rxdata};
                2: data_o <= {29'b0, (txdone && !transmit), rxdone, 1'b0};
                default: data_o <= 0;
            endcase
        end
    end
endmodule

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

// Single midpoint sample per bit (no oversampling), with a two-flop synchronizer.
// Invalid start/stop bits are discarded; there is no error status in the guide.
module uart_rx #(parameter integer CLKS_PER_BIT = 174) (
    input wire clk_i, rst_i, rx_i,
    output reg [7:0] data_o,
    output reg valid_o
);
    localparam integer CW = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    localparam [1:0] IDLE=0, START=1, DATA=2, STOP=3;
    (* ASYNC_REG = "TRUE" *) reg rx_meta, rx_sync;
    reg [1:0] state;
    reg [CW-1:0] count;
    reg [2:0] bit_index;
    reg [7:0] shift;
    always @(posedge clk_i) begin
        if (rst_i) begin rx_meta <= 1; rx_sync <= 1; end
        else begin rx_meta <= rx_i; rx_sync <= rx_meta; end
    end
    always @(posedge clk_i) begin
        if (rst_i) begin
            state <= IDLE; count <= 0; bit_index <= 0;
            shift <= 0; data_o <= 0; valid_o <= 0;
        end else begin
            valid_o <= 0;
            case (state)
                IDLE: if (!rx_sync) begin count <= 0; state <= START; end
                START: if (count == (CLKS_PER_BIT/2)-1) begin
                    count <= 0;
                    if (!rx_sync) begin bit_index <= 0; state <= DATA; end
                    else state <= IDLE;
                end else count <= count + 1'b1;
                DATA: if (count == CLKS_PER_BIT-1) begin
                    count <= 0; shift[bit_index] <= rx_sync;
                    if (bit_index == 7) state <= STOP;
                    else bit_index <= bit_index + 1'b1;
                end else count <= count + 1'b1;
                STOP: if (count == CLKS_PER_BIT-1) begin
                    count <= 0; state <= IDLE;
                    if (rx_sync) begin data_o <= shift; valid_o <= 1; end
                end else count <= count + 1'b1;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
