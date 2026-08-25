// top.v — owned by Teammate A (control unit) per build order in
// docs/TOP_BUILD_PLAN.md.
//
// SLICE 7b SCOPE (done): fetch path only. Proves instructions arrive at
// the IR in program order and pc/old_pc behave (trap 1). Modules
// instantiated: control_unit, imem, address_decoder.
//
// SLICE 7c SCOPE (done): + regfile, ALU, imm_extend, alu_out register,
// mux_alu_a/mux_alu_b/mux_result. R-type and I-type ALU instructions
// execute end to end and write back.
//
// SLICE 7d SCOPE (done): + branch_comparator, real branch_taken_i.
// Branches (all six funct3) and jumps (JAL/JALR) now change control flow
// for real. mux_pc_next's TARGET/JALR arms (wired since 7c) go live.
// Fixed trap 6 (RESULT_SRC_PC4 must be old_pc+4, not pc — see deviation
// note 2).
//
// SLICE 7e SCOPE (this slice): + dmem, lsu, real mux_mem_addr ALU arm.
// Loads (lw/lh/lhu/lb/lbu) and stores (sw/sh/sb) execute end to end
// against DMEM, and lw from IMEM works (guide §4.2). Fixed trap 7 (see
// deviation note 5). Still no MUL/CRC (7f).
//
// Governing source: docs/TOP_BUILD_PLAN.md §2 (registers/muxes top.v
// must create), §3 traps 1/2/6/7 (old_pc vs live pc, alu_out register vs
// live ALU, RESULT_SRC_PC4 vs redirected pc, alu_out clobbered during
// MEM_ACCESS_*), §4 (wiring table), §5 (slice list, this is 7e).
//
// DEVIATIONS / ASSUMPTIONS (CLAUDE.md step 8):
//
// 1. pc, old_pc, and ir share one always block instead of one register
//    per block. TOP_BUILD_PLAN.md §2 asks for this explicitly: "Both
//    registers load in the same cycle (FETCH), and old_pc captures pc
//    *before* the increment — non-blocking assignment in the same
//    always block gives you this for free, which is the point." Treated
//    as one CLAUDE.md-step-4 "purpose" (the fetch-stage register file),
//    not three. NBA semantics would give the same pre-increment capture
//    even split across blocks (all RHS reads use pre-edge values
//    regardless of block), but the plan's stated intent is one block —
//    followed as written rather than silently split.
//
// 2. alu_out is a real register (trap 2): loads from the live ALU output
//    every cycle, no load enable, per TOP_BUILD_PLAN.md §2's table
//    ("Loaded when: every cycle"). mux_result's RESULT_SRC_ALU arm taps
//    this register, not the live alu.result_o — WRITE_BACK leaves
//    alu_src_a_o/alu_src_b_o/alu_op_o at their RS1/RS2/PASS_B defaults,
//    so the live ALU output during WRITE_BACK is rs2_data, not the
//    value computed a cycle earlier in EXECUTE_ALU. mux_pc_next's
//    TARGET/JALR arms and control_unit.addr_lsb_i need the opposite tap
//    (live alu_result / registered alu_out respectively) — see trap 2
//    in the plan and the mux_pc_next/control_unit instantiation comments
//    below for which is which.
//
//    RESULT_SRC_PC4 (JAL/JALR's link value) is a related but distinct
//    bug, found this slice and not documented in the plan as trap 6:
//    "already incremented" was true when this arm read plain pc for
//    ordinary instructions, but JAL/JALR redirect pc to the jump target
//    inside EXECUTE_ALU (pc_write_o=1, PC_SRC_TARGET/PC_SRC_JALR), so by
//    WRITE_BACK pc holds the *target*, not pc+4. Fixed: mux_result's
//    RESULT_SRC_PC4 arm now computes old_pc+4 directly (old_pc is stable
//    across an instruction's full 4 cycles since ir_write_o only fires
//    in FETCH) instead of reading the (possibly-redirected) pc register.
//
// 3. branch_comparator is now instantiated (slice 7d); control_unit's
//    branch_taken_i is wired to its live branch_taken_o, not tied off.
//
// 4. mux_result's MUL/CRC arms are tied to 32'b0 this slice — no
//    mult/crc module instantiated yet (7f). Named per the slice that
//    fills them in so they aren't mistaken for finished wiring.
//
// 5. alu_out no longer loads every cycle (trap 7) — TOP_BUILD_PLAN.md
//    §2's table says "every cycle", and that was correct through slice
//    7d (nothing depended on alu_out surviving past the cycle it was
//    computed). Loads break it: MEM_ACCESS_ADDR leaves
//    alu_src_a_o/alu_src_b_o/alu_op_o at their RS1/RS2/PASS_B defaults
//    (control_unit.v:525-531 drives only oe_o/op_size_o/adr_src_o), so
//    the live ALU output during that state is rs2_data — for an I-type
//    load ir[24:20] is immediate bits, not a real rs2 field, so this is
//    effectively garbage. Left alu_out loading unconditionally, that
//    garbage overwrites the effective address one cycle after MEM_ADDR
//    computed it correctly, and MEM_ACCESS_DATA presents the wrong
//    address to DMEM. Fixed: alu_out now loads only when adr_src_o is
//    ADR_SRC_PC (i.e. NOT during MEM_ACCESS_ADDR/MEM_ACCESS_DATA/
//    MEM_ACCESS_STORE, the three states adr_src_o=ADR_SRC_ALU covers) —
//    freezing the effective address for the memory path's own three
//    cycles, then resuming normal every-cycle loading everywhere else
//    (including WRITE_BACK, where ALU/I-type/MUL/CRC results still need
//    the register to update from that state's live ALU result the
//    following edge — no regression for the non-memory instruction
//    classes since adr_src_o is ADR_SRC_PC in all of their states).
//    MEM_ADDR itself does not assert adr_src_o (control_unit.v's D1
//    table), so the effective address still latches normally at the end
//    of MEM_ADDR, unaffected by this change.
//
// 6. mem_result register added — NOT in TOP_BUILD_PLAN.md §2's table,
//    and contradicts its explicit claim that "an MDR is not required"
//    (found this slice; that claim's own reasoning only covers DMEM).
//    lsu.core_data_i is combinational from mem_data_o (=decoder_data_o),
//    op_size_o, and core_address_o. During MEM_ACCESS_DATA all three are
//    correct (adr_src_o=ADR_SRC_ALU keeps mux_mem_addr=alu_out routed at
//    the right device, oe_o is held per trap 5, op_size_o is held per
//    trap 3) and lsu.core_data_i is a valid extended load result. But by
//    WRITE_BACK, adr_src_o has reverted to ADR_SRC_PC (its default) so
//    mux_mem_addr=pc — always inside IMEM's address range — and
//    address_decoder.data_o RE-ROUTES to the imem_data_i branch based on
//    that CURRENT address, regardless of which device the load actually
//    read from. Confirmed in simulation: this breaks even a plain DMEM
//    lw (decoder_data_o reads back 0 at WRITE_BACK, sourced from
//    imem_data_o, which is itself 0 because oe_o is not asserted in
//    WRITE_BACK and imem.v is purely combinational). Wiring mem_data_o
//    to dmem_data_o directly (bypassing the decoder, mirroring the
//    store-data path) would fix DMEM loads alone, but IMEM loads (guide
//    §4.2) have no register at all in imem.v — there is no live signal
//    at WRITE_BACK, decoder-routed or not, that can recover an IMEM
//    load's value once oe_o drops. The only fix available from top.v
//    (control_unit.v/memory/ are off-limits this slice) is to capture
//    the LSU's already-fully-computed output at the moment it's valid
//    and hold it: mem_result loads lsu_core_data_i whenever
//    result_src_o==RESULT_SRC_MEM, which is true both in MEM_ACCESS_DATA
//    (when the capture is correct) and in the following WRITE_BACK
//    (when the load fires again using the by-then-stale live value, but
//    harmlessly — same reasoning as alu_out/trap 7: the register's
//    WRITE_BACK-edge update happens after write_data_i has already been
//    sampled by the regfile using the value held from the prior edge).
//    mux_result's RESULT_SRC_MEM arm reads this register, not the live
//    lsu_core_data_i wire.
//
// Wiring notes from the plan, restated here because they are exactly
// where a fetch-path bug hides:
// - address_decoder.address_o is [29:0] (bottom two bits already
//   dropped). imem.addr_i and dmem.addr_i are both [31:0] word
//   addresses. Zero-extended with {2'b00, ...} for both — not shifted
//   again.
// - ir loads from address_decoder.data_o, not imem.data_o directly, and
//   lsu.mem_data_o (the load path's read of memory) reuses that same
//   decoder_data_o net — one read-back path serves both fetch and loads.

