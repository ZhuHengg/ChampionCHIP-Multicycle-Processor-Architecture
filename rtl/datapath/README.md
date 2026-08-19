# rtl/datapath/ — owned by Teammate B

ALU, multiplier, CRC unit, branch comparator, immediate extender.

## Expected files

- `alu.v` — Table 9. 11 operations, `alu_op` 4 bits. Also used for
  address calc (loads/stores) and branch/jump target calc — reused
  hardware, not instruction-specific.
- `mult.v` — Table 10. `mult_op` is a **direct passthrough of funct3**
  (zero-extended) — see `rvbl2_defines.vh` and `HANDOFF_control_unit.md`
  §6. Decision: combinational, single cycle (§7 item 1 of handoff doc).
- `crc.v` — Table 11. `crc_op` also a **direct passthrough of funct3**.
- `branch_comparator.v` — §3.1.6 of guide. Evaluates rs1/rs2 per funct3,
  signed/unsigned aware, outputs `branch_taken`.
- `imm_extend.v` — §3.1.5 of guide. Decodes I/S/B/U/J immediate formats.
  Note: `imm_sel` encoding is NOT yet defined anywhere (not in the guide,
  not yet decided by the team) — coordinate with Teammate A before
  finalizing this module's select input.

## Ports

Match `alu_op`/`mult_op`/`crc_op` widths and values exactly against
`rtl/pkg/rvbl2_defines.vh` — don't re-derive from the guide tables
independently, use the shared header.

## Testbenches

Corresponding tests live in `tb/datapath/`, not here.
