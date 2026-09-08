

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


//  ---------- INLCUDED BLOCK: control_unit_eq26  ---------- 
// control_unit.v — owned by Teammate A
//
// Implements the FSM described in HANDOFF_control_unit.md.
// Follow the workflow in CLAUDE.md: spec review -> interface -> state
// table -> RTL -> self-review -> testbench -> simulate -> document.
//
// `include "pkg/rvbl2_defines.vh" for every opcode/op-code literal.
// Do not hardcode values already defined there.
//
// SLICE 1 SCOPE (DONE): FETCH -> DECODE -> EXECUTE_ALU -> WRITE_BACK,
// R-type ALU only (opcode OPCODE_RTYPE, funct7 else-branch).
//
// SLICE 2 SCOPE (DONE): load/store. New states MEM_ADDR,
// MEM_ACCESS_ADDR, MEM_ACCESS_DATA, MEM_ACCESS_STORE. See
// docs/HANDOFF_control_unit_ALL_STAGES.md "Slice 2" section.
//
// SLICE 3 SCOPE (DONE): branch/jump. No new states — handoff §1
// puts branch/jump as cases inside EXECUTE, same state as ALU
// (EXECUTE_ALU here; the handoff's state diagram just calls it
// "EXECUTE" generically). New cases for OPCODE_BRANCH/JAL/JALR, new
// input branch_taken_i.
//
// SLICE 4 SCOPE (DONE): MUL/CRC. No new states — MUL is
// combinational/single-cycle, handled inside EXECUTE_ALU's R-type
// else-branch, disambiguated by funct7 (FUNCT7_MUL/FUNCT7_CRC, else
// ALU — handoff §5 else-trap, exactly the structure slice 1 set up
// for). New ports mult_op_o/crc_op_o/mult_en_o/crc_en_o.
//
// SLICE 5 SCOPE (DONE): LUI/AUIPC/system no-ops. No new states —
// all EXECUTE cases. New cases for OPCODE_LUI, OPCODE_AUIPC,
// OPCODE_SYSTEM, OPCODE_FENCE. LUI is the only user of ALU_PASS_B.
// ECALL/EBREAK/FENCE are no-ops (handoff §7 decision 4). ECALL also
// raises the sticky halt_o status flag added 2026-08-25 — see the
// halt_o always block and handoff decision 15. Execution semantics are
// unchanged for all three; halt_o is observability only.
//
// SLICE 6 SCOPE (this slice): I-type ALU. No new states — extends the
// R-type ALU else-fallthrough inside EXECUTE_ALU to also accept
// OPCODE_ITYPE. Only difference from R-type: alu_src_b_o=IMM (not RS2)
// and imm_sel_o=IMM_SEL_I; the alu_op_o decode table is reused as-is,
// keyed on funct3 alone (handoff Slice-6 section).
//
// DEVIATIONS / ASSUMPTIONS specific to slice 3 (flagged per CLAUDE.md
// step 8):
//
// 1. Branch/jump reuse the EXECUTE_ALU state name from slice 1 rather
//    than a renamed generic EXECUTE — renaming would touch every
//    existing case label for no behavioral change, and the handoff
//    itself doesn't require a rename (§1's diagram calls it "EXECUTE"
//    informally, not as a literal identifier). Documented here so the
//    name isn't mistaken for "ALU-only."
//
// DEVIATIONS / ASSUMPTIONS specific to slice 2 (flagged per CLAUDE.md
// step 8 — none of these are stated outright in the handoff docs):
//
// 1. funct3 -> op_size_o for loads/stores is NOT given as a table
//    anywhere in the handoff (unlike alu_op_o, which has an explicit
//    decode table). Decoded here per the RISC-V spec's standard load/
//    store funct3 encoding: lb=000, lh=001, lw=010, lbu=100, lhu=101;
//    sb=000, sh=001, sw=010 (sign bit don't-care for stores per
//    handoff §5/§3). Cross-checked against RV32I spec, not invented.
//
// 2. address_o / core_data_o / core_data_i (handoff §4, guide-fixed
//    names) are NOT control_unit ports. The per-state table (handoff §9)
//    never shows the control unit driving address_o in any row, and
//    core_data_o/i are a pure datapath bus (ALU/regfile <-> LSU) with no
//    control logic gating the value itself — only oe_o/we_o gate
//    *when* that bus is sampled/committed. Those get wired directly at
//    top.v (slice 7), not through this module. Confirmed with user
//    before implementing (see conversation) rather than guessed.
//
// 3. bw_o's formula (handoff §5) needs address[1:0], but the control
//    unit does not compute the effective address (the ALU does, in
//    MEM_ADDR). So address[1:0] arrives here as a new INPUT,
//    addr_lsb_i, sourced from the ALU/adder result — not as part of an
//    address_o output this module owns. Confirmed with user.
//
// Recommended build order (handoff doc §11 / ALL_STAGES Part III):
//   1. FETCH -> DECODE -> EXECUTE(ALU only) -> WRITE BACK, verify in sim  [SLICE 1, DONE]
//   2. Add MEM_ADDR / MEM_ACCESS (load 2-cycle, store 1-cycle)           [THIS SLICE]
//   3. Add branch / jump cases inside EXECUTE
//   4. Add MUL / CRC / LUI / AUIPC / system no-op cases inside EXECUTE

// ---------------------------------------------------------------------
// Opcodes (IR[6:0])
// ---------------------------------------------------------------------
`define OPCODE_RTYPE   7'b0110011  // ALU R-type, MUL (Zmmul), CRC (Xicrc)
`define OPCODE_ITYPE   7'b0010011  // ALU I-type
`define OPCODE_LOAD    7'b0000011
`define OPCODE_STORE   7'b0100011
`define OPCODE_BRANCH  7'b1100011
`define OPCODE_JAL     7'b1101111
`define OPCODE_JALR    7'b1100111
`define OPCODE_LUI     7'b0110111
`define OPCODE_AUIPC   7'b0010111
`define OPCODE_SYSTEM  7'b1110011  // ECALL / EBREAK
`define OPCODE_FENCE   7'b0001111

// ---------------------------------------------------------------------
// funct12 / funct7 disambiguation
// ---------------------------------------------------------------------
`define FUNCT12_ECALL  12'h000
`define FUNCT12_EBREAK 12'h001
`define FUNCT7_MUL     7'b0000001
`define FUNCT7_CRC     7'b1000000

// ---------------------------------------------------------------------
// alu_op — Table 9
// ---------------------------------------------------------------------
`define ALU_PASS_B     4'h0
`define ALU_ADD        4'h1
`define ALU_SUB        4'h2
`define ALU_AND        4'h3
`define ALU_OR         4'h4
`define ALU_XOR        4'h5
`define ALU_SLL        4'h6
`define ALU_SRL        4'h7
`define ALU_MRS        4'h8  // SRA
`define ALU_SLT        4'h9
`define ALU_SLTU       4'hA

// ---------------------------------------------------------------------
// mult_op_o (Table 10) & crc_op_o (Table 11)
// ---------------------------------------------------------------------
`define MULT_MUL       4'h0
`define MULT_MULH      4'h1
`define MULT_MULHSU    4'h2
`define MULT_MULHU     4'h3

