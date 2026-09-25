# Stage 3 — Brief, Constraints, and Stand-Out Strategy

**Date:** 2026-09-26
**Sources:** `docs/BlockGuide_Stage3_Part1.pdf` (v1.0, Part 2 not yet released),
`docs/meeting_min.md`, organiser slides from the 2026-09-22 briefing (Roadmap,
Video Guideline ×2, Report Guideline, Pedro's repo walkthrough), our own RTL in
`chip-inventor/rtl/`, and public competitor repos.

**Status of this document:** research + recommendation. The application choice
in §6 is a *recommendation pending team decision*, not a decided design.

---

## 1. Our scope for Stage 3

The organiser roadmap (slide "Roadmap") has 10 boxes in four colour groups.
Our working assumption: Stage 3 ends at **Sky130/OpenLane synthesis** of the
core + GPIO + UART with our application firmware in IMEM. Everything on AWS F2
is Stage 4 (top-10 teams only). This matches the ASEM page: Stage 3 = "Design
Challenge… SkyWater 130nm PDK", Stage 4 = "AWS Cloud FPGA Prototype".

| # | Roadmap box | Colour group | Stage | Our status |
|---|---|---|---|---|
| 1 | GPIO & UART integration | green | 3 | RTL + unit testbenches exist (`gpio.v`, `uart.v`, `uart_tx.v`, `uart_rx.v`, `testbench/gpio`, `testbench/uart`). Chip Inventor integration still open per `chip-inventor/HANDOFF_ZHU_HENG.md`. Tests not re-run for this review. |
| 2 | Communication firmware test (testbench) | green | 3 | Not started. Echo test is the organiser-recommended first step. |
| 3 | Application definition | green | 3 | **This document — pending decision (§6).** |
| 4 | Application firmware development | yellow | 3 | Not started |
| 5 | Application firmware testbench | yellow | 3 | Not started |
| 6 | Emulator adaptation (C) | yellow | **disputed** — see §8 | Not started |
| 7 | Top adaptation Verilog | purple | 4 | — |
| 8 | Synthesis on AWS (FPGA) | purple | 4 | — |
| 9 | Load FPGA image on F2 | purple | 4 | — |
| 10 | Run the emulator | purple | 4 | — |
| — | Record 1-min video demonstration | pink | 4 per roadmap; guidelines already given | — |

For Stage 3 we additionally owe an **OpenLane (Sky130) synthesis** of the
updated design (core + peripherals + app firmware ROM).

---

## 2. What the organisers asked for

### 2.1 Application definition (meeting minutes)

- Define a concrete **system context** and the **processor's responsibility**:
  what inputs it receives, what it computes, what it outputs.
- The organisers' examples — **do not use these, other teams will**:
  - Drone: velocity/pitch → acceleration → deceleration value / over-limit flag / motor command.
  - Stock market: price ticks → mid-price / decision metric → buy/sell.
  - Game.
- Balance creativity and feasibility. Present the application on competition day.
- The organiser's own sample repo (slide 5, `RVBL-2-AWS-FPGA`) contains
  `ecu_firmware/` (engine control unit) and `uii_firmware/`, `simple_firmware/`.
  **Automotive-ECU-style apps will look derivative of the organiser sample.**

### 2.2 Firmware and testbench (minutes)

- Firmware runs on the core, reads inputs via UART/GPIO, processes, writes outputs via UART/GPIO.
- Testbench must **simulate inputs and validate outputs against expected results**.
  Echo test is the recommended starting point. The organiser-provided
  firmware/testbench (≈10 samples promised on GitHub) is only a starting point —
  robustness is on us.
- Organiser tooling: C firmware compiled with `riscv32-unknown-elf-*` via
  `make` (slide 5 terminal: `make` → `objdump -D build/firmware.elf`), plus an
  assembler/Makefile like Stage 2.

### 2.3 Video requirements (slides "Video Guideline")

| Must show | Detail |
|---|---|
| GPIO setup | Detailed port configuration process |
| UART setup | Serial communication protocol initialisation |
| Execution | Clear step-by-step implementation logic |
| Validation firmware | Explain validation logic step by step |
| **No AI narration** | Authentic human voices only |
| **Mandatory subtitles** | Text captions for accessibility |

Delivery = **pitch presentation**: design rationale (explain GPIO/UART
choices), showcase validation logic, professional tone ("sell the technical
concept"). Roadmap final box: 1-minute demonstration video.

### 2.4 Report requirements (slide "Report Guideline")

Standard cover (members, team, project name) · mandatory table of contents ·
legible high-resolution screenshots · a single font family throughout.

### 2.5 Emulator / AWS F2 interface facts (for Stage 4 readiness)

From Pedro's walkthrough — design Stage 3 choices so Stage 4 is cheap:

- SoC on FPGA: core + GPIO + UART + memories + AXI→core wrapper.
- **GPIO via emulator:** one 16-bit register, upper 8 bits = direction
  (1 = output), lower 8 bits = value. Inputs set from the emulator must be
  de-asserted after use or they interfere with the next test.
- **UART via emulator:** separate TX-write and RX-read registers. RX is a
  **64-entry circular FIFO; Pedro recommends reading at most 8 entries at a time.**
- Reset: write 0 then 1 to the reset bit.
- Two tools: low-level AXI read/write (precise, you encode dir+value bits
  yourself) and a higher-level GUI for batch testing.

---

## 3. Hardware facts that constrain the application

These come from the Stage 3 guide and our own RTL. Any application idea that
ignores them will not fit.

| Resource | Fact | Source | Consequence for the app |
|---|---|---|---|
| GPIO | 8 bidirectional pins, `0xF0000000`: DATAOUT `+0x0`, DATAIN `+0x4`, DATADIR `+0x8` (1 = output). No pull-ups, no drive strength. | Guide §1 | 8 pins total — the pin map is a design decision worth explaining in the pitch. |
| UART | 115200 baud, 8-N-1, `0xF1000000`: TXDATA `+0x0`, RXDATA `+0x4`, CONTROL `+0x8` (bit0 TRANSMIT, bit1 RXDONE, bit2 TXDONE). **Single-byte buffer, no FIFO, no flow control, no interrupts.** | Guide §2 | Polling only. If firmware is busy when a second byte arrives, a byte is lost (our `uart.v`: newest byte wins on overrun). |
| Clock | 20 MHz (`CLOCK_PERIOD 50.0` ns in `chip-inventor/config.json`) | config | ≈5 MIPS peak. |
| CPI | ALU/MUL/CRC 4, branch 3, store 4, **load 6** | Handoff §2 | ~4 cycles/instruction average. |
| Byte time | 10 bits × 174 clk/bit = **1740 cycles/byte** | `uart.v` CLKS_PER_BIT | **~400 instructions of budget per received byte** if processing inline. |
| DMEM | Flip-flop array, **8 words = 32 bytes** (`chip-inventor`), 4 words in synth track — organiser instruction, applies to all teams | `dmem_eq26.v` header | **No sample buffers, no lookup tables.** State must live in the 31 GPRs. Streaming algorithms only. |
| IMEM | Combinational `case` ROM, ≤1024 words | `imem.v` | **Code size = silicon area** in OpenLane. Compact firmware is a measurable win. |
| Timer | None. No CSRs (no `rdcycle`), no interrupts | ISA = RV32I+Zmmul+Xicrc | **Time must come from the data** (sample index = time base), not a wall clock. |
| Arithmetic | `mul/mulh/mulhsu/mulhu` (1 instr, 4 cycles). **No divide, no floating point.** | Handoff §8 | Fixed-point (Q15/Q14) with `mulh`. Avoid division: compare `a² ≥ k²·b` instead of `a/b ≥ k`. |
| CRC | `crcb/crch/crcw`: CRC-16, poly `0x1021`, non-reflected, xorout 0, **seed in via second operand** | `crc.eq26.v` | With seed `0xFFFF` this is **CRC-16/IBM-3740 (a.k.a. CCITT-FALSE)** — catalogue check value for `"123456789"` is **`0x29B1`**. With seed `0x0000` it is CRC-16/XMODEM. |

**CRC byte-order gotcha (worth a line in the report):** `crcw` consumes bit 31
first. Memory is little-endian, so a `lw` of four stream bytes puts the *first*
stream byte in bits [7:0] — `crcw` on that word processes the stream bytes in
**reverse** order. For stream-order CRC over UART bytes, use `crcb` per byte (or
byte-swap first). Confirm the rs1/rs2 → `a_i`/`b_i` mapping in `top.v` before
writing firmware.

---

## 4. Competitive landscape

- **Every team builds the same RVBL-2 spec** (RV32I + Zmmul + Xicrc) — see
  public repos [Niccc8/rvbl2-riscv-cpu-core](https://github.com/Niccc8/rvbl2-riscv-cpu-core)
  and [Lourencohg/championchip-rv32-riscv](https://github.com/Lourencohg/championchip-rv32-riscv).
  **Having** CRC/MUL hardware is not a differentiator. **Using it where it
  matters, and measuring the win,** is.
- The strongest visible competitor (Niccc8) already has: clean Sky130
  sign-off (0 DRC, LVS match), lockstep equivalence over 410,400 cycles,
  7,384 checks across 15 testbenches, a 20-page report. **Verification rigor
  is table stakes at the top.** We must match it and add something they don't
  show.
- Neither public repo shows a Stage 3 application yet.
- Likely crowd choices: the three organiser examples (drone, stock, game),
  traffic lights, smart home, temperature monitor, and ECU copies of the
  organiser sample. Anything in this set competes on execution alone.

---

## 5. Stand-out strategy — seven levers

Ordered by expected marks per hour of effort.

### L1. Pick an application outside the crowd, anchored to a real problem and a real standard
Judges hear many drones and stock bots. An app that names a real industry
pain point, cites a real standard for its thresholds, and has local relevance
(ASEM is Malaysian; the organisers are Brazilian) reads as engineering, not a
toy.

### L2. Hardware–software co-design story with measured numbers
Put `crcb` and `mul/mulh` in the application's **hot path**, then prove the
benefit in simulation:
- **GPIO probe-pin technique:** firmware toggles a spare GPIO pin at the start
  and end of a routine; the testbench counts clock cycles between the edges.
  The same trick works later on the FPGA with a logic analyser.
- Report a table: software CRC vs `crcb`, shift-add multiply vs `mul`.
  *Rough estimates to be replaced by measurement:* bitwise software CRC-16
  ≈ 200 cycles/byte vs 4 cycles for `crcb` (~50×); software 32×32 multiply
  ≈ 600 cycles vs 4 for `mul`.
- Memory argument: a table-driven software CRC-16 needs a **512-byte table —
  16× our entire 32-byte DMEM.** Xicrc is not a nice-to-have here; it is the
  only way to get fast CRC at all.

### L3. A robust, validated UART protocol (feeds the "Validation Firmware" video segment directly)
- Framed packets: `[SOF][TYPE][SEQ][payload…][CRC16_hi][CRC16_lo]`, CRC via `crcb`.
- **Stop-and-wait:** host sends one frame, waits for the reply. This gives flow
  control for free on a UART that has none (guide §2), and keeps per-byte work
  inside the 1740-cycle budget.
- Error handling: bad CRC → NACK, SOF hunting for resync, bounded frame length.
- **Fault-injection tests:** bit flips, truncated frames, garbage between
  frames, back-to-back frames. Show the firmware rejecting them on video.
- **Replies ≤ 8 bytes**, matching Pedro's "read up to 8 FIFO entries" advice,
  so Stage 4 needs no protocol change.

### L4. Quantified validation, not "it works"
- Python golden model, **bit-exact** with the firmware's fixed-point math,
  generates stimulus and expected outputs.
- Self-checking Verilog testbench with a UART bus-functional model (drive
  `rx_i`, decode `tx_o`) and GPIO drive/monitor.
- Requirement → test traceability table (every requirement has a test ID and
  a pass/fail).
- Where possible, validate against a **public labelled dataset** and report an
  accuracy figure (confusion matrix / detection rate). A number like "correctly
  classified 97 of 100 windows" is something toy apps cannot claim.
- First golden vector for the comm test: CRC-16/IBM-3740 of `"123456789"` = `0x29B1`.

### L5. Resource-aware design as a talking point
Fits 32 B DMEM by design (register-resident state, streaming algorithms).
Report firmware size in words and the OpenLane area/timing delta for adding
GPIO + UART + app ROM. Frame it as a deliberate trade-off, same style as the
Stage 2 DMEM rationale in `v2-chip-inventor-synth/rtl/dmem_eq26.v`.

### L6. Stage-4-ready choices made now (cheap, and a good pitch line)
- Replies ≤ 8 bytes; pin map expressed in the emulator's 16-bit dir/value format.
- `CLK_HZ` / `BAUD` stay parameters (F2 clock will differ from 20 MHz).
- Keep GPIO's out/oe/in logic separable from the `inout` pad so the FPGA top
  adaptation needs no internal tri-states (FPGA fabric does not support them).
- Keep the Python frame encoder simple enough to port to the C emulator adapter.

### L7. Presentation polish
Human narration + subtitles (mandatory), a scripted 1-minute demo with a
visible before/after (e.g. LEDs change from green to red when a fault is
injected), consistent report typography, legible screenshots. Cheap marks that
careless teams lose.

---

## 6. Application candidates

Filter used: not an organiser example or ECU; uses **both** UART and GPIO;
uses MUL **and** CRC for real reasons; streaming so it fits 32 B DMEM; data
supplies its own time base; testable through UART/GPIO only; demonstrable in
one minute.

### Scoring (3 = best)

| Criterion | A. Machine-health vibration monitor | B. EV battery-pack monitor | C. Solar PV protection relay | D. Flood early-warning station |
|---|---|---|---|---|
| Distance from examples / ECU | 3 | 1 (automotive, near ECU) | 3 | 3 |
| Real MUL use | 3 (RMS, Goertzel) | 2 (coulomb count) | 3 (RMS, power) | 1 |
| Natural CRC use | 3 | 3 | 3 | 3 |
| Fits 32 B DMEM | 3 | 2 | 3 | 3 |
| Public labelled data for accuracy claim | 3 (CWRU bearing data) | 1 | 1 (synthetic) | 2 |
| 1-minute demo clarity | 3 | 3 | 2 | 3 |
| Local / industry relevance | 3 (E&E, fabs, mills) | 3 (EV roadmap) | 3 (rooftop solar) | 3 (monsoon floods) |
| Risk of looking "too simple" | 3 | 2 | 3 | 1 |
| Implementation risk (3 = low) | 2 (DSP tuning) | 3 | 2 | 3 |
| **Total** | **26** | 20 | 23 | 22 |

### A. Machine-health vibration monitor (predictive maintenance) — **recommended**

- **Context:** rotating machines (pumps, fans, motors) in Malaysian E&E plants,
  semiconductor fabs, and palm-oil mills. Unplanned bearing failure means
  downtime. The node flags developing faults early. Severity zones follow
  ISO 20816 (successor to ISO 10816) vibration-severity bands.
- **Inputs:**
  - UART data frames: batches of int16 acceleration samples (sample index is the time base).
  - UART config frames: alarm thresholds and Goertzel coefficients for this
    machine's fault frequencies, computed on the host. This doubles as the
    "configure parameters" behaviour the emulator adapter needs in Stage 4.
  - GPIO in: P0 machine-running interlock, P1 operator acknowledge/reset.
- **Processing (all streaming, register-resident):**
  1. DC removal — 1-pole IIR high-pass.
  2. RMS over an N-sample block — sum of squares with `mul`/`mulh` (64-bit accumulate).
  3. Peak and crest factor, compared without division: `peak² ≥ k²·mean_sq`.
  4. Envelope (|x| → IIR low-pass), then **Goertzel** at 1–3 configured fault
     frequencies (outer race / inner race) — Q14 coefficients with `mulh`.
     Two state words per frequency, no buffer.
  5. Health state machine Normal → Watch → Alarm → Trip, with hysteresis and debounce.
- **Outputs:**
  - GPIO out: P4/P5/P6 zone LEDs (green/amber/red), P7 trip relay. P2/P3 spare —
    one of them is the cycle-measurement probe pin (L2).
  - UART reply (exactly 8 bytes): `[SOF][TYPE][STATE][RMS_hi][RMS_lo][FLAGS][CRC_hi][CRC_lo]`.
- **Validation:** bit-exact Python golden model; synthetic sine/impulse tests
  for Goertzel correctness; replay of the **Case Western Reserve University
  bearing dataset** (public, labelled normal / inner-race / outer-race / ball
  faults) → confusion matrix. The dataset's bearing fault frequencies are
  published multiples of shaft speed — take them from the CWRU site, do not
  derive from memory.
- **Graceful scope:** RMS + ISO zones + protocol alone is already a complete,
  demonstrable app. Goertzel fault classification is the upgrade on top — if
  DSP tuning runs late we still ship.
- **Main risk:** simulation time. Thousands of samples at 1740 cycles/byte are
  slow in iverilog. Mitigation: a simulation-only `BAUD` override (fewer clocks
  per bit) for long dataset runs, full 115200 for the protocol/timing tests.

### B. EV battery-pack monitor (BMS slave)

- Inputs: frames with 4 cell voltages (mV), pack current, temperature; config
  frames; GPIO in P0 charger-connected, P1 E-stop.
- Processing: OV/UV/OT with debounce counters; coulomb-counting state of
  charge (`mul`/`mulh`); passive balancing decision; contactor state machine
  with pre-charge; fail-safe on N consecutive bad-CRC frames.
- Outputs: GPIO balance switches, contactor, fault LED; UART status frame.
- Strong CRC story (real battery front-ends CRC-protect their daisy-chain
  frames). Weaknesses: automotive, close to the organiser's ECU sample; no
  public dataset for an accuracy number.

### C. Solar PV grid-tie protection relay

- Inputs: voltage/current sample pairs; config frames with grid-code limits.
- Processing: Vrms, Irms, real power P = mean(v·i), power-factor check by
  comparing squares (no sqrt/divide), frequency from zero-crossing count
  (sample index as time base), over/under voltage and frequency trips with
  time delays.
- Outputs: GPIO trip relay, reconnect-permit, fault LEDs; UART event log.
- Strong maths. Weaknesses: synthetic data only; UART throughput limits
  samples per mains cycle (not an issue in simulation or the emulator, but
  worth stating).

### D. Flood early-warning river station

- Inputs: river level + rain-gauge tip counts per interval; config frames with
  alert thresholds.
- Processing: EWMA smoothing, rate of rise, rainfall accumulation, tiered
  alerts (Normal/Alert/Warning/Danger), optional time-to-danger estimate.
- Outputs: GPIO siren/LED tiers; UART telemetry.
- Excellent social-impact story for Malaysia. Weakness: computation is thin,
  MUL use is marginal — risks looking simple next to DSP-based entries.

### Recommendation

**A (vibration monitor)**: furthest from the crowd, heaviest legitimate use of
both custom extensions, fits the 32 B DMEM by construction, and is the only
candidate with a public labelled dataset — which turns "it works" into "97 of
100 windows correct". **Fallback: C**, which reuses the same RMS/protocol
building blocks.

---

## 7. Work that is app-independent — can start now

1. **Comm firmware test (roadmap box 2):** UART echo, then CRC echo — firmware
   returns the `crcb` CRC of received bytes. Golden: `"123456789"` → `0x29B1`
   with seed `0xFFFF`.
2. **Testbench infrastructure:** UART BFM (drive `rx_i`, decode `tx_o`), GPIO
   driver/monitor, cycle counter on a probe pin, self-checking summary.
3. **Frame protocol** (L3) with fault-injection tests.
4. Finish Chip Inventor GPIO/UART integration (`chip-inventor/HANDOFF_ZHU_HENG.md`).

---

## 8. Risks and open questions — confirm with organisers

| # | Question | Why it matters |
|---|---|---|
| 1 | Is the **emulator adaptation (C)** due in Stage 3 or Stage 4? The minutes say "a required intermediate submission for all teams now"; our reading of the roadmap/ASEM page says Stage 4. | If Stage 3, it is a missing deliverable. Hedge: keep the Python frame encoder C-portable (L6). |
| 2 | Is the **1-minute video** due at the end of Stage 3 or Stage 4? | Video guidelines were presented now; roadmap puts the video after "Run the Emulator". |
| 3 | Does **DMEM stay at 8 words** for Stage 3, or may we enlarge it for the application? | Decides whether any buffer is possible. Our plan assumes it stays at 8. |
| 4 | What will **Block Guide Part 2** add? | Might add a timer or interrupts, which would change the polling design. Keep the design adaptable. |
| 5 | May application firmware be **C** (organiser sample uses `riscv32-unknown-elf-gcc`) or must it be assembly? Which `-march`? | C needs `.insn` for Xicrc and `-march=rv32i_zmmul` for MUL. Opcode/funct fields must come from the handoff opcode table, not memory. |
| 6 | Format and count of the promised organiser test samples (~10). | Our testbench should ingest them unchanged. |
