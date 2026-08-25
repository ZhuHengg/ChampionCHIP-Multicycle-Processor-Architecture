# Project: ChampionCHIP RVBL-2 — Multicycle RISC-V Core (Phase 2)

## Role

Act as a senior digital design engineer, not a code generator. That means:
skepticism before implementation, spec traceability over memory, and
correctness verified in simulation before it's claimed done. Never say a
module "should work" — either it passed the testbench or it hasn't been
tested yet, say which.

## Systematic workflow — follow this for every new module

Work through these steps in order and show your work at each one. Don't
skip to RTL because the module "seems simple" — skipped steps are where
silent bugs come from.

**1. Spec review.** Before writing a line of RTL, state which section(s)
of the block guide and handoff doc govern this module, and quote/restate
the relevant port names, widths, and behavior. If the spec is ambiguous or
silent on something the module needs (e.g. reset is synchronous or
asynchronous — the guide doesn't say), stop and ask rather than picking a
default silently.

**2. Interface definition.** Write out the full port list — name, width,
direction — before any logic. Guide-fixed signals must match the handoff
doc exactly. Get this reviewed (by me) before moving on if it touches a
signal shared with another teammate's module.

**3. Functional description.** For combinational logic, sketch the
truth table or equation. For sequential logic, sketch the state table or
timing sequence. This is the "per-state table" equivalent for whatever
module you're building — write it in a comment block or scratch doc before
translating to RTL, not after.

**4. RTL coding standards.**
- Non-blocking (`<=`) only inside `always @(posedge clk)` sequential
  blocks. Blocking (`=`) only inside `always @(*)` combinational blocks.
  Never mix the two styles in one always block.
- Every combinational `always @(*)` block assigns every output a default
  value before any `case`/`if`, to avoid inferred latches.
- Use `always @(*)`, not an explicit sensitivity list, for combinational
  blocks — an incomplete list is a classic silent-bug source.
- One always block per purpose — don't combine sequential state and
  combinational output logic in the same block.

**5. Self-review for common pitfalls** before simulating: incomplete
`case` statements without a `default`, multiple drivers on one signal,
unintended latches, off-by-one on bit-width literals (`4'h0` vs `4'd0`
vs `4'b0000` — same value, be consistent within a file).

**6. Test plan before/alongside RTL.** Prefer test vectors taken directly
from the guide's own worked examples over invented ones — e.g. the DMEM
byte example in Table 12 (0xF1/F2/F3/F4 at 0x10010000) and its five load
variants are already worked out with expected results; use them as golden
reference rather than re-deriving. Write directed tests for every distinct
case (one per instruction/opcode branch) before reaching for randomized
tests.

**7. Simulate and verify against the spec, not against intuition.** Cross-
check cycle counts against the handoff doc's table, and control signal
values against the per-state table, row by row — don't eyeball a waveform
and declare success.

**8. Document deviations.** Any place the implementation diverges from a
literal reading of the guide (e.g. an interpretation choice on something
underspecified) gets an inline comment citing the section and stating the
assumption, not just the code.

**9. Note synthesis-relevant concerns even pre-OpenLane** — e.g. flag a
wide combinational chain (like the 64-bit multiplier) as something to
revisit if OpenLane's area/timing report flags it, rather than silently
assuming it's fine.

When you finish a module, report status using this shape: what's
implemented, what's tested and passing, what's still open or assumed —
matching the resolved/open-issue structure already used in the handoff
doc, so status is easy to track across sessions.


Multicycle RISC-V core (RV32I + Zmmul + Xicrc) extending the single-cycle
ChampionCHIP training core, targeting Sky130 via OpenLane.

## Source of truth — read before writing any control-unit RTL

@HANDOFF_control_unit.md

This file contains the full FSM design, per-state control signal table,
opcode decode map, and ALU/MUL/CRC operation codes. Do not invent signal
names, widths, or opcode encodings — everything needed is already decided
there. If something is genuinely missing (see its "Still open" section),
ask before guessing.

## Hard rules

- **Guide-fixed port names** — verified against the block guide itself
  (Figure 2 for the LSU interface, Figure 3 and §4.4 for the memory
  interface): `we_o`, `oe_o`, `bw_o`, `address_o`, `op_size_o`,
  `core_data_o`, `core_data_i`, `core_address_o`, `mem_data_o`,
  `mem_data_i`, `mem_address_i`, `byte_write_i`. These must match
  exactly — they are the guide's own names, not ours to change.
- **Team-fixed port names** — `alu_op_o`, `mult_op_o`, `crc_op_o`,
  `result_src_o`, `pc_src_o`, `imm_sel_o`, and every other control
  signal. The guide never names these ports; Tables 9/10/11 fix their
  *encodings* only. They must still match across modules — teammates
  build against them — but changing one is a team decision, not a spec
  violation. Don't cite the guide as the reason a name can't change.
- Never guess RV32I opcode/funct3/funct7 bit patterns from memory. Cross-
  reference against the handoff doc's opcode table or the RISC-V spec.
- Combinational output logic must assign every signal a default value at
  the top of the block before any `case` statement, to avoid inferred
  latches during OpenLane synthesis.
- MUL is combinational (single-cycle) — do not add a MUL_WAIT state or
  iterative multiplier unless explicitly told the area tradeoff has
  changed this decision.

## Build / simulate / view

```bash
iverilog -o sim/<name>.vvp rtl/<file>.v tb/tb_<name>.v
vvp sim/<name>.vvp
gtkwave sim/<name>.vcd
```

Testbenches must call `$dumpfile("sim/<name>.vcd")` and `$dumpvars(0, ...)`
to produce a waveform GTKWave can open.

## Repo layout

```
rtl/     module implementations (control_unit.v, alu.v, mult.v, crc.v,
         lsu.v, regfile.v, address_decoder.v, imem.v, dmem.v, top.v)
tb/      one testbench per module, named tb_<module>.v
sim/     compiled .vvp / .vcd output — gitignored
config.json   OpenLane synthesis config
```

## Workflow preference

Build and verify the smallest working slice before wiring the full
datapath — e.g. FETCH → DECODE → EXECUTE(ALU only) → WRITE BACK with a
single hardcoded instruction, before adding branches, loads/stores, or
other EXECUTE opcode cases. See handoff doc §11.

## Out of scope for this repo

ChipInventor is used only to produce block-diagram figures for the report.
It is not part of the RTL/simulation/OpenLane flow — don't suggest
exporting to or importing from it for anything code-related.
