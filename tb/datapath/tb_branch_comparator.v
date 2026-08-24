// tb_branch_comparator.v
// Directed tests: all 6 branch instructions, taken + not-taken, plus the
// signed/unsigned disagreement case (build plan trap).

`timescale 1ns/1ps

module tb_branch_comparator;

    reg  [31:0] rs1_i, rs2_i;
    reg  [2:0]  funct3_i;
    wire        branch_taken_o;

    integer errors = 0;

    branch_comparator dut (
        .rs1_i(rs1_i),
        .rs2_i(rs2_i),
        .funct3_i(funct3_i),
        .branch_taken_o(branch_taken_o)
    );

    task check(input [127:0] name, input expected);
        begin
            if (branch_taken_o !== expected) begin
                $display("FAIL: %0s  rs1=%h rs2=%h funct3=%b got=%b exp=%b",
                          name, rs1_i, rs2_i, funct3_i, branch_taken_o, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s  rs1=%h rs2=%h funct3=%b -> %b",
                          name, rs1_i, rs2_i, funct3_i, branch_taken_o);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_branch_comparator.vcd");
        $dumpvars(0, tb_branch_comparator);

        // BEQ
        funct3_i = 3'b000; rs1_i = 32'd5; rs2_i = 32'd5; #1; check("BEQ taken", 1'b1);
        funct3_i = 3'b000; rs1_i = 32'd5; rs2_i = 32'd6; #1; check("BEQ not taken", 1'b0);

        // BNE
        funct3_i = 3'b001; rs1_i = 32'd5; rs2_i = 32'd6; #1; check("BNE taken", 1'b1);
        funct3_i = 3'b001; rs1_i = 32'd5; rs2_i = 32'd5; #1; check("BNE not taken", 1'b0);

        // BLT (signed) — negative operand case
        funct3_i = 3'b100; rs1_i = -32'sd1; rs2_i = 32'd1; #1; check("BLT taken (-1<1)", 1'b1);
        funct3_i = 3'b100; rs1_i = 32'd5;  rs2_i = 32'd1; #1; check("BLT not taken (5<1)", 1'b0);

        // BGE (signed)
        funct3_i = 3'b101; rs1_i = 32'd5;  rs2_i = 32'd1; #1; check("BGE taken (5>=1)", 1'b1);
        funct3_i = 3'b101; rs1_i = -32'sd1; rs2_i = 32'd1; #1; check("BGE not taken (-1>=1)", 1'b0);

        // BLTU (unsigned)
        funct3_i = 3'b110; rs1_i = 32'd1; rs2_i = 32'd5; #1; check("BLTU taken (1<5)", 1'b1);
        funct3_i = 3'b110; rs1_i = 32'd5; rs2_i = 32'd1; #1; check("BLTU not taken (5<1)", 1'b0);

        // BGEU (unsigned)
        funct3_i = 3'b111; rs1_i = 32'd5; rs2_i = 32'd1; #1; check("BGEU taken (5>=1)", 1'b1);
        funct3_i = 3'b111; rs1_i = 32'd1; rs2_i = 32'd5; #1; check("BGEU not taken (1>=5)", 1'b0);

        // THE TRAP: rs1=0xFFFFFFFF, rs2=0x00000001
        // signed: -1 < 1  -> BLT taken
        funct3_i = 3'b100; rs1_i = 32'hFFFFFFFF; rs2_i = 32'h00000001; #1;
        check("TRAP BLT (-1<1 signed)", 1'b1);
        // unsigned: 4294967295 < 1 is false -> BLTU not taken
        funct3_i = 3'b110; rs1_i = 32'hFFFFFFFF; rs2_i = 32'h00000001; #1;
        check("TRAP BLTU (huge<1 unsigned)", 1'b0);
        // BGE signed: -1 >= 1 false
        funct3_i = 3'b101; rs1_i = 32'hFFFFFFFF; rs2_i = 32'h00000001; #1;
        check("TRAP BGE (-1>=1 signed)", 1'b0);
        // BGEU unsigned: huge >= 1 true
        funct3_i = 3'b111; rs1_i = 32'hFFFFFFFF; rs2_i = 32'h00000001; #1;
        check("TRAP BGEU (huge>=1 unsigned)", 1'b1);

        // Unused funct3 -> default not-taken
        funct3_i = 3'b010; rs1_i = 32'd5; rs2_i = 32'd5; #1; check("unused funct3 010", 1'b0);
        funct3_i = 3'b011; rs1_i = 32'd5; rs2_i = 32'd5; #1; check("unused funct3 011", 1'b0);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
