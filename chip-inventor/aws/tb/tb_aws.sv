`timescale 1ns/1ps
// Stage 4 AWS FPGA system testbench.
//
// DUT = the organiser's top.sv, unmodified (CCX_Malaysia_Edition_Stage_4)
//     + our generated riscv.sv (RISCV, Transmitter, Receiver)
//     + aws/sim/stubs (cl_ports.vh, sh_ddr and BUFGCE_DIV stand-ins).
//
// The host side follows RVBL-Emulator/src/emu.c call for call, over the OCL
// AXI-Lite port, the way ./emu drives the FPGA:
//   - every AXI access is preceded by DELAY_AXI() = usleep(50 ms)
//   - fpga_init: read-modify-write IN to set direction 0x01, then reset 1,0,1
//   - -i / -d: read-modify-write of register 0x04
//   - -o: one read of 0x08, compared with all 32 bits
//   - -tN: per byte, write 0x0C, then poll 0x0C until bit 8 (TX done)
//   - -rN: read 0x10 and 0x14, consume bytes through a static pointer
//   - the first [error] skips every later option (goto main_end)
//
// Time compression: real pacing (50 ms per AXI access) would mean 12.5 M cycles
// per access at 250 MHz. TIME_SCALE divides both the emu delay AND the
// millisecond base of meter_timer (defparam), so every firmware timeout (400 ms
// inter-byte, 4000 ms watchdog) keeps its true ratio to the host pacing. UART
// bit timing is NOT scaled: 2170 clocks/bit, as on the FPGA.
//
// Scenario bodies (scenario.vh) are shared with testbench/app/tb_app.v and
// generated from testbench/app/scenarios.py by aws/run_aws_tests.py.
module tb_aws;

`ifndef TIME_SCALE
`define TIME_SCALE 100            // sim ms = real ms / TIME_SCALE
`endif
`ifndef AXI_DELAY_MS
`define AXI_DELAY_MS 50           // emu.c DELAY_AXI()
`endif
`ifndef CORE_DIV
`define CORE_DIV 1                // must match the riscv.sv image (1 or 5)
`endif
`ifndef PRESET_IN
`define PRESET_IN 0               // IN register left over from a previous run
`endif
`ifndef INIT_DIRECTION
`define INIT_DIRECTION 1          // stock emu.c; application host should use 0xF0
`endif

    localparam integer SYS_HZ      = 250_000_000;
    localparam integer CORE_HZ     = SYS_HZ / `CORE_DIV;
    localparam integer CYC_PER_MS  = SYS_HZ / 1000 / `TIME_SCALE;   // sys clocks
    localparam integer AXI_DELAY   = `AXI_DELAY_MS * CYC_PER_MS;

    // OCL register map (top.sv header / emu.c)
    localparam [31:0] RESET_ADDR = 32'h00, IN_ADDR = 32'h04, OUT_ADDR = 32'h08,
                      TX_ADDR = 32'h0C, RX0_ADDR = 32'h10, RX1_ADDR = 32'h14,
                      RXN_ADDR = 32'h18, PC_ADDR = 32'h1C;

    // ---- clock / shell reset ---------------------------------------------
    reg clk_main_a0 = 1'b0;
    always #2 clk_main_a0 = ~clk_main_a0;      // 250 MHz
    reg rst_main_n = 1'b0;

    // ---- OCL AXI-Lite master signals ---------------------------------------
    reg         awvalid = 0, wvalid = 0, bready = 1, arvalid = 0, rready = 1;
    reg  [31:0] awaddr = 0, wdata = 0, araddr = 0;
    reg  [3:0]  wstrb = 4'hF;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;

    top dut (
        .clk_main_a0   (clk_main_a0),
        .rst_main_n    (rst_main_n),
        .ocl_cl_awvalid(awvalid), .ocl_cl_awaddr(awaddr), .cl_ocl_awready(awready),
        .ocl_cl_wvalid (wvalid),  .ocl_cl_wdata(wdata),   .ocl_cl_wstrb(wstrb),
        .cl_ocl_wready (wready),
        .cl_ocl_bvalid (bvalid),  .cl_ocl_bresp(bresp),   .ocl_cl_bready(bready),
        .ocl_cl_arvalid(arvalid), .ocl_cl_araddr(araddr), .cl_ocl_arready(arready),
        .cl_ocl_rvalid (rvalid),  .cl_ocl_rdata(rdata),   .cl_ocl_rresp(rresp),
        .ocl_cl_rready (rready),
        .CLK_DIMM_DP(1'b0), .CLK_DIMM_DN(1'b1)
    );

    // Millisecond base scaled with the host pacing (see header).
    defparam dut.riscvtop.e_PROCESSOR.meter_timer_inst.CLK_HZ = CORE_HZ / `TIME_SCALE;

    // ---- bookkeeping ---------------------------------------------------------
    integer errors = 0;
    integer aborted = 0;                  // emu.c: first [error] -> main_end
    integer halted = 0;
    integer x_reads = 0;
    reg     dir_written = 0;
    reg     core_out_of_reset = 0;
    integer rx_bytes = 0;                 // bytes top.sv's Receiver stored
    reg [7:0] uart_ptr = 0;               // emu.c fpga_read_uart static current_ptr

