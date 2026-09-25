

//  ---------- INLCUDED BLOCK: alu_eq26  ---------- 
module alu_eq26 (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  alu_op_i,
    output reg  [31:0] result_o
);
    // ALU op codes
    localparam [3:0] ALU_PASS_B = 4'h0;
    localparam [3:0] ALU_ADD    = 4'h1;
    localparam [3:0] ALU_SUB    = 4'h2;
    localparam [3:0] ALU_AND    = 4'h3;
    localparam [3:0] ALU_OR     = 4'h4;
    localparam [3:0] ALU_XOR    = 4'h5;
    localparam [3:0] ALU_SLL    = 4'h6;
    localparam [3:0] ALU_SRL    = 4'h7;
    localparam [3:0] ALU_MRS    = 4'h8; // SRA
    localparam [3:0] ALU_SLT    = 4'h9;
    localparam [3:0] ALU_SLTU   = 4'hA;
    always @(*) begin
        result_o = 32'b0; // default value
        case (alu_op_i)
            ALU_PASS_B: result_o = b_i;
            ALU_ADD:    result_o = a_i + b_i;
            ALU_SUB:    result_o = a_i - b_i;
            ALU_AND:    result_o = a_i & b_i;
            ALU_OR:     result_o = a_i | b_i;
            ALU_XOR:    result_o = a_i ^ b_i;
            ALU_SLL:    result_o = a_i << b_i[4:0];
            ALU_SRL:    result_o = a_i >> b_i[4:0];
            ALU_MRS:    result_o = $signed(a_i) >>> b_i[4:0];
            ALU_SLT:    result_o = ($signed(a_i) < $signed(b_i)) ? 32'd1 : 32'd0;
            ALU_SLTU:   result_o = (a_i < b_i) ? 32'd1 : 32'd0;
            default:    result_o = 32'b0;
        endcase
    end
endmodule



//  ---------- INLCUDED BLOCK: branch_comparator_eq26  ----------
// Branch condition comparator.
module branch_comparator_eq26(
    input  wire [31:0] rs1_i,
    input  wire [31:0] rs2_i,
    input  wire [2:0]  funct3_i,
    output reg  branch_taken_o
);

    // RV32I branch funct3 codes.
    localparam FUNCT3_BEQ  = 3'b000;
    localparam FUNCT3_BNE  = 3'b001;
    localparam FUNCT3_BLT  = 3'b100;
    localparam FUNCT3_BGE  = 3'b101;
    localparam FUNCT3_BLTU = 3'b110;
    localparam FUNCT3_BGEU = 3'b111;

    always @(*) begin
        branch_taken_o = 1'b0; // default: not taken (covers 010/011 unused)
        case (funct3_i)
            FUNCT3_BEQ:  branch_taken_o = (rs1_i == rs2_i);
            FUNCT3_BNE:  branch_taken_o = (rs1_i != rs2_i);
            FUNCT3_BLT:  branch_taken_o = ($signed(rs1_i) <  $signed(rs2_i));
            FUNCT3_BGE:  branch_taken_o = ($signed(rs1_i) >= $signed(rs2_i));
            FUNCT3_BLTU: branch_taken_o = (rs1_i <  rs2_i);
            FUNCT3_BGEU: branch_taken_o = (rs1_i >= rs2_i);
            default:     branch_taken_o = 1'b0;
        endcase
    end

endmodule



