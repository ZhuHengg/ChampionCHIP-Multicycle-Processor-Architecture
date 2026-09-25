module testbench(); 

reg [31:0] a_i = 0;
reg [31:0] b_i = 0;
reg [3:0] mult_op_i = 0;
wire [31:0] result_o;



 top ai45( .a_i(a_i), .b_i(b_i), .mult_op_i(mult_op_i), .result_o(result_o)); 


initial begin 
		$display("--- SIMULATION START for mult_eq26 ---");
        
        // 1. Initialize
        a_i = 32'd0; b_i = 32'd0; mult_op_i = 4'd0;
        #20;
        
        // ---------------------------------------------------------
        // 2. Test Basic Multiplication (op = 0 is MUL)
        a_i = 32'd10; b_i = 32'd5; mult_op_i = 4'd0;
        #1; 
        $display("\n[Time %0t] TEST MUL (Basic): a = %d, b = %d, op = %d", $time, a_i, b_i, mult_op_i);
        $display("  -> READ : result_o = %d", result_o);
        if (result_o === 32'd50) 
            $display("  -> SUCCESS (Reason: 10 * 5 = 50)"); 
        else $display("  -> FAILED: Expected 50");
        #9;
        
        // ---------------------------------------------------------
        // 3. Test Negative Multiplication (op = 0)
        a_i = 32'hFFFFFFFE; b_i = 32'd6; mult_op_i = 4'd0;
        #1; 
        $display("\n[Time %0t] TEST MUL (Negative): a = %d (signed), b = %d, op = %d", $time, $signed(a_i), b_i, mult_op_i);
        $display("  -> READ : result_o = %d (signed)", $signed(result_o));
        if (result_o === 32'hFFFFFFF4) 
            $display("  -> SUCCESS (Reason: -2 * 6 = -12, which is FFFFFFF4 in 32-bit two's complement)"); 
        else $display("  -> FAILED: Expected -12 (fffffff4)");
        #9;

        // ---------------------------------------------------------
        // 4. Test Large Number Multiplication (op = 0)
        a_i = 32'h00010000; b_i = 32'h00010000; mult_op_i = 4'd0;
        #1; 
        $display("\n[Time %0t] TEST MUL (Overflow): a = %h, b = %h, op = %d", $time, a_i, b_i, mult_op_i);
        $display("  -> READ : result_o = %h", result_o);
        if (result_o === 32'h00000000) 
            $display("  -> SUCCESS (Reason: 0x10000 * 0x10000 = 0x100000000. Lower 32 bits are 00000000)"); 
        else $display("  -> FAILED: Expected 00000000");
        #9;

        // ---------------------------------------------------------
        // 5. Test MULH (op = 1): Signed * Signed (Upper 32 bits)
        a_i = 32'h40000000; b_i = 32'h40000000; mult_op_i = 4'd1;
        #1; 
        $display("\n[Time %0t] TEST MULH (op=1): a = %h, b = %h, op = %d", $time, a_i, b_i, mult_op_i);
        $display("  -> READ : result_o = %h", result_o);
        if (result_o === 32'h10000000) 
            $display("  -> SUCCESS (Reason: 2^30 * 2^30 = 2^60 (0x10000000_00000000). Upper 32 bits are 10000000)"); 
        else $display("  -> FAILED: Expected 10000000");
        #9;

        // ---------------------------------------------------------
        // 6. Test MULHSU (op = 2): Signed * Unsigned (Upper 32 bits)
        a_i = 32'hFFFFFFFF; b_i = 32'hFFFFFFFF; mult_op_i = 4'd2;
        #1; 
        $display("\n[Time %0t] TEST MULHSU (op=2): a = %h, b = %h, op = %d", $time, a_i, b_i, mult_op_i);
        $display("  -> READ : result_o = %h", result_o);
        if (result_o === 32'hFFFFFFFF) 
            $display("  -> SUCCESS (Reason: -1 * 4294967295 = -4294967295 (0xFFFFFFFF_00000001). Upper 32 bits are FFFFFFFF)"); 
        else $display("  -> FAILED: Expected ffffffff");
        #9;

        // ---------------------------------------------------------
        // 7. Test MULHU (op = 3): Unsigned * Unsigned (Upper 32 bits)
        a_i = 32'hFFFFFFFF; b_i = 32'hFFFFFFFF; mult_op_i = 4'd3;
        #1; 
        $display("\n[Time %0t] TEST MULHU (op=3): a = %h, b = %h, op = %d", $time, a_i, b_i, mult_op_i);
        $display("  -> READ : result_o = %h", result_o);
        if (result_o === 32'hFFFFFFFE) 
            $display("  -> SUCCESS (Reason: 4294967295 * 4294967295 = 0xFFFFFFFE_00000001. Upper 32 bits are FFFFFFFE)"); 
        else $display("  -> FAILED: Expected fffffffe");

        // End simulation
        #20;
        $display("\n--- TEST RESULT: COMPLETE ---");
        $display("--- SIMULATION END ---");
        $finish;

end 



initial begin 

	$dumpfile("testbench.vcd");

	$dumpvars(0,testbench);

end 



endmodule 

