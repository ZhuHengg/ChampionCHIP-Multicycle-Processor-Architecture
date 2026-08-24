// tb_address_decoder.v
// Directed tests per docs/MEMORY_BUILD_PLAN.md address_decoder.v section:
//  - address in IMEM range routes to IMEM (imem_oe_o), not DMEM
//  - address in DMEM range routes to DMEM (dmem_oe_o/dmem_we_o), not IMEM
//  - we_i reaches dmem_we_o but NEVER imem (no imem_we_o port exists at all)
//  - bw_o reaches DMEM only (zeroed when address is IMEM range)
//  - bottom 2 bits dropped from address_o
//  - read mux returns the right device's data
//  - unmapped address returns zero

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_address_decoder;

    reg  [31:0] address;
    reg         we, oe;
    reg  [3:0]  bw;
    reg  [31:0] dmem_data, imem_data;

    wire [29:0] address_o;
    wire        dmem_we_o, dmem_oe_o, imem_oe_o;
    wire [3:0]  bw_o;
    wire [31:0] data_o;

    integer errors;

    address_decoder dut (
        .address_i(address),
        .we_i(we),
        .oe_i(oe),
        .bw_i(bw),
        .dmem_data_i(dmem_data),
        .imem_data_i(imem_data),
        .address_o(address_o),
        .dmem_we_o(dmem_we_o),
        .dmem_oe_o(dmem_oe_o),
        .imem_oe_o(imem_oe_o),
        .bw_o(bw_o),
        .data_o(data_o)
    );

    task check1(input [255:0] name, input got, input exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got=%b exp=%b", name, got, exp);
                errors = errors + 1;
            end else begin
                $display("PASS %0s: got=%b", name, got);
            end
        end
    endtask

    task check32(input [255:0] name, input [31:0] got, input [31:0] exp);
        begin
            if (got !== exp) begin
                $display("FAIL %0s: got=%h exp=%h", name, got, exp);
                errors = errors + 1;
            end else begin
                $display("PASS %0s: got=%h", name, got);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_address_decoder.vcd");
        $dumpvars(0, tb_address_decoder);

        errors = 0;
        dmem_data = 32'hAAAA_AAAA;
        imem_data = 32'h5555_5555;

        // --- IMEM range routing ---
        address = `IMEM_BASE + 32'h100;
        we = 1'b1; oe = 1'b1; bw = 4'b1111;
        #1;
        check1("IMEM addr -> imem_oe_o asserted", imem_oe_o, 1'b1);
        check1("IMEM addr -> dmem_oe_o deasserted", dmem_oe_o, 1'b0);
        check1("IMEM addr -> dmem_we_o deasserted (we never reaches IMEM path)", dmem_we_o, 1'b0);
        check1("IMEM addr -> bw_o zeroed (DMEM only)", |bw_o, 1'b0);
        check32("IMEM addr -> data_o = imem_data", data_o, imem_data);
        check32("bottom 2 bits dropped from address_o", {address_o, 2'b00}, `IMEM_BASE + 32'h100);

        // --- DMEM range routing ---
        address = `DMEM_BASE + 32'h4;
        we = 1'b1; oe = 1'b1; bw = 4'b0011;
        #1;
        check1("DMEM addr -> dmem_oe_o asserted", dmem_oe_o, 1'b1);
        check1("DMEM addr -> imem_oe_o deasserted", imem_oe_o, 1'b0);
        check1("DMEM addr -> dmem_we_o follows we_i", dmem_we_o, 1'b1);
        check1("DMEM addr -> bw_o passed through", bw_o == 4'b0011, 1'b1);
        check32("DMEM addr -> data_o = dmem_data", data_o, dmem_data);
        check32("bottom 2 bits dropped (DMEM)", {address_o, 2'b00}, `DMEM_BASE + 32'h4);

        // --- we_i never reaches IMEM (no imem_we_o port exists; confirm
        // dmem_we_o stays clear when address is IMEM range even with
        // we_i asserted, and that no such signal is wired to IMEM at all
        // by construction — checked structurally via port list above) ---
        address = `IMEM_BASE;
        we = 1'b1; oe = 1'b0; bw = 4'b1111;
        #1;
        check1("IMEM addr, we_i=1 -> dmem_we_o still 0", dmem_we_o, 1'b0);

        // --- Unmapped address ---
        address = 32'h2000_0000;
        we = 1'b0; oe = 1'b1; bw = 4'b0000;
        #1;
        check1("unmapped -> imem_oe_o 0", imem_oe_o, 1'b0);
        check1("unmapped -> dmem_oe_o 0", dmem_oe_o, 1'b0);
        check32("unmapped -> data_o = 0", data_o, 32'h0);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
