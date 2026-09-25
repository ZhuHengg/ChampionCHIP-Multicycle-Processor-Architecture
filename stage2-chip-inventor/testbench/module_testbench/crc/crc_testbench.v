module testbench(); 

reg [31:0] a_i = 0;
reg [31:0] b_i = 0;
reg [3:0] crc_op_i = 0;
wire [31:0] result_o;



 top ai45( .a_i(a_i), .b_i(b_i), .crc_op_i(crc_op_i), .result_o(result_o)); 


initial begin 
// --- Setup Default State ---
        a_i = 32'h0;
        b_i = 32'h0;
        crc_op_i = 4'hF; // Invalid opcode to start
        #10; 

        $display("========================================");
        $display("STARTING CRC SELF-CHECKING TESTS");
        $display("========================================");

        // ----------------------------------------------------
        // TEST 1: Byte CRC (CRC_CRCB = 4'h0)
        // ----------------------------------------------------
        $display("\n[TEST 1] Testing Byte CRC (CRCB)...");
        a_i = 32'h00000031;      // Data: arbitrary test byte
        b_i = 32'h0000FFFF;      // Seed
        crc_op_i = 4'h0;         // CRCB opcode
        #10;                     // Wait for combinational logic
        
        $display("   -> ACTION: Data = 0x%h, Seed = 0x%h, Op = 0x%h", a_i, b_i, crc_op_i);
        
        // EVIDENCE CHECK
        if (result_o === 32'h0000c782) begin
            $display("   -> [PASS] Expected 0x0000c782 and got 0x%h", result_o);
        end else begin
            $display("   -> [FAIL] Expected 0x0000c782, but got 0x%h", result_o);
        end

        // ----------------------------------------------------
        // TEST 2: Half-Word CRC (CRC_CRCH = 4'h1)
        // ----------------------------------------------------
        $display("\n[TEST 2] Testing Half-Word CRC (CRCH)...");
        a_i = 32'h00003132;      // Data: arbitrary test half-word
        b_i = 32'h0000FFFF;      // Seed
        crc_op_i = 4'h1;         // CRCH opcode
        #10;
        
        $display("   -> ACTION: Data = 0x%h, Seed = 0x%h, Op = 0x%h", a_i, b_i, crc_op_i);
        
        // EVIDENCE CHECK
        if (result_o === 32'h00003dba) begin
            $display("   -> [PASS] Expected 0x00003dba and got 0x%h", result_o);
        end else begin
            $display("   -> [FAIL] Expected 0x00003dba, but got 0x%h", result_o);
        end

        // ----------------------------------------------------
        // TEST 3: Word CRC (CRC_CRCW = 4'h2)
        // ----------------------------------------------------
        $display("\n[TEST 3] Testing Word CRC (CRCW)...");
        a_i = 32'h31323334;      // Data: arbitrary test word
        b_i = 32'h0000FFFF;      // Seed
        crc_op_i = 4'h2;         // CRCW opcode
        #10;
        
        $display("   -> ACTION: Data = 0x%h, Seed = 0x%h, Op = 0x%h", a_i, b_i, crc_op_i);
        
        // EVIDENCE CHECK
        if (result_o === 32'h00005349) begin
            $display("   -> [PASS] Expected 0x00005349 and got 0x%h", result_o);
        end else begin
            $display("   -> [FAIL] Expected 0x00005349, but got 0x%h", result_o);
        end

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

