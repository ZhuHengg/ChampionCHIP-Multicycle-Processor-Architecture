# rtl/datapath/ — shared across all four

ALU, multiplier, CRC unit, branch comparator, immediate extender.

**Ownership changed:** this folder was originally Teammate B's alone; under
the current split (2 on FSM, 2 on memory) it is shared by all four. That
means nobody specifically owns any given module — **assign these five before
starting**, or you get two people building `alu.v` and nobody building
`crc.v`. See `docs/DATAPATH_BUILD_PLAN.md` for scope, order, and per-module
detail.

## Expected files

- `alu.v` — Table 9. 11 operations, `alu_op` 4 bits. Also used for
  address calc (loads/stores) and branch/jump target calc — reused
  hardware, not instruction-specific.
- `mult.v` — Table 10. `mult_op` is a **direct passthrough of funct3**
  (zero-extended) — see `rvbl2_defines.vh` and `HANDOFF_control_unit.md`
  §6. Decision: combinational, single cycle (§7 item 1 of handoff doc).
- `crc.v` — Table 11. `crc_op` also a **direct passthrough of funct3**.
  ⚠ **Blocked — the guide never states the CRC polynomial, initial value,
  bit ordering, or reflection.** Table 11 gives only `rd = CRC8(rs1,
  rs2)[15:0]`. Those missing parameters determine whether your output
  matches the validation firmware. Do not guess — see the build plan.
- `branch_comparator.v` — §3.1.6 of guide. Evaluates rs1/rs2 per funct3,
  signed/unsigned aware, outputs `branch_taken` (arrives at the control
  unit as `branch_taken_i`).
- `imm_extend.v` — §3.1.5 of guide. Decodes I/S/B/U/J immediate formats.
  **`imm_sel_o` encoding is now decided** — `000`=I, `001`=S, `010`=B,
  `011`=U, `100`=J, with `` `IMM_SEL_* `` macros in `rvbl2_defines.vh`.
  (This README previously said it was undecided; that's stale.)

## Ports

Match `alu_op`/`mult_op`/`crc_op` widths and values exactly against
`rtl/pkg/rvbl2_defines.vh` — don't re-derive from the guide tables
independently, use the shared header.

## Testbenches

Corresponding tests live in `tb/datapath/`, not here.
