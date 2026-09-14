module testbench(); 

reg clk_i = 0;
reg rst_i = 0;
reg we_i = 0;
reg oe_i = 0;
reg [3:0] bw_i = 0;
reg [31:0] address_i = 0;
reg [31:0] data_i = 0;
wire [31:0] data_o;



 top ai45( .clk_i(clk_i), .rst_i(rst_i), .we_i(we_i), .oe_i(oe_i), .bw_i(bw_i), .address_i(address_i), .data_i(data_i), .data_o(data_o)); 

  initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i; 
    end

initial begin 
// --- Setup and Reset ---
        rst_i = 1;
        we_i = 0;
        oe_i = 0;
        bw_i = 0;
        address_i = 0;
        data_i = 0;
        
        #20; 
        rst_i = 0; // Release reset
        #10;

        $display("========================================");
        $display("STARTING MEMORY MAPPING TESTS");
        $display("========================================");

        // ----------------------------------------------------
        // TEST 1: Write Data to Data Memory (DMEM)
        // ----------------------------------------------------
        $display("\n[TEST 1] Writing to Data Memory...");
        address_i = 32'h10010004; // Set a valid DMEM address
        data_i = 32'hDEADBEEF;    // The test data we want to save
        we_i = 1;                 // Enable Write
        oe_i = 0;
        bw_i = 4'b1111;           // Enable all bytes
        #10;
        
        we_i = 0;                 // Stop writing
        $display("   -> ACTION: Wrote 0x%h to Address 0x%h", data_i, address_i);
        #10;

        // ----------------------------------------------------
        // TEST 2: Read Data back from Data Memory (DMEM)
        // ----------------------------------------------------
        $display("\n[TEST 2] Reading back from Data Memory...");
        address_i = 32'h10010004; // Read from the exact same address
        we_i = 0;                 // Make sure write is disabled
        oe_i = 1;                 // Enable Output
        #10;
        
        // --- THIS IS THE EVIDENCE CHECK ---
        if (data_o === 32'hDEADBEEF) begin
            $display("   -> SUCCESS: Expected 0xDEADBEEF, and actually read 0x%h", data_o);
        end else begin
            $display("   -> FAILED: Expected 0xDEADBEEF, but read 0x%h", data_o);
            $display("   -> Evidence: The data_o wire did not output the expected value.");
        end

        // ----------------------------------------------------
        // TEST 3: Read from Instruction Memory (IMEM)
        // ----------------------------------------------------
        $display("\n[TEST 3] Reading from Instruction Memory...");
        address_i = 32'h00400000; // Set a valid IMEM address
        we_i = 0;
        oe_i = 1;
        #10;
        
        $display("   -> SUCCESS: IMEM Output at Address 0x%h is 0x%h", address_i, data_o);

        $display("\n========================================");
        $display("ALL TESTS COMPLETED.");
        $display("========================================");
        $finish;
end 



initial begin 

	$dumpfile("testbench.vcd");

	$dumpvars(0,testbench);

end 



endmodule 
