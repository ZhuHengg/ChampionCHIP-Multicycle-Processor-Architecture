// Stage 3 Part 1, sections 1.1-1.3: eight independent GPIO pins.
// Bus: clk/rst (1), full byte address addr_i (32), we/oe (1), byte mask (4),
// write/read data (32), split pin bus pins_i/pins_o/pins_oe_o (8 each).
// addr_i takes the whole address bus so the ChipInventor canvas can wire it
// bus-to-bus (no bit slicing on the canvas); the register select is taken
// from addr_i[3:2] here. The decoder gates we_i/oe_i, so upper bits are unused.
// Offsets: 0 DATAOUT (RW), 1 DATAIN (R), 2 DATADIR (RW).
// Direction 0 releases the pin; direction 1 drives DATAOUT.
// Implementation choices where the guide is silent: synchronous active-high
// reset, all registers reset to zero, DATAIN holds its last sample in output
// mode. Reserved bits/offsets read zero. Writes only affect byte lane zero.
// Read data registers on oe_i and holds otherwise, matching the core's
// MEM_ACCESS_ADDR -> MEM_ACCESS_DATA load sequence and DMEM interface.
// Deviation from guide Figure 1: the tri-state buffer is NOT inside this block.
// ChipInventor's Inout Pin drops its C/D inputs (converter 3.15 emits only an
// inout port), and FPGA fabric/Sky130 macros want split in/out/enable anyway.
// The pad outside the core does: pin = pins_oe_o ? pins_o : Z; pins_i = pin.
module gpio (
    input wire clk_i,
    input wire rst_i,
    input wire [31:0] addr_i,
    input wire we_i,
    input wire oe_i,
    input wire [3:0] bw_i,
    input wire [31:0] data_i,
    output reg [31:0] data_o,
    input  wire [7:0] pins_i,    // level on each pad
    output wire [7:0] pins_o,    // DATAOUT, value to drive
    output wire [7:0] pins_oe_o  // DATADIR, 1 = drive pad (output enable)
);
    reg [7:0] dataout;
    reg [7:0] datadir;
    reg [7:0] datain;
    wire [1:0] reg_sel = addr_i[3:2]; // word offset; bits [1:0] ignored per guide 1.1

    assign pins_o    = dataout;
    assign pins_oe_o = datadir;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : pin_control
            always @(posedge clk_i) begin
                if (rst_i)
                    datain[i] <= 1'b0;
                else if (!datadir[i])
                    datain[i] <= pins_i[i];
            end
        end
    endgenerate

    always @(posedge clk_i) begin
        if (rst_i) begin
            dataout <= 8'b0;
            datadir <= 8'b0;
        end else if (we_i && bw_i[0]) begin
            case (reg_sel)
                2'd0: dataout <= data_i[7:0];
                2'd2: datadir <= data_i[7:0];
                default: begin end // DATAIN is read-only.
            endcase
        end
    end

    always @(posedge clk_i) begin
        if (rst_i)
            data_o <= 32'b0;
        else if (oe_i) begin
            case (reg_sel)
                2'd0: data_o <= {24'b0, dataout};
                2'd1: data_o <= {24'b0, datain};
                2'd2: data_o <= {24'b0, datadir};
                default: data_o <= 32'b0;
            endcase
        end
    end
endmodule
