// crc.v
// Guide §3.1.3, Table 11 (Xicrc). CRC-16/CCITT-FALSE over 8/16/32 bits of
// rs1, seeded by rs2. Parameters confirmed by organisers, verified against
// scripts/crc_reference.py and firmware/crc_test.S (all three chains ->
// 0x1E82). See docs/DATAPATH_BUILD_PLAN.md.
//
// NOTE operand roles are reversed from the usual incremental-CRC convention:
// a_i (rs1) is the DATA, b_i (rs2) is the running CRC SEED. Confirmed by the
// firmware's `crcb s0, s1, s0` (rd=s0, rs1=s1 data, rs2=s0 seed).
//
// Combinational only: guide §3.1.3 "without latency" — values in, value out,
// no clock, no state.

module crc (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  crc_op_i,
    output reg  [31:0] result_o
);

    // CRC Operation Codes (Table 11 - Xicrc)
    localparam [3:0] CRC_CRCB = 4'h0;
    localparam [3:0] CRC_CRCH = 4'h1;
    localparam [3:0] CRC_CRCW = 4'h2;

    parameter POLY    = 16'h1021;
    parameter INIT    = 16'hFFFF; // unused directly — seed comes in via b_i, kept for spec visibility
    parameter XOR_OUT = 16'h0000;

    integer i;
    reg [15:0] crc;
    reg        bit_in, msb;

    always @(*) begin
        result_o = 32'b0; // default, also covers illegal crc_op
        case (crc_op_i)
            CRC_CRCB, CRC_CRCH, CRC_CRCW: begin
                crc = b_i[15:0]; // seed threads through rs2
                case (crc_op_i)
                    CRC_CRCB: begin
                        for (i = 7; i >= 0; i = i - 1) begin
                            bit_in = a_i[i];
                            msb    = crc[15];
                            crc    = (crc << 1) & 16'hFFFF;
                            if (msb ^ bit_in) crc = crc ^ POLY;
                        end
                    end
                    CRC_CRCH: begin
                        for (i = 15; i >= 0; i = i - 1) begin
                            bit_in = a_i[i];
                            msb    = crc[15];
                            crc    = (crc << 1) & 16'hFFFF;
                            if (msb ^ bit_in) crc = crc ^ POLY;
                        end
                    end
                    default: begin // CRC_CRCW
                        for (i = 31; i >= 0; i = i - 1) begin
                            bit_in = a_i[i];
                            msb    = crc[15];
                            crc    = (crc << 1) & 16'hFFFF;
                            if (msb ^ bit_in) crc = crc ^ POLY;
                        end
                    end
                endcase
                result_o = {16'b0, crc ^ XOR_OUT};
            end
            default: result_o = 32'b0;
        endcase
    end

endmodule
