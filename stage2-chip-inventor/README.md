# ChampionCHIP RVBL-2 — ChipInventor Build

ChipInventor-assisted synthesis and validation package for the RVBL-2
multicycle RISC-V core (RV32I + Zmmul + Xicrc). Everything referenced
below lives inside this `chip-inventor/` folder — no paths point
outside it. This folder mirrors `final-submission/` (the submission
copy); both are kept in sync.

## Contents

```
hdl.v               flattened canvas netlist (all modules, incl. imem
                     with the baked-in Stage 2 validation firmware)
rtl/                 same modules split one-per-file, mirrors hdl.v
simulate.v           ChipInventor simulation harness
testbench/           firmware + per-module simulation evidence (below)
results/final/       GDSII + gate-level netlist (OpenLane output)
logs/                OpenLane synthesis run log
convertion/          ChipInventor JSON->Verilog converter log + diagram.json
config.json          OpenLane synthesis config
front.hex            firmware hex image
fpga_exec.sh         FPGA execution script
README.md            this file
```

## 1. Project functionality

- **RV32I base** — `alu_eq26`, `branch_comparator_eq26`,
  `imm_extend_eq26`, `lsu_eq26`, `regfile_eq`, `dmem_eq26`,
  `control_unit_eq26`
- **Zmmul** — `mult_eq26`
- **Xicrc** — `crc.eq26`
- **GDSII via OpenLane** — `results/final/gds/top.gds`
- **Gate-level netlist** — `results/final/verilog/gl/top.v`,
  `results/final/verilog/gl/top.nl.v`
- **`config.json`** — OpenLane synthesis config used for the run above

Synthesis flow result — see `logs/synthesis-output.log`:

```
[INFO]: There are no hold violations in the design at the Typical corner.
[INFO]: There are no setup violations in the design at the Typical corner.
[SUCCESS]: Flow complete.
```

Non-blocking warnings only: max slew and max fanout at the Typical
corner (see the same log for the referenced STA report path), plus the
usual deprecated-option/missing-SDC warnings OpenLane always prints.

## 2. Validation firmware execution

`hdl.v`'s `imem` module has the **official Stage 2 validation firmware**
baked in — confirmed word-for-word identical to
[`CCX_Malaysia_Edition_Firmware_Stage_2/firmware.txt`](https://github.com/championchip-experience-community/CCX_Malaysia_Edition_Firmware_Stage_2),
not a mock. Pass/fail contract per that repo's spec: entry PC =
`0x00400000`, terminal self-loop, `x4 == 0x00000000` → PASS,
`x4 == 0xFFFFFFFF` → FAIL.

### Full-firmware result: PASS ✅

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

Cycle count independently confirmed against the legacy slice's
`rtl/top.v` + `tb/system/tb_top_organiser.v` — reused directly here as
`EXPECTED_CYCLES` (see `testbench/testbench.v` header).

Evidence:
- [`testbench/sim_testbench_output.log`](testbench/sim_testbench_output.log) — console output of the run above
- [`testbench/testbench.vcd`](testbench/testbench.vcd) — full waveform dump
- [`testbench/full_firmware_waveform/`](testbench/full_firmware_waveform/) — waveform screenshots (`gtkwave_screenshot.png`, `full_view_wavescreenshot.png`, `waveform_0_500ms.png`, `zoom_in_x4_and_pc_end_waveform.png`)

Reproduce:
```bash
cd chip-inventor
iverilog -o testbench/sim_testbench.vvp hdl.v testbench/testbench.v
vvp testbench/sim_testbench.vvp | tee testbench/sim_testbench_output.log
gtkwave testbench/testbench.vcd
```

### Per-module testbenches — all PASS ✅

In addition to the full-firmware run above, every individual block has
its own directed testbench under `testbench/module_testbench/`, each
with its own `.v` source, console log, and waveform screenshot:

| Module | Testbench | Log result |
|---|---|---|
| ALU | `alu/alu_testbench.v` | ✅ PASS — all cases SUCCESS |
| Branch comparator | `branch_comparator/branchcomparator_testbench.v` | ✅ PASS — all cases SUCCESS |
| Control unit | `control_unit/control_unit_testbench.v` | ✅ PASS — 15 cases (R-type, I-type, store, load, branch, MUL, JAL, JALR, LUI, AUIPC, CRC, illegal opcode, EBREAK, FENCE, ECALL/halt), all SUCCESS |
| CRC (Xicrc) | `crc/crc_testbench.v` | ✅ PASS — CRCB/CRCH/CRCW all PASS |
| Immediate extend | `imm/imm_testbench.v` | ✅ PASS — I/S/B/U formats SUCCESS |
| LSU | `lsu/lsu_testbench.v` | ✅ PASS — SW/SB/LW/LB/LBU all SUCCESS |
| Memory mapping (address decoder + DMEM/IMEM) | `memory_mapping/memory_mapping_testbench.v` | ✅ PASS — DMEM write/readback + IMEM read SUCCESS |
| Multiplier (Zmmul) | `multiplier/mult_testbench.v` | ✅ PASS — MUL/MULH/MULHSU/MULHU all SUCCESS |
| Register file | `regfile/regfile_testbench.v` | ✅ PASS, incl. x0 write-protection check |

No `FAIL` lines appear in any of the nine module logs.

### ISA coverage — 47/47

| Category | Expected | Covered | Source |
|---|---|---|---|
| Arithmetic and Logic (Register) | 10 | 10/10 | Full firmware run exercises ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND |
| Arithmetic and Logic (Immediate) | 9 | 9/9 | Full firmware run exercises all 9 I-type ALU ops |
| Load | 5 | 5/5 | Full firmware run exercises LB/LH/LW/LBU/LHU |
| Store | 3 | 3/3 | Full firmware run exercises SB/SH/SW |
| Branch | 6 | 6/6 | Full firmware run + `branch_comparator_testbench.v` (BEQ/BNE/BLT/BGE/BLTU/BGEU) |
| Jump | 2 | 2/2 | Full firmware run + `control_unit_testbench.v` (JAL/JALR) |
| Upper Immediate | 2 | 2/2 | Full firmware run + `control_unit_testbench.v` (LUI/AUIPC) |
| System / Synchronization | 3 | 3/3 | `control_unit_testbench.v` (ECALL/EBREAK/FENCE — not exercised by the firmware itself, since it terminates via a self-loop rather than a trap) |
| Multiplication (Zmmul) | 4 | 4/4 | `mult_testbench.v` (MUL/MULH/MULHSU/MULHU) |
| CRC (Xicrc) | 3 | 3/3 | `crc_testbench.v` (CRCB/CRCH/CRCW) |
| **Total** | **47** | **47/47** | |

Full instruction-by-instruction decode of every word in `rtl/imem.v`
(the baked-in Stage 2 firmware) confirms 44/47 mnemonics appear directly
in the firmware; the remaining 3 (ECALL, EBREAK, FENCE) are covered by
`control_unit_testbench.v` instead, since the firmware halts by looping
on its own address rather than trapping.

## 3. Reproducing the OpenLane flow

The synthesis run referenced above was produced through ChipInventor's
OpenLane integration using `config.json` in this folder. `logs/synthesis-output.log`
is the full console output of that run, start to finish.
