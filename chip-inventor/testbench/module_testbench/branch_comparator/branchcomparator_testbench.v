module testbench(); 

reg [31:0] rs1_i = 0;
reg [31:0] rs2_i = 0;
reg [2:0] funct3_i = 0;
wire branch_taken_o;



 top ai45( .rs1_i(rs1_i), .rs2_i(rs2_i), .funct3_i(funct3_i), .branch_taken_o(branch_taken_o)); 


initial begin 

	$display("--- SIMULATION START for branch_comparator ---");
        
        // 1. Initialize
        rs1_i = 32'h00000000;
        rs2_i = 32'h00000000;
        funct3_i = 3'b000;
        #20;
        
        // 2. Test BEQ (Branch Equal) - funct3 = 3'd0
        rs1_i = 32'd150; 
        rs2_i = 32'd150; 
        funct3_i = 3'd0;
        
        #1; 
        $display("[Time %0t] TEST BEQ: rs1 = %d, rs2 = %d, funct3 = %d", $time, rs1_i, rs2_i, funct3_i);
        $display("  -> READ : branch_taken_o = %b", branch_taken_o);
        if (branch_taken_o === 1'b1) $display("  -> SUCCESS");
        else $display("  -> FAILED: Expected 1");

        #9;
        
        // 3. Test BNE (Branch Not Equal) - funct3 = 3'd1
        rs1_i = 32'd150; 
        rs2_i = 32'd200; 
        funct3_i = 3'd1;
        
        #1; 
        $display("[Time %0t] TEST BNE: rs1 = %d, rs2 = %d, funct3 = %d", $time, rs1_i, rs2_i, funct3_i);
        $display("  -> READ : branch_taken_o = %b", branch_taken_o);
        if (branch_taken_o === 1'b1) $display("  -> SUCCESS");
        else $display("  -> FAILED: Expected 1");

        #9;

        // 4. Test BLT (Branch Less Than, Signed) - funct3 = 3'd4
        rs1_i = 32'hFFFFFFF6; // -10 in two's complement
        rs2_i = 32'd10; 
        funct3_i = 3'd4;
        
        #1; 
        $display("[Time %0t] TEST BLT: rs1 = %h, rs2 = %h, funct3 = %d", $time, rs1_i, rs2_i, funct3_i);
        $display("  -> READ : branch_taken_o = %b", branch_taken_o);
        if (branch_taken_o === 1'b1) $display("  -> SUCCESS");
        else $display("  -> FAILED: Expected 1");

        #9;

        // 5. Test BGE (Branch Greater/Equal, Signed) - funct3 = 3'd5
        rs1_i = 32'd10; 
        rs2_i = 32'hFFFFFFF6; // -10 in two's complement
        funct3_i = 3'd5;
        
        #1; 
        $display("[Time %0t] TEST BGE: rs1 = %h, rs2 = %h, funct3 = %d", $time, rs1_i, rs2_i, funct3_i);
        $display("  -> READ : branch_taken_o = %b", branch_taken_o);
        if (branch_taken_o === 1'b1) $display("  -> SUCCESS");
        else $display("  -> FAILED: Expected 1");

        #9;

        // 6. Test BLTU (Branch Less Than, Unsigned) - funct3 = 3'd6
        rs1_i = 32'd10; 
        rs2_i = 32'hFFFFFFF6; // Unsigned, this is a very large positive number
        funct3_i = 3'd6;
        
        #1; 
        $display("[Time %0t] TEST BLTU: rs1 = %h, rs2 = %h, funct3 = %d", $time, rs1_i, rs2_i, funct3_i);
        $display("  -> READ : branch_taken_o = %b", branch_taken_o);
        if (branch_taken_o === 1'b1) $display("  -> SUCCESS");
        else $display("  -> FAILED: Expected 1");

        #9;

        // 7. Test BGEU (Branch Greater/Equal, Unsigned) - funct3 = 3'd7
        rs1_i = 32'hFFFFFFF6; // Unsigned, this is a very large positive number
        rs2_i = 32'd10; 
        funct3_i = 3'd7;
        
        #1; 
        $display("[Time %0t] TEST BGEU: rs1 = %h, rs2 = %h, funct3 = %d", $time, rs1_i, rs2_i, funct3_i);
        $display("  -> READ : branch_taken_o = %b", branch_taken_o);
        if (branch_taken_o === 1'b1) $display("  -> SUCCESS");
        else $display("  -> FAILED: Expected 1");

        // End simulation
        #20;
        $display("--- TEST RESULT: COMPLETE ---");
        $display("--- SIMULATION END ---");
        $finish;

end 



initial begin 

	$dumpfile("testbench.vcd");

	$dumpvars(0,testbench);

end 



endmodule 

