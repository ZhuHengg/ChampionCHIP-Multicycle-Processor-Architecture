// tb_alu.v — all 11 ALU ops, shift masking, SRA negative, SLT/SLTU trap

`timescale 1ns/1ps
`include "pkg/rvbl2_defines.vh"

module tb_alu;

    reg  [31:0] a_i, b_i;
    reg  [3:0]  alu_op_i;
    wire [31:0] result_o;

    integer errors = 0;

    alu dut (
        .a_i(a_i),
        .b_i(b_i),
        .alu_op_i(alu_op_i),
        .result_o(result_o)
    );

    task check(input [127:0] name, input [31:0] expected);
        begin
            if (result_o !== expected) begin
                $display("FAIL: %0s  a=%h b=%h op=%h got=%h exp=%h",
                          name, a_i, b_i, alu_op_i, result_o, expected);
                errors = errors + 1;
            end else begin
                $display("PASS: %0s  a=%h b=%h op=%h -> %h",
                          name, a_i, b_i, alu_op_i, result_o);
            end
        end
    endtask

    initial begin
        $dumpfile("sim/tb_alu.vcd");
        $dumpvars(0, tb_alu);

        a_i = 32'h0000000A; b_i = 32'h00000003;

        alu_op_i = `ALU_PASS_B; #1; check("PASS_B", b_i);
        alu_op_i = `ALU_ADD;    #1; check("ADD", 32'd13);
        alu_op_i = `ALU_SUB;    #1; check("SUB", 32'd7);
        alu_op_i = `ALU_AND;    #1; check("AND", 32'h0000000A & 32'h00000003);
        alu_op_i = `ALU_OR;     #1; check("OR",  32'h0000000A | 32'h00000003);
        alu_op_i = `ALU_XOR;    #1; check("XOR", 32'h0000000A ^ 32'h00000003);
        alu_op_i = `ALU_SLL;    #1; check("SLL", 32'h0000000A << 3);
        alu_op_i = `ALU_SRL;    #1; check("SRL", 32'h0000000A >> 3);

        // SRA on negative operand
        a_i = 32'hFFFFFFF0; b_i = 32'd4; // -16 >>> 4 = -1
        alu_op_i = `ALU_MRS; #1; check("MRS/SRA negative", 32'hFFFFFFFF);

        // shift amount > 31: only b_i[4:0] used
        a_i = 32'hFFFFFFFF; b_i = 32'd32; // b[4:0] = 0 -> shift by 0
        alu_op_i = `ALU_SLL; #1; check("SLL shamt>31 masked", 32'hFFFFFFFF);
        alu_op_i = `ALU_SRL; #1; check("SRL shamt>31 masked", 32'hFFFFFFFF);
        b_i = 32'd33; // b[4:0] = 1 -> shift by 1
        alu_op_i = `ALU_SRL; #1; check("SRL shamt=33 masked to 1", 32'h7FFFFFFF);

        // SLT/SLTU trap: a=0xFFFFFFFF (-1 signed), b=0x00000001
        a_i = 32'hFFFFFFFF; b_i = 32'h00000001;
        alu_op_i = `ALU_SLT;  #1; check("SLT trap (-1<1 signed)", 32'd1);
        alu_op_i = `ALU_SLTU; #1; check("SLTU trap (huge<1 unsigned)", 32'd0);

        // SLT/SLTU normal case
        a_i = 32'd1; b_i = 32'd5;
        alu_op_i = `ALU_SLT;  #1; check("SLT normal (1<5)", 32'd1);
        alu_op_i = `ALU_SLTU; #1; check("SLTU normal (1<5)", 32'd1);

        // illegal alu_op -> default
        a_i = 32'hDEADBEEF; b_i = 32'hCAFEBABE;
        alu_op_i = 4'hF; #1; check("illegal op default", 32'b0);

        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("%0d TEST(S) FAILED", errors);

        $finish;
    end

endmodule