//  ---------- INLCUDED BLOCK: crc_eq26  ----------
// CRC-16 compute unit.
module crc_eq26(
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  crc_op_i,
    output reg  [31:0] result_o
);

    // CRC Operation Codes (Table 11 - Xicrc)
    localparam [3:0] CRC_CRCB = 4'h0;
    localparam [3:0] CRC_CRCH = 4'h1;
    localparam [3:0] CRC_CRCW = 4'h2;

    parameter POLY    = 16'h1021;
    parameter INIT    = 16'hFFFF; // unused directly — seed comes in via b_i, kept for spec visibility
    parameter XOR_OUT = 16'h0000;

    integer i;
    reg [15:0] crc;
    reg        bit_in, msb;

    always @(*) begin
        result_o = 32'b0; // default, also covers illegal crc_op
        case (crc_op_i)
            CRC_CRCB, CRC_CRCH, CRC_CRCW: begin
                crc = b_i[15:0]; // seed threads through rs2
                case (crc_op_i)
                    CRC_CRCB: begin
                        for (i = 7; i >= 0; i = i - 1) begin
                            bit_in = a_i[i];
                            msb    = crc[15];
                            crc    = (crc << 1) & 16'hFFFF;
                            if (msb ^ bit_in) crc = crc ^ POLY;
                        end
                    end
                    CRC_CRCH: begin
                        for (i = 15; i >= 0; i = i - 1) begin
                            bit_in = a_i[i];
                            msb    = crc[15];
                            crc    = (crc << 1) & 16'hFFFF;
                            if (msb ^ bit_in) crc = crc ^ POLY;
                        end
                    end
                    default: begin // CRC_CRCW
                        for (i = 31; i >= 0; i = i - 1) begin
                            bit_in = a_i[i];
                            msb    = crc[15];
                            crc    = (crc << 1) & 16'hFFFF;
                            if (msb ^ bit_in) crc = crc ^ POLY;
                        end
                    end
                endcase
                result_o = {16'b0, crc ^ XOR_OUT};
            end
            default: result_o = 32'b0;
        endcase
    end

endmodule



//  ---------- INLCUDED BLOCK: imm_extend_eq26  ----------
// Immediate extender.
module imm_extend_eq26(
    input  wire [31:0] instr_i,
    input  wire [2:0]  imm_sel_i,
    output reg  [31:0] imm_o
);
    // Immediate format selectors
    localparam [2:0] IMM_SEL_I = 3'b000;
    localparam [2:0] IMM_SEL_S = 3'b001;
    localparam [2:0] IMM_SEL_B = 3'b010;
    localparam [2:0] IMM_SEL_U = 3'b011;
    localparam [2:0] IMM_SEL_J = 3'b100;
    always @(*) begin
        imm_o = 32'b0; // default
        case (imm_sel_i)
            // I-type
            IMM_SEL_I: imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
            // S-type
            IMM_SEL_S: imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
            // B-type
            IMM_SEL_B: imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                                  instr_i[30:25], instr_i[11:8], 1'b0};
            // U-type
            IMM_SEL_U: imm_o = {instr_i[31:12], 12'b0};
            // J-type
            IMM_SEL_J: imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                                  instr_i[20], instr_i[30:21], 1'b0};
            default: imm_o = 32'b0;
        endcase
    end
endmodule



//  ---------- INLCUDED BLOCK: mult_eq26  ----------
// 32x32 combinational multiplier.
module mult_eq26(
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  mult_op_i,
    output reg  [31:0] result_o
);

    // Multiplier op codes
    localparam [3:0] MULT_MUL    = 4'h0;
    localparam [3:0] MULT_MULH   = 4'h1;
    localparam [3:0] MULT_MULHSU = 4'h2;
    localparam [3:0] MULT_MULHU  = 4'h3;

    wire signed [63:0] p_ss = $signed(a_i) * $signed(b_i);                       // signed x signed
    wire signed [63:0] p_su = $signed({{32{a_i[31]}}, a_i}) * $signed({32'b0, b_i}); // signed x unsigned
    wire        [63:0] p_uu = a_i * b_i;                                         // unsigned x unsigned

    always @(*) begin
        result_o = 32'b0; // default
        case (mult_op_i)
            MULT_MUL:    result_o = p_ss[31:0];  // low half identical regardless of signedness
            MULT_MULH:   result_o = p_ss[63:32];
            MULT_MULHSU: result_o = p_su[63:32];
            MULT_MULHU:  result_o = p_uu[63:32];
            default:      result_o = 32'b0;
        endcase
    end

endmodule



//  ---------- INLCUDED BLOCK: regfile_eq  ---------- 
module regfile_eq(
    input  wire        clk_i,
    input  wire        rst_i,

    input  wire [4:0]  rs1_addr_i,
    input  wire [4:0]  rs2_addr_i,
    input  wire [4:0]  rd_addr_i,
    input  wire [31:0] write_data_i,
    input  wire        reg_write_i,

    output wire [31:0] rs1_data_o,
    output wire [31:0] rs2_data_o,
    // Debug tap for testbench.
    output wire [31:0] x4_dbg_o
);

    reg [31:0] regs [0:31];

    integer i;

    // Async read, x0 hardwired zero.
    assign rs1_data_o = (rs1_addr_i == 5'd0) ? 32'b0 : regs[rs1_addr_i];
    assign rs2_data_o = (rs2_addr_i == 5'd0) ? 32'b0 : regs[rs2_addr_i];
    assign x4_dbg_o   = regs[4];

    // Sync write, x0 write-protected.
    always @(posedge clk_i) begin
        if (rst_i) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (reg_write_i && rd_addr_i != 5'd0) begin
            regs[rd_addr_i] <= write_data_i;
        end
    end

endmodule



//  ---------- INLCUDED BLOCK: lsu_eq26  ----------
// Load/store alignment unit.
module lsu_eq26(
    input  wire [31:0] core_data_o,     // INPUT: store data from core (rs2)
    input  wire [31:0] core_address_o,  // INPUT: effective address from core (uses [1:0])
    input  wire [2:0]  op_size_o,       // INPUT: from control unit
    input  wire [31:0] mem_data_o,      // INPUT: word read back from memory

    output reg  [31:0] core_data_i,     // OUTPUT: load result, extended, back to core
    output reg  [31:0] mem_data_i       // OUTPUT: store data, positioned, out to memory
);

    localparam [2:0] OP_SIZE_BYTE_S = 3'b000; // lb / sb
    localparam [2:0] OP_SIZE_BYTE_U = 3'b001; // lbu
    localparam [2:0] OP_SIZE_HALF_S = 3'b010; // lh / sh
    localparam [2:0] OP_SIZE_HALF_U = 3'b011; // lhu
    localparam [2:0] OP_SIZE_WORD   = 3'b100; // lw / sw

    wire [1:0] byte_sel = core_address_o[1:0];

    // Load path.
    reg [7:0]  load_byte;
    reg [15:0] load_half;

    always @(*) begin
        load_byte = 8'b0;
        case (byte_sel)
            2'b00:   load_byte = mem_data_o[ 7: 0];
            2'b01:   load_byte = mem_data_o[15: 8];
            2'b10:   load_byte = mem_data_o[23:16];
            2'b11:   load_byte = mem_data_o[31:24];
            default: load_byte = mem_data_o[7:0];
        endcase
    end

    always @(*) begin
        load_half = 16'b0;
        case (byte_sel[1])
            1'b0:    load_half = mem_data_o[15: 0];
            1'b1:    load_half = mem_data_o[31:16];
            default: load_half = mem_data_o[15:0];
        endcase
    end

    always @(*) begin
        core_data_i = 32'b0; // default
        case (op_size_o)
            OP_SIZE_BYTE_S: core_data_i = {{24{load_byte[7]}}, load_byte};
            OP_SIZE_BYTE_U: core_data_i = {24'b0, load_byte};
            OP_SIZE_HALF_S: core_data_i = {{16{load_half[15]}}, load_half};
            OP_SIZE_HALF_U: core_data_i = {16'b0, load_half};
            OP_SIZE_WORD:   core_data_i = mem_data_o;
            default:         core_data_i = mem_data_o;
        endcase
    end

    // Store path.
    always @(*) begin
        mem_data_i = 32'b0; // default
        case (op_size_o[2:1]) // size bits only; sign bit don't-care for stores
            2'b00: begin // byte
                case (byte_sel)
                    2'b00:   mem_data_i = {24'b0, core_data_o[7:0]};
                    2'b01:   mem_data_i = {16'b0, core_data_o[7:0], 8'b0};
                    2'b10:   mem_data_i = {8'b0, core_data_o[7:0], 16'b0};
                    2'b11:   mem_data_i = {core_data_o[7:0], 24'b0};
                    default: mem_data_i = {24'b0, core_data_o[7:0]};
                endcase
            end
            2'b01: begin // half
                mem_data_i = byte_sel[1] ? {core_data_o[15:0], 16'b0}
                                          : {16'b0, core_data_o[15:0]};
            end
            2'b10: mem_data_i = core_data_o; // word
            default: mem_data_i = core_data_o;
        endcase
    end

endmodule



//  ---------- INLCUDED BLOCK: imem  ---------- 
module imem (
    input  wire        clk_i,
    input  wire [31:0] addr_i,
    input  wire        oe_i,
    output reg  [31:0] data_o
);
    always @(*) begin
        if (!oe_i) begin
            data_o = 32'h00000000;
        end else begin
            case (addr_i[9:0])
                10'd0: data_o = 32'h123452B7;
                10'd1: data_o = 32'h12345337;
                10'd2: data_o = 32'h3E629463;
                10'd3: data_o = 32'h00001297;
                10'd4: data_o = 32'h3E028063;
                10'd5: data_o = 32'h00A00293;
                10'd6: data_o = 32'hFFD28313;
                10'd7: data_o = 32'h00700393;
                10'd8: data_o = 32'h3C731863;
                10'd9: data_o = 32'h006283B3;
                10'd10: data_o = 32'h01100E13;
                10'd11: data_o = 32'h3DC39263;
                10'd12: data_o = 32'h405E03B3;
                10'd13: data_o = 32'h3A639E63;
                10'd14: data_o = 32'h0FF00293;
                10'd15: data_o = 32'h0F02C313;
                10'd16: data_o = 32'h00F00393;
                10'd17: data_o = 32'h3A731663;
                10'd18: data_o = 32'h7002E313;
                10'd19: data_o = 32'h7FF00393;
                10'd20: data_o = 32'h3A731063;
                10'd21: data_o = 32'h0F02F313;
                10'd22: data_o = 32'h0F000393;
                10'd23: data_o = 32'h38731A63;
                10'd24: data_o = 32'h0AA00293;
                10'd25: data_o = 32'h05500313;
                10'd26: data_o = 32'h0062C3B3;
                10'd27: data_o = 32'h0FF00E13;
                10'd28: data_o = 32'h39C39063;
                10'd29: data_o = 32'h0062E3B3;
                10'd30: data_o = 32'h37C39C63;
                10'd31: data_o = 32'h0062F3B3;
                10'd32: data_o = 32'h36039863;
                10'd33: data_o = 32'h00100293;
                10'd34: data_o = 32'h00429313;
                10'd35: data_o = 32'h01000393;
                10'd36: data_o = 32'h36731063;
                10'd37: data_o = 32'h0023D313;
                10'd38: data_o = 32'h00400E13;
                10'd39: data_o = 32'h35C31A63;
                10'd40: data_o = 32'hFF000293;
                10'd41: data_o = 32'h4022D313;
                10'd42: data_o = 32'hFFC00393;
                10'd43: data_o = 32'h34731263;
                10'd44: data_o = 32'h00100293;
                10'd45: data_o = 32'h00400313;
                10'd46: data_o = 32'h006293B3;
                10'd47: data_o = 32'h01000E13;
                10'd48: data_o = 32'h33C39863;
                10'd49: data_o = 32'h00200313;
                10'd50: data_o = 32'h006E53B3;
                10'd51: data_o = 32'h00400E93;
                10'd52: data_o = 32'h33D39063;
                10'd53: data_o = 32'hFF000293;
                10'd54: data_o = 32'h4062D3B3;
                10'd55: data_o = 32'hFFC00E93;
                10'd56: data_o = 32'h31D39863;
                10'd57: data_o = 32'h00A00293;
                10'd58: data_o = 32'h0142A313;
                10'd59: data_o = 32'h00100393;
                10'd60: data_o = 32'h30731063;
                10'd61: data_o = 32'hFF600293;
                10'd62: data_o = 32'h0142B313;
                10'd63: data_o = 32'h2E031A63;
                10'd64: data_o = 32'h00A00293;
                10'd65: data_o = 32'h01400313;
                10'd66: data_o = 32'h0062A3B3;
                10'd67: data_o = 32'h00100E13;
                10'd68: data_o = 32'h2FC39063;
                10'd69: data_o = 32'h005333B3;
                10'd70: data_o = 32'h2C039C63;
                10'd71: data_o = 32'h0FC10417;
                10'd72: data_o = 32'hEE440413;
                10'd73: data_o = 32'h12345337;
                10'd74: data_o = 32'h67830313;
                10'd75: data_o = 32'h00642023;
                10'd76: data_o = 32'h0000B3B7;
                10'd77: data_o = 32'hABB38393;
                10'd78: data_o = 32'h00741223;
                10'd79: data_o = 32'h0CC00E13;
                10'd80: data_o = 32'h01C40423;
                10'd81: data_o = 32'h00042E83;
                10'd82: data_o = 32'h2A6E9463;
                10'd83: data_o = 32'h00441F03;
                10'd84: data_o = 32'hFFFFBFB7;
                10'd85: data_o = 32'hABBF8F93;
                10'd86: data_o = 32'h29FF1C63;
                10'd87: data_o = 32'h00445F03;
                10'd88: data_o = 32'h0000BFB7;
                10'd89: data_o = 32'hABBF8F93;
                10'd90: data_o = 32'h29FF1463;
                10'd91: data_o = 32'h00840F03;
                10'd92: data_o = 32'hFCC00F93;
                10'd93: data_o = 32'h27FF1E63;
                10'd94: data_o = 32'h00844F03;
                10'd95: data_o = 32'h0CC00F93;
                10'd96: data_o = 32'h27FF1863;
                10'd97: data_o = 32'h00500293;
                10'd98: data_o = 32'h00A00313;
                10'd99: data_o = 32'h00500393;
                10'd100: data_o = 32'hFF600E13;
                10'd101: data_o = 32'hFF600E93;
                10'd102: data_o = 32'h00728463;
                10'd103: data_o = 32'h2540006F;
                10'd104: data_o = 32'h01DE0463;
                10'd105: data_o = 32'h24C0006F;
                10'd106: data_o = 32'h00629463;
                10'd107: data_o = 32'h2440006F;
                10'd108: data_o = 32'h01C29463;
                10'd109: data_o = 32'h23C0006F;
                10'd110: data_o = 32'h0062C463;
                10'd111: data_o = 32'h2340006F;
                10'd112: data_o = 32'h005E4463;
                10'd113: data_o = 32'h22C0006F;
                10'd114: data_o = 32'h00535463;
                10'd115: data_o = 32'h2240006F;
                10'd116: data_o = 32'h01C2D463;
                10'd117: data_o = 32'h21C0006F;
                10'd118: data_o = 32'h0062E463;
                10'd119: data_o = 32'h2140006F;
                10'd120: data_o = 32'h01C2E463;
                10'd121: data_o = 32'h20C0006F;
                10'd122: data_o = 32'h00537463;
                10'd123: data_o = 32'h2040006F;
                10'd124: data_o = 32'h005E7463;
                10'd125: data_o = 32'h1FC0006F;
                10'd126: data_o = 32'h00800F6F;
                10'd127: data_o = 32'h1F40006F;
                10'd128: data_o = 32'h00000F97;
                10'd129: data_o = 32'h010F8F93;
                10'd130: data_o = 32'h000F8067;
                10'd131: data_o = 32'h1E40006F;
                10'd132: data_o = 32'h00100013;
                10'd133: data_o = 32'h1C001E63;
                10'd134: data_o = 32'hDEADC2B7;
                10'd135: data_o = 32'hEEF28293;
                10'd136: data_o = 32'h00028313;
                10'd137: data_o = 32'h00030393;
                10'd138: data_o = 32'h00038F93;
                10'd139: data_o = 32'hDEADC2B7;
                10'd140: data_o = 32'hEEF28293;
                10'd141: data_o = 32'h1A5F9E63;
                10'd142: data_o = 32'h000185B7;
                10'd143: data_o = 32'h6A058593;
                10'd144: data_o = 32'h00200613;
                10'd145: data_o = 32'hEE6B36B7;
                10'd146: data_o = 32'h80068693;
                10'd147: data_o = 32'h000312B7;
                10'd148: data_o = 32'hD4028293;
                10'd149: data_o = 32'hDCD65337;
                10'd150: data_o = 32'hFFF00393;
                10'd151: data_o = 32'h00100E13;
                10'd152: data_o = 32'h02C58533;
                10'd153: data_o = 32'h18551663;
                10'd154: data_o = 32'h02C68533;
                10'd155: data_o = 32'h18651263;
                10'd156: data_o = 32'h02C59533;
                10'd157: data_o = 32'h16051E63;
                10'd158: data_o = 32'h02C69533;
                10'd159: data_o = 32'h16751A63;
                10'd160: data_o = 32'h02C6B533;
                10'd161: data_o = 32'h17C51663;
                10'd162: data_o = 32'h02C6A533;
                10'd163: data_o = 32'h16751263;
                10'd164: data_o = 32'h02D62533;
                10'd165: data_o = 32'h15C51E63;
                10'd166: data_o = 32'h000028B7;
                10'd167: data_o = 32'hE8288893;
                10'd168: data_o = 32'h00010437;
                10'd169: data_o = 32'hFFF40413;
                10'd170: data_o = 32'h01200493;
                10'd171: data_o = 32'h03400913;
                10'd172: data_o = 32'h05600993;
                10'd173: data_o = 32'h07800A13;
                10'd174: data_o = 32'h09000A93;
                10'd175: data_o = 32'h0AB00B13;
                10'd176: data_o = 32'h0CD00B93;
                10'd177: data_o = 32'h0EF00C13;
                10'd178: data_o = 32'h80848433;
                10'd179: data_o = 32'h80890433;
                10'd180: data_o = 32'h80898433;
                10'd181: data_o = 32'h808A0433;
                10'd182: data_o = 32'h808A8433;
                10'd183: data_o = 32'h808B0433;
                10'd184: data_o = 32'h808B8433;
                10'd185: data_o = 32'h808C0433;
                10'd186: data_o = 32'h11141463;
                10'd187: data_o = 32'h000102B7;
                10'd188: data_o = 32'hFFF28293;
                10'd189: data_o = 32'h00001337;
                10'd190: data_o = 32'h23430313;
                10'd191: data_o = 32'h000053B7;
                10'd192: data_o = 32'h67838393;
                10'd193: data_o = 32'h00009E37;
                10'd194: data_o = 32'h0ABE0E13;
                10'd195: data_o = 32'h0000DEB7;
                10'd196: data_o = 32'hDEFE8E93;
                10'd197: data_o = 32'h805312B3;
                10'd198: data_o = 32'h805392B3;
                10'd199: data_o = 32'h805E12B3;
                10'd200: data_o = 32'h805E92B3;
                10'd201: data_o = 32'h0D129663;
                10'd202: data_o = 32'h00010537;
                10'd203: data_o = 32'hFFF50513;
                10'd204: data_o = 32'h123455B7;
                10'd205: data_o = 32'h67858593;
                10'd206: data_o = 32'h90ABD637;
                10'd207: data_o = 32'hDEF60613;
                10'd208: data_o = 32'h80A5A533;
                10'd209: data_o = 32'h80A62533;
                10'd210: data_o = 32'h0B151463;
                10'd211: data_o = 32'h00000297;
                10'd212: data_o = 32'h0AC28293;
                10'd213: data_o = 32'h0002A303;
                10'd214: data_o = 32'h0042A383;
                10'd215: data_o = 32'h00010537;
                10'd216: data_o = 32'hFFF50513;
                10'd217: data_o = 32'h80A32533;
                10'd218: data_o = 32'h80A3A533;
                10'd219: data_o = 32'h000028B7;
                10'd220: data_o = 32'hE8288893;
                10'd221: data_o = 32'h07151E63;
                10'd222: data_o = 32'h01400293;
                10'd223: data_o = 32'h00A00313;
                10'd224: data_o = 32'h006283B3;
                10'd225: data_o = 32'h40628E33;
                10'd226: data_o = 32'h03C38EB3;
                10'd227: data_o = 32'h12C00F13;
                10'd228: data_o = 32'h07EE9063;
                10'd229: data_o = 32'h00000297;
                10'd230: data_o = 32'h06C28293;
                10'd231: data_o = 32'h0FC10317;
                10'd232: data_o = 32'hC7430313;
                10'd233: data_o = 32'h00300393;
                10'd234: data_o = 32'h0002AE03;
                10'd235: data_o = 32'h01C32023;
                10'd236: data_o = 32'h00428293;
                10'd237: data_o = 32'h00430313;
                10'd238: data_o = 32'hFFF38393;
                10'd239: data_o = 32'hFE0396E3;
                10'd240: data_o = 32'h0FC10317;
                10'd241: data_o = 32'hC5030313;
                10'd242: data_o = 32'h00032E03;
                10'd243: data_o = 32'h11111EB7;
                10'd244: data_o = 32'h111E8E93;
                10'd245: data_o = 32'h01DE1E63;
                10'd246: data_o = 32'h00832E03;
                10'd247: data_o = 32'h33333EB7;
                10'd248: data_o = 32'h333E8E93;
                10'd249: data_o = 32'h01DE1663;
                10'd250: data_o = 32'h00000213;
                10'd251: data_o = 32'h0000006F;
                10'd252: data_o = 32'hFFF00213;
                10'd253: data_o = 32'h0000006F;
                10'd254: data_o = 32'h12345678;
                10'd255: data_o = 32'h90ABCDEF;
                10'd256: data_o = 32'h11111111;
                10'd257: data_o = 32'h22222222;
                10'd258: data_o = 32'h33333333;
                default: data_o = 32'h00000013; // NOP (addi x0, x0, 0)
            endcase
        end
    end
endmodule



//  ---------- INLCUDED BLOCK: dmem_eq26  ----------
// Data memory (registered read).
module dmem_eq26 #(
    parameter DEPTH_WORDS = 8
) (
    input  wire        clk_i,
    input  wire         rst_i,
    input  wire [31:0] addr_i,   // word address
    input  wire        we_i,
    input  wire        oe_i,
    input  wire [3:0]  bw_i,     // byte write mask
    input  wire [31:0] data_i,
    output reg  [31:0] data_o    // registered — see timing note above
);

    localparam IDX_W = $clog2(DEPTH_WORDS);

    reg [31:0] mem [0:DEPTH_WORDS-1];

    wire [IDX_W-1:0] index = addr_i[IDX_W-1:0];

    always @(posedge clk_i) begin
        if (rst_i) begin
            data_o <= 32'b0;
        end else begin
            if (we_i) begin
                if (bw_i[0]) mem[index][ 7: 0] <= data_i[ 7: 0];
                if (bw_i[1]) mem[index][15: 8] <= data_i[15: 8];
                if (bw_i[2]) mem[index][23:16] <= data_i[23:16];
                if (bw_i[3]) mem[index][31:24] <= data_i[31:24];
            end
            if (oe_i) begin
                data_o <= mem[index]; // registered read, NOT combinational
            end
        end
    end

endmodule



//  ---------- INLCUDED BLOCK: address_decoder  ----------
// Memory address decoder.
module address_decoder (
    input  wire [31:0] address_i,
    input  wire        we_i,
    input  wire        oe_i,
    input  wire [3:0]  bw_i,

    input  wire [31:0] dmem_data_i,
    input  wire [31:0] imem_data_i,

    output wire [31:0] address_o,     // word address (zero-extended)
    output wire        dmem_we_o,
    output wire        dmem_oe_o,
    output wire        imem_oe_o,
    output wire [3:0]  bw_o,
    output reg  [31:0] data_o
);

    localparam [31:0] IMEM_BASE = 32'h0040_0000;
    localparam [31:0] DMEM_BASE = 32'h1001_0000;

    localparam [31:0] IMEM_LOW  = IMEM_BASE;
    localparam [31:0] IMEM_HIGH = IMEM_BASE + 32'h0040_0000 - 1; // +4MB
    localparam [31:0] DMEM_LOW  = DMEM_BASE;
    localparam [31:0] DMEM_HIGH = DMEM_BASE + 32'h0000_2000 - 1; // +8kB

    wire is_imem = (address_i >= IMEM_LOW) && (address_i <= IMEM_HIGH);
    wire is_dmem = (address_i >= DMEM_LOW) && (address_i <= DMEM_HIGH);

  	assign address_o = {2'b00, address_i[31:2]};// zeroextending

    assign dmem_we_o = we_i && is_dmem;
    assign dmem_oe_o = oe_i && is_dmem;
    assign imem_oe_o = oe_i && is_imem;
    assign bw_o      = is_dmem ? bw_i : 4'b0000;

    always @(*) begin
        data_o = 32'b0; // default: unmapped address, guide silent (see header note)
        if (is_dmem)
            data_o = dmem_data_i;
        else if (is_imem)
            data_o = imem_data_i;
    end

endmodule



//  ---------- INLCUDED BLOCK: control_unit_eq26  ---------- 
// Multicycle FSM control unit.

// Opcodes (IR[6:0])
`define OPCODE_RTYPE   7'b0110011
`define OPCODE_ITYPE   7'b0010011
`define OPCODE_LOAD    7'b0000011
`define OPCODE_STORE   7'b0100011
`define OPCODE_BRANCH  7'b1100011
`define OPCODE_JAL     7'b1101111
`define OPCODE_JALR    7'b1100111
`define OPCODE_LUI     7'b0110111
`define OPCODE_AUIPC   7'b0010111
`define OPCODE_SYSTEM  7'b1110011
`define OPCODE_FENCE   7'b0001111

// funct12 / funct7 disambiguation
`define FUNCT12_ECALL  12'h000
`define FUNCT12_EBREAK 12'h001
`define FUNCT7_MUL     7'b0000001
`define FUNCT7_CRC     7'b1000000

// alu_op — Table 9
`define ALU_PASS_B     4'h0
`define ALU_ADD        4'h1
`define ALU_SUB        4'h2
`define ALU_AND        4'h3
`define ALU_OR         4'h4
`define ALU_XOR        4'h5
`define ALU_SLL        4'h6
`define ALU_SRL        4'h7
`define ALU_MRS        4'h8
`define ALU_SLT        4'h9
`define ALU_SLTU       4'hA

// mult_op_o (Table 10) & crc_op_o (Table 11)
`define MULT_MUL       4'h0
`define MULT_MULH      4'h1
`define MULT_MULHSU    4'h2
`define MULT_MULHU     4'h3

`define CRC_CRCB       4'h0
`define CRC_CRCH       4'h1
`define CRC_CRCW       4'h2

// Mux select lines
`define RESULT_SRC_ALU   3'b000
`define RESULT_SRC_MUL   3'b001
`define RESULT_SRC_CRC   3'b010
`define RESULT_SRC_MEM   3'b011
`define RESULT_SRC_PC4   3'b100

`define PC_SRC_PLUS4     2'b00
`define PC_SRC_TARGET    2'b01
`define PC_SRC_JALR      2'b10

`define ALU_SRC_A_RS1    1'b0
`define ALU_SRC_A_PC     1'b1

`define ALU_SRC_B_RS2    2'b00
`define ALU_SRC_B_IMM    2'b01
`define ALU_SRC_B_CONST4 2'b10

`define ADR_SRC_PC       1'b0
`define ADR_SRC_ALU      1'b1

// Memory map (Table 13)
`define PC_RESET_ADDR    32'h00400000
`define IMEM_BASE        32'h00400000
`define DMEM_BASE        32'h10010000

// op_size_o & imm_sel_o
`define OP_SIZE_BYTE_S   3'b000
`define OP_SIZE_BYTE_U   3'b001
`define OP_SIZE_HALF_S   3'b010
`define OP_SIZE_HALF_U   3'b011
`define OP_SIZE_WORD     3'b100

`define IMM_SEL_I        3'b000
`define IMM_SEL_S        3'b001
`define IMM_SEL_B        3'b010
`define IMM_SEL_U        3'b011
`define IMM_SEL_J        3'b100

module control_unit_eq26(
    input  wire        clk_i,
    input  wire        rst_i,

    // Decode fields
    input  wire [6:0]  opcode_i,
    input  wire [2:0]  funct3_i,
    input  wire [6:0]  funct7_i,
    input  wire [11:0] funct12_i,

    input  wire [1:0]  addr_lsb_i,
    input  wire        branch_taken_i,

    // Datapath control
    output reg         pc_write_o,
    output reg  [1:0]  pc_src_o,
    output reg         ir_write_o,
    output reg         reg_write_o,
    output reg  [2:0]  result_src_o,
    output reg         alu_src_a_o,
    output reg  [1:0]  alu_src_b_o,
    output reg  [3:0]  alu_op_o,
    output reg  [2:0]  imm_sel_o,
    output reg  [3:0]  mult_op_o,
    output reg  [3:0]  crc_op_o,
    output reg         mult_en_o,
    output reg         crc_en_o,

    // Memory interface
    output reg         we_o,
    output reg         oe_o,
    output reg  [3:0]  bw_o,
    output reg  [2:0]  op_size_o,
    output reg         adr_src_o,

    // Status
    output reg         halt_o,

    // Derived enables
    output wire        not_adr_src_o,
    output wire        result_src_is_mem_o
);

    assign not_adr_src_o       = !adr_src_o;
    assign result_src_is_mem_o = (result_src_o == `RESULT_SRC_MEM);

    // State encoding
    localparam [3:0] RESET             = 4'd0;
    localparam [3:0] FETCH             = 4'd1;
    localparam [3:0] DECODE            = 4'd2;
    localparam [3:0] EXECUTE_ALU       = 4'd3;
    localparam [3:0] WRITE_BACK        = 4'd4;
    localparam [3:0] MEM_ADDR          = 4'd5;
    localparam [3:0] MEM_ACCESS_ADDR   = 4'd6;
    localparam [3:0] MEM_ACCESS_DATA   = 4'd7;
    localparam [3:0] MEM_ACCESS_STORE  = 4'd8;

    reg [3:0] state, next_state;

    // Tracks state for WRITE_BACK's result_src_o
    reg [3:0] prev_state;

    // State register
    always @(posedge clk_i) begin
        if (rst_i) begin
            state      <= RESET;
            prev_state <= RESET;
        end else begin
            prev_state <= state;
            state      <= next_state;
        end
    end

    // Sticky ECALL status flag
    wire is_ecall = (opcode_i  == `OPCODE_SYSTEM) &&
                    (funct3_i  == 3'b000)         &&
                    (funct12_i == `FUNCT12_ECALL);

    always @(posedge clk_i) begin
        if (rst_i) begin
            halt_o <= 1'b0;
        end else if ((state == EXECUTE_ALU) && is_ecall) begin
            halt_o <= 1'b1;
        end
    end

    // Illegal-opcode detection
    wire opcode_legal = (opcode_i == `OPCODE_RTYPE)  ||
                        (opcode_i == `OPCODE_ITYPE)  ||
                        (opcode_i == `OPCODE_LOAD)   ||
                        (opcode_i == `OPCODE_STORE)  ||
                        (opcode_i == `OPCODE_BRANCH) ||
                        (opcode_i == `OPCODE_JAL)    ||
                        (opcode_i == `OPCODE_JALR)   ||
                        (opcode_i == `OPCODE_LUI)    ||
                        (opcode_i == `OPCODE_AUIPC)  ||
                        (opcode_i == `OPCODE_SYSTEM) ||
                        (opcode_i == `OPCODE_FENCE);

    // Next-state logic
    always @(*) begin
        next_state = state;
        case (state)
            RESET:  next_state = FETCH;
            FETCH:  next_state = DECODE;

            DECODE: begin
                if (opcode_i == `OPCODE_LOAD || opcode_i == `OPCODE_STORE)
                    next_state = MEM_ADDR;
                else
                    next_state = EXECUTE_ALU;
            end

            EXECUTE_ALU: begin
                if (opcode_i == `OPCODE_BRANCH ||
                    opcode_i == `OPCODE_SYSTEM ||
                    opcode_i == `OPCODE_FENCE  ||
                    !opcode_legal)
                    next_state = FETCH;
                else
                    next_state = WRITE_BACK;
            end

            WRITE_BACK:  next_state = FETCH;

            MEM_ADDR: begin
                if (opcode_i == `OPCODE_STORE)
                    next_state = MEM_ACCESS_STORE;
                else
                    next_state = MEM_ACCESS_ADDR;
            end

            MEM_ACCESS_ADDR: next_state = MEM_ACCESS_DATA;
            MEM_ACCESS_DATA: next_state = WRITE_BACK;
            MEM_ACCESS_STORE: next_state = FETCH;

            default: next_state = RESET;
        endcase
    end

    // Output logic
    // funct3 -> op_size_o lookup
    reg [2:0] op_size_lookup;
    always @(*) begin
        case (funct3_i)
            3'b000:  op_size_lookup = `OP_SIZE_BYTE_S;
            3'b001:  op_size_lookup = `OP_SIZE_HALF_S;
            3'b010:  op_size_lookup = `OP_SIZE_WORD;
            3'b100:  op_size_lookup = `OP_SIZE_BYTE_U;
            3'b101:  op_size_lookup = `OP_SIZE_HALF_U;
            default: op_size_lookup = `OP_SIZE_WORD;
        endcase
    end

    // Byte-write mask lookup
    reg [3:0] bw_lookup;
    always @(*) begin
        case (op_size_lookup[2:1])
            2'b10: bw_lookup = 4'b1111;
            2'b01: bw_lookup = addr_lsb_i[1] ? 4'b1100 : 4'b0011;
            2'b00: bw_lookup = 4'b0001 << addr_lsb_i;
            default: bw_lookup = 4'b1111;
        endcase
    end

    always @(*) begin
        // Defaults
        pc_write_o   = 1'b0;
        pc_src_o     = `PC_SRC_PLUS4;
        ir_write_o   = 1'b0;
        reg_write_o  = 1'b0;
        result_src_o = `RESULT_SRC_ALU;
        alu_src_a_o  = `ALU_SRC_A_RS1;
        alu_src_b_o  = `ALU_SRC_B_RS2;
        alu_op_o     = `ALU_PASS_B;
        imm_sel_o    = `IMM_SEL_I;
        mult_op_o      = 4'h0;
        crc_op_o       = 4'h0;
        mult_en_o    = 1'b0;
        crc_en_o     = 1'b0;
        we_o         = 1'b0;
        oe_o         = 1'b0;
        bw_o         = 4'b0000;
        op_size_o    = `OP_SIZE_WORD;
        adr_src_o    = `ADR_SRC_PC;

        case (state)
            RESET: begin
            end

            FETCH: begin
                pc_write_o = 1'b1;
                ir_write_o = 1'b1;
                oe_o       = 1'b1;
            end

            DECODE: begin
                // imm_sel_o per opcode
                if (opcode_i == `OPCODE_LOAD)
                    imm_sel_o = `IMM_SEL_I;
                else if (opcode_i == `OPCODE_STORE)
                    imm_sel_o = `IMM_SEL_S;
                else if (opcode_i == `OPCODE_BRANCH)
                    imm_sel_o = `IMM_SEL_B;
                else if (opcode_i == `OPCODE_JAL)
                    imm_sel_o = `IMM_SEL_J;
                else if (opcode_i == `OPCODE_JALR)
                    imm_sel_o = `IMM_SEL_I;
                else if (opcode_i == `OPCODE_LUI || opcode_i == `OPCODE_AUIPC)
                    imm_sel_o = `IMM_SEL_U;
                else if (opcode_i == `OPCODE_ITYPE)
                    imm_sel_o = `IMM_SEL_I;
                else
                    imm_sel_o = `IMM_SEL_I;
            end

            EXECUTE_ALU: begin
                if (opcode_i == `OPCODE_BRANCH) begin
                    // Branch
                    pc_write_o   = branch_taken_i;
                    pc_src_o     = `PC_SRC_TARGET;
                    alu_src_a_o  = `ALU_SRC_A_PC;
                    alu_src_b_o  = `ALU_SRC_B_IMM;
                    alu_op_o     = `ALU_ADD;
                    imm_sel_o    = `IMM_SEL_B;
                end else if (opcode_i == `OPCODE_JAL) begin
                    pc_write_o   = 1'b1;
                    pc_src_o     = `PC_SRC_TARGET;
                    alu_src_a_o  = `ALU_SRC_A_PC;
                    alu_src_b_o  = `ALU_SRC_B_IMM;
                    alu_op_o     = `ALU_ADD;
                    imm_sel_o    = `IMM_SEL_J;
                    result_src_o = `RESULT_SRC_PC4;
                end else if (opcode_i == `OPCODE_JALR) begin
                    // Target = rs1 + imm
                    pc_write_o   = 1'b1;
                    pc_src_o     = `PC_SRC_JALR;
                    alu_src_a_o  = `ALU_SRC_A_RS1;
                    alu_src_b_o  = `ALU_SRC_B_IMM;
                    alu_op_o     = `ALU_ADD;
                    imm_sel_o    = `IMM_SEL_I;
                    result_src_o = `RESULT_SRC_PC4;
                end else if (opcode_i == `OPCODE_LUI) begin
                    alu_src_b_o = `ALU_SRC_B_IMM;
                    alu_op_o    = `ALU_PASS_B;
                    imm_sel_o   = `IMM_SEL_U;
                end else if (opcode_i == `OPCODE_AUIPC) begin
                    alu_src_a_o = `ALU_SRC_A_PC;
                    alu_src_b_o = `ALU_SRC_B_IMM;
                    alu_op_o    = `ALU_ADD;
                    imm_sel_o   = `IMM_SEL_U;
                end else if (opcode_i == `OPCODE_SYSTEM || opcode_i == `OPCODE_FENCE) begin
                    // No-op
                end else if (opcode_i == `OPCODE_RTYPE && funct7_i == `FUNCT7_MUL) begin
                    // Zmmul
                    mult_en_o    = 1'b1;
                    mult_op_o      = {1'b0, funct3_i};
                    result_src_o = `RESULT_SRC_MUL;
                end else if (opcode_i == `OPCODE_RTYPE && funct7_i == `FUNCT7_CRC) begin
                    // Xicrc
                    crc_en_o     = 1'b1;
                    crc_op_o       = {1'b0, funct3_i};
                    result_src_o = `RESULT_SRC_CRC;
                end else begin
                    // R-type / I-type ALU
                    if (opcode_i == `OPCODE_ITYPE) begin
                        alu_src_b_o = `ALU_SRC_B_IMM;
                        imm_sel_o   = `IMM_SEL_I;
                    end

                    case (funct3_i)
                        3'b000: alu_op_o = (opcode_i != `OPCODE_ITYPE && funct7_i[5]) ? `ALU_SUB : `ALU_ADD;
                        3'b001: alu_op_o = `ALU_SLL;
                        3'b010: alu_op_o = `ALU_SLT;
                        3'b011: alu_op_o = `ALU_SLTU;
                        3'b100: alu_op_o = `ALU_XOR;
                        3'b101: alu_op_o = funct7_i[5] ? `ALU_MRS : `ALU_SRL;
                        3'b110: alu_op_o = `ALU_OR;
                        3'b111: alu_op_o = `ALU_AND;
                        default: alu_op_o = `ALU_ADD;
                    endcase
                end
            end

            MEM_ADDR: begin
                // Effective address = rs1 + imm
                alu_src_a_o = `ALU_SRC_A_RS1;
                alu_src_b_o = `ALU_SRC_B_IMM;
                alu_op_o    = `ALU_ADD;
                imm_sel_o   = (opcode_i == `OPCODE_STORE) ? `IMM_SEL_S : `IMM_SEL_I;
                op_size_o   = op_size_lookup;
                bw_o        = bw_lookup;
            end

            MEM_ACCESS_ADDR: begin
                // Load sub-cycle 1
                oe_o      = 1'b1;
                op_size_o = op_size_lookup;
                adr_src_o = `ADR_SRC_ALU;
            end

            MEM_ACCESS_DATA: begin
                // Load sub-cycle 2
                result_src_o = `RESULT_SRC_MEM;
                op_size_o    = op_size_lookup;
                oe_o         = 1'b1;
                adr_src_o    = `ADR_SRC_ALU;
            end

            MEM_ACCESS_STORE: begin
                // Store commit
                we_o      = 1'b1;
                op_size_o = op_size_lookup;
                bw_o      = bw_lookup;
                adr_src_o = `ADR_SRC_ALU;
            end

            WRITE_BACK: begin
                reg_write_o = 1'b1;
                if (prev_state == MEM_ACCESS_DATA) begin
                    result_src_o = `RESULT_SRC_MEM;
                    op_size_o    = op_size_lookup;
                end
                else if (prev_state == EXECUTE_ALU &&
                         (opcode_i == `OPCODE_JAL || opcode_i == `OPCODE_JALR))
                    result_src_o = `RESULT_SRC_PC4;
                else if (prev_state == EXECUTE_ALU && opcode_i == `OPCODE_RTYPE &&
                         funct7_i == `FUNCT7_MUL)
                    result_src_o = `RESULT_SRC_MUL;
                else if (prev_state == EXECUTE_ALU && opcode_i == `OPCODE_RTYPE &&
                         funct7_i == `FUNCT7_CRC)
                    result_src_o = `RESULT_SRC_CRC;
                else
                    result_src_o = `RESULT_SRC_ALU;
            end

            default: begin
            end
        endcase

        // Halt override: freezes pc + ir on ECALL
        if (halt_o) begin
            pc_write_o = 1'b0;
            ir_write_o = 1'b0;
        end
    end

endmodule



//  ---------- INLCUDED BLOCK: reg32_dff_eq26  ---------- 
module reg32_dff_eq26 #(
    parameter RESET_VALUE = 32'h00000000
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        en_i,       // Enable: 1 = load d_i, 0 = hold current value
    input  wire [31:0] d_i,        // Data input (D)
    output reg  [31:0] q_o         // Data output (Q)
);

    always @(posedge clk_i) begin
        if (rst_i) begin
            q_o <= RESET_VALUE;
        end else if (en_i) begin
            q_o <= d_i;
        end
    end

endmodule
// Generic D flip-flop register.



//  ---------- INLCUDED BLOCK: mux_result  ---------- 
module mux_result (
    input  wire [2:0]  result_src_i,   // Select code from Control Unit (result_src_o)
    input  wire [31:0] alu_out_i,      // ALU registered result (3'b000)
    input  wire [31:0] mult_result_i,  // Multiplier registered result (3'b001)
    input  wire [31:0] crc_result_i,   // CRC registered result (3'b010)
    input  wire [31:0] mem_result_i,   // Memory loaded result from LSU (3'b011)
    input  wire [31:0] old_pc_i,       // Old PC for JAL/JALR return address (3'b100 -> Old_PC + 4)
    output reg  [31:0] result_o        // Selected 32-bit data to regfile.write_data_i
);

    localparam [2:0] RESULT_SRC_ALU = 3'b000;
    localparam [2:0] RESULT_SRC_MUL = 3'b001;
    localparam [2:0] RESULT_SRC_CRC = 3'b010;
    localparam [2:0] RESULT_SRC_MEM = 3'b011;
    localparam [2:0] RESULT_SRC_PC4 = 3'b100;

    always @(*) begin
        case (result_src_i)
            RESULT_SRC_ALU: result_o = alu_out_i;
            RESULT_SRC_MUL: result_o = mult_result_i;
            RESULT_SRC_CRC: result_o = crc_result_i;
            RESULT_SRC_MEM: result_o = mem_result_i;
            RESULT_SRC_PC4: result_o = old_pc_i + 32'd4;
            default:        result_o = alu_out_i;
        endcase
    end

endmodule



//  ---------- INLCUDED BLOCK: ir_splitter_eq26  ---------- 
module ir_splitter_eq26(
    input  wire [31:0] instr_i,      // 32-bit instruction from IR register (q_o of reg32)
    output wire [6:0]  opcode_o,     // instr_i[6:0]   -> to control_unit.opcode_i
    output wire [4:0]  rd_o,         // instr_i[11:7]  -> to regfile.rd_addr_i
    output wire [2:0]  funct3_o,     // instr_i[14:12] -> to control_unit & branch_comparator
    output wire [4:0]  rs1_o,        // instr_i[19:15] -> to regfile.rs1_addr_i
    output wire [4:0]  rs2_o,        // instr_i[24:20] -> to regfile.rs2_addr_i
    output wire [6:0]  funct7_o,     // instr_i[31:25] -> to control_unit.funct7_i
    output wire [11:0] funct12_o     // instr_i[31:20] -> to control_unit.funct12_i
);
    assign opcode_o  = instr_i[6:0];
    assign rd_o      = instr_i[11:7];
    assign funct3_o  = instr_i[14:12];
    assign rs1_o     = instr_i[19:15];
    assign rs2_o     = instr_i[24:20];
    assign funct7_o  = instr_i[31:25];
    assign funct12_o = instr_i[31:20];
endmodule



//  ---------- INLCUDED BLOCK: mux_alu_a  ---------- 
module mux_alu_a (
    input  wire        alu_src_a_i,   // 0: RS1 data, 1: Old_PC
    input  wire [31:0] rs1_data_i,    // Data from RegFile rs1
    input  wire [31:0] old_pc_i,      // Saved PC from Old_PC register
    output wire [31:0] a_o            // Operand A into ALU
);

    assign a_o = alu_src_a_i ? old_pc_i : rs1_data_i;

endmodule



//  ---------- INLCUDED BLOCK: mux_alu_b  ---------- 
module mux_alu_b (
    input  wire [1:0]  alu_src_b_i,   // 2'b00: RS2, 2'b01: Immediate, 2'b10: Constant 4
    input  wire [31:0] rs2_data_i,    // Data from RegFile rs2
    input  wire [31:0] imm_i,         // Extended immediate from imm_extend
    output reg  [31:0] b_o            // Operand B into ALU
);

    always @(*) begin
        case (alu_src_b_i)
            2'b00:   b_o = rs2_data_i;
            2'b01:   b_o = imm_i;
            2'b10:   b_o = 32'd4;
            default: b_o = rs2_data_i;
        endcase
    end

endmodule



//  ---------- INLCUDED BLOCK: fetch_registers  ---------- 
module fetch_registers #(
    parameter PC_RESET_ADDR = 32'h00400000
) (
    input  wire        clk_i,
    input  wire        rst_i,
    // Controls from Control Unit
    input  wire        pc_write_i,      // From control_unit.pc_write_o
    input  wire        ir_write_i,      // From control_unit.ir_write_o
    // Data inputs
    input  wire [31:0] pc_next_i,       // From mux_pc_next.pc_next_o
    input  wire [31:0] mem_data_i,      // Instruction data from memory (decoder_data_o)
    // Register outputs
    output reg  [31:0] pc_o,            // Current PC -> to mux_mem_addr, PC+4 adder
    output reg  [31:0] old_pc_o,        // Saved Old PC -> to mux_alu_a, mux_result
    output reg  [31:0] ir_o             // Instruction Register -> to ir_splitter, imm_extend
);
    always @(posedge clk_i) begin
        if (rst_i) begin
            pc_o     <= PC_RESET_ADDR;
            old_pc_o <= 32'b0;
            ir_o     <= 32'b0;
        end else begin
            if (pc_write_i) begin
                pc_o <= pc_next_i;
            end
            if (ir_write_i) begin
                old_pc_o <= pc_o;        // Captures pre-increment PC in FETCH
                ir_o     <= mem_data_i;  // Latches fetched instruction in FETCH
            end
        end
    end
endmodule



//  ---------- INLCUDED BLOCK: mux_pc_next  ---------- 
module mux_pc_next (
    input  wire [1:0]  pc_src_i,      // From control_unit.pc_src_o[1:0]
    input  wire [31:0] pc_i,          // From fetch_registers.pc_o (adds +4 internally!)
    input  wire [31:0] alu_result_i,  // From alu.result_o (Live branch/jump target)
    output reg  [31:0] pc_next_o      // To fetch_registers.pc_next_i
);
    always @(*) begin
        case (pc_src_i)
            2'b00:   pc_next_o = pc_i + 32'd4;                 // PC + 4 computed inside!
            2'b01:   pc_next_o = alu_result_i;                 // Branch / JAL target
            2'b10:   pc_next_o = {alu_result_i[31:1], 1'b0};   // JALR target (clears bit 0)
            default: pc_next_o = pc_i + 32'd4;
        endcase
    end
endmodule



//  ---------- INLCUDED BLOCK: mux_mem_addr  ---------- 
module mux_mem_addr (
    input  wire        adr_src_i,     // 0: PC, 1: ALU_Out
    input  wire [31:0] pc_i,          // Current PC address (Fetch)
    input  wire [31:0] alu_out_i,     // Calculated memory address (Load/Store)
    output wire [31:0] address_o      // Address sent to address_decoder
);

    assign address_o = adr_src_i ? alu_out_i : pc_i;

endmodule



//  ---------- INLCUDED BLOCK: alu_out_reg  ---------- 
module alu_out_reg #(
    parameter RESET_VALUE = 32'h00000000
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        en_i,           // Enable: 1 = load alu_result_i, 0 = hold
    input  wire [31:0] alu_result_i,   // From alu.result_o
    output reg  [31:0] alu_out_o,      // Registered 32-bit ALU output
    output wire [1:0]  addr_lsb_o      // Direct tap of alu_out_o[1:0] -> to CU.addr_lsb_i
);

    always @(posedge clk_i) begin
        if (rst_i) begin
            alu_out_o <= RESET_VALUE;
        end else if (en_i) begin
            alu_out_o <= alu_result_i;
        end
    end

    // Direct extraction of lowest 2 bits for the Control Unit byte-write mask
    assign addr_lsb_o = alu_out_o[1:0];

endmodule


// Automatically generated by ChipInventor Cloud EDA Tool - 3.15
// Careful: this file (hdl.v) will be automatically replaced
// when you ask tool to generate top Verilog code by clicking
// at BLOCKS button.

module top (

  input wire clk_i,
  input wire rst_i,
  output wire halt_o,
  output wire [31:0] x4_dbg_o,
  output wire [31:0] pc_dbg_o

);

//Internal Wires
 wire w_1;
 wire [31:0] w_2;
 wire [31:0] w_3;
 wire [31:0] w_4;
 wire [31:0] w_5;
 wire [31:0] w_6;
 wire w_7;
 wire w_8;
 wire [3:0] w_9;
 wire [31:0] w_10;
 wire [31:0] w_11;
 wire [31:0] w_12;
 wire w_14;
 wire w_15;
 wire w_16;
 wire [3:0] w_17;
 wire [31:0] w_18;
 wire [31:0] w_20;
 wire [31:0] w_21;
 wire [3:0] w_22;
 wire [31:0] w_23;
 wire [31:0] w_25;
 wire [1:0] w_28;
 wire [31:0] w_29;
 wire [31:0] w_30;
 wire [2:0] w_31;
 wire w_32;
 wire [6:0] w_33;
 wire [6:0] w_35;
 wire [11:0] w_36;
 wire w_37;
 wire [1:0] w_38;
 wire w_39;
 wire w_40;
 wire [2:0] w_41;
 wire w_42;
 wire [1:0] w_43;
 wire [2:0] w_44;
 wire [3:0] w_45;
 wire [3:0] w_46;
 wire w_47;
 wire [2:0] w_48;
 wire w_49;
 wire [31:0] w_52;
 wire [31:0] w_53;
 wire [31:0] w_54;
 wire [31:0] w_55;
 wire [31:0] w_59;
 wire [31:0] w_61;
 wire [31:0] w_63;
 wire [4:0] w_64;
 wire [4:0] w_65;
 wire [4:0] w_66;
 wire [31:0] w_72;
 wire [31:0] w_73;

//Interface Assigns
assign pc_dbg_o[31:0] = w_55;

//Instances of Modules
reg32_dff_eq26 #(.RESET_VALUE(32'h00000000)) blk3722_24 (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (w_1),
         .d_i (w_2),
         .q_o (w_3)
     );

