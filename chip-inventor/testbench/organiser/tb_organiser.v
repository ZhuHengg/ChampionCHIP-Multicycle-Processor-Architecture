`timescale 1ns/1ps
// Validates FIRMWARE 4 (the verbatim official Stage 3 GPIO/UART test
// firmware, see external/CCX_Malaysia_Edition_Stage_3/RVBL-GPIO-UART-Test-
// Firmware) against the organiser's own minimum test in that folder's
// README: P3-0 = 0xA must appear as P7-4 = 0xA (DATAOUT = 0xA0), and a
// byte sent on UART RX (0x30) must be echoed back on UART TX.
//
// Firmware behavior (main.s): P7-4 output / P3-0 input (opposite of our
// own gpio_program's direction), continuously copy P3-0 -> P7-4, then
// wait for one UART RX byte, echo it on TX, and repeat -- so GPIO and
// UART both run in the same infinite loop, not once each.
module testbench;

    reg clk = 0;
    always #25 clk = ~clk;                 // 20 MHz, matches config.json

    localparam integer BIT = 174;          // 20 MHz / 115200 baud

    reg  rst = 1, rx = 1;
    reg  [3:0] sw_p3_0 = 4'h0;             // external stimulus on P3-0
    wire [7:0] pins_i, pins_o, pins_oe_o;
    wire tx;

    // Pad model: a pin reads back what the chip drives when output-enabled
    // (P7-4), otherwise the external stimulus (P3-0).
    assign pins_i = (pins_o & pins_oe_o) | ({4'h0, sw_p3_0} & ~pins_oe_o);

    top dut (.clk_i(clk), .rst_i(rst), .rx_i(rx), .tx_o(tx),
             .pins_i(pins_i), .pins_o(pins_o), .pins_oe_o(pins_oe_o));

    // Select this test's program in imem (0 = Stage 2, the default).
    // IMEM_INST is imem's instance name in the top: blk3564_70 on the
    // ChipInventor canvas; run_tests.py overrides it for hdl_ref.v/rtl/top.v.
`ifndef IMEM_INST
`define IMEM_INST blk3564_70
`endif
    defparam dut.`IMEM_INST.FIRMWARE = 4;

    integer errors = 0;
    integer i;
    reg [7:0] rxb;

    // Poll pins_o[7:4] until it matches `exp` or `limit` clocks pass. The
    // firmware only refreshes P7-4 once per loop iteration (after each
    // UART round trip), so a fixed-delay sample can catch a stale value.
    task wait_gpio_echo(input [3:0] exp, input integer limit, input [8*24-1:0] what);
        integer n;
        begin
            n = 0;
            while (pins_o[7:4] !== exp && n < limit) begin
                @(negedge clk);
                n = n + 1;
            end
            if (pins_o[7:4] !== exp) begin
                $display("FAIL [%0s] P7-4 = %h, expected %h (timed out after %0d clocks)",
                          what, pins_o[7:4], exp, n);
                errors = errors + 1;
            end else
                $display("PASS [%0s] P3-0 = 0x%h, P7-4 = 0x%h (%0d clocks)", what, exp, exp, n);
        end
    endtask

    task send_byte(input [7:0] b);
        integer k;
        begin
            @(negedge clk); rx = 0;                  // start bit
            repeat (BIT) @(negedge clk);
            for (k = 0; k < 8; k = k + 1) begin       // LSB first
                rx = b[k];
                repeat (BIT) @(negedge clk);
            end
            rx = 1;                                   // stop bit
            repeat (BIT) @(negedge clk);
        end
    endtask

    task recv_byte(output [7:0] b);
        integer k;
        begin
            @(negedge tx);                            // start bit edge
            repeat (BIT / 2) @(posedge clk);
            if (tx !== 1'b0) begin
                $display("FAIL [tx start bit] not low at mid-bit");
                errors = errors + 1;
            end
            for (k = 0; k < 8; k = k + 1) begin
                repeat (BIT) @(posedge clk);
                b[k] = tx;
            end
            repeat (BIT) @(posedge clk);
            if (tx !== 1'b1) begin
                $display("FAIL [tx stop bit] not high");
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("testbench.vcd");
        $dumpvars(0, testbench);

        // Per the organiser README: "The first GPIO stimulus must be
        // present before the firmware performs its GPIO read." The
        // firmware samples P3-0 once per loop pass, then blocks on UART
        // RX until a byte arrives -- so P3-0 must be driven before reset
        // releases, or the first (only, until a UART byte unblocks it)
        // sample would see 0.
        sw_p3_0 = 4'hA;
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (100) @(negedge clk);       // let DATADIR setup + first echo settle

        // GPIO: P3-0 = 0xA must appear as P7-4 = 0xA (DATAOUT = 0xA0).
        if (pins_oe_o !== 8'hF0) begin
            $display("FAIL [GPIO direction] pins_oe_o = %h, expected f0 (P7-4 out)", pins_oe_o);
            errors = errors + 1;
        end
        wait_gpio_echo(4'hA, 300, "GPIO");

        // Loop restarts only after a full UART round trip (organiser
        // README: "A new GPIO value is processed only after the UART
        // echo completes"), so change P3-0 before sending the byte and
        // check the new echo only after TX finishes.
        sw_p3_0 = 4'h5;

        // UART: send 0x30 through RX, expect 0x30 echoed back through TX.
        fork
            send_byte(8'h30);
            recv_byte(rxb);
        join
        if (rxb !== 8'h30) begin
            $display("FAIL [UART echo] RX = 30, TX = %h", rxb);
            errors = errors + 1;
        end else
            $display("PASS [UART] RX = 0x30, TX = 0x30");

        wait_gpio_echo(4'h5, 300, "GPIO after UART");

        if (errors == 0)
            $display("PASS: GPIO and UART firmware test completed successfully");
        else
            $display("FAIL: %0d organiser firmware check(s) failed", errors);
        $finish;
    end

    initial begin
        #2_000_000;                        // 40k cycles
        $display("FAIL [timeout]");
        $finish;
    end

endmodule