`ifdef TRACE_RX
    // Event-based startup trace: expose floating inputs and false sessions.
    always @(dut.riscvtop.e_PROCESSOR.x4_dbg_o or dut.input_en or dut.io_Pins)
        if (core_out_of_reset)
            $display("[startup] t=%0d ms: state=%0d direction=%02X pads=%02X",
                     $time / 4 / CYC_PER_MS,
                     dut.riscvtop.e_PROCESSOR.x4_dbg_o, dut.input_en, dut.io_Pins);
`endif

    always @(posedge clk_main_a0) begin
        if (!dut.riscv_nreset) rx_bytes <= 0;
        else if (dut.w_Rx_Done) rx_bytes <= rx_bytes + 1;
`ifdef TRACE_RX
        if (dut.riscv_nreset && dut.w_Rx_Done)
            $display("[trace] t=%0d ms: core sent 0x%02X (byte %0d, state x4=%0d, pins=%02X)",
                     $time / 4 / CYC_PER_MS, dut.w_Rx_Data, rx_bytes,
                     dut.riscvtop.e_PROCESSOR.x4_dbg_o, dut.output_pins);
`endif
        if (core_out_of_reset && dut.riscvtop.e_PROCESSOR.halt_o === 1'b1) halted <= 1;
    end

    // Contention: the host drives io_Pins[i] while input_en[i] = 0; our core
    // drives it while DATADIR[i] = 1. Both at once is a fight on the FPGA.
    always @(posedge clk_main_a0) begin
        if (dir_written && core_out_of_reset && !aborted &&
            ((dut.riscvtop.pins_oe & ~dut.input_en) != 8'h00)) begin
            $display("[tb] FAIL contention: core oe=%02X host dir=%02X",
                     dut.riscvtop.pins_oe, dut.input_en);
            errors = errors + 1;
            aborted = 1;
        end
    end

    // ---- AXI-Lite master (no emu delay) --------------------------------------
    task automatic axi_write_raw(input [31:0] addr, input [31:0] data);
        reg aw_done, w_done;
        begin
            @(negedge clk_main_a0);
            awaddr = addr; awvalid = 1; wdata = data; wstrb = 4'hF; wvalid = 1;
            aw_done = 0; w_done = 0;
            while (!(aw_done && w_done)) begin
                @(posedge clk_main_a0);
                if (awvalid && awready) aw_done = 1;
                if (wvalid && wready)   w_done = 1;
                @(negedge clk_main_a0);
                if (aw_done) awvalid = 0;
                if (w_done)  wvalid = 0;
            end
            @(posedge clk_main_a0);
            while (!bvalid) @(posedge clk_main_a0);
        end
    endtask

    // Bits top.sv returns as z (OUT bits whose direction is 0: output_pins[i]
    // is z there) read as 0 on the FPGA, where Vivado turns internal tristates
    // into logic; the organiser's own example confirms it: -i 0x02 then
    // -o 0x20. x means contention or uninitialised logic and is reported.
    task automatic axi_read_raw(input [31:0] addr, output [31:0] data);
        integer k;
        begin
            @(negedge clk_main_a0);
            araddr = addr; arvalid = 1;
            @(posedge clk_main_a0);
            while (!arready) @(posedge clk_main_a0);
            @(negedge clk_main_a0);
            arvalid = 0;
            @(posedge clk_main_a0);
            while (!rvalid) @(posedge clk_main_a0);
            data = rdata;
            for (k = 0; k < 32; k = k + 1) begin
                if (data[k] === 1'bz) data[k] = 1'b0;
                else if (data[k] === 1'bx) begin
                    data[k] = 1'b0;
                    x_reads = x_reads + 1;
                end
            end
        end
    endtask

    // emu.c fpga_write_addr / fpga_read_addr: DELAY_AXI() first.
    task automatic axi_delay;
        begin
            repeat (AXI_DELAY) @(posedge clk_main_a0);
        end
    endtask
    task automatic fpga_write_addr(input [31:0] addr, input [31:0] data);
        begin axi_delay; axi_write_raw(addr, data); end
    endtask
    task automatic fpga_read_addr(input [31:0] addr, output [31:0] data);
        begin axi_delay; axi_read_raw(addr, data); end
    endtask

    // ---- emu.c options ---------------------------------------------------
    task emu_begin;
        reg [31:0] in_reg;
        begin
            repeat (20) @(posedge clk_main_a0);
            rst_main_n = 1;                          // shell reset released
            repeat (20) @(posedge clk_main_a0);
            axi_write_raw(IN_ADDR, `PRESET_IN);      // IN persists from earlier runs
            // fpga_init: fpga_write_direction(0x01), then fpga_reset (1, 0, 1)
            fpga_read_addr(IN_ADDR, in_reg);
            fpga_write_addr(IN_ADDR, (in_reg & 32'h00FF) | (`INIT_DIRECTION << 8));
            fpga_write_addr(RESET_ADDR, 32'h1);
            fpga_write_addr(RESET_ADDR, 32'h0);
            fpga_write_addr(RESET_ADDR, 32'h1);
            core_out_of_reset = 1;
            $display("[ok] RISC-V started!");
        end
    endtask

    task emu_d(input [7:0] value);
        reg [31:0] in_reg;
        begin
            if (!aborted) begin
                fpga_read_addr(IN_ADDR, in_reg);
                fpga_write_addr(IN_ADDR, (in_reg & 32'h00FF) | ({24'h0, value} << 8));
                dir_written = 1;
                $display("[ok] Written 0x%08X to DIRECTION", {24'h0, value});
            end
        end
    endtask

    task emu_i(input [7:0] value);
        reg [31:0] in_reg;
        begin
            if (!aborted) begin
                fpga_read_addr(IN_ADDR, in_reg);
                fpga_write_addr(IN_ADDR, (in_reg & 32'hFF00) | value);
                $display("[ok] Written 0x%08X to INPUT PINS", {24'h0, value});
            end
        end
    endtask

    // state == 8'hFF skips the x4 (application state) check, as in tb_app.v.
    task emu_o(input [7:0] exp, input [7:0] state);
        reg [31:0] got;
        reg [31:0] x4;
        begin
            if (!aborted) begin
                fpga_read_addr(OUT_ADDR, got);
                if (got !== {24'h0, exp}) begin
                    $display("[error] OUT read error. Expected 0x%08X. Got 0x%08X",
                             {24'h0, exp}, got);
                    errors = errors + 1;
                    aborted = 1;
                end else begin
                    $display("[ok] Read 0x%08X from OUTPUT PINS", got);
                    x4 = dut.riscvtop.e_PROCESSOR.x4_dbg_o;
                    if (state !== 8'hFF && x4 !== {24'h0, state}) begin
                        $display("[tb] FAIL x4 = 0x%08X, expected 0x%02X", x4, state);
                        errors = errors + 1;
                        aborted = 1;
                    end
                end
            end
        end
    endtask

    task emu_t(input integer n, input [31:0] value);
        integer k;
        reg [31:0] tx_reg;
        begin
            if (!aborted) begin
                for (k = 0; k < n; k = k + 1) begin         // fpga_write_uart
                    fpga_write_addr(TX_ADDR, value[8 * k +: 8]);
                    tx_reg = 0;
                    while (!tx_reg[8]) fpga_read_addr(TX_ADDR, tx_reg);
                end
                case (n)
                    1: $display("[ok] Written 0x%02X to UART RX", value[7:0]);
                    2: $display("[ok] Written 0x%04X to UART RX", value[15:0]);
                    default: $display("[ok] Written 0x%08X to UART RX", value);
                endcase
            end
        end
    endtask

    task emu_r(input integer n, input [31:0] value);
        reg [31:0] rx0, rx1, got;
        reg [63:0] window;
        integer k;
        begin
            if (!aborted) begin
                if (n <= 0 || n > 8 || uart_ptr + n > 8) begin
                    // emu.c returns 1 for n > 8; past the 64-bit window the C
                    // shift is undefined, which the tb also treats as an error.
                    $display("[error] \"fpga_read_uart\" error: 1");
                    errors = errors + 1;
                    aborted = 1;
                end else begin
                    fpga_read_addr(RX0_ADDR, rx0);
                    fpga_read_addr(RX1_ADDR, rx1);
                    window = {rx1, rx0};
                    got = 32'h0;
                    for (k = 0; k < n; k = k + 1)
                        got[8 * k +: 8] = window[8 * (uart_ptr + k) +: 8];
                    uart_ptr = uart_ptr + n;
                    if (got !== value) begin
                        case (n)
                            1: $display("[error] UART read error. Expected 0x%02X. Got 0x%02X",
                                        value[7:0], got[7:0]);
                            2: $display("[error] UART read error. Expected 0x%04X. Got 0x%04X",
                                        value[15:0], got[15:0]);
                            default: $display("[error] UART read error. Expected 0x%08X. Got 0x%08X",
                                              value, got);
                        endcase
                        errors = errors + 1;
                        aborted = 1;
                    end else begin
                        case (n)
                            1: $display("[ok] Read 0x%02X from UART TX", got[7:0]);
                            2: $display("[ok] Read 0x%04X from UART TX", got[15:0]);
                            default: $display("[ok] Read 0x%08X from UART TX", got);
                        endcase
                    end
                end
            end
        end
    endtask

    // Harness-only checks after the emu options (not part of emu.c).
    task emu_end;
        reg [31:0] pc;
        begin
            repeat (AXI_DELAY) @(posedge clk_main_a0);
            if (!aborted && rx_bytes > 8) begin
                // top.sv's walker wraps after 8 bytes and overwrites byte 0.
                $display("[tb] FAIL %0d bytes transmitted; top.sv keeps only 8", rx_bytes);
                errors = errors + 1;
            end
            if (!aborted && rx_bytes > uart_ptr) begin
                $display("[tb] FAIL unread reply bytes: %0d received, %0d read",
                         rx_bytes, uart_ptr);
                errors = errors + 1;
            end
            if (halted) begin
                $display("[tb] FAIL halt asserted (ecall/ebreak or illegal instruction)");
                errors = errors + 1;
            end
            if (x_reads) begin
                $display("[tb] FAIL %0d x bit(s) read over AXI", x_reads);
                errors = errors + 1;
            end
            // PC readback (0x1C) goes through top.sv's hierarchical reference
            // riscvtop.e_PROCESSOR.w_PC_Output: proves that path elaborates.
            axi_read_raw(PC_ADDR, pc);
            if (pc < 32'h0040_0000 || pc >= 32'h0040_1000 || pc[1:0] != 2'b00) begin
                $display("[tb] FAIL PC readback 0x%08X outside IMEM", pc);
                errors = errors + 1;
            end else
                $display("[tb] PC readback 0x%08X", pc);
            $display("[tb] pacing: %0d ms per AXI access, time scale 1/%0d, core %0d MHz",
                     `AXI_DELAY_MS, `TIME_SCALE, CORE_HZ / 1_000_000);
            if (errors == 0) $display("SCENARIO RESULT: PASS");
            else             $display("SCENARIO RESULT: FAIL (%0d errors)", errors);
            $finish;
        end
    endtask

    initial begin
`ifdef VCD
        $dumpfile("aws.vcd");
        $dumpvars(0, tb_aws);
`endif
`include "scenario.vh"
    end

`ifndef TB_TIMEOUT_MS
`define TB_TIMEOUT_MS 60000          // real (unscaled) emu milliseconds
`endif
    initial begin
        repeat (`TB_TIMEOUT_MS) repeat (CYC_PER_MS) @(posedge clk_main_a0);
        $display("[tb] FAIL timeout");
        $display("SCENARIO RESULT: FAIL (%0d errors)", errors + 1);
        $finish;
    end

endmodule
