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

`include "pkg/rvbl2_defines.vh"

module control_unit (
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
    output reg         halt_o
);

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