reg32_dff_eq26 #(.RESET_VALUE(32'h00000000)) blk3722_32 (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (1'b1),
         .d_i (w_4),
         .q_o (w_5)
     );

address_decoder blk3566_49 (
         .address_i (w_6),
         .we_i (w_7),
         .oe_i (w_8),
         .bw_i (w_9),
         .dmem_data_i (w_10),
         .imem_data_i (w_11),
         .address_o (w_12),
         .dmem_we_o (w_14),
         .dmem_oe_o (w_15),
         .imem_oe_o (w_16),
         .bw_o (w_17),
         .data_o (w_18)
     );

alu_eq26 blk3550_50 (
         .a_i (w_20),
         .b_i (w_21),
         .alu_op_i (w_22),
         .result_o (w_23)
     );

alu_out_reg #(.RESET_VALUE(32'h00000000)) blk3811_51 (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (1'b1),
         .alu_result_i (w_23),
         .alu_out_o (w_25),
         .addr_lsb_o (w_28)
     );

branch_comparator_eq26 blk3552_52 (
         .rs1_i (w_29),
         .rs2_i (w_30),
         .funct3_i (w_31),
         .branch_taken_o (w_32)
     );

control_unit_eq26 blk3567_53 (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .halt_o (halt_o),
         .mult_en_o (w_1),
         .we_o (w_7),
         .oe_o (w_8),
         .bw_o (w_9),
         .alu_op_o (w_22),
         .addr_lsb_i (w_28),
         .branch_taken_i (w_32),
         .opcode_i (w_33),
         .funct3_i (w_31),
         .funct7_i (w_35),
         .funct12_i (w_36),
         .pc_write_o (w_37),
         .pc_src_o (w_38),
         .ir_write_o (w_39),
         .reg_write_o (w_40),
         .result_src_o (w_41),
         .alu_src_a_o (w_42),
         .alu_src_b_o (w_43),
         .imm_sel_o (w_44),
         .mult_op_o (w_45),
         .crc_op_o (w_46),
         .crc_en_o (w_47),
         .op_size_o (w_48),
         .adr_src_o (w_49)
     );

