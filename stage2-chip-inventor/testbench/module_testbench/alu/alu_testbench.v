module testbench(); 
  
  reg [31:0] a_i = 0; 
  reg [31:0] b_i = 0; 
  reg [3:0] alu_op_i = 0; 
  wire [31:0] result_o; 
  
  // Variable to store the expected result and operation name for logging
  reg [31:0] expected;
  reg [63:0] op_name; // 64 bits to hold up to an 8-character string
  integer i;
  
  // Instantiate the ALU module
 top ai45( .a_i(a_i), .b_i(b_i), .alu_op_i(alu_op_i), .result_o(result_o)); 
  
  // Stimulus and self-checking block
  initial begin 
    // Set the initial inputs
    a_i = 2;
    b_i = 1;
    
    $display("--- Starting ALU Verification ---");
    $display("Set a_i = 2; b_i = 1;");
    // Loop alu_op_i from 0 to 7
    for (i = 0; i <= 7; i = i + 1) begin
      alu_op_i = i;
      
      // Wait 10 time units for the ALU to process the result
      #10; 
      
      // Calculate the expected result and assign the string name based on the table
      case(i)
        4'h0: begin expected = b_i;             op_name = "PASS_B"; end
        4'h1: begin expected = a_i + b_i;       op_name = "ADD";    end
        4'h2: begin expected = a_i - b_i;       op_name = "SUB";    end
        4'h3: begin expected = a_i & b_i;       op_name = "AND";    end
        4'h4: begin expected = a_i | b_i;       op_name = "OR";     end
        4'h5: begin expected = a_i ^ b_i;       op_name = "XOR";    end
        4'h6: begin expected = a_i << b_i[4:0]; op_name = "SLL";    end
        4'h7: begin expected = a_i >> b_i[4:0]; op_name = "SRL";    end
        default: begin expected = 32'bx;        op_name = "UNKNOWN"; end
      endcase
      
      // Compare actual result_o with the expected value and log it with the operation name
      if (result_o === expected) begin
        $display("Time %0t: SUCCESS | ALU_OP = %0s (%0d) | a = %0d, b = %0d | result = %0d", $time, op_name, i, a_i, b_i, result_o);
      end else begin
        $display("Time %0t: FAILED  | ALU_OP = %0s (%0d) | a = %0d, b = %0d | expected = %0d, got = %0d", $time, op_name, i, a_i, b_i, expected, result_o);
      end
    end
    
    $display("--- Verification Complete ---");
    
    // Finish simulation shortly after the loop finishes
    #20 $finish; 
  end
  // VCD dump for waveform viewing
  initial begin 
    $dumpfile("testbench.vcd"); 
    $dumpvars(0, testbench); 
  end 
  
endmodule