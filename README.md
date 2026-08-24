# RVBL-2 Multicycle RISC-V Core — Phase 2

ChampionCHIP eXperience submission. A multicycle RISC-V core implementing
RV32I + Zmmul (multiply) + Xicrc (CRC), targeting Sky130 via OpenLane.

**New here? Read `docs/HANDOFF_control_unit_ALL_STAGES.md`** — self-contained
handoff covering the control unit spec, all build slices, and the decision
log. `.claude/CLAUDE.md` has the AI-agent working rules.

---

## Folder structure

```
rvbl2-core/
├── rtl/                    Hardware description (Verilog) — the chip itself
│   ├── control_unit.v      FSM: decides what happens each cycle
│   ├── top.v               Top-level wiring (not built yet)
│   ├── pkg/                Shared constants — every module includes this
│   ├── datapath/           Combinational compute blocks
│   └── memory/             Stateful storage + memory interface
├── tb/                     Testbenches — one folder per owner
│   ├── control_unit/
│   ├── datapath/
│   ├── memory/
│   └── system/             Full-core test, firmware validation
├── docs/                   Specs, build plans, report assets
│   ├── figures/            ChipInventor diagrams for the report
│   └── report/             Report drafts
├── firmware/               Validation firmware (official + team test programs)
├── openlane/               Physical design flow
│   └── runs/               Synthesis output (gitignored)
├── scripts/                Build/automation helpers
└── sim/                    Compiled .vvp / .vcd scratch (gitignored)
```

### What each folder is for

| Folder | Contents |
|---|---|
| `rtl/` | The actual hardware. Everything here becomes silicon. |
| `rtl/pkg/` | `rvbl2_defines.vh` — every opcode, op-code value, and encoding, in one place. See the golden rule below. |
| `rtl/datapath/` | **Combinational** blocks: values in, value out, no clock, no state. ALU, multiplier, CRC, branch comparator, immediate extender. Each takes a select line from the control unit and does one transform. |
| `rtl/memory/` | **Stateful** blocks: register file, LSU, address decoder, IMEM, DMEM. These hold data and need a clock. |
| `tb/` | Testbenches. Simulation only — never synthesized, never becomes hardware. |
| `docs/` | Specs and build plans. `docs/report/` and `docs/figures/` hold submission assets. |
| `firmware/` | Programs the core executes. The official validation firmware lands here when released. |
| `openlane/` | `config.json` plus synthesis runs. Produces the GDSII and gate-level netlist for submission. |
| `sim/` | Build scratch. Gitignored — nothing here is worth keeping. |

**Control unit vs datapath**, since the split isn't obvious: the control unit
emits *select lines and enables* (`alu_op_o = 4'h2`, `reg_write_o = 1`) — it
decides what happens when, but never touches the data. The datapath carries
the *32-bit values* and transforms them. Restaurant analogy: the control unit
is the head chef calling out orders; the datapath is the kitchen equipment.
Same menu (ISA), and you could satisfy it with a completely different kitchen.

---

## Ownership map

Two pairs own the hard-boundary modules; datapath, firmware, OpenLane, and
integration are shared. **Don't edit outside your pair's folder without
asking.** Shared folders still need coordination — "shared" means "everyone's
responsible," not "whoever gets there first wins."

| Folder | Owner | Contents |
|---|---|---|
| `rtl/control_unit.v`, `rtl/top.v` | **FSM pair** | FSM, top-level integration |
| `tb/control_unit/` | **FSM pair** | Control unit testbench |
| `rtl/memory/` | **Memory pair** | Register file, LSU, address decoder, IMEM, DMEM |
| `tb/memory/` | **Memory pair** | Per-module memory-side testbenches |
| `rtl/datapath/` | **Shared — all four** | ALU, multiplier, CRC, branch comparator, immediate extender |
| `tb/datapath/` | **Shared — all four** | Per-module datapath testbenches |
| `rtl/pkg/` | **Shared — read freely, edit only by team agreement** | `rvbl2_defines.vh` |
| `tb/system/` | **Shared — all four** | Full-core testbench, firmware validation |
| `firmware/` | **Shared — all four** | Validation firmware |
| `openlane/` | **Shared — all four** | `config.json`, synthesis runs |
| `docs/` | **Shared — all four** | Specs, report assets, diagrams |
| `sim/` | **Nobody — gitignored** | Scratch output |

⚠ **`rtl/datapath/` being shared means nobody owns any given module by
default** — which is how you end up with two `alu.v` implementations and no
`crc.v`. Assign a name to each module before starting.

---

## Golden rule for `rtl/pkg/rvbl2_defines.vh`

About to write a raw opcode, `alu_op`, `mult_op`, `crc_op`, `result_src`, or
`pc_src` literal into your module? Stop. `` `include "pkg/rvbl2_defines.vh" ``
and use the named macro instead.

Two modules hardcoding the same constant, with a typo in one, is the single
most likely source of an integration bug that only surfaces at `top.v` time —
and it surfaces as "the processor executes the wrong instruction," not as a
compile error.

---

## Build / simulate

Requires [Icarus Verilog](http://iverilog.icarus.com/) (`iverilog`, `vvp`) and
optionally [GTKWave](http://gtkwave.sourceforge.net/) for waveforms.

```bash
# compile RTL + testbench into a simulation binary
iverilog -o sim/<name>.vvp -I rtl rtl/<path>/<file>.v tb/<path>/tb_<name>.v

# run it — prints PASS/FAIL lines, ends with ALL TESTS PASSED
vvp sim/<name>.vvp

