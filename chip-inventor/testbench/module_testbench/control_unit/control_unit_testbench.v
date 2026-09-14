module testbench(); 

reg clk_i = 0;
reg rst_i = 0;
reg [6:0] opcode_i = 0;
reg [2:0] funct3_i = 0;
reg [6:0] funct7_i = 0;
reg [11:0] funct12_i = 0;
reg [1:0] addr_lsb_i = 0;
reg branch_taken_i = 0;
wire pc_write_o;
wire [1:0] pc_src_o;
wire ir_write_o;
wire reg_write_o;
wire [2:0] result_src_o;
wire alu_src_a_o;
wire [1:0] alu_src_b_o;
wire [3:0] alu_op_o;
wire [2:0] imm_sel_o;
wire [3:0] mult_op_o;
wire [3:0] crc_op_o;
wire mult_en_o;
wire crc_en_o;
wire we_o;
wire oe_o;
wire [3:0] bw_o;
wire [2:0] op_size_o;
wire adr_src_o;
wire halt_o;



 control_unit_eq26 ai45( .clk_i(clk_i), .rst_i(rst_i), .opcode_i(opcode_i), .funct3_i(funct3_i), .funct7_i(funct7_i), .funct12_i(funct12_i), .addr_lsb_i(addr_lsb_i), .branch_taken_i(branch_taken_i), .pc_write_o(pc_write_o), .pc_src_o(pc_src_o), .ir_write_o(ir_write_o), .reg_write_o(reg_write_o), .result_src_o(result_src_o), .alu_src_a_o(alu_src_a_o), .alu_src_b_o(alu_src_b_o), .alu_op_o(alu_op_o), .imm_sel_o(imm_sel_o), .mult_op_o(mult_op_o), .crc_op_o(crc_op_o), .mult_en_o(mult_en_o), .crc_en_o(crc_en_o), .we_o(we_o), .oe_o(oe_o), .bw_o(bw_o), .op_size_o(op_size_o), .adr_src_o(adr_src_o), .halt_o(halt_o));


