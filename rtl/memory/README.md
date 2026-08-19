# rtl/memory/ — owned by Teammate C

Register file, LSU, address decoder, IMEM, DMEM.

## Expected files

- `regfile.v` — 32×32-bit, x0 hardwired to zero (must silently discard
  writes to x0 — see `HANDOFF_control_unit.md` §8 open items), async
  read of rs1/rs2, sync write of rd.
- `lsu.v` — §3.3 of guide. Alignment, sign/zero extension (LB/LH/LBU/LHU),
  byte-write mask (`bw_o`) generation for SB/SH. `op_size_o` encoding is
  NOT yet defined — this module effectively owns that decision; write it
  up and share with Teammate A once settled.
- `address_decoder.v` — §4.4 of guide, Figure 3. Core-side ports named
  `we_i`/`oe_i`/`bw_i`/`address_i` (same wires as the core's `_o` outputs,
  opposite-end naming — see handoff doc §3). Routes `dmem_we_o` to DMEM
  only; IMEM gets no write path at all.
- `imem.v` — 4 MB ROM at `0x00400000` (`` `IMEM_BASE `` in
  `rvbl2_defines.vh`).
- `dmem.v` — 8 kB SRAM at `0x10010000` (`` `DMEM_BASE ``).
  **Critical timing detail:** must be registered-output (synchronous read)
  — address captured on a clock edge, data valid only on the *next* edge.
  This is what forces loads to take 2 sub-cycles in the FSM
  (`HANDOFF_control_unit.md` §7 item 2). Writes commit directly on the
  edge, no extra cycle needed.

## Ports

Guide-fixed signal names (`we_o`/`oe_o`/`bw_o`/`address_o` from the core
side, `dmem_we_o` on the decoder's DMEM-facing side) must match
`rtl/pkg/rvbl2_defines.vh` and `HANDOFF_control_unit.md` §3 exactly.

## Testbenches

Corresponding tests live in `tb/memory/`, not here. Table 12 of the block
guide (DMEM byte example, 0xF1/F2/F3/F4) is a ready-made golden test
vector set for LSU load variants — use it before inventing new ones.
