<p align="center">
  <strong>CHAMPIONCHIP eXPERIENCE · MALAYSIA EDITION 2026</strong>
</p>
<h1 align="center">RVBL-2 — Gripper, a Multicycle RISC-V Core</h1>
<p align="center"><strong>A 47-instruction RISC-V SoC that keeps a charging station safe on a shaky grid.</strong></p>
<p align="center">
  <i>RV32I + Zmmul + Xicrc multicycle processor with GPIO and UART, running a grid-aware EV-charger controller. Built in ChipInventor, targeting Sky130 via OpenLane.</i>
</p>
<p align="center">
  <img src="https://img.shields.io/badge/RISC--V-RV32I_+_Zmmul_+_Xicrc-283272?style=flat-square&logo=riscv&logoColor=white" alt="RISC-V" />
  <img src="https://img.shields.io/badge/Verilog-Icarus_iverilog-8A2BE2?style=flat-square" alt="Verilog" />
  <img src="https://img.shields.io/badge/Sky130-OpenLane-F58220?style=flat-square" alt="Sky130 OpenLane" />
  <img src="https://img.shields.io/badge/Firmware-RISC--V_assembly-4B8BBE?style=flat-square" alt="Assembly" />
  <img src="https://img.shields.io/badge/Viz-React_+_Vite-20232A?style=flat-square&logo=react&logoColor=61DAFB" alt="React" />
  <img src="https://img.shields.io/badge/Tests-pytest_+_Verilog_TB-0A9EDC?style=flat-square&logo=pytest&logoColor=white" alt="pytest" />
</p>

---

## Overview

> **What is Xicrc?** A custom ISA extension adding three CRC-16 instructions (`crcb`, `crch`, `crcw`) that consume 8 / 16 / 32 bits of `rs1` with `rs2` as the seed. CRC-16/CCITT-FALSE: polynomial `0x1021`, init `0xFFFF`, no reflection, no final XOR.
>
> **What is Zmmul?** The RISC-V multiply-only subset of "M": `mul`, `mulh`, `mulhsu`, `mulhu`. No divide.

**RVBL-2** is a multicycle RISC-V core designed in ChipInventor. Stage 2 delivered the processor and its Sky130 layout. Stage 3 adds a **GPIO** and a **UART**, then builds a real application on them: a **grid-aware EV charging-station controller**.

**At a glance**

- **47 instructions** — RV32I (40), Zmmul (4), Xicrc (3); all execute in 3–6 cycles on a 7-state FSM.
- **Peripherals on plain `lw`/`sw`** — GPIO (8 pins, per-pin direction) and UART (115200 8-N-1) memory-mapped through the address decoder. No new FSM states, no new instructions.
- **Official firmware passes** — organiser GPIO/UART test firmware echoes the UART byte and mirrors P3–0 to P7–4.
- **Application** — IEC 61851 control-pilot FSM, protocol-v2 meter frames (escaped `0x7E` delimiters, sequence numbers, CRC-16), grid-hold on frequency/voltage excursions, fleet-staggered restart.
- **Meter watchdog** — a hardware elapsed-time timer at `0xF2000000` lets firmware latch `METER_TIMEOUT` after 4000 ms without a valid frame, and discard a half-received frame after 400 ms.
- **Hardware `crcb` earns its keep** — about 21× faster than software shift-XOR (~60 vs ~1,276 cycles for 6 bytes), which the 1,740-cycle inter-byte budget at 115200 baud needs.
- **Golden-model verification** — a bit-exact Python model produces every expected value; none are hand-written.
- **Gripper (interactive visualiser)** — a React + Three.js app replays one station and a city-scale fleet as chapter timelines, with a without/with RVBL-2 comparison and an emulator-preview panel.

---

## The Problem

A charging station is a safety device attached to a grid that can fail under it.

### 1. Grid events
- A frequency dip or voltage sag means the station should stop drawing power.
- Hundreds of stations resuming at the same instant cause a second surge.

**Answer:** autonomous GRID_HOLD, then a **per-charger restart delay** (2–9 frames) hashed from the charger ID with `crcb`. The hash spreads exactly 1,250 per bucket over 10,000 sequential IDs. A 1,000-charger simulation shows a **7.94× peak-load reduction** versus simultaneous restart.

### 2. Untrusted meter data
- Frames can be corrupted, dropped, replayed, or simply stop arriving.

**Answer:** protocol v2 frames carry a sequence number and CRC-16, so gaps, duplicates and corruption are rejected, and `0x7E` delimiters let the receiver resync on byte alignment. A **4000 ms watchdog** covers silence: charging needs a healthy first frame, and losing the meter opens the contactor.