# optional: inspect waveforms when debugging a failure
gtkwave sim/<name>.vcd
```

**`-I rtl`, not `-I rtl/pkg`.** Modules include `"pkg/rvbl2_defines.vh"`, so
the search root is `rtl/`. Using `-I rtl/pkg` fails with
`Include file pkg/rvbl2_defines.vh not found`.

**Always recompile before running.** `vvp` on a stale `.vvp` silently runs
your previous build and reports its results — the compile step is what picks
up your edits.

### Worked examples

```bash
# control unit — 48 tests, all 47 instructions
iverilog -o sim/tb_control_unit.vvp -I rtl rtl/control_unit.v tb/control_unit/tb_control_unit.v
vvp sim/tb_control_unit.vvp

# ALU
iverilog -o sim/tb_alu.vvp -I rtl rtl/datapath/alu.v tb/datapath/tb_alu.v
vvp sim/tb_alu.vvp

# every datapath module in one go
for m in alu branch_comparator imm_extend mult; do
  iverilog -o sim/tb_$m.vvp -I rtl rtl/datapath/$m.v tb/datapath/tb_$m.v && vvp sim/tb_$m.vvp
done
```

### Testbench requirements

Every testbench must call:

```verilog
$dumpfile("sim/<name>.vcd");
$dumpvars(0, <testbench_module_name>);
```

Without these there's no waveform to inspect when something fails.

---

## Status

**Control unit — done.** Slices 1-6 complete, 48/48 tests passing, all 47
instructions decoding. Verified: SUB/SRA survive the funct7 dispatch added in
slice 4, and the SRAI/SRLI bit-30 trap is covered.

**Datapath — 4 of 5 done.** `alu.v`, `branch_comparator.v`, `imm_extend.v`,
`mult.v` all pass their testbenches, including the signedness traps
(SLT/SLTU and BLT/BLTU disagreeing on the same bits, MULHSU's mixed
extension, SRA sign-extension, shift-amount masking).

| Item | Status |
|---|---|
| Control unit FSM design | ✅ `docs/HANDOFF_control_unit_ALL_STAGES.md` |
| `control_unit.v` slices 1-6 | ✅ 48/48 passing |
| `alu.v` | ✅ passing |
| `branch_comparator.v` | ✅ passing |
| `imm_extend.v` | ✅ passing |
| `mult.v` | ✅ passing |
| `crc.v` | ⚠ **Blocked** — see below |
| Memory modules (5) | ⬜ Not started — `rtl/memory/README.md` |
| `top.v` integration | ⬜ Blocked on memory modules + `crc.v` |
| System testbench + firmware | ⬜ Blocked on `top.v` |
| OpenLane physical flow | ⬜ Blocked on `top.v` |

### Blocked: `crc.v`

The Block Guide (§3.1.3, Table 11) defines `crcb`/`crch`/`crcw` as returning
a 16-bit CRC but never states the **polynomial, initial value, input/output
reflection, final XOR, or the rs1/rs2 operand roles**. These are arbitrary
parameters with exactly one right answer in the validation firmware — a guess
would produce a module that is perfectly self-consistent and fails validation.

Question raised with the organisers. Until answered, build `crc.v` with the
parameters as Verilog `parameter`s so swapping them is a one-line change:

```verilog
parameter POLY = 16'h1021, INIT = 16'hFFFF, REF_IN = 1'b0,
          REF_OUT = 1'b0, XOR_OUT = 16'h0000;   // CRC-16/CCITT-FALSE placeholder
```

### Open questions

| Question | Blocks | Notes |
|---|---|---|
| CRC parameters | `crc.v` | Raised with organisers |
| Does the validation firmware use ECALL as a halt signal? | Slice 5 correctness | A no-op ECALL passes the coverage table *and* silently fails firmware validation if the suite depends on it. Add a `halt_o` output held at 0 so the fix stays one line |

---

## Build order from here

1. **Memory modules** (memory pair) — `regfile.v`, `lsu.v`,
   `address_decoder.v`, `imem.v`, `dmem.v`. ⚠ `dmem.v` **must be
   registered-output** (synchronous read): address captured on one edge, data
   valid the *next*. The FSM's 2-cycle load design depends on it. Build it
   combinational and slice 2's timing is wrong — and you won't find out until
   integration.
2. **`crc.v`** once the parameters land.
3. **`top.v`** (FSM pair) — control unit slice 7.
4. **System testbench + firmware validation.**
5. **OpenLane flow** → GDSII, gate-level netlist, area/density numbers for
   report §5. Watch the multiplier's area here: a full combinational 64-bit
   multiply is the largest block in the design, and if it dominates, the
   fallback (iterative shift-add) changes the FSM, not just `mult.v`.

---

## Key documents

| Path | Contents |
|---|---|
| `docs/HANDOFF_control_unit_ALL_STAGES.md` | **Start here.** Control unit spec, all slices, decision log |
| `docs/DATAPATH_BUILD_PLAN.md` | Per-module ports, operation tables, traps |
| `docs/CONTROL_UNIT_BUILD_PLAN.md` | Slice-by-slice roadmap |
| `docs/HANDOFF_control_unit.md` | Original spec doc |
| `docs/fsm_control_signal_table.md` | Scaffold with issue-resolution history |
| `docs/Championchip-stage-2-guide.pdf` | Competition block guide — source of truth for guide-fixed signals |
| `rtl/pkg/rvbl2_defines.vh` | **All constants — what the RTL actually compiles against** |
| `.claude/CLAUDE.md` | 9-step workflow, RTL coding standards |

## Submission checklist (guide §9)

- [ ] Report (PDF, ≤20 pages, ≤10 MB) covering guide topics 1-6
- [ ] GDSII from OpenLane
- [ ] Gate-level netlist (`results/final/verilog/gl/`)
- [ ] `config.json` used for synthesis
- [ ] All RTL and testbench files
- [ ] YouTube demo video URL (3-4 min), included in the report
