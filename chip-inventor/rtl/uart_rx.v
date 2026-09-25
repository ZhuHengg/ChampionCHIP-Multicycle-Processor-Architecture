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
