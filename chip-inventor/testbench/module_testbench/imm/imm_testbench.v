module testbench(); 

reg [31:0] instr_i = 0;
reg [2:0] imm_sel_i = 0;
wire [31:0] imm_o;



 top ai45( .instr_i(instr_i), .imm_sel_i(imm_sel_i), .imm_o(imm_o)); 



initial begin
        $display("--- SIMULATION START for imm_extend ---");
        
        // 1. Initialize
        instr_i = 32'h00000000; 
        imm_sel_i = 3'b000;
        #20;
        
        // 2. Test I-Type Immediate
        instr_i = 32'h80000000; 
        imm_sel_i = 3'd0; // Assuming 0 is I-Type
        
        #1; 
        $display("[Time %0t] TEST I-Type: instr = %h, sel = %d", $time, instr_i, imm_sel_i);
        $display("  -> READ : imm_o = %h", imm_o);
        if (imm_o === 32'hFFFFF800) $display("  -> SUCCESS");
        else $display("  -> FAILED: Expected fffff800");

        #9;

        // 3. Test S-Type Immediate
        instr_i = 32'h7E000F80; 
        imm_sel_i = 3'd1; // Assuming 1 is S-Type
        
        #1;
        $display("[Time %0t] TEST S-Type: instr = %h, sel = %d", $time, instr_i, imm_sel_i);
        $display("  -> READ : imm_o = %h", imm_o);
        if (imm_o === 32'h000007FF) $display("  -> SUCCESS");
        else $display("  -> FAILED: Expected 000007ff");

        #9;
        
        // 3.5 Test B-Type Immediate
        instr_i = 32'h00000663; 
        imm_sel_i = 3'd2; // Assuming 2 is B-Type
        
        #1;
        $display("[Time %0t] TEST B-Type: instr = %h, sel = %d", $time, instr_i, imm_sel_i);
        $display("  -> READ : imm_o = %h", imm_o);
        if (imm_o === 32'h0000000C) $display("  -> SUCCESS");
        else $display("  -> FAILED: Expected 0000000c");

        #9; 

        // 4. Test U-Type Immediate
        instr_i = 32'h12345000; 
        imm_sel_i = 3'd3; // Assuming 3 is U-Type
        
        #1;
        $display("[Time %0t] TEST U-Type: instr = %h, sel = %d", $time, instr_i, imm_sel_i);
        $display("  -> READ : imm_o = %h", imm_o);
        if (imm_o === 32'h12345000) $display("  -> SUCCESS");
        else $display("  -> FAILED: Expected 12345000");

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