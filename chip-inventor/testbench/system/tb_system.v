`timescale 1ns/1ps
// System-level test: CPU + UART + GPIO + MUL + Xicrc running one firmware
// (imem FIRMWARE 3, selected by the defparam below). Uses only top-level
// ports and real UART timing (CLK_HZ 20 MHz / 115200 baud = 174 clocks/bit),
// so it runs unchanged in ChipInventor against the canvas top.
//
// Firmware contract, per received byte b with switches s on pins P7..P4:
//   LEDs P3..P0 = b[3:0], UART reply = (b * s) & 0xFF, crc = CRCB(b, crc).
// After 4 bytes it sends crc low byte, crc high byte, then sets x4 = 0x55.
// Expected values computed independently in Python (CRC-16/CCITT-FALSE,
// seed 0xFFFF, poly 0x1021; reference checked against "123456789" = 0x29B1).
module testbench;

    // ---- Clock (20 MHz, matches config.json 50 ns) ----------------------
    reg clk_i = 0;
    always #25 clk_i = ~clk_i;

    localparam integer BIT = 174;         // clocks per UART bit

    // ---- DUT ports --------------------------------------------------------
    reg         rst_i = 1;
    reg         rx_i  = 1;                // UART line idles high
    reg  [3:0]  switches = 0;             // external inputs on P7..P4
    wire [7:0]  pins_i, pins_o, pins_oe_o;
    wire        tx_o, halt_o;
    wire [31:0] pc_dbg_o, x4_dbg_o;

    // Pad model: a pin reads back what the chip drives when output-enabled,
    // otherwise the external switch level (P3..P0 have nothing external).
    assign pins_i = {switches, 4'b0000} & ~pins_oe_o | (pins_o & pins_oe_o);

    top dut (
        .clk_i(clk_i), .rst_i(rst_i), .halt_o(halt_o),
        .pins_i(pins_i), .pins_o(pins_o), .pins_oe_o(pins_oe_o),
        .rx_i(rx_i), .tx_o(tx_o),
        .pc_dbg_o(pc_dbg_o), .x4_dbg_o(x4_dbg_o)
    );

    // Select this test's program in imem (0 = Stage 2, the default).
    // IMEM_INST is imem's instance name in the top: blk3564_70 on the
    // ChipInventor canvas; run_tests.py overrides it for rtl/top.v.
`ifndef IMEM_INST
`define IMEM_INST blk3564_70
`endif
    defparam dut.`IMEM_INST.FIRMWARE = 3;

    // ---- Test vectors -----------------------------------------------------
    reg [7:0] rx_bytes [0:3];
    reg [3:0] sw_vals  [0:3];
    reg [7:0] replies  [0:3];
    localparam [15:0] CRC_EXPECTED = 16'h71E0;

    initial begin
        rx_bytes[0] = 8'h31; sw_vals[0] = 4'h3; replies[0] = 8'h93;
        rx_bytes[1] = 8'hA5; sw_vals[1] = 4'h0; replies[1] = 8'h00;
        rx_bytes[2] = 8'h0F; sw_vals[2] = 4'hF; replies[2] = 8'hE1;
        rx_bytes[3] = 8'hC3; sw_vals[3] = 4'h9; replies[3] = 8'hDB;
    end

    integer errors = 0;

    // ---- UART helpers (host side) ----------------------------------------
    task send_byte(input [7:0] b);
        integer i;
        begin
            @(negedge clk_i); rx_i = 0;                   // start bit
            repeat (BIT) @(negedge clk_i);
            for (i = 0; i < 8; i = i + 1) begin           // LSB first
                rx_i = b[i];
                repeat (BIT) @(negedge clk_i);
            end
            rx_i = 1;                                     // stop bit
            repeat (BIT) @(negedge clk_i);
        end
    endtask

    task recv_byte(output [7:0] b);
        integer i;
        begin
            @(negedge tx_o);                              // start bit edge
            repeat (BIT / 2) @(posedge clk_i);            // middle of start bit
            if (tx_o !== 1'b0) begin
                $display("FAIL [tx start bit] not low at mid-bit");
                errors = errors + 1;
            end
            for (i = 0; i < 8; i = i + 1) begin
                repeat (BIT) @(posedge clk_i);
                b[i] = tx_o;
            end
            repeat (BIT) @(posedge clk_i);
            if (tx_o !== 1'b1) begin
                $display("FAIL [tx stop bit] not high");
                errors = errors + 1;
            end
        end
    endtask

    task expect_eq(input [8*24-1:0] what, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL [%0s] got %h expected %h", what, got, exp);
                errors = errors + 1;
            end else
                $display("PASS [%0s] %h", what, got);
        end
    endtask

    // ---- Test sequence ----------------------------------------------------
    integer k;
    reg [7:0] got;

    initial begin
        $dumpfile("testbench.vcd");
        $dumpvars(0, testbench);

        repeat (3) @(negedge clk_i);
        rst_i = 0;
        repeat (200) @(negedge clk_i);                    // firmware setup
        expect_eq("GPIO direction", pins_oe_o, 8'h0F);
        expect_eq("TX idle high", tx_o, 1'b1);

        for (k = 0; k < 4; k = k + 1) begin
            switches = sw_vals[k];
            // Receive in parallel: the CPU may start its reply before the
            // host has finished driving the stop bit.
            fork
                send_byte(rx_bytes[k]);
                recv_byte(got);
            join
            expect_eq("UART reply b*s", got, replies[k]);
            expect_eq("LEDs = b[3:0]", pins_o[3:0], rx_bytes[k][3:0]);
        end

        recv_byte(got);
        expect_eq("CRC low byte", got, CRC_EXPECTED[7:0]);
        recv_byte(got);
        expect_eq("CRC high byte", got, CRC_EXPECTED[15:8]);

        repeat (200) @(negedge clk_i);
        expect_eq("x4 pass marker", x4_dbg_o, 32'h55);

        if (errors == 0)
            $display("ALL TESTS PASSED: system (UART + GPIO + MUL + CRC)");
        else
            $display("FAIL: %0d system check(s) failed", errors);
        $finish;
    end

    initial begin
        #5_000_000;                                       // ~100k cycles
        $display("FAIL [timeout] pc=%h x4=%h", pc_dbg_o, x4_dbg_o);
        $finish;
    end

endmodule