`define CRC_CRCB       4'h0
`define CRC_CRCH       4'h1
`define CRC_CRCW       4'h2

// ---------------------------------------------------------------------
// Multiplexer select lines
// ---------------------------------------------------------------------
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

// ---------------------------------------------------------------------
// Memory Map (Table 13)
// ---------------------------------------------------------------------
`define PC_RESET_ADDR    32'h00400000
`define IMEM_BASE        32'h00400000
`define DMEM_BASE        32'h10010000

// ---------------------------------------------------------------------
// op_size_o & imm_sel_o
// ---------------------------------------------------------------------
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

    // From IR — decode fields
    input  wire [6:0]  opcode_i,      // IR[6:0]
    input  wire [2:0]  funct3_i,      // IR[14:12]
    input  wire [6:0]  funct7_i,      // IR[31:25]
    // ECALL/EBREAK disambiguation. funct7_i cannot do this job: both
    // instructions have funct7 = 0000000 and differ only in IR[20], so
    // the full IR[31:20] field is required. Unused for every opcode
    // other than OPCODE_SYSTEM.
    input  wire [11:0] funct12_i,     // IR[31:20]

    // Slice 2: low address bits from the ALU/adder result (MEM_ADDR
    // computes rs1+imm), needed only to compute bw_o. Not an
    // address_o output owned by this module — see deviation note 3
    // above.
    input  wire [1:0]  addr_lsb_i,

    // Slice 3: comparator result, feeds the conditional pc_write_o for
    // branches (handoff §9 footnote — the only output that isn't a pure
    // function of state). Input, not output — hence _i.
    input  wire        branch_taken_i,

    // Datapath control — invented signals (handoff §3)
    output reg         pc_write_o,
    output reg  [1:0]  pc_src_o,
    output reg         ir_write_o,
    output reg         reg_write_o,
    output reg  [2:0]  result_src_o,
    output reg         alu_src_a_o,
    output reg  [1:0]  alu_src_b_o,
    // Declared alu_op_o per the handoff §3 convention (all CU outputs
    // take _o). Settled 2026-08-25: the block guide names no op-select
    // port anywhere — its Table 9 fixes the *encoding* only — so there
    // was never a guide-fixed bare "alu_op" to conflict with. alu.v
    // receives this as alu_op_i; both are built and passing.
    output reg  [3:0]  alu_op_o,
    output reg  [2:0]  imm_sel_o,
    // Slice 4: 4 bits each (handoff §7 item 7), direct funct3
    // passthrough (handoff §8), no lookup table. NOTE the missing _o
    // suffix — these are outputs, and every other output here has one.
    // The guide names no op-select port (verified 2026-08-25), so the
    // name is ours; renaming to mult_op_o/crc_op_o is still cheap while
    // nothing outside this file references them. Open.
    output reg  [3:0]  mult_op_o,
    output reg  [3:0]  crc_op_o,
    output reg         mult_en_o,
    output reg         crc_en_o,

    // Memory interface — guide-fixed names, must match exactly
    output reg         we_o,
    output reg         oe_o,
    output reg  [3:0]  bw_o,
    output reg  [2:0]  op_size_o,
    // Slice 7a: memory address mux select (top.v build plan §6 decision
    // D1). PC during FETCH, alu_out during the three memory-access
    // states. No owner existed before this slice — trap 4.
    output reg         adr_src_o,

    // Status output — not a datapath control signal, drives nothing
    // inside the core. Sticky: set when an ECALL retires, cleared only
    // by reset. See the halt_o block below for the full rationale.
    output reg         halt_o,

    // Derived enable outputs. top_structural.v (main rtl/) computes both
    // of these as inline expressions at the consuming instance's port:
    //   alu_out_reg.en_i     = !adr_src_o
    //   reg_mem_result.en_i  = (result_src_o == RESULT_SRC_MEM)
    // ChipInventor blocks only connect port-to-port with no inline-
    // expression nets, and its block library has no home for a bare gate,
    // so the same two expressions are computed here instead — in the
    // module that already owns both source signals. Not new architectural
    // signals: identical logic, moved upstream of the wire.
    output wire        not_adr_src_o,
    output wire        result_src_is_mem_o
);

    assign not_adr_src_o       = !adr_src_o;
    assign result_src_is_mem_o = (result_src_o == `RESULT_SRC_MEM);

    // ------------------------------------------------------------------
    // State encoding — localparam, not in defines.vh (never crosses a
    // module boundary per handoff §3).
    // ------------------------------------------------------------------
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

    // Slice 2: WRITE_BACK's result_src_o depends on which state led into
    // it (EXECUTE_ALU -> RESULT_SRC_ALU, MEM_ACCESS_DATA -> RESULT_SRC_MEM
    // — handoff §9's WRITE_BACK row says "carried from prior state" but
    // doesn't specify the mechanism). prev_state records that, read
    // combinationally by the output-logic block. Confirmed with user
    // rather than guessed.
    reg [3:0] prev_state;

    // ------------------------------------------------------------------
    // State register — sync reset (plan decision 1), NBA only.
    // ------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            state      <= RESET;
            prev_state <= RESET;
        end else begin
            prev_state <= state;
            state      <= next_state;
        end
    end

    // ------------------------------------------------------------------
    // halt_o — sticky ECALL status flag. Sequential, NBA, sync reset
    // (decision 12), own always block per CLAUDE.md step 4.
    //
    // WHAT IT IS: a status flag saying "an ECALL has retired". Its only
    // consumer is the system testbench, which waits on it instead of
    // guessing a cycle-count timeout for when firmware has finished.
    //
    // WHAT IT IS NOT: it does not stop the core. ECALL's execution
    // semantics are unchanged from slice 5 — still a no-op, still 3
    // cycles, PC still advances. Nothing inside this module reads
    // halt_o, so every one of the 48 pre-existing tests is unaffected
    // by construction.
    //
    // DEVIATION NOTE (CLAUDE.md step 8): the block guide never mentions
    // ECALL, halting, or trap handling at all — verified by full-text
    // search of the PDF, 2026-08-25. So there is no spec to comply with
    // here and no "correct" answer to look up. Two readings exist:
    //
    //   (a) ECALL flags completion, core keeps running   ← implemented
    //   (b) ECALL stops the core (PC frozen / HALT state)
    //
    // (a) is chosen because it is strictly weaker: it adds an observable
    // signal without changing any executed behavior, so it cannot break
    // firmware that uses ECALL mid-program for something other than
    // termination. (b) can be layered on top later by gating pc_write_o
    // on !halt_o — it is a one-line change from here, whereas starting
    // at (b) and discovering the firmware needs (a) is not.
    //
    // SET CONDITION: EXECUTE_ALU, not DECODE. The flag means "retired",
    // so it must not assert for an instruction that never executed.
    // ------------------------------------------------------------------
    wire is_ecall = (opcode_i  == `OPCODE_SYSTEM) &&
                    (funct3_i  == 3'b000)         &&
                    (funct12_i == `FUNCT12_ECALL);

    always @(posedge clk_i) begin
        if (rst_i) begin
            halt_o <= 1'b0;
        end else if ((state == EXECUTE_ALU) && is_ecall) begin
            halt_o <= 1'b1;
        end
        // else: hold. Sticky by design — a one-cycle pulse would be
        // missed by a testbench sampling on the wrong edge.
    end

    // ------------------------------------------------------------------
    // Illegal-opcode detection (handoff §8 — policy DECIDED: silent
    // no-op). True only for the eleven opcodes this core implements;
    // anything else is an illegal instruction.
    //
    // Without this, DECODE's else-branch routes an unknown opcode to
    // EXECUTE_ALU, which falls through to WRITE_BACK and asserts
    // reg_write_o — so an illegal instruction executed as an ADD and
    // clobbered rd. Confirmed in simulation before the fix (custom-0
    // opcode 7'b0001011 with rd=x6 overwrote x6). "Silent no-op" means
    // no architectural side effect at all: no register write, no memory
    // write, PC advances normally.
    // ------------------------------------------------------------------
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

    // ------------------------------------------------------------------
    // Next-state logic — combinational, blocking only.
    // ------------------------------------------------------------------
    always @(*) begin
        next_state = state; // default: hold (overwritten below)
        case (state)
            RESET:  next_state = FETCH;
            FETCH:  next_state = DECODE;

            DECODE: begin
                // Slice 2: DECODE starts reading opcode_i for real.
                // OPCODE_LOAD/OPCODE_STORE -> MEM_ADDR; everything else
                // (R-type/I-type ALU, and slice 3's branch/jump) falls
                // through to EXECUTE_ALU, same state for all of them
                // (handoff §1 — branch/jump are cases inside EXECUTE,
                // not separate states).
                if (opcode_i == `OPCODE_LOAD || opcode_i == `OPCODE_STORE)
                    next_state = MEM_ADDR;
                else
                    next_state = EXECUTE_ALU;
            end

            EXECUTE_ALU: begin
                // Slice 3: branch skips WRITE_BACK, loops straight to
                // FETCH (handoff §1 — branches produce no register
                // result). Slice 5: ECALL/EBREAK/FENCE no-ops do the
                // same — no register result, straight to FETCH. JAL/
                // JALR, ALU/I-type, MUL/CRC, and (slice 5) LUI/AUIPC all
                // still go to WRITE_BACK.
                // An illegal opcode takes this same skip-WRITE_BACK path
                // (handoff §8, silent no-op) — 3 cycles, no register
                // write, identical in shape to the system no-ops.
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
                // Effective address (rs1+imm) computed this cycle by the
                // ALU; branch on opcode to pick the load/store sub-path.
                if (opcode_i == `OPCODE_STORE)
                    next_state = MEM_ACCESS_STORE;
                else
                    next_state = MEM_ACCESS_ADDR;
            end

            MEM_ACCESS_ADDR: next_state = MEM_ACCESS_DATA;
            MEM_ACCESS_DATA: next_state = WRITE_BACK;
            MEM_ACCESS_STORE: next_state = FETCH; // store skips WRITE_BACK

            default: next_state = RESET;
        endcase
    end

    // ------------------------------------------------------------------
    // Output logic — combinational, blocking only. Every output gets a
    // default before the case, per CLAUDE.md rule 4 (no inferred latches).
    //
    // DEVIATION from handoff §4: that table shows "-" (don't care) in
    // many cells; this block fills them with concrete defaults (mostly
    // matching FETCH-state values) instead, purely to satisfy the
    // latch-avoidance requirement. Behavior is identical — the datapath
    // ignores these signals in states where they're "-".
    // ------------------------------------------------------------------
    // Slice 2: funct3 -> op_size_o lookup, shared by MEM_ADDR (stores
    // need only size, sign bit don't-care) and MEM_ACCESS_ADDR (loads
    // need size+sign). See deviation note 1 at top of file — this table
    // is not given explicitly in the handoff, decoded from the RISC-V
    // spec's standard load/store funct3 encoding.
    reg [2:0] op_size_lookup;
    always @(*) begin
        case (funct3_i)
            3'b000:  op_size_lookup = `OP_SIZE_BYTE_S; // lb / sb
            3'b001:  op_size_lookup = `OP_SIZE_HALF_S; // lh / sh
            3'b010:  op_size_lookup = `OP_SIZE_WORD;   // lw / sw
            3'b100:  op_size_lookup = `OP_SIZE_BYTE_U; // lbu
            3'b101:  op_size_lookup = `OP_SIZE_HALF_U; // lhu
            // Illegal funct3 within a legal load/store opcode. Distinct
            // from the illegal-OPCODE case (handoff §8, now decided —
            // see opcode_legal above): the instruction is still a load
            // or store, only its width field is undefined. Falls back to
            // word width. Unreachable for any RV32I encoding; kept for
            // latch avoidance.
            default: op_size_lookup = `OP_SIZE_WORD;
        endcase
    end

    // Slice 2: bw_o formula (handoff §5) — computed from op_size_lookup
    // and addr_lsb_i, combinational, reused by MEM_ADDR/MEM_ACCESS_ADDR/
    // MEM_ACCESS_STORE below.
    reg [3:0] bw_lookup;
    always @(*) begin
        case (op_size_lookup[2:1])
            2'b10: bw_lookup = 4'b1111; // word
            2'b01: bw_lookup = addr_lsb_i[1] ? 4'b1100 : 4'b0011; // half
            2'b00: bw_lookup = 4'b0001 << addr_lsb_i; // byte
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
                // all defaults
            end

            FETCH: begin
                pc_write_o = 1'b1;
                ir_write_o = 1'b1;
                oe_o       = 1'b1;
            end

            DECODE: begin
                // imm_sel_o per opcode (handoff §9 "per opcode"). Only
                // load/store are wired this slice; everything else
                // (R-type, and unwired opcodes from later slices) keeps
                // the IMM_SEL_I default, matching slice 1 behavior.
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
                    // Slice 3 (handoff §9/Slice-3 table). Do NOT decode
                    // funct3 here — that picks which comparison, which is
                    // the comparator's job (handoff explicit warning).
                    // pc_write_o is the one output that isn't a pure
                    // function of state: it follows branch_taken_i.
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
                    // Target = rs1 + imm, not PC + imm — alu_src_a_o
                    // differs from JAL for exactly this reason (handoff
                    // §9 Slice-3 table note).
                    pc_write_o   = 1'b1;
                    pc_src_o     = `PC_SRC_JALR;
                    alu_src_a_o  = `ALU_SRC_A_RS1;
                    alu_src_b_o  = `ALU_SRC_B_IMM;
                    alu_op_o     = `ALU_ADD;
                    imm_sel_o    = `IMM_SEL_I;
                    result_src_o = `RESULT_SRC_PC4;
                end else if (opcode_i == `OPCODE_LUI) begin
                    // Slice 5 (handoff §9/Slice-5 section). The only use
                    // of ALU_PASS_B — result is just the immediate,
                    // passed through the ALU unchanged.
                    alu_src_b_o = `ALU_SRC_B_IMM;
                    alu_op_o    = `ALU_PASS_B;
                    imm_sel_o   = `IMM_SEL_U;
                end else if (opcode_i == `OPCODE_AUIPC) begin
                    alu_src_a_o = `ALU_SRC_A_PC;
                    alu_src_b_o = `ALU_SRC_B_IMM;
                    alu_op_o    = `ALU_ADD;
                    imm_sel_o   = `IMM_SEL_U;
                end else if (opcode_i == `OPCODE_SYSTEM || opcode_i == `OPCODE_FENCE) begin
                    // Slice 5: ECALL/EBREAK/FENCE no-op (handoff §7
                    // decision 4). Advance to FETCH, write nothing,
                    // assert nothing — all defaults apply, nothing to
                    // set here.
                    //
                    // ECALL additionally raises the sticky halt_o
                    // status flag — see the halt_o always block above.
                    // That is handled there, not here: halt_o is
                    // sequential and this is the combinational output
                    // block, so driving it from both would be a
                    // multiple-driver error (CLAUDE.md step 5).
                    //
                    // Execution semantics stay identical for all three
                    // instructions: no-op, 3 cycles, PC advances.
                    // EBREAK and FENCE are genuinely finished this way
                    // — no debugger, no caches, nothing for either to
                    // do in this core. Only ECALL carries a remaining
                    // question, and it is now observable rather than
                    // silent.
                end else if (opcode_i == `OPCODE_RTYPE && funct7_i == `FUNCT7_MUL) begin
                    // Slice 4: Zmmul. Combinational/single-cycle, same
                    // EXECUTE_ALU state as everything else (handoff §7
                    // decision 1 — no MUL_WAIT). Direct funct3 passthrough
                    // (handoff §8), no lookup table. Gated on
                    // OPCODE_RTYPE explicitly (handoff §6's opcode map
                    // scopes funct7 disambiguation to opcode 0110011
                    // only) — I-type's IR[31:25] is immediate bits, not a
                    // real funct7, and could otherwise coincidentally
                    // match FUNCT7_MUL/CRC once slice 6 wires I-type in.
                    mult_en_o    = 1'b1;
                    mult_op_o      = {2'b00, funct3_i};
                    result_src_o = `RESULT_SRC_MUL;
                end else if (opcode_i == `OPCODE_RTYPE && funct7_i == `FUNCT7_CRC) begin
                    // Slice 4: Xicrc. Same pattern as MUL.
                    crc_en_o     = 1'b1;
                    crc_op_o       = {2'b00, funct3_i};
                    result_src_o = `RESULT_SRC_CRC;
                end else begin
                    // R-type ALU (else-fallthrough, handoff §5 trap:
                    // covers funct7 0000000 AND 0100000, never an
                    // equality check against either) AND I-type ALU
                    // (slice 6 — OPCODE_ITYPE has no funct7 field at all;
                    // IR[31:25] there is immediate bits, not a category
                    // selector, so it naturally falls through to this
                    // same else with no additional opcode check needed).
                    //
                    // Slice 6: I-type differs from R-type only in
                    // alu_src_b_o/imm_sel_o (immediate operand, not rs2).
                    // The alu_op_o decode table below is shared as-is.
                    if (opcode_i == `OPCODE_ITYPE) begin
                        alu_src_b_o = `ALU_SRC_B_IMM;
                        imm_sel_o   = `IMM_SEL_I;
                    end

                    // alu_op decode (handoff §6, reused by slice 6 per
                    // its "no change" instruction). funct3 000: R-type
                    // ADD/SUB need funct7[5]; I-type has no SUBI (handoff
                    // Slice-6 section — bit 30 in that position is
                    // immediate data, not a category bit), so ADDI must
                    // always decode as ADD regardless of that bit.
                    // funct3 101: SRLI/SRAI genuinely reuse the same bit
                    // position (instruction bit 30) as funct7[5] even
                    // though it's not a "funct7" for I-type — confirmed
                    // against the RISC-V spec (handoff explicit warning:
                    // getting this wrong makes srai silently execute as
                    // srli).
                    case (funct3_i)
                        3'b000: alu_op_o = (opcode_i != `OPCODE_ITYPE && funct7_i[5]) ? `ALU_SUB : `ALU_ADD;
                        3'b001: alu_op_o = `ALU_SLL;
                        3'b010: alu_op_o = `ALU_SLT;
                        3'b011: alu_op_o = `ALU_SLTU;
                        3'b100: alu_op_o = `ALU_XOR;
                        3'b101: alu_op_o = funct7_i[5] ? `ALU_MRS : `ALU_SRL;
                        3'b110: alu_op_o = `ALU_OR;
                        3'b111: alu_op_o = `ALU_AND;
                        // funct3_i is 3 bits and all eight values are
                        // covered above, so this arm is unreachable —
                        // kept only for latch avoidance. Illegal
                        // *opcodes* never reach here at all: they skip
                        // WRITE_BACK entirely (see opcode_legal above,
                        // handoff §8 silent-no-op policy), so alu_op_o's
                        // value is irrelevant for them.
                        default: alu_op_o = `ALU_ADD;
                    endcase
                end
            end

            MEM_ADDR: begin
                // Effective address = rs1 + imm (handoff §9 row).
                alu_src_a_o = `ALU_SRC_A_RS1;
                alu_src_b_o = `ALU_SRC_B_IMM;
                alu_op_o    = `ALU_ADD;
                imm_sel_o   = (opcode_i == `OPCODE_STORE) ? `IMM_SEL_S : `IMM_SEL_I;
                op_size_o   = op_size_lookup;
                bw_o        = bw_lookup;
            end

            MEM_ACCESS_ADDR: begin
                // Load, sub-cycle 1: present address to DMEM (registered-
                // output SRAM — data not valid until next cycle).
                oe_o      = 1'b1;
                op_size_o = op_size_lookup;
                adr_src_o = `ADR_SRC_ALU;
            end

            MEM_ACCESS_DATA: begin
                // Load, sub-cycle 2: DMEM's registered read data is valid
                // this cycle. Trap 3: op_size_o must stay driven here too
                // — this is the state result_src_o=RESULT_SRC_MEM is
                // consumed downstream by the LSU's extension logic, so
                // letting it fall back to the OP_SIZE_WORD default made
                // every lb/lh/lbu/lhu behave like lw. ir is unchanged
                // since DECODE, so op_size_lookup is still valid.
                // Trap 5: oe_o must stay asserted here too — imem.v is
                // combinational and its data_o collapses to 0 the instant
                // oe_i drops, so a load whose effective address lands in
                // IMEM read as zero. DMEM's data_o is a real register, so
                // re-asserting oe_o there just re-reads/re-latches the
                // same value — harmless. Depends on adr_src_o still
                // selecting alu_out here (D1), which it now does.
                result_src_o = `RESULT_SRC_MEM;
                op_size_o    = op_size_lookup;
                oe_o         = 1'b1;
                adr_src_o    = `ADR_SRC_ALU;
            end

            MEM_ACCESS_STORE: begin
                // Store: commit write this single cycle, then straight to
                // FETCH (no WRITE_BACK — handoff §1/§9).
                we_o      = 1'b1;
                op_size_o = op_size_lookup;
                bw_o      = bw_lookup;
                adr_src_o = `ADR_SRC_ALU;
            end

            WRITE_BACK: begin
                reg_write_o = 1'b1;
                // result_src_o depends on the path taken to get here
                // (see prev_state comment above). EXECUTE_ALU can mean
                // ALU result, (slice 3) JAL/JALR's PC+4 link value, or
                // (slice 4) MUL/CRC result — opcode_i/funct7_i still hold
                // the just-executed instruction's fields here since IR
                // isn't re-latched until FETCH, so they disambiguate
                // within the EXECUTE_ALU-sourced case.
                if (prev_state == MEM_ACCESS_DATA) begin
                    result_src_o = `RESULT_SRC_MEM;
                    // Trap 3, second half: the LSU's extension logic
                    // reads op_size_o here too (this is where
                    // reg_write_o actually commits the loaded/extended
                    // value), so it needs the same fix as
                    // MEM_ACCESS_DATA. ir is still unchanged since
                    // DECODE, so op_size_lookup is still valid — guarded
                    // on prev_state so non-load writers (ALU/MUL/CRC/
                    // JAL/JALR) don't get op_size_o overridden away from
                    // their don't-care default.
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
                // all defaults
            end
        endcase

        // --------------------------------------------------------------
        // Halt override (handoff §8 "ECALL semantics" — RESOLVED
        // 2026-08-26: the core STOPS, it does not merely flag).
        // Placed after the case deliberately: it must win over whatever
        // the current state drove, and both signals already have
        // defaults at the top of this block, so no latch is inferred.
        //
        // BOTH signals must be gated, not just pc_write_o as the handoff
        // originally sketched. Gating pc_write_o alone freezes pc at
        // (ECALL address + 4), but ir_write_o keeps firing every FETCH,
        // so the core reloads mem[ECALL+4] and re-executes that one
        // instruction forever — side effects included, so a store there
        // would repeat indefinitely. Freezing ir as well pins it at the
        // ECALL itself, which is a no-op that writes nothing, so the FSM
        // spins harmlessly through FETCH/DECODE/EXECUTE_ALU with no
        // architectural state change.
        //
        // halt_o is sticky and cleared only by reset, so this is a
        // permanent stop until the core is reset.
        // --------------------------------------------------------------
        if (halt_o) begin
            pc_write_o = 1'b0;
            ir_write_o = 1'b0;
        end
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
    // Debug tap for testbench observability (ChipInventor's canvas
    // compiler rejects hierarchical dot-refs into instance internals, so
    // x4 -- the organiser firmware's PASS/FAIL result register -- needs a
    // real port to be checkable from testbench.v). Not part of the guide
    // or team-fixed interface; simulation-only observability signal.
    output wire [31:0] x4_dbg_o
);

    reg [31:0] regs [0:31];

    integer i;

    // Async reads — x0 forced to zero even if somehow never reset-cleared.
    assign rs1_data_o = (rs1_addr_i == 5'd0) ? 32'b0 : regs[rs1_addr_i];
    assign rs2_data_o = (rs2_addr_i == 5'd0) ? 32'b0 : regs[rs2_addr_i];
    assign x4_dbg_o   = regs[4];

    // Sync write, x0 write-protected (guide §3.1.4: "hardwired (fixed) at
    // zero and cannot be modified"). Control unit asserts reg_write_o
    // regardless of rd — this guard is the only place that catches it.
    always @(posedge clk_i) begin
        if (rst_i) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (reg_write_i && rd_addr_i != 5'd0) begin
            regs[rd_addr_i] <= write_data_i;
        end
    end

endmodule


//  ---------- INLCUDED BLOCK: imm_extend_eq26  ---------- 
// imm_extend.v
// Guide §3.1.5. Extracts immediate per format, sign-extends to 32 bits.
module imm_extend_eq26(
    input  wire [31:0] instr_i,
    input  wire [2:0]  imm_sel_i,
    output reg  [31:0] imm_o
);
    // Immediate Format Selectors
    localparam [2:0] IMM_SEL_I = 3'b000; // I-type (ALU imm, loads, JALR)
    localparam [2:0] IMM_SEL_S = 3'b001; // S-type (stores)
    localparam [2:0] IMM_SEL_B = 3'b010; // B-type (branches)
    localparam [2:0] IMM_SEL_U = 3'b011; // U-type (LUI, AUIPC)
    localparam [2:0] IMM_SEL_J = 3'b100; // J-type (JAL)
    always @(*) begin
        imm_o = 32'b0; // default
        case (imm_sel_i)
            // I-type: instr[31:20], sign-extended
            IMM_SEL_I: imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
            // S-type: {instr[31:25], instr[11:7]}, sign-extended
            IMM_SEL_S: imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
            // B-type: {instr[31], instr[7], instr[30:25], instr[11:8], 0},
            // sign-extended. Implicit trailing zero (2-byte aligned).
            IMM_SEL_B: imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                                  instr_i[30:25], instr_i[11:8], 1'b0};
            // U-type: {instr[31:12], 12'b0} — no sign extension needed,
            // immediate occupies the upper bits directly.
            IMM_SEL_U: imm_o = {instr_i[31:12], 12'b0};
            // J-type: {instr[31], instr[19:12], instr[20], instr[30:21], 0},
            // sign-extended. Implicit trailing zero.
            IMM_SEL_J: imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                                  instr_i[20], instr_i[30:21], 1'b0};
            default: imm_o = 32'b0;
        endcase
    end
endmodule


//  ---------- INLCUDED BLOCK: branch_comparator_eq26  ---------- 
// branch_comparator.v
// Guide §3.1.6. Compares rs1/rs2 per funct3, drives branch_taken_o which
// arrives at the control unit as branch_taken_i.
//
// Combinational only: values in, value out, no clock, no state.

module branch_comparator_eq26(
    input  wire [31:0] rs1_i,
    input  wire [31:0] rs2_i,
    input  wire [2:0]  funct3_i,
    output reg  branch_taken_o
);

    // funct3 encodings are RV32I standard branch funct3 values (RISC-V
    // spec, not guide-defined — no macro exists for these in
    // rvbl2_defines.vh, so literals here are the spec encoding itself).
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
    input  wire [1:0]  alu_src_b_i,   // 00: RS2 data, 01: Imm, 10: Const 4
    input  wire [31:0] rs2_data_i,    // Data from RegFile rs2
    input  wire [31:0] imm_i,         // Sign-extended immediate
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


//  ---------- INLCUDED BLOCK: alu_eq26  ---------- 
module alu_eq26 (
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  alu_op_i,
    output reg  [31:0] result_o
);
    // ALU Operation Codes (Table 9)
    localparam [3:0] ALU_PASS_B = 4'h0;
    localparam [3:0] ALU_ADD    = 4'h1;
    localparam [3:0] ALU_SUB    = 4'h2;
    localparam [3:0] ALU_AND    = 4'h3;
    localparam [3:0] ALU_OR     = 4'h4;
    localparam [3:0] ALU_XOR    = 4'h5;
    localparam [3:0] ALU_SLL    = 4'h6;
    localparam [3:0] ALU_SRL    = 4'h7;
    localparam [3:0] ALU_MRS    = 4'h8; // SRA (arithmetic shift right)
    localparam [3:0] ALU_SLT    = 4'h9; // Set Less Than (signed)
    localparam [3:0] ALU_SLTU   = 4'hA; // Set Less Than Unsigned
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


//  ---------- INLCUDED BLOCK: mult_eq26  ---------- 
// mult.v
// Guide §3.1.2, Table 10. 32x32 -> 64-bit multiply, mux selects result half.
// Combinational, single cycle (handoff decision #1) — no MUL_WAIT state,
// no done handshake. Do not add one without an explicit area-tradeoff
// decision to do so.
//
// SYNTHESIS NOTE: full combinational 64-bit multiplier is the biggest area
// risk in the project (build plan §mult.v). Flag in OpenLane area report
// (report §5) once available; do not pre-optimize to an iterative version
// before measuring.

module mult_eq26(
    input  wire [31:0] a_i,
    input  wire [31:0] b_i,
    input  wire [3:0]  mult_op_i,
    output reg  [31:0] result_o
);

    // Multiplier Operation Codes (Table 10)
    localparam [3:0] MULT_MUL    = 4'h0;
    localparam [3:0] MULT_MULH   = 4'h1;
    localparam [3:0] MULT_MULHSU = 4'h2;
    localparam [3:0] MULT_MULHU  = 4'h3;

    // Each signedness combination extended to 64 bits independently before
    // multiplying — MULHSU is rs1 signed x rs2 unsigned, mixed extension.
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
/* With a D Flip-Flop:
 Cycle 4: LSU outputs 0x00000042.
          At the clock edge, the Flip-Flop SNAPS A PHOTO 📸 and freezes 0x00000042.
 Cycle 5: Even though the LSU input changes, the Flip-Flop holds the frozen photo!
          RegFile safely writes 0x00000042 into rd! 🎉
Summary:
A Wire changes instantaneously (0 delay).
A D Flip-Flop acts as a 1-cycle memory buffer (takes a snapshot at the clock edge and holds it stable for the next cycle). */


//  ---------- INLCUDED BLOCK: crc_eq26  ---------- 
// crc.v
// Guide §3.1.3, Table 11 (Xicrc). CRC-16/CCITT-FALSE over 8/16/32 bits of
// rs1, seeded by rs2. Parameters confirmed by organisers, verified against
// scripts/crc_reference.py and firmware/crc_test.S (all three chains ->
// 0x1E82). See docs/DATAPATH_BUILD_PLAN.md.
//
// NOTE operand roles are reversed from the usual incremental-CRC convention:
// a_i (rs1) is the DATA, b_i (rs2) is the running CRC SEED. Confirmed by the
// firmware's `crcb s0, s1, s0` (rd=s0, rs1=s1 data, rs2=s0 seed).
//
// Combinational only: guide §3.1.3 "without latency" — values in, value out,
// no clock, no state.

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


//  ---------- INLCUDED BLOCK: lsu_eq26  ---------- 
// lsu.v
// Guide §3.3. Combinational — sits between core and memory, handles
// byte/half/word selection + extension on loads, and positioning on
// stores.
//
// PORT NAMING (guide Figure 2, §3.3.3): names are from the CORE's
// perspective, so core_data_o / core_address_o / op_size_o are LSU
// INPUTS (they are the core's outputs). mem_data_i is also named from
// the core's naming convention carried into this module per
// MEMORY_BUILD_PLAN.md's port table (it's the LSU's read of the memory
// word, an LSU input). Matches Figure 2 exactly; directions commented
// per-port below since this is the easiest place in the project to wire
// backwards.
//
// bw_o is NOT generated here. The control unit already computes it
// (handoff decision #11, control_unit.v bw_lookup) from op_size + the
// low address bits. This module only positions data; if this were to
// grow byte-mask logic, that would duplicate the control unit's job.
//
// ============================================================================
// RESOLVED (was flagged for user decision; confirmed — reading (a) below is
// correct, and this implementation is right as written). Guide §3.3.1's
// repositioning paragraph illustrates BYTE SELECTION, not sign extension:
// it never names an instruction, sign extension already had its own worked
// examples earlier in the same section, the guide's explicit general rule
// for lb/lh contradicts the literal reading, and RISC-V settles it
// independently (lb sign-extends, unconditionally — a core returning
// 0x000000F3 for lb would fail the validation firmware). 0x000000F3 is the
// lbu result at that address. MEMORY_BUILD_PLAN.md has been corrected; its
// vector table previously repeated the guide's figure uncritically.
//
// Original analysis kept below — the reasoning is what justifies the call.
// ----------------------------------------------------------------------
// FLAG — Table 12 / guide §3.3.1 apparent inconsistency (do not silently
// resolve, per CLAUDE.md step 1/9 and MEMORY_BUILD_PLAN.md instruction):
//
// Guide §3.3.1 states plainly for lb/lh: "fill the rest of the register
// bits with the signal bit (MSB) value of the read value (signal
// extension)". Applied uniformly, lb at 0x10010002 (byte = 0xF3, MSB=1)
// should sign-extend to 0xFFFFFFF3.
//
// But guide's own worked text for repositioning says: "when reading the
// 0x10010002 address, only the 0xF3 byte ... will be placed in the
// register (which should then have the value 0x000000F3)" — i.e. NOT
// sign-extended, contradicting the general lb rule stated two paragraphs
// earlier in the same section. MEMORY_BUILD_PLAN.md's Table-12-vector
// list repeats this same value (0x000000F3) as a load golden vector.
//
// These two statements cannot both be literal en clair: either (a) the
// repositioning example is illustrating BYTE SELECTION only, independent
// of which load instruction (lb vs lbu) is used, and the guide simply
// didn't bother re-stating "for lbu" on that example — or (b) it's a
// genuine error in the guide's worked example, and a real lb at that
// address should read 0xFFFFFFF3 per the general rule.
//
// RESOLUTION TAKEN: implemented per the general rule in §3.3.1 (lb always
// sign-extends off the selected byte's MSB, regardless of which byte
// lane was selected) — this is the only internally-consistent reading of
// the *stated rule*, versus the *specific worked example* which never
// says outright which instruction (lb or lbu) produced 0x000000F3. Since
// the example prose only says "the 0xF3 byte ... will be placed in the
// register" without naming lb explicitly at that point, reading it as an
// lbu-style byte-select illustration (not a full lb load) resolves the
// conflict without contradicting the explicit signed-extension rule.
//
// Do not "fix" this by special-casing byte-lane 2 to skip sign extension;
// that would encode the contradiction instead of resolving it. lbu at the
// same address (0x000000F3) is unambiguous and is the better regression
// test — it passes under either reading.
// ============================================================================

module lsu_eq26(
    input  wire [31:0] core_data_o,     // INPUT: store data from core (rs2)
    input  wire [31:0] core_address_o,  // INPUT: effective address from core (uses [1:0])
    input  wire [2:0]  op_size_o,       // INPUT: from control unit
    input  wire [31:0] mem_data_o,      // INPUT: word read back from memory

    output reg  [31:0] core_data_i,     // OUTPUT: load result, extended, back to core
    output reg  [31:0] mem_data_i       // OUTPUT: store data, positioned, out to memory
);

    // Operation Size Encodings (from guide / handoff)
    localparam [2:0] OP_SIZE_BYTE_S = 3'b000; // lb / sb
    localparam [2:0] OP_SIZE_BYTE_U = 3'b001; // lbu
    localparam [2:0] OP_SIZE_HALF_S = 3'b010; // lh / sh
    localparam [2:0] OP_SIZE_HALF_U = 3'b011; // lhu
    localparam [2:0] OP_SIZE_WORD   = 3'b100; // lw / sw

    wire [1:0] byte_sel = core_address_o[1:0];

    // -----------------------------------------------------------------
    // Load path: select the addressed lane out of mem_data_o, extend.
    // -----------------------------------------------------------------
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

    // -----------------------------------------------------------------
    // Store path: position core_data_o's low bits into the addressed
    // lane. bw_o (which lane(s) actually get written) comes from the
    // control unit, not here — this only shifts the data into place.
    // Guide §3.3.2 example: writing 0x12 to 0x10010002 -> 0x00120000.
    // -----------------------------------------------------------------
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


//  ---------- INLCUDED BLOCK: mux_mem_addr  ---------- 
module mux_mem_addr (
    input  wire        adr_src_i,     // 0: PC, 1: ALU_Out
    input  wire [31:0] pc_i,          // Current PC address (Fetch)
    input  wire [31:0] alu_out_i,     // Calculated memory address (Load/Store)
    output wire [31:0] address_o      // Address sent to address_decoder
);

    assign address_o = adr_src_i ? alu_out_i : pc_i;

endmodule


//  ---------- INLCUDED BLOCK: address_decoder  ---------- 
// address_decoder.v
// Guide §4.4, Figure 3. Routes core memory requests to IMEM or DMEM
// based on address, and muxes the read data back to the core.
//
// - address_o: bottom 2 bits dropped (guide: "ignoring the bottom two
//   bits, alignment at 4 bytes") — both memories are word-addressed.
// - we_o -> DMEM only. IMEM has no write path at all (guide §4.4:
//   "EXCEPT IMEM memory, which cannot be written").
// - oe_o -> both devices.
// - bw_o -> DMEM only (guide: "sends the Byte Write signal ... ONLY to
//   the DMEM memory").
//
// Address ranges (guide Table 13):
//   IMEM: `IMEM_BASE (0x00400000) + 4 MB
//   DMEM: `DMEM_BASE (0x10010000) + 8 kB
//
// Unmapped addresses: guide is silent on behavior. Returns zero, asserts
// nothing — no bus-error mechanism invented. Flagged per CLAUDE.md step
// 8/MEMORY_BUILD_PLAN.md.
//
// FLAG: MEMORY_BUILD_PLAN.md's port table lists a core_data_i input
// (store data heading out) but no corresponding output toward DMEM/IMEM,
// and guide Figure 3 draws the decoder with only address/we/oe/bw
// arrows — no data path through it at all. Read literally, store data
// (LSU's mem_data_i) must wire directly from LSU to DMEM at top.v,
// bypassing the decoder entirely. Omitted that port here rather than
// wiring a dead input with no destination; flagging rather than
// silently guessing a route the guide never draws.

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

    // Memory Map Base Addresses (Guide Table 13)
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


//  ---------- INLCUDED BLOCK: imem  ---------- 
// imem.v
//
// INLINED FIRMWARE (ChipInventor constraint): ChipInventor's per-block
// canvas compiler cannot resolve `$readmemh("firmware/...")` any more
// than it can resolve `\`include "pkg/..."` -- both are file-path
// lookups outside the block's own text, and ChipInventor only ever sees
// one block's source at a time. Same fix as control_unit_eq26.v's
// inlined defines: no external file link, the data lives in the file.
//
// Content is firmware/organiser_validation.hex (259 words, official
// Stage 2 validation firmware) transcribed 1:1 into a case table,
// word-addressed (addr_i is already a word address from the address
// decoder, matching the main repo's imem.v/$readmemh addressing).
// Regenerate this table from the .hex file if the firmware is reissued
// -- do not hand-edit individual words.
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
// dmem.v
// Guide §4.3. 8 kB data SRAM at `DMEM_BASE (0x10010000).
//
// TIMING-CRITICAL: guide §4.3 states writes/reads via SRAM "will only be
// completed after a clock cycle" — registered-output, NOT combinational.
// The control unit's FSM has separate MEM_ACCESS_ADDR (present address,
// oe_o=1) and MEM_ACCESS_DATA (result_src_o=RESULT_SRC_MEM) states
// specifically because data isn't ready until the cycle after the
// address is presented. A combinational `assign data_o = mem[index]`
// would pass simulation (data arrives early, FSM reads a cycle late,
// looks fine) but fail in real SRAM. Built registered from the start.
//
// Byte-write: bw_i is a MASK (one bit per byte), not a binary selector
// (guide §4.3/§3.3.2, control unit computes it — decision #11, this
// module only applies it).
//
// Sizing: DEPTH_WORDS defaults to 2048 words = 8 kB, the guide's real
// size (guide is already small enough not to need shrinking for sim).

module dmem_eq26 #(
    parameter DEPTH_WORDS = 2048
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


// Automatically generated by ChipInventor Cloud EDA Tool - 3.15
// Careful: this file (hdl.v) will be automatically replaced
// when you ask tool to generate top Verilog code by clicking
// at BLOCKS button.

module top (

  input wire clk_i,
  input wire rst_i,
  output wire halt_o,
  // Debug/observability outputs -- simulation-only, not part of the
  // guide/team-fixed interface. Needed because ChipInventor's canvas
  // compiler rejects hierarchical dot-refs into instance internals, so
  // testbench.v cannot read pc/regfile contents any other way.
  output wire [31:0] pc_dbg_o,
  output wire [31:0] x4_dbg_o

);

// Internal nets
wire pc_write_o;
wire ir_write_o;
wire [31:0] pc_next;
wire [31:0] decoder_data_o;
wire [31:0] pc;
wire [31:0] old_pc;
wire [31:0] ir;
wire [1:0] pc_src_o;
wire [31:0] alu_result;
wire [6:0] opcode;
wire [4:0] rd_addr;
wire [2:0] funct3;
wire [4:0] rs1_addr;
wire [4:0] rs2_addr;
wire [6:0] funct7;
wire [11:0] funct12;
wire [1:0] addr_lsb;
wire branch_taken;
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
wire [31:0] mux_result;
wire [31:0] rs1_data;
wire [31:0] rs2_data;
wire [31:0] imm;
wire [31:0] mux_alu_a_out;
wire [31:0] mux_alu_b_out;
wire not_adr_src_o;
wire [31:0] alu_out;
wire [31:0] mult_result;
wire [31:0] mult_result_r;
wire [31:0] crc_result;
wire [31:0] crc_result_r;
wire [31:0] lsu_core_data_i;
wire [31:0] lsu_mem_data_i;
wire is_result_src_mem;
wire [31:0] mem_result;
wire [31:0] mux_mem_addr;
wire [31:0] dmem_data_o;
wire [31:0] imem_data_o;
wire [31:0] decoder_address_o;
wire dmem_we_o;
wire dmem_oe_o;
wire imem_oe_o;
wire [3:0] dmem_bw_o;

//Instances of Modules
fetch_registers u_fetch_registers (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .pc_write_i (pc_write_o),
         .ir_write_i (ir_write_o),
         .pc_next_i (pc_next[31:0]),
         .mem_data_i (decoder_data_o[31:0]),
         .pc_o (pc[31:0]),
         .old_pc_o (old_pc[31:0]),
         .ir_o (ir[31:0])
     );

mux_pc_next u_mux_pc_next (
         .pc_src_i (pc_src_o[1:0]),
         .pc_i (pc[31:0]),
         .alu_result_i (alu_result[31:0]),
         .pc_next_o (pc_next[31:0])
     );

ir_splitter_eq26 u_ir_splitter (
         .instr_i (ir[31:0]),
         .opcode_o (opcode[6:0]),
         .rd_o (rd_addr[4:0]),
         .funct3_o (funct3[2:0]),
         .rs1_o (rs1_addr[4:0]),
         .rs2_o (rs2_addr[4:0]),
         .funct7_o (funct7[6:0]),
         .funct12_o (funct12[11:0])
     );

control_unit_eq26 u_control_unit (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .opcode_i (opcode[6:0]),
         .funct3_i (funct3[2:0]),
         .funct7_i (funct7[6:0]),
         .funct12_i (funct12[11:0]),
         .addr_lsb_i (addr_lsb[1:0]),
         .branch_taken_i (branch_taken),
         .pc_write_o (pc_write_o),
         .pc_src_o (pc_src_o[1:0]),
         .ir_write_o (ir_write_o),
         .reg_write_o (reg_write_o),
         .result_src_o (result_src_o[2:0]),
         .alu_src_a_o (alu_src_a_o),
         .alu_src_b_o (alu_src_b_o[1:0]),
         .alu_op_o (alu_op_o[3:0]),
         .imm_sel_o (imm_sel_o[2:0]),
         .mult_op_o (mult_op_o[3:0]),
         .crc_op_o (crc_op_o[3:0]),
         .mult_en_o (mult_en_o),
         .crc_en_o (crc_en_o),
         .we_o (we_o),
         .oe_o (oe_o),
         .bw_o (bw_o[3:0]),
         .op_size_o (op_size_o[2:0]),
         .adr_src_o (adr_src_o),
         .halt_o (halt_o),
         .not_adr_src_o (not_adr_src_o),
         .result_src_is_mem_o (is_result_src_mem)
     );

regfile_eq u_regfile (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .rs1_addr_i (rs1_addr[4:0]),
         .rs2_addr_i (rs2_addr[4:0]),
         .rd_addr_i (rd_addr[4:0]),
         .write_data_i (mux_result[31:0]),
         .reg_write_i (reg_write_o),
         .rs1_data_o (rs1_data[31:0]),
         .rs2_data_o (rs2_data[31:0]),
         .x4_dbg_o (x4_dbg_o[31:0])
     );

assign pc_dbg_o = pc[31:0];

imm_extend_eq26 u_imm_extend (
         .instr_i (ir[31:0]),
         .imm_sel_i (imm_sel_o[2:0]),
         .imm_o (imm[31:0])
     );

branch_comparator_eq26 u_branch_comparator (
         .rs1_i (rs1_data[31:0]),
         .rs2_i (rs2_data[31:0]),
         .funct3_i (funct3[2:0]),
         .branch_taken_o (branch_taken)
     );

mux_alu_a u_mux_alu_a (
         .alu_src_a_i (alu_src_a_o),
         .rs1_data_i (rs1_data[31:0]),
         .old_pc_i (old_pc[31:0]),
         .a_o (mux_alu_a_out[31:0])
     );

mux_alu_b u_mux_alu_b (
         .alu_src_b_i (alu_src_b_o[1:0]),
         .rs2_data_i (rs2_data[31:0]),
         .imm_i (imm[31:0]),
         .b_o (mux_alu_b_out[31:0])
     );

alu_eq26 u_alu (
         .a_i (mux_alu_a_out[31:0]),
         .b_i (mux_alu_b_out[31:0]),
         .alu_op_i (alu_op_o[3:0]),
         .result_o (alu_result[31:0])
     );

alu_out_reg u_alu_out_reg (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (not_adr_src_o),
         .alu_result_i (alu_result[31:0]),
         .alu_out_o (alu_out[31:0]),
         .addr_lsb_o (addr_lsb[1:0])
     );

mult_eq26 u_mult (
         .a_i (rs1_data[31:0]),
         .b_i (rs2_data[31:0]),
         .mult_op_i (mult_op_o[3:0]),
         .result_o (mult_result[31:0])
     );

reg32_dff_eq26 u_reg_mult_result (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (mult_en_o),
         .d_i (mult_result[31:0]),
         .q_o (mult_result_r[31:0])
     );

crc_eq26 u_crc (
         .a_i (rs1_data[31:0]),
         .b_i (rs2_data[31:0]),
         .crc_op_i (crc_op_o[3:0]),
         .result_o (crc_result[31:0])
     );

reg32_dff_eq26 u_reg_crc_result (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (crc_en_o),
         .d_i (crc_result[31:0]),
         .q_o (crc_result_r[31:0])
     );

lsu_eq26 u_lsu (
         .core_data_o (rs2_data[31:0]),
         .core_address_o (alu_out[31:0]),
         .op_size_o (op_size_o[2:0]),
         .mem_data_o (decoder_data_o[31:0]),
         .core_data_i (lsu_core_data_i[31:0]),
         .mem_data_i (lsu_mem_data_i[31:0])
     );

reg32_dff_eq26 u_reg_mem_result (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .en_i (is_result_src_mem),
         .d_i (lsu_core_data_i[31:0]),
         .q_o (mem_result[31:0])
     );

mux_result u_mux_result (
         .result_src_i (result_src_o[2:0]),
         .alu_out_i (alu_out[31:0]),
         .mult_result_i (mult_result_r[31:0]),
         .crc_result_i (crc_result_r[31:0]),
         .mem_result_i (mem_result[31:0]),
         .old_pc_i (old_pc[31:0]),
         .result_o (mux_result[31:0])
     );

mux_mem_addr u_mux_mem_addr (
         .adr_src_i (adr_src_o),
         .pc_i (pc[31:0]),
         .alu_out_i (alu_out[31:0]),
         .address_o (mux_mem_addr[31:0])
     );

address_decoder u_addr_decoder (
         .address_i (mux_mem_addr[31:0]),
         .we_i (we_o),
         .oe_i (oe_o),
         .bw_i (bw_o[3:0]),
         .dmem_data_i (dmem_data_o[31:0]),
         .imem_data_i (imem_data_o[31:0]),
         .address_o (decoder_address_o[31:0]),
         .dmem_we_o (dmem_we_o),
         .dmem_oe_o (dmem_oe_o),
         .imem_oe_o (imem_oe_o),
         .bw_o (dmem_bw_o[3:0]),
         .data_o (decoder_data_o[31:0])
     );

imem u_imem (
         .clk_i (clk_i),
         .addr_i (decoder_address_o[31:0]),
         .oe_i (imem_oe_o),
         .data_o (imem_data_o[31:0])
     );

dmem_eq26 #(
    .DEPTH_WORDS (2048)
) u_dmem (
         .clk_i (clk_i),
         .rst_i (rst_i),
         .addr_i (decoder_address_o[31:0]),
         .we_i (dmem_we_o),
         .oe_i (dmem_oe_o),
         .bw_i (dmem_bw_o[3:0]),
         .data_i (lsu_mem_data_i[31:0]),
         .data_o (dmem_data_o[31:0])
     );


endmodule