### 3. Safety interlocks
- Overcurrent, emergency stop, invalid pilot codes, and a dead meter must never leave the contactor closed.

**Answer:** latched FAULT and METER_TIMEOUT states, entered from any of those conditions, released only by the documented sequence (emergency input clear and pilot back to A).

---

## Processor Architecture

| Extension | Instructions | Module |
|---|---|---|
| RV32I | 40 | `alu_eq26`, `branch_comparator_eq26`, `control_unit_eq26`, `lsu_eq26` |
| Zmmul | 4 | `mult_eq26` (combinational, single-cycle) |
| Xicrc | 3 | `crc.eq26` |

FSM states: `FETCH → DECODE → EXECUTE → MEM_ACCESS_ADDR → MEM_ACCESS_DATA → WRITE_BACK → HALT`.

**Memory map**

| Address | Region |
|---|---|
| `0x00400000` | IMEM — instruction ROM, up to 1024 words |
| `0x10010000` | DMEM — 32 bytes |
| `0xF0000000` | GPIO — DATAOUT `+0`, DATAIN `+4`, DATADIR `+8` |
| `0xF1000000` | UART — TXDATA `+0`, RXDATA `+4`, CONTROL `+8` |
| `0xF2000000` | Elapsed timers — meter age `+0`, UART byte age `+4`; a full-word `sw` refreshes the selected timer |

---

## The Application

**Inputs:** GPIO P0–P3 carry the control-pilot state and the safety trip. The UART carries protocol-v2 frames: two `0x7E` markers around an escaped 9-byte body (sequence, voltage 0.1 V, current 0.1 A, frequency 0.01 Hz, CRC-16), 11–20 wire bytes. The old unframed 8-byte format is no longer supported.

**Processing:** control-pilot FSM (IDLE, CONNECTED, CHARGING, GRID_HOLD, FAULT, METER_TIMEOUT), CRC and sequence validation, grid-health thresholds, the meter watchdog, staggered restart, and `mul`-based V×I accumulation.

**Outputs:** GPIO P4–P7 drive contactor, cable lock, grid-hold LED, and fault LED. On session end the UART returns an 8-byte record (energy, status flags, frame count, CRC-16).

Firmware is stackless and polling-based: all state lives in CPU registers. Source is `main.s` (370 words, about 36% of the 1,024-word IMEM), built with the organiser's RVBL-Firmware-Builder toolchain.

---

## Validation

| Check | Result |
|---|---|
| Stage 2 organiser firmware | PASS — `x4 = 0x00000000`, self-loop at `0x004003ec` |
| Stage 3 organiser GPIO/UART firmware | PASS — GPIO mirror and UART echo |
| Per-module testbenches (9 modules) | PASS — ALU, branch, control unit, CRC, imm, LSU, memory map, multiplier, regfile |
| ISA coverage | 47 / 47 |
| Application scenarios | 12 + 3 harness scenarios, run against 2 tops = 30 runs |
| Python tests | 78 pass: golden model, scenarios, watchdog, resync, rebound evidence |
| Meter watchdog RTL | 14 cases pass; timer unit test pass |
| UART recovery RTL | 44 cases pass |
| Synthesis | OpenLane flow completes; no setup or hold violations at the Typical corner |

Scenario counts and the exact figures differ between the folders below. Each folder's README is the source of truth for its own numbers.

---

## Repository Map

This repo holds **several build tracks**. Only the first two are current.

