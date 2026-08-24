// tb_regfile.v
// Directed tests per docs/MEMORY_BUILD_PLAN.md regfile.v section:
//  1. write x1-x31, read back
//  2. write x0, confirm still reads zero
//  3. read x0 before any write
//  4. simultaneous read of two different registers
//  5. read-during-write of same register: async read sees OLD value
//     (write lands on the edge, read is combinational off current regs)

`timescale 1ns/1ps

module tb_regfile;

    reg         clk;
    reg         rst;
    reg  [4:0]  rs1_addr, rs2_addr, rd_addr;
    reg  [31:0] write_data;
    reg         reg_write;
    wire [31:0] rs1_data, rs2_data;

    integer errors;

    regfile dut (
        .clk_i(clk),
        .rst_i(rst),
        .rs1_addr_i(rs1_addr),
        .rs2_addr_i(rs2_addr),
        .rd_addr_i(rd_addr),
        .write_data_i(write_data),
        .reg_write_i(reg_write),
        .rs1_data_o(rs1_data),
        .rs2_data_o(rs2_data)
    );

    always #5 clk = ~clk;

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
        $dumpfile("sim/tb_regfile.vcd");
        $dumpvars(0, tb_regfile);

        clk = 0; rst = 1; errors = 0;
        rs1_addr = 0; rs2_addr = 0; rd_addr = 0;
        write_data = 0; reg_write = 0;

        @(posedge clk); #1;
        rst = 0;

        // --- Test 3: read x0 before any write ---
        rs1_addr = 5'd0; rs2_addr = 5'd0; #1;
        check32("x0 read before any write", rs1_data, 32'h0);

        // --- Test 1: write x1..x31, read back ---
        for (integer r = 1; r < 32; r = r + 1) begin
            rd_addr = r[4:0];
            write_data = 32'hA000_0000 + r;
            reg_write = 1'b1;
            @(posedge clk); #1;
            reg_write = 1'b0;
            rs1_addr = r[4:0];
            #1;
            check32("write/readback", rs1_data, 32'hA000_0000 + r);
        end

        // --- Test 2: write x0, confirm still reads zero ---
        rd_addr = 5'd0;
        write_data = 32'hFFFF_FFFF;
        reg_write = 1'b1;
        @(posedge clk); #1;
        reg_write = 1'b0;
        rs1_addr = 5'd0;
        #1;
        check32("x0 write-protect", rs1_data, 32'h0);

        // --- Test 4: simultaneous read of two different registers ---
        rs1_addr = 5'd1; rs2_addr = 5'd2; #1;
        check32("simul read rs1(x1)", rs1_data, 32'hA000_0001);
        check32("simul read rs2(x2)", rs2_data, 32'hA000_0002);

        // --- Test 5: read-during-write of same register: async read
        // should see the OLD value (write lands on the clock edge) ---
        rd_addr = 5'd5;
        rs1_addr = 5'd5;
        write_data = 32'hDEAD_BEEF;
        reg_write = 1'b1;
        #1; // still combinational, before edge
        check32("read-during-write sees OLD value", rs1_data, 32'hA000_0005);
        @(posedge clk); #1;
        reg_write = 1'b0;
        check32("read after write-edge sees NEW value", rs1_data, 32'hDEAD_BEEF);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
