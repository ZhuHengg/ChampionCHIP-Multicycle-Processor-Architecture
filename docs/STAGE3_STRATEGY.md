# Stage 3 — Brief, Constraints, and Stand-Out Strategy

**Last updated:** 2026-09-27 (rev 3.2 — design frozen for implementation; plan in `docs/superpowers/plans/2026-09-27-grid-aware-ev-charger.md`)
**Sources:** `docs/Submission Guide_Stage__Block_Guide_Stage_3.pdf` (**authoritative**),
`docs/BlockGuide_Stage3_Part1.pdf`, `docs/meeting_min.md`, organiser slides
from the 2026-09-22 briefing, the organiser repo
[CCX_Malaysia_Edition_Stage_3](https://github.com/championchip-experience-community/CCX_Malaysia_Edition_Stage_3)
(local copy in `external/CCX_Malaysia_Edition_Stage_3/`), our RTL in
`chip-inventor/rtl/`, and public competitor repos.

**Status:** application **decided** (§7). Protocol, pin map and FSM in §7 are
the proposed design, to be frozen before firmware work starts (§8, day 1).

> ## ⚠ Deadline: **30 September 2026, 23:59 MYT** — 3 days from this revision. Late submissions are not accepted.

---

## 0. Revision history

### Rev 3.2 (2026-09-27)

| Topic | Change |
|---|---|
| §7.4, §7.6 | **CRC chain rule corrected:** seed = CRC field of the previous frame *received* (was "last accepted", which permanently desyncs after one corrupted frame because the meter gets no per-frame ACK). Exact pilot/safety and frame rules, constants table, and record flag bits pinned. |
| §7.6 | **P1 passed:** restart-delay hash `& 7` spreads exactly 1,250 per bucket over 10,000 sequential charger IDs — hash frozen. |
| §7.8 | Scenarios S9 (invalid pilot), S10 (replayed frame), S11 (stale inputs at boot), S1X (back-to-back bytes) added. Repo layout mirrors the organiser repo; new `chip-inventor/emulator/` folder. |
| §3, §9 | `-d` polarity and the first-8-bytes RX window confirmed from the local emulator README; observation on the organiser's own example command. |
| Plan | Implementation plan written: `docs/superpowers/plans/2026-09-27-grid-aware-ev-charger.md`. |

### Rev 3.1 (2026-09-27)

| Topic | Change |
|---|---|
| §6 | Rewritten as **"How we stand out"**: three layers (choice, innovation, execution), us-vs-typical-team per guide section, levers L9 (evidence) and L10 (honesty). |
| §7.1 | Rewritten: the problem, **how the charger works in general** (four jobs, normal session, grid event, faults), **what is innovative, honestly separated** from what already exists, the pitch line, and proofs P1–P4. |
| §8 | Delay-spread check (P1) now gates the design freeze on day 1; rebound graph (P2) added to day 3. |

### Rev 3 (2026-09-27)

| Topic | Change |
|---|---|
| Application | **Decided: grid-aware EV charging-station controller** (IEC 61851 control-pilot FSM + autonomous grid support). Replaces the solar-relay recommendation. Full definition in §7. |
| Status | GPIO/UART integration and the **official firmware testbench are done and passing** (§1). Re-run 2026-09-27 on all three tops. |
| Emulator | `emu.c` source read line by line. New hard facts in §3: **≤ 8 reply bytes per command in total**, the first mismatch aborts the command, **the exit code is inverted** (pass/fail must come from the `[ok]`/`[error]` text), default direction is `0x01` until `-d` is given. |
| Toolchain | Builder uses `-march=rv32i_zmmul -mabi=ilp32` (resolves old open question 5). **No RISC-V toolchain on the dev machine yet** (§8 blocker). |
| CRC operands | Confirmed from `hdl.v` comment: `crcb rd, rs1, rs2` — rs1 = data, rs2 = seed/running CRC. |

### Rev 2 (2026-09-26) — after the Submission Guide

| Topic | Rev 1 assumption | Submission Guide says | Impact |
|---|---|---|---|
| Deadline | unknown | **30 Sep 2026 23:59 MYT** | Scope must fit the deadline. §8 plan. |
| Synthesis | Stage 3 ends at Sky130/OpenLane synthesis | **Not a deliverable.** Workflow ends at "Emulator Preview"; AWS FPGA not covered | Drop OpenLane from the critical path. RTL must stay synthesizable. |
| Emulator | Stage 4 / disputed | **In scope as a concept:** app definition must explain `./emu` values; video must show emulator ↔ processor logic. Running on AWS is **not** required | Design the app's I/O around `./emu` (§3). |
| Official test | "echo test recommended" | **Mandatory:** run the organiser's GPIO/UART test firmware; logs/waveforms in the report | Done (§1). |
| Block diagram | ChipInventor for figures | **Mandatory:** block diagram generated in ChipInventor | Still to export (§1). |
| Video | 1 min | **Max 8 min**: technical, application logic with `./emu`, pitch | Script in §2.4. |
| Report | cover, TOC, screenshots, one font | **Topics 1–5, PDF, max 7 pages, max 10 MB** | Outline in §2.3. |
| Firmware format | C or asm (open) | Organiser builder is **assembly** (`src/main.s`); deliver **binary and assembly** | Write the app in assembly. |
| Integrity | — | Code must be the team's own | Competitor repos are landscape only. **Do not reuse their code.** |

---

## 1. Scope, workflow, and status

Official workflow (Submission Guide §1 figure):

`GPIO & UART integration → Official Firmware Testbench → [Application Definition → Application Firmware Development → Application Firmware Testbench] → Emulator Preview`

| # | Step | Guide § | Status (2026-09-27) |
|---|---|---|---|
| 1 | GPIO & UART integration | §2 | **Done.** Integrated in `hdl.v` (ChipInventor canvas top), `hdl_ref.v`, `rtl/top.v`. GPIO exposed as split `pins_i/pins_o/pins_oe_o` (no internal tri-state — FPGA-friendly). System test `testbench/system/tb_system.v` (UART + GPIO + MUL + CRC, FIRMWARE 3) passes 13/13 checks on all three tops. |
| 1b | ChipInventor block diagram image | §2 (mandatory) | **Missing.** `convertion/diagram.json` exists; export an image for the report. |
| 2 | Official Firmware Testbench | §3 (mandatory) | **Done.** `testbench/organiser/tb_organiser.v` runs the verbatim organiser firmware (FIRMWARE 4). Passes on all three tops: GPIO `0xA → 0xA`, UART `0x30 → 0x30`, plus a GPIO re-check after UART. Still needed: waveform screenshot for the report. Optional: match the organiser's log wording (`[PASS] GPIO: P3-P0 = 0xA, P7-P4 = 0xA`). |
| 3 | Application Definition | §4 | **Done** — §7, frozen. Protocol answered against the emulator's own checklist in `chip-inventor/emulator/README.md`. |
| 4 | Application Firmware Development | §5 | **Done.** `chip-inventor/firmware/src/main.s` (264 words, `FIRMWARE 5`), built with the organiser's vendored Firmware-Builder (`riscv64-unknown-elf`, MSYS2 UCRT64). Toolchain validated by rebuilding the organiser's own firmware byte-for-byte (21/21 lines identical). All five states, chained-CRC frame validation (`crcb`), `mul` metering, over-current and CRC-lost faults, and the CRC-hashed grid-hold restart. |
| 5 | Application Firmware Testbench | §6 | **Done.** `testbench/app/` models `./emu` + the FPGA wrapper (one `emu_*` task per option). 15 scenarios × 3 tops = 45 runs, all as expected (H1 is an expected-fail harness self-check). 36 pytest cases cover the golden model and the scenario set. |
| 6 | Emulator Preview (`./emu` command set) | §4, §7 | **Done.** `chip-inventor/emulator/emu_commands.txt` — 12 scenarios (S1–S11 + S1X) as 13 `./emu` command lines (S11 needs a setup line that leaves IN = 0x02 for its boot), generated from the golden model, plus `run_scenarios.sh` to run them on the FPGA and `README.md` answering the organiser's protocol checklist. |
| — | `convertion/new_export/hdl.v` | — | Has FIRMWARE 1–3 only (no 4). Matters only if that export goes back into ChipInventor. |

---

## 2. Deliverables checklist

### 2.1 Files to submit (guide §9)

1. Technical report — PDF, **≤ 7 pages, ≤ 10 MB**, covering guide topics 1–5.
2. GitHub link.
3. Video demo — YouTube link, **≤ 8 minutes**.
4. Project files: **all** source code (C, Verilog, Python, …) and the complete
   firmware in **both binary and assembly** (`firmware.bin` + `main.s`; the
   builder also emits `firmware.txt` and `firmware.dmp`).

Evaluators may reproduce the simulation and execution flow on AWS from the
submitted files — **the repo must build and simulate from a clean checkout,
and the firmware must behave correctly under the real `./emu` rules (§3).**

### 2.2 Official Firmware Testbench (guide §3) — done

Requirements met by `testbench/organiser/`: firmware loaded from the
organiser's `firmware.txt`, `0xA` on P3–P0 → `0xA` on P7–P4, `0x30` echoed on
UART, timeout detection, clear PASS/FAIL log. Remaining: waveform screenshot
(clock, reset, GPIO transitions, UART byte timing).

### 2.3 Report outline (7 pages, topics 1–5 only)

| Page budget | Guide topic | Content |
|---|---|---|
| ~1 | 1. Project Overview | Grid-aware EV charger: goal, architecture, how firmware uses UART + GPIO |
| ~1.5 | 2. GPIO & UART Integration | Integration design, address decoding, split pin bus, **ChipInventor block diagram** |
| ~1 | 3. Official Firmware Testbench | PASS log + waveform screenshot |
| ~1.5 | 4. Application Definition | Context / Input / Processing / Output, pin map, frame format, `./emu` values (§7) |
| ~2 | 5. Firmware Development and Processing | Two-level FSM, frame handling, **chained CRC with `crcb`**, **energy metering with `mul`**, CRC-derived restart delay, measured cycle counts |

Plus: cover (members, team, project name), table of contents, legible
screenshots, one font family. Assume cover/TOC count towards 7 pages (§9 Q1).

### 2.4 Video (guide §7, ≤ 8 min) — suggested split

| Part | Time | Content |
|---|---|---|
| 1. Technical | ~3 min | Architecture, GPIO/UART integration, ChipInventor diagram, official testbench PASS, firmware structure, CRC/MUL usage with measured cycle numbers, **one waveform showing the hardware FSM and the application FSM (`x4_dbg_o`) together** |
| 2. Application logic | ~3 min | Walk through `./emu` command lines for: a normal charging session, a grid under-frequency event with CRC-timed restart, a corrupted meter frame, an emergency stop. Show the testbench running the same vectors |
| 3. Pitch | ~1.5 min | EV-charging growth vs grid peak; the rebound graph (P2); the pitch line from §7.1 (clock-free, random-free, auditable grid protection from one CRC instruction); trustworthy billing; honest scope |

From the earlier slides (assumed still valid): **human narration only, mandatory subtitles**, professional tone.

---

## 3. Emulator (`./emu`) facts — verified from `emu.c`

Source: `external/CCX_Malaysia_Edition_Stage_3/RVBL-Emulator/src/emu.c` (read in full).

| Option | Behaviour (from source) |
|---|---|
| `-d DIR` | Writes bits [15:8] of the AXI `IN` register (read-modify-write). "1 for output, 0 for input" |
| `-i DATA` | Writes bits [7:0] of `IN` = value driven onto the processor's GPIO inputs |
| `-o DATA` | Reads the 32-bit `OUT` register and compares to `DATA` |
| `-t1/-t2/-t4 V` | Sends 1/2/4 bytes, **low byte first**; waits for each byte's TX-done before the next |
| `-r1/-r2/-r4 V` | Reads the 64-bit RX window (`RX0`/`RX1`) and compares the next N bytes |

Hard facts that constrain our design:

1. **Every command starts with a reset** (`fpga_init`: reset register 1 → 0 → 1). No state survives between commands.
2. **Default direction is `0x01`** (set in `fpga_init`). Always pass `-d` first.
3. **Options run strictly in order, and `-i` may appear many times** — so one command can walk the car through several control-pilot states.
4. **At most 8 reply bytes per command, in total.** `fpga_read_uart` keeps a static byte pointer across all `-r` options and only has a 64-bit window. So the firmware must send **one reply of ≤ 8 bytes per command**, not a reply per frame.
5. **The first mismatch aborts the command** (`goto main_end`) — later options are skipped.
6. **The exit code is inverted** (`return err ? EXIT_SUCCESS : EXIT_FAILURE`): a clean run returns failure. **Judge pass/fail from the `[ok]` / `[error]` lines, not `$?`.** Worth reporting to the organisers.
7. **Each AXI access sleeps 50 ms**, so the host is far slower than the chip. Firmware never races the emulator; in simulation we model this with a short configurable gap between operations.

**Confirmed by the local `RVBL-Emulator/README.md` (2026-09-27):**
- `-d` bit 0 = the emulator drives the pin toward the processor; 1 = the
  emulator releases it and observes the processor output. So `-d 0xF0` matches
  our chip's `DATADIR = 0xF0`.
- AXI `0x10`/`0x14` hold the **first** four / next four bytes the processor
  returns, and `0x18` holds the current position: at most 8 reply bytes per
  execution. Our one-record-per-command design fits exactly.
- The README lists what **each application must define** for the emulator
  (which pins are inputs/outputs, whether a GPIO input is a trigger, how many
  bytes go in over UART and what they mean, how many bytes come back, and what
  the GPIO/UART results mean). `chip-inventor/emulator/README.md` answers that
  list in order.

Still unknown: whether `OUT` returns only the output pins (we assume yes).

**Observation on the organiser's own example.** `./emu -d 0xF0 -i 0x02 -o 0x20 -t1 0x30 -r1 0x30`
expects `-o 0x20` straight after `-i`, but their test firmware reads GPIO once
per loop and then blocks on UART. It can only pass if `IN` already held `0x02`
from a previous run (`IN` persists across the emulator's reset). Our firmware
polls its inputs continuously, so `-i` followed by `-o` works in any order —
one line worth putting in the report.

---

## 4. Hardware facts that constrain the application

| Resource | Fact | Source | Consequence |
|---|---|---|---|
| GPIO | 8 pins, `0xF0000000`: DATAOUT `+0x0`, DATAIN `+0x4`, DATADIR `+0x8` (1 = output) | Block Guide §1 | 4 inputs + 4 outputs in our pin map. |
| UART | 115200 8-N-1, `0xF1000000`: TXDATA `+0x0`, RXDATA `+0x4`, CONTROL `+0x8` (bit0 TRANSMIT, bit1 RXDONE, bit2 TXDONE). **Single-byte buffer, no flow control, no interrupts** | Block Guide §2 | Polling; read each byte before the next lands. |
| Clock | 20 MHz (`CLOCK_PERIOD 50.0`) | `chip-inventor/config.json` | ≈5 MIPS peak. |
| CPI | ALU/MUL/CRC 4, branch 3, store 4, **load 6** | Handoff §2 | ~4 cycles/instruction. |
| Byte time | 10 × 174 = **1740 cycles/byte** | `uart.v` | ~400 instructions of budget per received byte. |
| DMEM | **8 words = 32 bytes** (organiser instruction, all teams) | `dmem_eq26.v` header | State lives in registers; no buffers. |
| IMEM | `case` ROM, ≤ 1024 words | `imem.v` | Plenty for the app. |
| Timer / interrupts | None | ISA | **Time = meter-frame count** (one frame per metering interval). |
| Arithmetic | `mul/mulh/mulhsu/mulhu`, **no divide, no FP**; builder `-march=rv32i_zmmul` so `mul` assembles directly | Handoff §8, builder Makefile | Integer units chosen so no division is needed. |
| CRC | `crcb/crch/crcw`, CRC-16 poly `0x1021`, non-reflected, xorout 0; `crcb rd, rs1=data, rs2=seed` | `crc.eq26.v`, `hdl.v` comment | Seed `0xFFFF` = **CRC-16/IBM-3740 (CCITT-FALSE)**, check value `"123456789"` → **`0x29B1`**. |

**CRC byte order:** frames are CRC'd **byte by byte with `crcb` in wire order**
(the order `./emu -t` sends them, low byte first). Never `crcw` on a loaded
word — it would process the bytes in reverse.

**Custom instructions in assembly:** the stock assembler does not know
`crcb`. Encode with `.insn r 0x33, <funct3>, <funct7>, rd, rs1, rs2`, taking
funct3/funct7 from the handoff opcode table (Xicrc: opcode `0110011`, funct7
`1000000`, funct3 `000` crcb / `001` crch / `010` crcw) — verify against the
table before use.

---

## 5. Competitive landscape

- **Every team builds the same RVBL-2 spec** (RV32I + Zmmul + Xicrc) — e.g.
  [Niccc8/rvbl2-riscv-cpu-core](https://github.com/Niccc8/rvbl2-riscv-cpu-core),
  [Lourencohg/championchip-rv32-riscv](https://github.com/Lourencohg/championchip-rv32-riscv).
  Having CRC/MUL is not a differentiator; **using them for a real purpose and
  measuring the benefit is** — guide §5 explicitly asks how CRC/Zmmul are used.
- The strongest visible competitor has clean Sky130 sign-off and 7,384+ checks.
  Verification rigour is table stakes.
- Likely crowd choices: drone, stock market, game (organiser examples),
  traffic lights, smart home, temperature monitor, ECU copies.
- **Do not look at or reuse other teams' code** (guide Note 1).

---

## 6. How we stand out in Stage 3

### 6.1 The story in three layers

Standing out has three layers. A typical team gets the first one at most.

| Layer | Meaning | Our answer |
|---|---|---|
| 1. **Choice** | A domain nobody else picked | Public EV-charging infrastructure — not a drone, stock bot, game, traffic light, or ECU copy |
| 2. **Innovation** | Something beyond standard practice, tied to our hardware | Clock-free, random-free, auditable grid protection built from the CRC instruction; one custom instruction doing three jobs (§7.1) |
| 3. **Execution** | Evidence, not claims | Bit-exact golden model, every test = a real `./emu` command, measured cycle counts, delay-spread and rebound proofs (§7.1, P1–P4) |

**Continuity with Phase 2:** our Phase 2 edge was the comprehensive 9-state
control FSM. Stage 3 extends it into a **two-level FSM** — the hardware FSM
runs a standards-defined application FSM, and one waveform shows both.

### 6.2 Us vs a typical team, section by section of the Submission Guide

| Guide § | Typical team | Us |
|---|---|---|
| §1 Overview | Toy scenario (echo, LED toggle, example app) | Real infrastructure problem (grid stress + billing trust) with a named standard |
| §2 Integration | "GPIO and UART are connected" | Split pin bus (no internal tri-state, FPGA-ready), same RTL verified on three tops |
| §3 Official test | Runs the organiser test once | Passes on all three tops, plus a GPIO re-check after UART |
| §4 Application definition | Inputs/outputs listed | Pin map, frame format, session record, FSM, **and 8 exact `./emu` scenarios** designed around the emulator's real limits (read from `emu.c`) |
| §5 Firmware | "We use CRC/MUL" | CRC used three ways, MUL for metering, **measured** cycle savings, division-free integer units |
| §6 Testbench | A few PASS lines | Self-checking, golden-model-driven, each test prints its `./emu` command; fault injection (bad CRC, broken chain, E-stop, unplug under load) |
| §7 Video | Code walkthrough | Two-FSM waveform, grid-dip-and-staggered-restart demo, rebound graph, honest scope statement |

### 6.3 Levers

| # | Lever | How our app delivers it |
|---|---|---|
| L1 | Application outside the crowd, tied to a real problem and a named standard | EV charging infrastructure; IEC 61851 control-pilot FSM; grid-support twist (§7.1) |
| L2 | **CRC + MUL in the hot path, with measured cycle counts** | `crcb` on every meter-frame byte (chained CRC) and as the restart hash; `mul` for V·I energy. Proof P3 |
| L3 | Defined error behaviour, shown on video | Bad/missing frame → not billed; two in a row → FAULT; E-stop → FAULT |
| L4 | **Testbench vectors exported 1:1 as `./emu` commands** | Every scenario prints its exact `./emu` command line (§7.8) |
| L5 | Self-checking team testbench with a bit-exact Python golden model | Golden model computes every CRC, energy value, restart frame, and session record |
| L6 | Reproducible repo | One script builds firmware and runs every testbench from a clean checkout |
| L7 | Presentation polish | Human narration + subtitles, 8-min structure, 7 tight pages |
| L8 | **Two-level FSM — continues our Phase 2 edge** | Firmware keeps its state in `x4`, so `x4_dbg_o` shows both FSMs in one waveform. Proof P4 |
| L9 | **Innovation backed by evidence** | Delay-spread histogram (P1) and rebound simulation graph (P2) |
| L10 | **Honesty as credibility** | Report states plainly what already exists and what CRC cannot do (§7.1) — pre-empts the judge's "isn't this just OpenEVSE?" |

Dropped for Stage 3: OpenLane reporting, dataset replay, Stage 4 FPGA prep.

---

## 7. Application — Grid-aware EV charging-station controller

### 7.1 Overview — how it works, and what is innovative

#### The problem

Public AC chargers are spreading fast (Malaysia's national EV-charger
build-out; the same trend in Brazil). Two problems grow with them:
1. **Grid stress.** Thousands of chargers drawing power at the evening peak.
   When the grid wobbles (a power plant trips and frequency drops), chargers
   keep drawing, and when the grid recovers they all switch back on at the
   same instant, a "rebound" spike that can knock it down again.
2. **Billing trust.** Drivers and operators must trust that every billed
   kilowatt-hour was really measured.

#### How it works in general

In one sentence: **our chip is the brain of a public EV charger. It lets power
flow only when the car and user are safe, bills energy only from trusted
measurements, and steps back by itself when the grid is struggling.**

```
                 ┌────────────── CHARGING STATION ──────────────┐
  ┌───────┐ pilot│  ┌──────────────────┐       ┌───────────────┐ │   ┌────────────┐
  │  CAR  │◄────►│  │  OUR RISC-V CHIP │◄─UART─│ ENERGY METER  │◄┼───│ POWER GRID │
  └───┬───┘ line │  │  (the "brain")   │ frames│ measures V,I,f│ │   └────────────┘
      │          │  └──┬───────┬───────┘       └───────────────┘ │
      │ cable    │     │GPIO   │UART                             │
      └──────────┼─ contactor, │ session record ───────────────► │──► Operator backend
                 │  cable lock,│                                 │    (billing)
                 │  LEDs       │                                 │
                 │  ◄── E-stop button / residual-current sensor  │
                 └───────────────────────────────────────────────┘
```

The chip has four jobs:

| Job | What it means | Hardware used |
|---|---|---|
| 1. **Safety gatekeeper** | IEC 61851 state machine: power reaches the cable only when the car is connected, the cable is locked, the car asked for power, and nothing is faulty | Firmware FSM on our hardware FSM |
| 2. **Honest meter** | Energy += V × I, only for meter frames that pass the chained CRC check. Corrupted, missing, repeated, or re-ordered frames are never billed | `mul`, `crcb` |
| 3. **Grid guardian** | Grid frequency low or voltage sagging → pause charging by itself. Grid healthy again → wait this charger's own unique delay, then resume | compare + `crcb` as a hash |
| 4. **Reporter** | At session end (or on a fault), send one CRC-protected session record to the backend | `crcb` |

**Time base:** the chip has no clock. Each meter frame is one tick (a real
meter reports roughly every second), so "wait 5 frames" means about 5 seconds.

**A normal session:**

| Step | World | Chip sees | Chip does | Outputs |
|---|---|---|---|---|
| 1 | Station idle | Pilot A | Nothing | all off |
| 2 | Driver plugs in | Pilot B | Locks cable | lock |
| 3 | Car asks for charge | Pilot C | Closes contactor | lock + power |
| 4 | Meter reports 230.0 V, 16.0 A, 50.00 Hz each interval | Frames, CRC OK, grid healthy | Energy += V·I | lock + power |
| 5 | Battery full | Pilot B | Opens contactor | lock |
| 6 | Driver unplugs | Pilot A | Unlocks, sends session record | all off |

**A grid event (the innovation in action):**

| Step | Meter reports | Chip does | Outputs |
|---|---|---|---|
| 1 | 49.20 Hz (unhealthy) | Opens contactor, enters `GRID_HOLD`, computes its restart delay from the CRC hash | lock + grid-hold |
| 2 | 49.40 Hz (still unhealthy) | Keeps waiting; healthy counter reset | lock + grid-hold |
| 3… | 50.00 Hz (healthy) | Counts healthy frames 1, 2, 3, … | lock + grid-hold |
| n | Count reaches its own delay (2–9 frames) | Resumes charging | lock + power |

Because every charger's delay is different, the load returns gradually
instead of as one spike:

| Charger | Resumes after (illustrative) |
|---|---|
| Mall charger #1 | 5 frames |
| Mall charger #2 | 9 frames |
| Office charger #7 | 2 frames |

**Faults:** one bad frame is ignored and not billed; two in a row, an E-stop,
earth leakage, a car error (pilot E/F), or over-current latch `FAULT` (power
off until the safety device is released **and** the car is unplugged). Pilot
D (ventilation required) → charging refused, since the station has none.

#### What is innovative — honestly separated

| Level | Feature | Already exists? | How we claim it |
|---|---|---|---|
| Standard | IEC 61851 state machine, cable lock, contactor, fault latch | Yes, every charger (e.g. open-source OpenEVSE on an 8-bit MCU) | Correct implementation, not innovation |
| Standard | Energy metering, CRC-checked meter frames | Yes | Correct implementation |
| Uncommon | Pausing charging on grid under-frequency / voltage sag | Yes, in research, regulation, and high-end chargers; most commercial chargers do it **via the cloud** (backend commands), so it fails when the network is down | "Brings grid support into a basic controller, working **with no network at all**" |
| Uncommon | Staggered restart to avoid the rebound spike | Yes, randomised delays appear in regulation (e.g. UK smart-charge-point rules — verify the wording before quoting) | Known concept, new setting |
| **Ours** | **Staggered restart with no random-number generator and no timer** — delay = CRC-16 of the charger ID, seeded with the triggering frame's CRC | Normal designs use an RNG plus a timer; our chip has neither | **Design innovation**: solving a real constraint with hardware already on the chip |
| **Ours** | **Deterministic, auditable delay** — same charger + same event → same delay | True random delays cannot be verified afterwards | A regulator or operator can **prove** a charger behaved correctly |
| **Ours** | **One custom instruction, three roles** — frame integrity, billing-chain continuity (no sequence-number field needed, so frames stay 8 bytes), and restart de-synchronisation | — | **Hardware–software co-design**: shows why the Xicrc extension earns its silicon area |

**The innovation claim (pitch line):**

> "We turned the chip's CRC instruction into a clock-free, random-free grid-protection
> mechanism: every charger restarts at its own predictable, auditable moment — with
> no network, no timer, and 32 bytes of RAM."

This is a chip-design competition: the last row is what judges care about
most. We did not just use the custom instruction; we found three jobs for it.

#### Proving it, not just claiming it

| # | Proof | Tool | When | Why |
|---|---|---|---|---|
| P1 | **Delay-spread check.** Histogram of the restart delay over ~10,000 charger IDs × events | Python golden model | Day 1, **before freezing the hash** | CRC is linear, so for sequential IDs the low 3 bits may not spread evenly. If they don't, fix the hash (different bit slice, or hash twice) before writing firmware. Checking our own claim is itself a sign of rigour |
| P2 | **Rebound simulation.** 1,000 chargers × 7 kW through a grid dip: all restarting at once = 7.0 MW in one frame; CRC-hashed staggering spreads load across 8 frames, peak ≈ 0.88 MW (**7.94× reduction**). See `testbench/app/evidence/rebound_sim.py` and `docs/figures/rebound.png` | Python | Day 3 | One graph that turns the pitch into evidence |
| P3 | **Co-design numbers.** 6-byte frame CRC: `crcb` = **60 cycles**, software shift-xor = **1276 cycles** (**21× speedup**). Both produce 0xCC77. A table-driven CRC needs 512 B = 16× our DMEM. See `testbench/app/evidence/run_crc_bench.py` (FIRMWARE 6, `tb_crc_bench.v`) | Testbench, `x4_dbg_o` cycle count | Day 3 | Guide §5 asks how CRC/Zmmul are used |
| P4 | **Two FSMs in one waveform.** Hardware control-unit state and application state (`x4_dbg_o`) side by side | GTKWave | Day 3 | Continues our Phase 2 edge visually |

#### What it is not — honesty statements for the report

- **Not a new charging standard or protocol**, and not a world first in
  grid-responsive charging.
- **CRC is not security.** It detects accidental corruption and broken
  sequences; an attacker can recompute a CRC. Tamper-proof billing needs a
  cryptographic MAC — out of scope.
- The control pilot is an analogue ±12 V signal; we model its decoded state as
  a 3-bit code from a pilot-sensing circuit.
- A real charger asks the car to stop through the pilot PWM before opening the
  contactor, and advertises its current limit through PWM duty. We have no
  timer/PWM, so pause happens at contactor level and the current limit is a
  fixed parameter.
- Grid thresholds are placeholders, not quoted grid-code values.
- Meter frames are the time base; there is no real-time clock.

### 7.2 System context (guide §4)

The controller inside an AC charging station. It sits between:
- **the car**, via the control-pilot line (sensed as a GPIO code) and the charging cable (contactor + cable lock);
- **the station's energy meter**, which sends one CRC-protected frame per metering interval over UART;
- **the backend / charge-point operator**, which receives a session record (charge detail record) over UART when the session ends.

In the emulator, `./emu` plays the car (`-i`), the meter (`-t`), the backend (`-r`) and the indicator/relay observer (`-o`).

### 7.3 Pin map (chip view) — proposed, freeze day 1

DATADIR = `0xF0` (P7–P4 outputs, P3–P0 inputs) — the same split as the official firmware.

| Pin | Dir | Signal | Meaning |
|---|---|---|---|
| P2–P0 | in | `CP_STATE` | Control-pilot state code: 0 = A (no car), 1 = B (connected), 2 = C (charge request), 3 = D (charge, ventilation required), 4 = E (error), 5 = F (EVSE fault); 6, 7 invalid |
| P3 | in | `SAFETY_TRIP` | 1 = emergency stop pressed or residual-current device tripped |
| P4 | out | `CONTACTOR` | 1 = power on the cable |
| P5 | out | `CABLE_LOCK` | 1 = cable locked in the socket |
| P6 | out | `GRID_HOLD` | 1 = charging paused for grid support |
| P7 | out | `FAULT` | 1 = latched fault |

Reset value of `IN` is 0 → state A with no safety trip → **safe default**.

### 7.4 Meter frame (UART in) — proposed, freeze day 1

8 bytes, all fields little-endian (matches `./emu -t` byte order):

| Bytes | Field | Unit | Example |
|---|---|---|---|
| 0–1 | `V` voltage | 0.1 V | 2300 = 230.0 V |
| 2–3 | `I` current | 0.1 A | 160 = 16.0 A |
| 4–5 | `F` frequency | 0.01 Hz | 5000 = 50.00 Hz |
| 6–7 | `CRC` | CRC-16 over bytes 0–5 with `crcb`, **seed = the CRC field of the previous frame received, valid or not** (0xFFFF after reset). The meter advances its chain on every frame it produces | — |

**Why "previous frame received", not "last accepted":** there is no per-frame
acknowledgement (the emulator allows only 8 reply bytes per command), so the
meter cannot know which frames the charger accepted. Seeding from the
previous frame's transmitted CRC field makes the chain self-resynchronising:
a corrupted payload costs exactly one rejected frame, and a dropped or
re-ordered frame is caught as one rejected frame (the one after the gap).
A replayed frame, or a corrupted CRC field, costs two frames → `FAULT`.

As `./emu` options: `-t4 (I<<16 | V) -t4 (CRC<<16 | F)`.

### 7.5 Session record (UART out) — proposed, freeze day 1

Exactly one record per session, **8 bytes** (the emulator's per-command limit),
sent when the session ends (car unplugged) or when a fault latches:

| Bytes | Field |
|---|---|
| 0–3 | `ENERGY`, 32-bit Σ V·I over accepted frames while charging (unit 0.01 W × frame interval; host converts to kWh) |
| 4 | `STATUS`: bits [2:0] end state, bits [7:3] cause flags (E-stop, CP error, over-current, CRC chain lost, grid hold occurred) |
| 5 | `FRAMES`: number of accepted (billed) frames |
| 6–7 | `CRC` over bytes 0–5, seed 0xFFFF |

As `./emu` options: `-r4 ENERGY -r2 (FRAMES<<8 | STATUS) -r2 CRC`.

### 7.6 Application FSM (runs on the hardware FSM; state mirrored in `x4`)

| State | Outputs P7..P4 | `-o` value | Leave when |
|---|---|---|---|
| `IDLE` (A) | 0000 | `0x00` | CP = B, C or D → `CONNECTED` (clear energy, frame count, flags) |
| `CONNECTED` (B) | lock | `0x20` | CP = C → `CHARGING`; CP = A → `IDLE` (send record); CP = B or D → stay (D: no ventilation support, charging refused) |
| `CHARGING` (C) | lock + contactor | `0x30` | CP = B or D → `CONNECTED`; CP = A → `IDLE` (send record); frame rules below |
| `GRID_HOLD` | lock + grid-hold | `0x60` | CP = B or D → `CONNECTED`; CP = A → `IDLE` (send record); frame rules below |
| `FAULT` | fault | `0x80` | Latched. Only `SAFETY_TRIP = 0` **and** CP = A → `IDLE` (no record — it was sent on entry) |

**Pilot/safety rules** are evaluated continuously and re-applied until the
state is stable (so CP = C straight from `IDLE` goes `IDLE → CONNECTED →
CHARGING`). In every state except `FAULT`, checked first: `SAFETY_TRIP = 1` →
`FAULT` with the E-stop flag; CP ≥ 4 (E, F, invalid 6/7) → `FAULT` with the
CP-error flag. Entering `FAULT` sends the record.

**Frame rules** (on the 8th byte of each frame; frames are aligned by byte
count from reset — no resync byte, the emulator always sends whole frames):
1. `valid = (CRC-16(bytes 0–5, seed) == CRC field)`; then **seed ← CRC field** (always).
2. Invalid → consecutive-bad counter + 1; at 2, in any state except `FAULT` → `FAULT` with the CRC-lost flag. Stop.
3. Valid → counter ← 0, then by state:
   - `CHARGING`: `I > I_MAX` → `FAULT` (over-current flag); else `F < F_LOW` or `V < V_SAG` → `GRID_HOLD` (grid-hold flag; delay ← `HOLD_BASE + (hash & 7)`, hash = CRC-16 of the 4 `CHARGER_ID` bytes little-endian, seeded with this frame's CRC field; hold count ← 0); else bill: energy ← (energy + V·I) mod 2³², frames ← min(frames + 1, 255).
   - `GRID_HOLD`: healthy → hold count + 1, and at hold count ≥ delay → `CHARGING` (that frame is not billed); unhealthy → hold count ← 0. Over-current is ignored (contactor open).
   - Other states: nothing beyond the chain update.

**Record** (§7.5): `STATUS[2:0]` = the state being entered (0 `IDLE` or 4
`FAULT`); flag bits: `0x08` E-stop, `0x10` CP error, `0x20` over-current,
`0x40` CRC lost, `0x80` grid hold occurred. `FRAMES` saturates at 255.

**Constants (placeholders, not grid-code values; `.equ` in firmware, same names in the golden model):**
healthy when `F ≥ F_LOW` and `V ≥ V_SAG`.

| Name | Raw value | Meaning |
|---|---|---|
| `F_LOW` | 4950 | 49.50 Hz |
| `V_SAG` | 2070 | 207.0 V (−10 % of 230 V) |
| `I_MAX` | 320 | 32.0 A (over-current when `I > I_MAX`) |
| `HOLD_BASE` | 2 | minimum healthy frames before restart |
| `CHARGER_ID` | `0x4D590001` | "MY" + 0001; hashed as bytes `01 00 59 4D` |

**Restart hash:** on entering `GRID_HOLD`, `hash = CRC-16(CHARGER_ID bytes, seed = CRC of the triggering frame)`;
wait `HOLD_BASE + (hash & 7)` healthy frames. Different chargers and different
events give different delays; the Python golden model predicts the exact frame.

**P1 result (2026-09-27): passed, hash frozen as `hash & 7`.** Over 10,000
sequential charger IDs the 8 delay buckets hold exactly 1,250 each (CRC is
linear, so sequential IDs spread perfectly); over 10,000 random trigger events
for one charger, 1,220–1,278 per bucket.

### 7.7 Input → processing → output summary (guide §4 wording)

| | |
|---|---|
| **System context** | Controller of a public AC EV charging station that protects the car, the user, the grid, and the bill |
| **System input** | Control-pilot state + safety trip (GPIO); CRC-chained meter frames V/I/f (UART) |
| **System processing** | IEC 61851 state machine; chained CRC validation (`crcb`); energy accumulation (`mul`); grid-health check; CRC-hashed de-synchronised restart; fault latching |
| **System output** | Contactor, cable lock, grid-hold and fault indicators (GPIO); one CRC-protected session record (UART) |

### 7.8 Emulator mapping — scenario set (Emulator Preview)

Each scenario is **one `./emu` command**, and the same scenario is a test in
our Verilog testbench, which prints the equivalent command line. `<…>` values
come from the Python golden model.

| # | Scenario | Shape of the command |
|---|---|---|
| S1 | Normal session | `-d 0xF0 -i 0 -o 0x00 -i 1 -o 0x20 -i 2 -o 0x30 -t4 <f1a> -t4 <f1b> -t4 <f2a> -t4 <f2b> -i 1 -o 0x20 -i 0 -o 0x00 -r4 <E> -r2 <S> -r2 <C>` |
| S2 | Grid under-frequency → hold → CRC-timed restart | as S1, with a frame at F = 49.20 Hz → `-o 0x60`, then healthy frames → `-o 0x30` exactly at the predicted frame |
| S3 | Corrupted frame and dropped frame | each costs one rejected (unbilled) frame; charging continues at `0x30`; chain resynchronises |
| S4 | Meter link lost | two consecutive corrupted frames → `-o 0x80`, record with the CRC-lost flag |
| S5 | Emergency stop while charging, latch | `-i 0x0A` (C + SAFETY_TRIP) → `-o 0x80`, record with the E-stop flag; stays `0x80` until E-stop released **and** unplugged |
| S6 | Plug straight into C, unplug while charging | CP A → C → `0x30`; C → A → contactor off immediately, `-o 0x00`, record |
| S7 | Boundaries and over-current | frame at exactly V_SAG, F_LOW, I_MAX is billed; I = I_MAX + 1 → `-o 0x80` |
| S8 | Ventilation required, then CP error | CP = D refused (`0x20`) or stops charging; CP = E → `FAULT` |
| S9 | Invalid pilot code | CP = 7 → `FAULT` with CP-error flag |
| S1X | Stress: S1 with back-to-back UART bytes | proves the firmware keeps up with no gap between bytes |

Exact command lines and expected values are generated by the Python golden
model (implementation plan: `docs/superpowers/plans/2026-09-27-grid-aware-ev-charger.md`)
into `chip-inventor/emulator/emu_commands.txt`.

**Repo layout mirrors the organiser's Stage 3 repo**, so evaluators find each
piece where they expect it:

| Organiser folder | Ours |
|---|---|
| `RVBL-GPIO-UART-Test-Firmware/` | `chip-inventor/testbench/organiser/` |
| `RVBL-Firmware-Builder/` | `chip-inventor/firmware/` — same layout; our `src/main.s` drops into their builder unchanged |
| `RVBL-Emulator/` | `chip-inventor/emulator/` — our application protocol, `emu_commands.txt`, and a Stage 4 runner script |

The testbench's `emu_d / emu_i / emu_o / emu_t / emu_r` tasks mirror the
options 1:1, so a passing simulation *is* a passing `./emu` command against
our RTL — and, if we reach the top 10, the same lines run unchanged on the FPGA.

### 7.9 Alternatives considered

| Idea | Why not chosen |
|---|---|
| Solar PV protection relay | Strong runner-up; harder for a general audience; CRC rationale (telemetry) less vivid than billing |
| Train protection (braking curve) | "Speed → brake" echoes the organiser's drone example |
| Vibration monitor | Best feature (public dataset replay) is impossible through `./emu` |
| EV battery monitor | Reads close to the organiser's ECU sample |
| Flood early warning | Too little computation; MUL barely used |

---

## 8. Three-day plan (27 → 30 Sep)

| Day | Date | Work |
|---|---|---|
| 1 | Sun 27 | **Install RISC-V toolchain** (MSYS2 `riscv64-unknown-elf` package recommended; no toolchain on the dev machine today). Copy the organiser Firmware-Builder into `chip-inventor/firmware/` (Makefile, `bsp/`, `scripts/` unchanged; our `src/main.s`). Rebuild the organiser test firmware and diff against their `firmware.txt` to validate the toolchain. Python golden model: CRC chain, energy, restart hash, session record; check `"123456789"` → `0x29B1`. **Run the delay-spread check (P1) and fix the hash if uneven, then freeze §7.3–7.6.** Export the ChipInventor block diagram. |
| 2 | Mon 28 | `main.s`: I/O layer (UART byte RX/TX, GPIO), frame receiver + chained CRC, FSM, metering, grid hold, session record. Add as FIRMWARE 5 via `gen_imem.py`. Testbench with `emu_*` tasks; S1, S3, S5 passing by end of day. |
| 3 | Tue 29 | Remaining scenarios S2, S4, S6–S8; cycle measurements (P3: `crcb` vs software CRC); `./emu` command export; waveform screenshots incl. the two-FSM view (P4). Rebound simulation graph (P2). Report draft. Video script. |
| 4 | Wed 30 | Record video (human narration, subtitles, ≤ 8 min). Final report PDF. Repo cleanup: firmware `.bin` + `.s`, all sources, README with clean-checkout steps. **Submit well before 23:59 MYT.** |

**Cut order if late:** drop S8 → drop the chained CRC (keep per-frame CRC) →
keep grid hold with the CRC-hashed restart (the core of the story).

---

## 9. Open questions — confirm with organisers

| # | Question | Why it matters |
|---|---|---|
| 1 | Do the cover and TOC count towards the 7-page limit? | Page budget |
| 2 | Is the "no AI narration / mandatory subtitles" rule still in force for the 8-min video? | Recording plan |
| 3 | Does DMEM stay at 8 words for Stage 3? | Design assumes yes |
| 4 | Does the wrapper's `OUT` register return only the output pins (input pins read as 0)? (`-d` polarity and the first-8-bytes RX window are now confirmed by the emulator README — §3.) | `-o` expected values |
| 5 | `emu.c` returns `EXIT_FAILURE` on success (`return err ? EXIT_SUCCESS : EXIT_FAILURE`). Intended? | Our scripts must parse `[ok]`/`[error]` instead |
| 6 | Where do team-testbench results (guide §6) go, given the report covers only topics 1–5? | Report page budget |
