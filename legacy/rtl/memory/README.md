# rtl/memory/ — owned by Teammate C

Register file, LSU, address decoder, IMEM, DMEM.

## Expected files

- `regfile.v` — 32×32-bit, async read of rs1/rs2, sync write of rd.
  **x0 write protection is this module's job**, not the control unit's:
  the CU asserts `reg_write_o` regardless of `rd`, so the guard lives here.
  Guide §3.1.4 — "x0 is hardwired (fixed) at zero and cannot be modified."
  One line: `if (reg_write_i && rd_addr_i != 5'd0) regs[rd_addr_i] <= ...`.
  Not a design question, just a task — don't skip it, nothing upstream
  catches a write to x0.
- `lsu.v` — §3.3 of guide. Alignment and sign/zero extension
  (LB/LH/LBU/LHU).
  **Two things changed since this file was written — read before starting:**
  - `op_size_o`'s 3-bit encoding **is now defined** (`[2:1]`=size,
    `[0]`=sign) with `` `OP_SIZE_* `` macros in `rvbl2_defines.vh`. It was
    decided control-unit-side while nothing was built against it. If you
    have a reason to want it different, say so now — it's cheap to change
    until this module exists.
  - **`bw_o` generation is NOT this module's job any more.** The control
    unit drives it (decision #11), computed from `op_size_o` and a 2-bit
    `addr_lsb_i` input. This was a close call — you have the address
    locally and could own `bw_o` with no extra port — so push back if you
    disagree, but don't build it in parallel: two modules driving the same
    mask is worse than either choice.
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