crc_eq26 #(.POLY(16'h1021), .XOR_OUT(16'h0000)) blk3553_54 (
         .crc_op_i (w_46),
         .a_i (w_29),
         .b_i (w_30),
         .result_o (w_52)
     );

dmem_eq26 #(.DEPTH_WORDS(8)) blk3565_55 (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .data_o (w_10),
         .addr_i (w_12),
         .we_i (w_14),
         .oe_i (w_15),
         .bw_i (w_17),
         .data_i (w_53)
     );

fetch_registers #(.PC_RESET_ADDR(32'h00400000)) blk3804_56 (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .pc_o (w_55),
         .mem_data_i (w_18),
         .pc_write_i (w_37),
         .ir_write_i (w_39),
         .pc_next_i (w_54),
         .old_pc_o (w_59),
         .ir_o (w_61)
     );

imem blk3564_57 (
         .clk_i (clk_i),
         .data_o (w_11),
         .addr_i (w_12),
         .oe_i (w_16)
     );

imm_extend_eq26 blk3556_58 (
         .imm_sel_i (w_44),
         .instr_i (w_61),
         .imm_o (w_63)
     );

ir_splitter_eq26 blk3781_59 (
         .funct3_o (w_31),
         .opcode_o (w_33),
         .funct7_o (w_35),
         .funct12_o (w_36),
         .instr_i (w_61),
         .rd_o (w_64),
         .rs1_o (w_65),
         .rs2_o (w_66)
     );

