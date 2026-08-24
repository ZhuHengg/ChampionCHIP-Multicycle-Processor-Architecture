# RVBL-2 Multicycle RISC-V Core — Phase 2

ChampionCHIP eXperience submission. **Start with
`docs/HANDOFF_control_unit_ALL_STAGES.md`** — single self-contained handoff
covering the control unit spec, all 7 build slices, and the decision log.
`.claude/CLAUDE.md` has the AI-agent working rules.

## Ownership map

Two pairs own the two hard-boundary modules; everything else (datapath,
firmware, OpenLane, system integration) is shared by all four. **Don't edit
outside your pair's folder without asking** — if you need a change in the
other pair's module, ask them, or open a comment/issue with the exact port
and expected behavior. This keeps merges clean and keeps one pair's
assumptions from silently overwriting another's. Shared folders still need
coordination before editing — "shared" means "everyone's responsible," not
"whoever gets there first wins."

| Folder | Owner | Contents |
|---|---|---|
| `rtl/control_unit.v`, `rtl/top.v` | **FSM pair** | FSM, top-level integration |
| `tb/control_unit/` | **FSM pair** | Control unit testbench |
| `rtl/memory/` | **Memory pair** | Register file, LSU, address decoder, IMEM, DMEM |
| `tb/memory/` | **Memory pair** | Per-module memory-side testbenches |
| `rtl/datapath/` | **Shared — all four** | ALU, multiplier, CRC, branch comparator, immediate extender |
| `tb/datapath/` | **Shared — all four** | Per-module datapath testbenches |
| `rtl/pkg/` | **Shared — everyone reads, nobody edits without team agreement** | `rvbl2_defines.vh`, the single source of truth for every opcode/op-code literal |
| `tb/system/` | **Shared — all four** | Full-core testbench, firmware validation |
| `firmware/` | **Shared — all four** | Validation firmware (official + any team test programs) |
| `openlane/` | **Shared — all four** | `config.json`, synthesis run outputs |
| `docs/` | **Shared — all four** | Report assets, ChipInventor-exported diagrams |
| `sim/` | **Nobody — gitignored** | Compiled `.vvp` / `.vcd` scratch output |

## Golden rule for `rtl/pkg/rvbl2_defines.vh`

If you're about to write a raw opcode, `alu_op`, `mult_op`, `crc_op`,
`result_src`, or `pc_src` literal directly into your module — stop, and
`` `include "../pkg/rvbl2_defines.vh" `` instead, then use the named
macro. Two modules hardcoding the same constant with a typo in one of them
is the single most likely source of an integration bug that only shows up
at `top.v` time.

## Build / simulate

```bash
iverilog -o sim/<name>.vvp -I rtl rtl/<path>/<file>.v tb/<path>/tb_<name>.v
vvp sim/<name>.vvp
gtkwave sim/<name>.vcd
```

## Status

- [x] Control unit FSM designed (see `docs/HANDOFF_control_unit.md`)
- [x] `control_unit.v` slices 1-6 — all 47 instructions decoding, 48/48 tests passing
- [ ] Datapath modules — `alu.v`, `mult.v`, `crc.v`, `branch_comparator.v`,
      `imm_extend.v`. See `docs/DATAPATH_BUILD_PLAN.md`. **Assign owners
      first** — shared folder, so nobody owns any given module by default.
      `crc.v` is blocked on a spec gap; raise it now.
- [ ] Memory modules — `regfile.v`, `lsu.v`, `address_decoder.v`, `imem.v`,
      `dmem.v` (Memory pair). See `rtl/memory/README.md`.
- [ ] `top.v` integration — control unit slice 7, blocked until the above land
- [ ] System testbench + firmware validation (Shared — all four)
- [ ] OpenLane physical flow (Shared — all four)
