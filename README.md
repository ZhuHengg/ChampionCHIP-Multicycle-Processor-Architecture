# RVBL-2 Multicycle RISC-V Core — Phase 2

ChampionCHIP eXperience submission. See `docs/HANDOFF_control_unit.md` for
the full FSM design and control signal spec, and `.claude/CLAUDE.md` for
AI-agent working rules.

## Ownership map

Every folder below has exactly one owner. **Don't edit outside your
folder** — if you need a change in someone else's module, ask them to
change it, or open a comment/issue with the exact port and expected
behavior. This keeps merges clean and keeps one person's assumptions from
silently overwriting another's.

| Folder | Owner | Contents |
|---|---|---|
| `rtl/control_unit.v`, `rtl/top.v` | **Teammate A** | FSM, top-level integration |
| `rtl/datapath/` | **Teammate B** | ALU, multiplier, CRC, branch comparator, immediate extender |
| `rtl/memory/` | **Teammate C** | Register file, LSU, address decoder, IMEM, DMEM |
| `rtl/pkg/` | **Shared — everyone reads, nobody edits without team agreement** | `rvbl2_defines.vh`, the single source of truth for every opcode/op-code literal |
| `tb/control_unit/` | **Teammate A** | Control unit testbench |
| `tb/datapath/` | **Teammate B** | Per-module datapath testbenches |
| `tb/memory/` | **Teammate C** | Per-module memory-side testbenches |
| `tb/system/` | **Teammate D** | Full-core testbench, firmware validation |
| `firmware/` | **Teammate D** | Validation firmware (official + any team test programs) |
| `openlane/` | **Teammate D** | `config.json`, synthesis run outputs |
| `docs/` | **Shared** | Report assets, ChipInventor-exported diagrams |
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
iverilog -o sim/<name>.vvp -I rtl/pkg rtl/<path>/<file>.v tb/<path>/tb_<name>.v
vvp sim/<name>.vvp
gtkwave sim/<name>.vcd
```

## Status

- [x] Control unit FSM designed (see `docs/HANDOFF_control_unit.md`)
- [ ] `control_unit.v` — in progress (Teammate A)
- [ ] Datapath modules (Teammate B)
- [ ] Memory modules (Teammate C)
- [ ] `top.v` integration (Teammate A, after B/C land)
- [ ] System testbench + firmware validation (Teammate D)
- [ ] OpenLane physical flow (Teammate D)
