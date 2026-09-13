# ChipInventor Build — ChampionCHIP RVBL-2

ChipInventor-assisted synthesis and validation slice of the RVBL-2
multicycle RISC-V core (RV32I + Zmmul + Xicrc). This directory is the
ChipInventor canvas wiring of the design (`hdl.v`, mirrored per-module in
`rtl/`) plus its OpenLane build output and simulation evidence.

## Contents

```
hdl.v              flattened canvas netlist (all modules, incl. imem with
                    the baked-in Stage 2 validation firmware)
rtl/                same modules split one-per-file, mirrors hdl.v
testbench.v         full Stage 2 firmware validation testbench
testbench/          simulation evidence (see below)
build/              OpenLane synthesis-to-GDSII output (see below)
logs/               OpenLane run logs, incl. earlier failed attempts
convertion/         ChipInventor JSON->Verilog converter logs
config.json         OpenLane synthesis config
simulate.v          ChipInventor simulation harness
```

## Extensions implemented

- **RV32I base** — `alu_eq26`, `branch_comparator_eq26`, `imm_extend_eq26`,
  `lsu_eq26`, `regfile_eq`, `dmem_eq26`, `control_unit_eq26`
- **Zmmul** — `mult_eq26`
- **Xicrc** — `crc_eq26`

## Validation firmware

`hdl.v`'s `imem` module has the **official Stage 2 validation firmware**
baked in — word-for-word identical to
[`CCX_Malaysia_Edition_Firmware_Stage_2/firmware.txt`](https://github.com/championchip-experience-community/CCX_Malaysia_Edition_Firmware_Stage_2),
not a mock. Pass/fail contract per that repo's spec: entry PC =
`0x00400000`, terminal self-loop, `x4 == 0x00000000` → PASS,
`x4 == 0xFFFFFFFF` → FAIL.

### Result: PASS ✅

```
t=9996: pc=004003ec x4=00000000 (after 999 cycles)
PASS [organiser firmware self-check] x4 = 0x00000000 (PASS)
ALL TESTS PASSED
```

| Check | Expected | Got | Result |
|---|---|---|---|
| Entry PC | `0x00400000` | `0x00400000` | ✅ PASS |
| Terminal self-loop PC | `0x004003ec` | `0x004003ec` | ✅ PASS |
| x4 sentinel | `0x00000000` | `0x00000000` | ✅ PASS |
| Cycle count | 979 (+20 margin) | settled at 999 | ✅ PASS |

Cycle count independently confirmed against `rtl/top.v` +
`tb/system/tb_top_organiser.v` in the legacy slice — reused directly here
as `EXPECTED_CYCLES` (see `testbench.v` header).

### Evidence

- [`testbench/sim_testbench_output.log`](testbench/sim_testbench_output.log) — console output of the run above
- [`testbench/testbench.vcd`](testbench/testbench.vcd) — full waveform dump (open with `gtkwave`)
- [`testbench/gtkwave_screenshot.png`](testbench/gtkwave_screenshot.png) — waveform screenshot (`pc_dbg_o`, `x4_dbg_o`, `clk_i`, `imem_oe_o`, memory address/data buses)

### Reproduce

```bash
cd chip-inventor
iverilog -o testbench/sim_testbench.vvp hdl.v testbench.v
vvp testbench/sim_testbench.vvp | tee testbench/sim_testbench_output.log
gtkwave testbench/testbench.vcd
```

## OpenLane synthesis (GDSII)

Flow completed successfully — see `build/openlane.log`:

```
[INFO]: No Magic DRC violations after GDS streaming out.
[INFO]: No KLayout DRC violations after GDS streaming out.
[INFO]: There are no hold violations in the design at the Typical corner.
[INFO]: There are no setup violations in the design at the Typical corner.
[SUCCESS]: Flow complete.
```

Non-blocking warnings only: max slew and max fanout violations at the
Typical corner (see `build/openlane.log` for the referenced STA report).

### Outputs

- `build/gds/top.gds` — final GDSII layout
- `build/verilog/gl/top.v`, `build/verilog/gl/top.nl.v` — gate-level netlists
