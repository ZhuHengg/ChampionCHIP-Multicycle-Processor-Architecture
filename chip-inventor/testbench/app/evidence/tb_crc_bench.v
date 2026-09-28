`timescale 1ns/1ps
// CRC-16 cycle bench: measures crcb (hardware) vs software shift-xor loop
// on the same 6-byte payload. FIRMWARE 6 sets x4 = 1 before the hw CRC,
// x4 = 2 before the sw CRC, x4 = 3 when done, then x4 = (hw << 16) | sw.
module testbench;

    reg clk_i = 0;
    always #25 clk_i = ~clk_i;

    reg        rst_i = 1;
    reg        rx_i  = 1;
    wire [7:0] pins_i, pins_o, pins_oe_o;
    wire       tx_o, halt_o;
    wire [31:0] pc_dbg_o, x4_dbg_o;

    assign pins_i = 8'h00;

    top dut (
        .clk_i(clk_i), .rst_i(rst_i), .halt_o(halt_o),
        .pins_i(pins_i), .pins_o(pins_o), .pins_oe_o(pins_oe_o),
        .rx_i(rx_i), .tx_o(tx_o),
        .pc_dbg_o(pc_dbg_o), .x4_dbg_o(x4_dbg_o)
    );

`ifndef IMEM_INST
`define IMEM_INST blk3564_70
`endif
    defparam dut.`IMEM_INST.FIRMWARE = 6;

    localparam [15:0] EXPECTED_CRC = 16'hCC77;

    integer errors = 0;
    integer cycle_count = 0;
    integer hw_start = 0, hw_end = 0, sw_start = 0, sw_end = 0;

    always @(posedge clk_i) cycle_count <= cycle_count + 1;

    // Track x4 transitions
    reg [31:0] prev_x4 = 0;
    always @(posedge clk_i) begin
        if (!rst_i) begin
            if (x4_dbg_o != prev_x4) begin
                case (x4_dbg_o)
                    32'h1: begin
                        hw_start = cycle_count;
                        $display("x4=1 at cycle %0d: hw CRC start", cycle_count);
                    end
                    32'h2: begin
                        hw_end = cycle_count;
                        sw_start = cycle_count;
                        $display("x4=2 at cycle %0d: hw CRC done, sw CRC start", cycle_count);
                    end
                    32'h3: begin
                        sw_end = cycle_count;
                        $display("x4=3 at cycle %0d: sw CRC done", cycle_count);
                    end
                endcase
            end
            prev_x4 <= x4_dbg_o;
        end
    end

    initial begin
        $dumpfile("crc_bench.vcd");
        $dumpvars(0, testbench);

        repeat (3) @(negedge clk_i);
        rst_i = 0;

        // Wait for x4 to reach 3 (both CRCs computed)
        wait (x4_dbg_o == 32'h3);
        repeat (50) @(posedge clk_i);

        // Wait for final x4 value (hw << 16 | sw)
        wait (x4_dbg_o != 32'h3);
        repeat (5) @(posedge clk_i);

        $display("");
        $display("hw CRC cycles: %0d", hw_end - hw_start);
        $display("sw CRC cycles: %0d", sw_end - sw_start);
        if (sw_start > hw_start && hw_end > hw_start)
            $display("speedup: %0dx", (sw_end - sw_start) / (hw_end - hw_start));

        // Check both halves match expected CRC
        if (x4_dbg_o[31:16] !== EXPECTED_CRC) begin
            $display("FAIL [hw CRC] got 0x%04X expected 0x%04X",
                     x4_dbg_o[31:16], EXPECTED_CRC);
            errors = errors + 1;
        end else
            $display("PASS [hw CRC] 0x%04X", x4_dbg_o[31:16]);

        if (x4_dbg_o[15:0] !== EXPECTED_CRC) begin
            $display("FAIL [sw CRC] got 0x%04X expected 0x%04X",
                     x4_dbg_o[15:0], EXPECTED_CRC);
            errors = errors + 1;
        end else
            $display("PASS [sw CRC] 0x%04X", x4_dbg_o[15:0]);

        if (halt_o) begin
            $display("FAIL [halt] halt_o asserted");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("ALL TESTS PASSED: crcb vs software CRC-16 bench");
        else
            $display("FAIL: %0d error(s)", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL [timeout] pc=%h x4=%h", pc_dbg_o, x4_dbg_o);
        $finish;
    end

endmodule