initial begin
        clk_i = 0;
        forever #5 clk_i = ~clk_i; // 10ns period
    end

    // Monitor to show FSM state transitions in the log (Peek inside uut.state)
    initial begin
       $monitor("Time=%0t | Opcode=%b | RegWe=%b | MemWe=%b", $time, opcode_i, reg_write_o, we_o);
    end

    // 4. Stimulus Process for Multi-Cycle FSM
    initial begin
        // Initialize Inputs
        rst_i = 1;
        opcode_i = 7'b0;
        funct3_i = 3'b0;
        funct7_i = 7'b0;
        funct12_i = 12'b0;
        addr_lsb_i = 2'b0;
        branch_taken_i = 0;

        // Wait for reset to finish
        #20;
        rst_i = 0;
        
        // Wait for the first posedge after reset drops.
        // FSM moves from RESET (0) to FETCH (1)
        @(posedge clk_i); 

        // ---------------------------------------------------------
        // TEST CASE 1: R-Type ALU (e.g., ADD)
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> WRITE_BACK -> FETCH
        // ---------------------------------------------------------
        opcode_i = 7'b0110011; funct3_i = 3'b000; funct7_i = 7'b0000000; 
        
        @(posedge clk_i); // Transition to DECODE
        @(posedge clk_i); // Transition to EXECUTE_ALU
        @(posedge clk_i); // Transition to WRITE_BACK
        #1; // Tiny delay to let combinational output logic settle
        
        if (reg_write_o !== 1'b1 || we_o !== 1'b0) $display("FAIL: R-Type ADD");
        else $display("SUCCESS: R-Type ADD");

        @(posedge clk_i); // Transition back to FETCH for next instruction

        // ---------------------------------------------------------
        // TEST CASE 2: I-Type ALU (e.g., ADDI)
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> WRITE_BACK -> FETCH
        // ---------------------------------------------------------
        opcode_i = 7'b0010011; funct3_i = 3'b000;
        
        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1;
        // The ALU needs the immediate source during the EXECUTE state
        if (alu_src_b_o !== 2'b01) $display("FAIL: I-Type ADDI (ALU Src)");
        
        @(posedge clk_i); // WRITE_BACK
        #1;
        // The register is written during the WRITE_BACK state
        if (reg_write_o !== 1'b1) $display("FAIL: I-Type ADDI (Reg Write)");
        else $display("SUCCESS: I-Type ADDI");

        @(posedge clk_i); // FETCH

        // ---------------------------------------------------------
        // TEST CASE 3: Store Instruction (e.g., SW)
        // Path: FETCH -> DECODE -> MEM_ADDR -> MEM_ACCESS_STORE -> FETCH
        // ---------------------------------------------------------
        opcode_i = 7'b0100011; funct3_i = 3'b010;
        
        @(posedge clk_i); // DECODE
        @(posedge clk_i); // MEM_ADDR
        @(posedge clk_i); // MEM_ACCESS_STORE
        #1;
        
        if (we_o !== 1'b1) $display("FAIL: Store SW");
        else $display("SUCCESS: Store SW");

        @(posedge clk_i); // FETCH

        // ---------------------------------------------------------
        // TEST CASE 4: Load Instruction (e.g., LW)
        // Path: FETCH -> DECODE -> MEM_ADDR -> MEM_ACCESS_ADDR -> MEM_ACCESS_DATA -> WRITE_BACK -> FETCH
        // ---------------------------------------------------------
        opcode_i = 7'b0000011; funct3_i = 3'b010;
        
        @(posedge clk_i); // DECODE
        @(posedge clk_i); // MEM_ADDR
        @(posedge clk_i); // MEM_ACCESS_ADDR
        @(posedge clk_i); // MEM_ACCESS_DATA
        @(posedge clk_i); // WRITE_BACK
        #1;
        
        if (reg_write_o !== 1'b1 || result_src_o !== 3'b011) $display("FAIL: Load LW");
        else $display("SUCCESS: Load LW");

        @(posedge clk_i); // FETCH

        // ---------------------------------------------------------
        // TEST CASE 5: Branch Taken (e.g., BEQ)
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> FETCH
        // ---------------------------------------------------------
        opcode_i = 7'b1100011; funct3_i = 3'b000; branch_taken_i = 1'b1;
        
        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1; 
        
        if (pc_write_o !== 1'b1 || pc_src_o !== 2'b01) $display("FAIL: Branch Taken");
        else $display("SUCCESS: Branch Taken");

        @(posedge clk_i); // FETCH

        // ---------------------------------------------------------
        // TEST CASE 6: Custom Multiplier Extension
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> WRITE_BACK -> FETCH
        // ---------------------------------------------------------
        opcode_i = 7'b0110011; funct7_i = 7'b0000001; branch_taken_i = 1'b0; // Reset branch
        
        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1; 
        if (mult_en_o !== 1'b1) $display("FAIL: Multiplier Op (Enable)"); // Check enable in EXECUTE
        
        @(posedge clk_i); // WRITE_BACK
        #1;
        if (reg_write_o !== 1'b1 || result_src_o !== 3'b001) $display("FAIL: Multiplier Op (Write)");
        else $display("SUCCESS: Multiplier Op");
        
        @(posedge clk_i); // FETCH

        // ---------------------------------------------------------
        // TEST CASE 7: JAL
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> WRITE_BACK -> FETCH
        // Per HANDOFF_control_unit.md §4: pc_write_o=1, pc_src_o=01,
        // alu_src_a_o=1(PC), alu_src_b_o=01(IMM), alu_op_o=ADD,
        // imm_sel_o=100(J), result_src_o=100(PC+4), reg_write_o=1 @ WB
        // ---------------------------------------------------------
        opcode_i = 7'b1101111; funct3_i = 3'b000; funct7_i = 7'b0;

        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1;
        if (pc_write_o !== 1'b1 || pc_src_o !== 2'b01 ||
            alu_src_a_o !== 1'b1 || alu_src_b_o !== 2'b01 ||
            alu_op_o !== 4'h1 || imm_sel_o !== 3'b100)
            $display("FAIL: JAL (EXECUTE)");

        @(posedge clk_i); // WRITE_BACK
        #1;
        if (reg_write_o !== 1'b1 || result_src_o !== 3'b100) $display("FAIL: JAL (Write)");
        else $display("SUCCESS: JAL");

        @(posedge clk_i); // FETCH

        // ---------------------------------------------------------
        // TEST CASE 8: JALR
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> WRITE_BACK -> FETCH
        // Per §4: pc_write_o=1, pc_src_o=10, alu_src_a_o=0(RS1),
        // alu_src_b_o=01(IMM), alu_op_o=ADD, imm_sel_o=000(I),
        // result_src_o=100(PC+4)
        // ---------------------------------------------------------
        opcode_i = 7'b1100111; funct3_i = 3'b000; funct7_i = 7'b0;

        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1;
        if (pc_write_o !== 1'b1 || pc_src_o !== 2'b10 ||
            alu_src_a_o !== 1'b0 || alu_src_b_o !== 2'b01 ||
            alu_op_o !== 4'h1 || imm_sel_o !== 3'b000)
            $display("FAIL: JALR (EXECUTE)");

        @(posedge clk_i); // WRITE_BACK
        #1;
        if (reg_write_o !== 1'b1 || result_src_o !== 3'b100) $display("FAIL: JALR (Write)");
        else $display("SUCCESS: JALR");

        @(posedge clk_i); // FETCH

        // ---------------------------------------------------------
        // TEST CASE 9: LUI
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> WRITE_BACK -> FETCH
        // Per §4: alu_src_b_o=01(IMM), alu_op_o=PASS_B(0), imm_sel_o=011(U),
        // result_src_o=000(ALU)
        // ---------------------------------------------------------
        opcode_i = 7'b0110111; funct3_i = 3'b000; funct7_i = 7'b0;

        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1;
        if (alu_src_b_o !== 2'b01 || alu_op_o !== 4'h0 || imm_sel_o !== 3'b011)
            $display("FAIL: LUI (EXECUTE)");

        @(posedge clk_i); // WRITE_BACK
        #1;
        if (reg_write_o !== 1'b1 || result_src_o !== 3'b000) $display("FAIL: LUI (Write)");
        else $display("SUCCESS: LUI");

        @(posedge clk_i); // FETCH

        // ---------------------------------------------------------
        // TEST CASE 10: AUIPC
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> WRITE_BACK -> FETCH
        // Per §4: alu_src_a_o=1(PC), alu_src_b_o=01(IMM), alu_op_o=ADD,
        // imm_sel_o=011(U), result_src_o=000(ALU)
        // ---------------------------------------------------------
        opcode_i = 7'b0010111; funct3_i = 3'b000; funct7_i = 7'b0;

        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1;
        if (alu_src_a_o !== 1'b1 || alu_src_b_o !== 2'b01 ||
            alu_op_o !== 4'h1 || imm_sel_o !== 3'b011)
            $display("FAIL: AUIPC (EXECUTE)");

        @(posedge clk_i); // WRITE_BACK
        #1;
        if (reg_write_o !== 1'b1 || result_src_o !== 3'b000) $display("FAIL: AUIPC (Write)");
        else $display("SUCCESS: AUIPC");

        @(posedge clk_i); // FETCH

        // ---------------------------------------------------------
        // TEST CASE 11: Xicrc (CRC)
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> WRITE_BACK -> FETCH
        // opcode 0110011, funct7 1000000 selects Xicrc per §5.
        // funct3=001 (CRCH) -> crc_op_o = {1'b0,funct3} = 4'h1
        // Per §4: crc_en_o=1, result_src_o=010
        // ---------------------------------------------------------
        opcode_i = 7'b0110011; funct3_i = 3'b001; funct7_i = 7'b1000000;

        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1;
        if (crc_en_o !== 1'b1 || crc_op_o !== 4'h1) $display("FAIL: CRC Op (Enable)");

        @(posedge clk_i); // WRITE_BACK
        #1;
        if (reg_write_o !== 1'b1 || result_src_o !== 3'b010) $display("FAIL: CRC Op (Write)");
        else $display("SUCCESS: CRC Op");

        @(posedge clk_i); // FETCH

        // ---------------------------------------------------------
        // TEST CASE 12: Illegal opcode (custom-0, 0001011)
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> FETCH (skips WRITE_BACK)
        // Per §8 "Resolved since this list was written": unknown opcode
        // takes the same skip-WRITE_BACK path as BRANCH/SYSTEM/FENCE —
        // 3 cycles, no reg_write_o, no we_o.
        // ---------------------------------------------------------
        opcode_i = 7'b0001011; funct3_i = 3'b000; funct7_i = 7'b0;

        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1;
        if (reg_write_o !== 1'b0 || we_o !== 1'b0) $display("FAIL: Illegal Opcode (no side effects)");
        else $display("SUCCESS: Illegal Opcode");

        @(posedge clk_i); // back to FETCH, not WRITE_BACK
        #1;
        if (ir_write_o !== 1'b1) $display("FAIL: Illegal Opcode (returned to FETCH, not WRITE_BACK)");

        // ---------------------------------------------------------
        // TEST CASE 13: EBREAK
        // opcode SYSTEM (1110011), funct3=000, funct12=001 (FUNCT12_EBREAK).
        // Per RTL is_ecall check (funct12_i == FUNCT12_ECALL == 12'h000 only),
        // EBREAK does NOT set halt_o -- it falls through the same SYSTEM
        // no-op path as ECALL's EXECUTE_ALU case, skipping WRITE_BACK.
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> FETCH, no side effects.
        // ---------------------------------------------------------
        opcode_i = 7'b1110011; funct3_i = 3'b000; funct7_i = 7'b0; funct12_i = 12'h001;

        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1;
        if (reg_write_o !== 1'b0 || we_o !== 1'b0 || halt_o !== 1'b0)
            $display("FAIL: EBREAK (no side effects, no halt)");
        else
            $display("SUCCESS: EBREAK");

        @(posedge clk_i); // back to FETCH, not WRITE_BACK
        #1;
        if (ir_write_o !== 1'b1) $display("FAIL: EBREAK (returned to FETCH, not WRITE_BACK)");

        // ---------------------------------------------------------
        // TEST CASE 14: FENCE
        // opcode 0001111 (OPCODE_FENCE). No-op, same skip-WRITE_BACK path
        // as SYSTEM/BRANCH/illegal opcode: 3 cycles, no reg_write_o,
        // no we_o.
        // Path: FETCH -> DECODE -> EXECUTE_ALU -> FETCH
        // ---------------------------------------------------------
        opcode_i = 7'b0001111; funct3_i = 3'b000; funct7_i = 7'b0; funct12_i = 12'h000;

        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU
        #1;
        if (reg_write_o !== 1'b0 || we_o !== 1'b0) $display("FAIL: FENCE (no side effects)");
        else $display("SUCCESS: FENCE");

        @(posedge clk_i); // back to FETCH, not WRITE_BACK
        #1;
        if (ir_write_o !== 1'b1) $display("FAIL: FENCE (returned to FETCH, not WRITE_BACK)");

        // ---------------------------------------------------------
        // TEST CASE 15: ECALL / halt
        // opcode SYSTEM (1110011), funct3=000, funct12=000 (FUNCT12_ECALL).
        // Per §8: halt_o becomes sticky 1 the cycle after EXECUTE_ALU sees
        // is_ecall, and both pc_write_o and ir_write_o are gated to 0
        // from then on, even through FETCH.
        // ---------------------------------------------------------
        opcode_i = 7'b1110011; funct3_i = 3'b000; funct7_i = 7'b0; funct12_i = 12'h000;

        @(posedge clk_i); // DECODE
        @(posedge clk_i); // EXECUTE_ALU (is_ecall recognized this state)
        #1;
        if (halt_o !== 1'b0) $display("FAIL: ECALL (halt_o asserted too early)");

        @(posedge clk_i); // halt_o latches to 1 on this edge
        #1;
        if (halt_o !== 1'b1) $display("FAIL: ECALL (halt_o not set)");

        @(posedge clk_i); // would-be next FETCH
        #1;
        if (pc_write_o !== 1'b0 || ir_write_o !== 1'b0)
            $display("FAIL: ECALL (pc_write_o/ir_write_o not gated after halt)");
        else
            $display("SUCCESS: ECALL / halt");

        // End simulation
        #50;
        $display("All multi-cycle test cases completed.");
        $finish;
    end



endmodule 

