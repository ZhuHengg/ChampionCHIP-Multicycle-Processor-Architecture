// Memory address decoder.

module address_decoder (
    input  wire [31:0] address_i,
    input  wire        we_i,
    input  wire        oe_i,
    input  wire [3:0]  bw_i,

    input  wire [31:0] dmem_data_i,
    input  wire [31:0] imem_data_i,
    input  wire [31:0] gpio_data_i,
    input  wire [31:0] uart_data_i,

    output wire [31:0] address_o,     // word address (zero-extended)
    output wire        dmem_we_o,
    output wire        dmem_oe_o,
    output wire        imem_oe_o,
    output wire        uart_we_o,
    output wire        uart_oe_o,
    output wire        gpio_we_o,
    output wire        gpio_oe_o,
    output wire [3:0]  bw_o,
    output reg  [31:0] data_o
);

    // Memory Map Base Addresses (Guide Table 13)
    localparam [31:0] IMEM_BASE = 32'h0040_0000;
    localparam [31:0] DMEM_BASE = 32'h1001_0000;

    localparam [31:0] IMEM_LOW  = IMEM_BASE;
    localparam [31:0] IMEM_HIGH = IMEM_BASE + 32'h0040_0000 - 1; // +4MB
    localparam [31:0] DMEM_LOW  = DMEM_BASE;
    localparam [31:0] DMEM_HIGH = DMEM_BASE + 32'h0000_2000 - 1; // +8kB

    // Stage 3 GPIO registers; low two byte-address bits are ignored.
    wire is_gpio = (address_i[31:4] == 28'hF000000) &&
                   (address_i[3:2] != 2'b11);

    wire is_uart = (address_i[31:4] == 28'hF100000) &&
                   (address_i[3:2] != 2'b11);

    wire is_imem = (address_i >= IMEM_LOW) && (address_i <= IMEM_HIGH);
    wire is_dmem = (address_i >= DMEM_LOW) && (address_i <= DMEM_HIGH);

  	assign address_o = {2'b00, address_i[31:2]};// zeroextending

    assign uart_we_o = we_i && is_uart;
    assign uart_oe_o = oe_i && is_uart;

    assign gpio_we_o = we_i && is_gpio;
    assign gpio_oe_o = oe_i && is_gpio;

    assign dmem_we_o = we_i && is_dmem;
    assign dmem_oe_o = oe_i && is_dmem;
    assign imem_oe_o = oe_i && is_imem;
    assign bw_o      = is_dmem ? bw_i : 4'b0000;

    always @(*) begin
        data_o = 32'b0; // default: unmapped address, guide silent (see header note)
        if (is_gpio)
            data_o = gpio_data_i;
        else if (is_uart)
            data_o = uart_data_i;
        else if (is_dmem)
            data_o = dmem_data_i;
        else if (is_imem)
            data_o = imem_data_i;
    end

endmodule