| Folder | What it is |
|---|---|
| [`chip-inventor/`](chip-inventor/) | **Active build.** Complete design, firmware, emulator interface, testbenches, and the Gripper visualiser (`frontend/`). Includes the meter-data watchdog and UART protocol v2 (see [`improvement made.md`](chip-inventor/improvement%20made.md)); not migrated to `legacy/` or `v2-chip-inventor-synth/`. |
| [`ChampionCHIP-Stage3/`](ChampionCHIP-Stage3/) | Stage 3 submission snapshot: RTL, firmware, testbenches, evidence waveforms, `viz/`. |
| [`ChampionCHIP - Stage2/`](ChampionCHIP%20-%20Stage2/) | Stage 2 submission: processor, OpenLane results, organiser-firmware validation. |
| [`v2-chip-inventor-synth/`](v2-chip-inventor-synth/) | ChipInventor synthesis version, lighter test and size. |
| [`legacy/`](legacy/) | First hand-written slice (pre-ChipInventor). Superseded. Per-module `rtl/` and `tb/` layout. |
| [`reference/`](reference/) | Read-only reference material (another team's public submission, used for landscape only; no code reused). |
| [`external/`](external/) | Vendored organiser material (Stage 2 firmware, Stage 3 test firmware). |
| [`docs/`](docs/) | Specs, handoff docs, build plans, strategy, video script, figures. |

```text
chip-inventor/
├── rtl/            one module per file
├── hdl.v           flattened canvas netlist
├── firmware/       main.s, Makefile, linker script, build outputs
├── testbench/      official-firmware, gpio, uart, per-module, app (golden model + scenarios)
├── emulator/       ./emu command lines and runner
├── evidence/       waveform screenshots
└── frontend/       React + Three.js Gripper visualiser (station view, city/fleet view)
```

---

## Key Documents

| Path | Contents |
|---|---|
| [`docs/STAGE3_STRATEGY.md`](docs/STAGE3_STRATEGY.md) | Stage 3 brief, constraints, application design, revision history |
| [`docs/HANDOFF_control_unit_ALL_STAGES.md`](docs/HANDOFF_control_unit_ALL_STAGES.md) | Control-unit spec, all slices, decision log |
| [`docs/DATAPATH_BUILD_PLAN.md`](docs/DATAPATH_BUILD_PLAN.md) | Per-module ports, operation tables, traps |
| [`docs/OPENLANE_SYNTHESIS.md`](docs/OPENLANE_SYNTHESIS.md) | Synthesis flow notes |
| [`docs/FIRMWARE_DEVELOPMENT.md`](docs/FIRMWARE_DEVELOPMENT.md) | Firmware workflow |
| [`docs/video/`](docs/video/) | Stage 3 video storyboard and script |
| [`chip-inventor/README.md`](chip-inventor/README.md) | Active build details, protocol v2, watchdog |
| [`.claude/CLAUDE.md`](.claude/CLAUDE.md) | Working rules and 9-step module workflow |

---

## Quickstart

Needs [Icarus Verilog](http://iverilog.icarus.com/), Python 3, and optionally GTKWave. Firmware builds also need a RISC-V GNU toolchain (`riscv32-unknown-elf` or `riscv64-unknown-elf`).

```bash
# 1. Official firmware testbench on the active build
cd chip-inventor
iverilog -g2012 -o testbench/sim_testbench.vvp hdl.v testbench/testbench.v
vvp testbench/sim_testbench.vvp
python testbench/run_tests.py            # both top-level designs

# 2. Peripheral tests
python testbench/gpio/run_tests.py
python testbench/uart/run_tests.py

# 3. Application: golden model + all scenarios x all tops
python -m pytest testbench/app -q
python testbench/app/run_tests.py

# 4. Firmware build
cd firmware && make

# 5. Gripper visualiser (from chip-inventor/)
cd frontend
npm install && npm run dev
```

**Always recompile before `vvp`.** A stale `.vvp` silently reruns the previous build.

Testbenches must call `$dumpfile` and `$dumpvars` so GTKWave has a waveform to open.

---

## Status

| Item | Status |
|---|---|
| Processor, 47 / 47 instructions | ✅ Done |
| GPIO and UART | ✅ Done, official firmware passes |
| Application firmware and golden model | ✅ Done |
| Meter watchdog and UART protocol v2 | ✅ In `chip-inventor/` |
| Gripper visualiser: station view, fleet view, without/with RVBL-2 comparison, emulator preview | ✅ Done; frontend migrated to protocol v2 and `METER_TIMEOUT` |
| Real hardware run (AWS FPGA) | ⬜ Out of Stage 3 scope |

**Known limits**

- Results are simulation only; the emulator flow has not been run on hardware.
- Senders must use protocol v2; see [`chip-inventor/emulator/README.md`](chip-inventor/emulator/README.md).
- Numbers quoted in sub-READMEs track their own folder. If two folders disagree, the newer build (`chip-inventor/`) wins.

---

## Submission Checklist (Stage 3)

- [x] Block diagram generated in ChipInventor
- [x] Official GPIO/UART test firmware run, with logs and waveforms
- [x] Application definition, including `./emu` values
- [x] Firmware in binary and assembly
- [x] Application testbench
- [ ] Report PDF and video URL: confirm against `docs/Submission Guide_Stage__Block_Guide_Stage_3.pdf` before submitting

---

<p align="center"><i>RVBL-2 — one small core, three extensions, one job done carefully: keep the contactor right when the grid is wrong.</i></p>
