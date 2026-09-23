// Stage 3 Part 1, sections 1.1-1.3: eight independent GPIO pins.
// Bus: clk/rst (1), word offset addr_i (2), we/oe (1), byte mask (4),
// write/read data (32), bidirectional pins_io (8).
// Offsets: 0 DATAOUT (RW), 1 DATAIN (R), 2 DATADIR (RW).
// Direction 0 releases the pin; direction 1 drives DATAOUT.
// Implementation choices where the guide is silent: synchronous active-high
// reset, all registers reset to zero, DATAIN holds its last sample in output
// mode. Reserved bits/offsets read zero. Writes only affect byte lane zero.
// Read data registers on oe_i and holds otherwise, matching the core's
// MEM_ACCESS_ADDR -> MEM_ACCESS_DATA load sequence and DMEM interface.
// Board integration must map the tri-state drivers to bidirectional I/O pads.
module gpio (
    input wire clk_i,
    input wire rst_i,
    input wire [1:0] addr_i,
    input wire we_i,
    input wire oe_i,
    input wire [3:0] bw_i,
    input wire [31:0] data_i,
    output reg [31:0] data_o,
    inout wire [7:0] pins_io
);
    reg [7:0] dataout;
    reg [7:0] datadir;
    reg [7:0] datain;

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : pin_control
            assign pins_io[i] = datadir[i] ? dataout[i] : 1'bz;
            always @(posedge clk_i) begin
                if (rst_i)
                    datain[i] <= 1'b0;
                else if (!datadir[i])
                    datain[i] <= pins_io[i];
            end
        end
    endgenerate

    always @(posedge clk_i) begin
        if (rst_i) begin
            dataout <= 8'b0;
            datadir <= 8'b0;
        end else if (we_i && bw_i[0]) begin
            case (addr_i)
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
            case (addr_i)
                2'd0: data_o <= {24'b0, dataout};
                2'd1: data_o <= {24'b0, datain};
                2'd2: data_o <= {24'b0, datadir};
                default: data_o <= 32'b0;
            endcase
        end
    end
endmodule