lsu_eq26 blk3562_60 (
         .core_data_i (w_4),
         .mem_data_o (w_18),
         .core_address_o (w_25),
         .op_size_o (w_48),
         .mem_data_i (w_53),
         .core_data_o (w_30)
     );

mult_eq26 blk3557_61 (
         .result_o (w_2),
         .mult_op_i (w_45),
         .a_i (w_29),
         .b_i (w_30)
     );

mux_alu_a blk3795_62 (
         .a_o (w_20),
         .alu_src_a_i (w_42),
         .old_pc_i (w_59),
         .rs1_data_i (w_29)
     );

mux_alu_b blk3796_63 (
         .b_o (w_21),
         .alu_src_b_i (w_43),
         .imm_i (w_63),
         .rs2_data_i (w_30)
     );

mux_mem_addr blk3808_64 (
         .address_o (w_6),
         .alu_out_i (w_25),
         .adr_src_i (w_49),
         .pc_i (w_55)
     );

mux_pc_next blk3807_65 (
         .alu_result_i (w_23),
         .pc_src_i (w_38),
         .pc_next_o (w_54),
         .pc_i (w_55)
     );

mux_result blk3724_66 (
         .mult_result_i (w_3),
         .mem_result_i (w_5),
         .alu_out_i (w_25),
         .result_src_i (w_41),
         .old_pc_i (w_59),
         .crc_result_i (w_72),
         .result_o (w_73)
     );

reg32_dff_eq26 #(.RESET_VALUE(32'h00000000)) blk3722_67 (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (w_47),
         .d_i (w_52),
         .q_o (w_72)
     );

regfile_eq blk3560_68 (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .x4_dbg_o (x4_dbg_o[31:0]),
         .rs1_data_o (w_29),
         .rs2_data_o (w_30),
         .reg_write_i (w_40),
         .rd_addr_i (w_64),
         .rs1_addr_i (w_65),
         .rs2_addr_i (w_66),
         .write_data_i (w_73)
     );


endmodule