`include "pkg/rvbl2_defines.vh"

module top #(
    parameter IMEM_DEPTH_WORDS = 1024,
    parameter IMEM_INIT_FILE   = ""
) (
    input  wire clk_i,
    input  wire rst_i,
    output wire halt_o
);

    // ------------------------------------------------------------------
    // Fetch-stage registers.
    // ------------------------------------------------------------------
    reg [31:0] pc;
    reg [31:0] old_pc;
    reg [31:0] ir;

    // alu_out — trap 2: registered ALU output. Loaded every cycle except
    // while the memory path owns the address (trap 7). See deviation
    // notes 2 and 5 above.
    reg [31:0] alu_out;

    // mem_result — captured load result, held through WRITE_BACK. See
    // deviation note 6 above.
    reg [31:0] mem_result;

    // ------------------------------------------------------------------
    // Control unit <-> datapath wiring.
    // ------------------------------------------------------------------
    wire        pc_write_o;
    wire [1:0]  pc_src_o;
    wire        ir_write_o;
    wire        reg_write_o;
    wire [2:0]  result_src_o;
    wire        alu_src_a_o;
    wire [1:0]  alu_src_b_o;
    wire [3:0]  alu_op_o;
    wire [2:0]  imm_sel_o;
    wire        we_o;
    wire        oe_o;
    wire [3:0]  bw_o;
    wire        adr_src_o;

    // Memory-path nets, declared here (ahead of the register block that
    // reads decoder_data_o) — Icarus requires nets declared before use.
    wire [29:0] decoder_address_o;
    wire [31:0] decoder_data_o;
    wire        imem_oe_o;
    wire [31:0] imem_data_o;

    // Regfile / ALU / immediate-extender nets.
    wire [31:0] rs1_data;
    wire [31:0] rs2_data;
    wire [31:0] imm;
    wire [31:0] alu_result; // live ALU output — trap 2, do not tap for RESULT_SRC_ALU
    wire        branch_taken;

    // Tie-offs — not yet computed by any module this slice. See
    // deviation note 4 above.
    wire [31:0] mult_result = 32'b0; // slice 7f
    wire [31:0] crc_result  = 32'b0; // slice 7f

    // DMEM / LSU nets.
    wire [31:0] dmem_data_o;
    wire        dmem_we_o;
    wire        dmem_oe_o;
    wire [3:0]  dmem_bw_o;
    wire [2:0]  op_size_o;
    wire [31:0] lsu_core_data_i;
    wire [31:0] lsu_mem_data_i;

    // ------------------------------------------------------------------
    // mux_pc_next — combinational, blocking only, full case + default
    // (CLAUDE.md rule: every case gets a default, every output a
    // default before the case).
    // ------------------------------------------------------------------
    reg [31:0] mux_pc_next;
    always @(*) begin
        mux_pc_next = pc + 32'd4; // default
        case (pc_src_o)
            `PC_SRC_PLUS4:  mux_pc_next = pc + 32'd4;
            // Live alu_result, not alu_out (trap 2, PC side): pc_write_o
            // fires during EXECUTE_ALU, the same cycle the ALU computes
            // the branch/jump target — alu_out does not latch it until
            // the following edge.
            `PC_SRC_TARGET: mux_pc_next = alu_result;
            // RISC-V spec: jalr target = (rs1 + imm) & ~1 — clear bit 0.
            `PC_SRC_JALR:   mux_pc_next = {alu_result[31:1], 1'b0};
            default:        mux_pc_next = pc + 32'd4;
        endcase
    end

    // ------------------------------------------------------------------
    // mux_mem_addr — combinational, blocking only, full case + default.
    // ------------------------------------------------------------------
    reg [31:0] mux_mem_addr;
    always @(*) begin
        mux_mem_addr = pc; // default
        case (adr_src_o)
            `ADR_SRC_PC:  mux_mem_addr = pc;
            `ADR_SRC_ALU: mux_mem_addr = alu_out;
            default:      mux_mem_addr = pc;
        endcase
    end

    // ------------------------------------------------------------------
    // mux_alu_a / mux_alu_b — ALU source operand muxes, combinational,
    // blocking only, full case + default.
    // ------------------------------------------------------------------
    reg [31:0] mux_alu_a;
    always @(*) begin
        mux_alu_a = rs1_data; // default
        case (alu_src_a_o)
            `ALU_SRC_A_RS1: mux_alu_a = rs1_data;
            `ALU_SRC_A_PC:  mux_alu_a = old_pc; // trap 1 — NOT pc
            default:        mux_alu_a = rs1_data;
        endcase
    end

    reg [31:0] mux_alu_b;
    always @(*) begin
        mux_alu_b = rs2_data; // default
        case (alu_src_b_o)
            `ALU_SRC_B_RS2:    mux_alu_b = rs2_data;
            `ALU_SRC_B_IMM:    mux_alu_b = imm;
            `ALU_SRC_B_CONST4: mux_alu_b = 32'd4;
            default:           mux_alu_b = rs2_data;
        endcase
    end

    // ------------------------------------------------------------------
    // mux_result — register write-back data mux, combinational, blocking
    // only, full case + default.
    // ------------------------------------------------------------------
    reg [31:0] mux_result;
    always @(*) begin
        mux_result = alu_out; // default
        case (result_src_o)
            `RESULT_SRC_ALU: mux_result = alu_out;         // trap 2 — the REGISTER
            `RESULT_SRC_MUL: mux_result = mult_result;      // slice 7f
            `RESULT_SRC_CRC: mux_result = crc_result;       // slice 7f
            `RESULT_SRC_MEM: mux_result = mem_result; // trap 8 — the REGISTER, not live lsu_core_data_i
            // trap 6: NOT pc — pc has already been redirected to the
            // jump target by JAL/JALR's pc_write_o inside EXECUTE_ALU,
            // so it no longer holds "this instruction's address + 4" by
            // the time WRITE_BACK reads it. old_pc is stable across the
            // whole instruction (only reloaded in FETCH), so old_pc+4 is
            // the correct return-address computation regardless of what
            // pc has been redirected to.
            `RESULT_SRC_PC4: mux_result = old_pc + 32'd4;
            default:         mux_result = alu_out;
        endcase
    end

    // ------------------------------------------------------------------
    // Fetch-stage register file — sync reset (decision 12), NBA only.
    // pc and old_pc/ir share this block so old_pc's read of pc happens
    // against the pre-edge value regardless of scheduling order (trap
    // 1) — see deviation note 1.
    // ------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i) begin
            pc     <= `PC_RESET_ADDR;
            old_pc <= 32'b0;
            ir     <= 32'b0;
        end else begin
            if (pc_write_o)
                pc <= mux_pc_next;
            if (ir_write_o) begin
                old_pc <= pc;              // pre-increment value (trap 1)
                ir     <= decoder_data_o;
            end
        end
    end

    // ------------------------------------------------------------------
    // alu_out register — trap 2 (which value: register vs live) and
    // trap 7 (when it may load). Own always block per CLAUDE.md step 4.
    // Loads every cycle EXCEPT while the memory path owns the address
    // (adr_src_o=ADR_SRC_ALU, i.e. MEM_ACCESS_ADDR/_DATA/_STORE) — see
    // deviation note 5. adr_src_o is 0 (ADR_SRC_PC) in every other
    // state, including WRITE_BACK, so non-memory instructions still get
    // an every-cycle-loading alu_out exactly as before.
    // ------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i)
            alu_out <= 32'b0;
        else if (!adr_src_o) // trap 7: freeze the effective address while
            alu_out <= alu_result; // MEM_ACCESS_* is using it
    end

    // ------------------------------------------------------------------
    // mem_result register — trap 8. Own always block per CLAUDE.md step
    // 4. Captures the LSU's extended load result while result_src_o
    // selects it (true in both MEM_ACCESS_DATA, when the capture is
    // correct, and the following WRITE_BACK, when the reload is
    // harmless — see deviation note 6).
    // ------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (rst_i)
            mem_result <= 32'b0;
        else if (result_src_o == `RESULT_SRC_MEM)
            mem_result <= lsu_core_data_i;
    end

    // ------------------------------------------------------------------
    // Module instances.
    // ------------------------------------------------------------------
    control_unit u_control_unit (
        .clk_i          (clk_i),
        .rst_i          (rst_i),
        .opcode_i       (ir[6:0]),
        .funct3_i       (ir[14:12]),
        .funct7_i       (ir[31:25]),
        .funct12_i      (ir[31:20]),
        .addr_lsb_i     (alu_out[1:0]), // register, not live ALU — plan §4
        .branch_taken_i (branch_taken),
        .pc_write_o     (pc_write_o),
        .pc_src_o       (pc_src_o),
        .ir_write_o     (ir_write_o),
        .reg_write_o    (reg_write_o),
        .result_src_o   (result_src_o),
        .alu_src_a_o    (alu_src_a_o),
        .alu_src_b_o    (alu_src_b_o),
        .alu_op_o       (alu_op_o),
        .imm_sel_o      (imm_sel_o),
        .mult_op_o      (),        // slice 7f
        .crc_op_o       (),        // slice 7f
        .mult_en_o      (),        // slice 7f
        .crc_en_o       (),        // slice 7f
        .we_o           (we_o),
        .oe_o           (oe_o),
        .bw_o           (bw_o),
        .op_size_o      (op_size_o),
        .adr_src_o      (adr_src_o),
        .halt_o         (halt_o)
    );

    address_decoder u_addr_decoder (
        .address_i    (mux_mem_addr),
        .we_i         (we_o),
        .oe_i         (oe_o),
        .bw_i         (bw_o),
        .dmem_data_i  (dmem_data_o),
        .imem_data_i  (imem_data_o),
        .address_o    (decoder_address_o),
        .dmem_we_o    (dmem_we_o),
        .dmem_oe_o    (dmem_oe_o),
        .imem_oe_o    (imem_oe_o),
        .bw_o         (dmem_bw_o),
        .data_o       (decoder_data_o)
    );

    imem #(
        .DEPTH_WORDS (IMEM_DEPTH_WORDS),
        .INIT_FILE   (IMEM_INIT_FILE)
    ) u_imem (
        .clk_i  (clk_i),
        .addr_i ({2'b00, decoder_address_o}), // zero-extend 30->32, not shifted again
        .oe_i   (imem_oe_o),
        .data_o (imem_data_o)
    );

    regfile u_regfile (
        .clk_i        (clk_i),
        .rst_i        (rst_i),
        .rs1_addr_i   (ir[19:15]),
        .rs2_addr_i   (ir[24:20]),
        .rd_addr_i    (ir[11:7]),
        .write_data_i (mux_result),
        .reg_write_i  (reg_write_o),
        .rs1_data_o   (rs1_data),
        .rs2_data_o   (rs2_data)
    );

    alu u_alu (
        .a_i      (mux_alu_a),
        .b_i      (mux_alu_b),
        .alu_op_i (alu_op_o),
        .result_o (alu_result)
    );

    imm_extend u_imm_extend (
        .instr_i   (ir),
        .imm_sel_i (imm_sel_o),
        .imm_o     (imm)
    );

    branch_comparator u_branch_comparator (
        .rs1_i          (rs1_data),
        .rs2_i          (rs2_data),
        .funct3_i       (ir[14:12]),
        .branch_taken_o (branch_taken)
    );

    dmem u_dmem (
        .clk_i  (clk_i),
        .rst_i  (rst_i),
        .addr_i ({2'b00, decoder_address_o}), // zero-extend 30->32, not shifted again
        .we_i   (dmem_we_o),
        .oe_i   (dmem_oe_o),
        .bw_i   (dmem_bw_o),
        .data_i (lsu_mem_data_i),
        .data_o (dmem_data_o)
    );

    // LSU port names are from the CORE's perspective (guide Figure 2) —
    // core_data_o/core_address_o/op_size_o/mem_data_o are LSU INPUTS.
    // core_address_o taps alu_out (the register), not mux_mem_addr: in
    // WRITE_BACK (where core_data_i is actually sampled into the
    // regfile) adr_src_o has returned to ADR_SRC_PC, so mux_mem_addr is
    // pc — always word-aligned, so every lb/lh at a nonzero byte offset
    // would collapse to lane 0. alu_out still holds the effective
    // address during WRITE_BACK (trap 7, deviation note 5), so it's the
    // correct tap. mem_data_i (store data, positioned) bypasses the
    // decoder straight to dmem.data_i — the decoder has no store-data
    // port (address_decoder.v's own header FLAG; guide Figure 3 draws no
    // data path through it).
    lsu u_lsu (
        .core_data_o    (rs2_data),
        .core_address_o (alu_out),
        .op_size_o      (op_size_o),
        .mem_data_o     (decoder_data_o),
        .core_data_i    (lsu_core_data_i),
        .mem_data_i     (lsu_mem_data_i)
    );

endmodule
