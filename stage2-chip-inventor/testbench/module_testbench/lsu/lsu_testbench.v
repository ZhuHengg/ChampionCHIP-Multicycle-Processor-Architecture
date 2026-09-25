module testbench(); 

reg [31:0] core_data_o = 0;
reg [31:0] core_address_o = 0;
reg [2:0] op_size_o = 0;
reg [31:0] mem_data_o = 0;
wire [31:0] core_data_i;
wire [31:0] mem_data_i;



 top ai45( .core_data_o(core_data_o), .core_address_o(core_address_o), .op_size_o(op_size_o), .mem_data_o(mem_data_o), .core_data_i(core_data_i), .mem_data_i(mem_data_i)); 


initial begin 
		// 1. Initialize
        core_data_o = 32'd0; 
        core_address_o = 32'd0; 
        op_size_o = 3'd0; 
        mem_data_o = 32'd0;
        #20;
        
        // ---------------------------------------------------------
        // 2. Test Store Word (SW)
        core_data_o = 32'h11223344;
        core_address_o = 32'h00000000;
        op_size_o = 3'd4; // CORRECTED: 4 = Word in your architecture
        #1; 
        $display("[Time %0t] TEST SW (Store Word): Addr = %h, Data = %h", $time, core_address_o, core_data_o);
        $display("  -> READ : mem_data_i = %h", mem_data_i);
        if (mem_data_i === 32'h11223344) $display("  -> SUCCESS"); 
        else $display("  -> FAILED: Expected 11223344");
        #9;

        // ---------------------------------------------------------
        // 3. Test Store Byte (SB) with offset
        core_data_o = 32'h000000AA;
        core_address_o = 32'h00000001;
        op_size_o = 3'd0; // 0 = Byte Signed
        #1; 
        $display("[Time %0t] TEST SB (Store Byte Offset 1): Addr = %h, Data = %h", $time, core_address_o, core_data_o);
        $display("  -> READ : mem_data_i = %h", mem_data_i);
        if (mem_data_i === 32'h0000AA00) $display("  -> SUCCESS"); 
        else $display("  -> FAILED: Expected 0000aa00");
        #9;

        // ---------------------------------------------------------
        // 4. Test Load Word (LW)
        mem_data_o = 32'hDEADBEEF;
        core_address_o = 32'h00000000;
        op_size_o = 3'd4; // CORRECTED: 4 = Word
        #1; 
        $display("[Time %0t] TEST LW (Load Word): Addr = %h, Mem = %h", $time, core_address_o, mem_data_o);
        $display("  -> READ : core_data_i = %h", core_data_i);
        if (core_data_i === 32'hDEADBEEF) $display("  -> SUCCESS"); 
        else $display("  -> FAILED: Expected deadbeef");
        #9;

        // ---------------------------------------------------------
        // 5. Test Load Byte Signed (LB)
        mem_data_o = 32'h0000FA00;
        core_address_o = 32'h00000001;
        op_size_o = 3'd0; // 0 = Byte Signed
        #1; 
        $display("[Time %0t] TEST LB (Load Byte Signed): Addr = %h, Mem = %h", $time, core_address_o, mem_data_o);
        $display("  -> READ : core_data_i = %h", core_data_i);
        if (core_data_i === 32'hFFFFFFFA) $display("  -> SUCCESS"); 
        else $display("  -> FAILED: Expected fffffffa");
        #9;

        // ---------------------------------------------------------
        // 6. Test Load Byte Unsigned (LBU)
        mem_data_o = 32'h0000FA00;
        core_address_o = 32'h00000001;
        op_size_o = 3'd1; // CORRECTED: 1 = Byte Unsigned
        #1; 
        $display("[Time %0t] TEST LBU (Load Byte Unsigned): Addr = %h, Mem = %h", $time, core_address_o, mem_data_o);
        $display("  -> READ : core_data_i = %h", core_data_i);
        if (core_data_i === 32'h000000FA) $display("  -> SUCCESS"); 
        else $display("  -> FAILED: Expected 000000fa");

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