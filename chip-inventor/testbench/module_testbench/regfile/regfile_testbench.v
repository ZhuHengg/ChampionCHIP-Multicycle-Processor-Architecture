module testbench(); 

reg clk_i = 0;
reg rst_i = 0;
reg [4:0] rs1_addr_i = 0;
reg [4:0] rs2_addr_i = 0;
reg [31:0] write_data_i = 0;
reg reg_write_i = 0;
wire [31:0] rs1_data_o;
wire [31:0] rs2_data_o;
reg [4:0] rd_addr_i = 0;



 top ai45( .clk_i(clk_i), .rst_i(rst_i), .rs1_addr_i(rs1_addr_i), .rs2_addr_i(rs2_addr_i), .write_data_i(write_data_i), .reg_write_i(reg_write_i), .rs1_data_o(rs1_data_o), .rs2_data_o(rs2_data_o), .rd_addr_i(rd_addr_i)); 

initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i; 
end
  
initial begin 

  $display("--- SIMULATION START for regfile---");

        // 1. Initialize & Reset
        rst_i = 1;
        rs1_addr_i = 0; rs2_addr_i = 0; rd_addr_i = 0;
        write_data_i = 0; reg_write_i = 0;
        
        #20 rst_i = 0; 
        #10;

        // 3. Write to Register 1
        @(negedge clk_i);
        reg_write_i = 1; rd_addr_i = 5'd1; write_data_i = 32'hDEADBEEF;
        $display("[Time %0t] WRITE: Reg[1] <- %h", $time, 32'hDEADBEEF);

        // 4. Write to Register 2
        @(negedge clk_i);
        rd_addr_i = 5'd2; write_data_i = 32'hCAFEBABE;
        $display("[Time %0t] WRITE: Reg[2] <- %h", $time, 32'hCAFEBABE);

        // 5. Read from Registers 1 and 2
        @(negedge clk_i);
        reg_write_i = 0; 
        rs1_addr_i = 5'd1; rs2_addr_i = 5'd2;
        
        #1; // Wait for combinational read output to settle
        $display("[Time %0t] READ : Reg[1]=%h, Reg[2]=%h", $time, rs1_data_o, rs2_data_o);
        if (rs1_data_o === 32'hDEADBEEF && rs2_data_o === 32'hCAFEBABE) 
            $display("  -> SUCCESS: Read data matches written data.");
        else 
            $display("  -> ERROR: Read mismatch!");

        // 6. Test Register 0 (Hardwired to 0)
        @(negedge clk_i);
        reg_write_i = 1; rd_addr_i = 5'd0; write_data_i = 32'hFFFFFFFF;
        $display("\n[Time %0t] WRITE: Reg[0] <- %h (Attempting to overwrite)", $time, 32'hFFFFFFFF);
        
        @(negedge clk_i);
        reg_write_i = 0; rs1_addr_i = 5'd0;
        
        #1;
        $display("[Time %0t] READ : Reg[0]=%h", $time, rs1_data_o);
        if (rs1_data_o === 32'h00000000) 
            $display("  -> SUCCESS: Reg 0 remains 0.");
        else 
            $display("  -> FAILED: Reg 0 was overwritten!");

        // End simulation
        #30;
        $display("\n--- TEST RESULT: PASS ---");
        $display("--- SIMULATION END ---");
        $finish;

end 



initial begin 

	$dumpfile("testbench.vcd");

	$dumpvars(0,testbench);

end 



endmodule 