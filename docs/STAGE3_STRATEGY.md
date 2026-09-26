# Stage 3 — Brief, Constraints, and Stand-Out Strategy

**Last updated:** 2026-09-26 (rev 2 — after the official Submission Guide)
**Sources:** `docs/Submission Guide_Stage__Block_Guide_Stage_3.pdf` (**authoritative**),
`docs/BlockGuide_Stage3_Part1.pdf`, `docs/meeting_min.md`, organiser slides
from the 2026-09-22 briefing, the organiser repo
[CCX_Malaysia_Edition_Stage_3](https://github.com/championchip-experience-community/CCX_Malaysia_Edition_Stage_3),
our RTL in `chip-inventor/rtl/`, and public competitor repos.

**Status:** research + recommendation. The application choice in §7 is a
*recommendation pending team decision*.

> ## ⚠ Deadline: **30 September 2026, 23:59 MYT** — 4 days from this revision. Late submissions are not accepted.

---

## 0. What changed in rev 2 (vs. rev 1 of this doc)

| Topic | Rev 1 assumption | Submission Guide says | Impact |
|---|---|---|---|
| Deadline | unknown | **30 Sep 2026 23:59 MYT** | Scope must fit 4 days. §8 plan. |
| Synthesis | Stage 3 ends at Sky130/OpenLane synthesis | **Not a deliverable.** Workflow ends at "Emulator Preview"; AWS FPGA not covered | Drop OpenLane from the critical path. |
| Emulator | Stage 4 / disputed | **In scope as a concept:** app definition must explain `./emu` values; video must show emulator ↔ processor logic. Running on AWS is **not** required | Design the app's I/O around `./emu` options (§3). |
| Official test | "echo test recommended" | **Mandatory:** run the organiser's GPIO/UART test firmware on our integrated design; logs/waveforms go in the report | Top priority, day 1. |
| Block diagram | ChipInventor for figures | **Mandatory:** block diagram generated in ChipInventor (coloured wires, project as a block) | Day 1 alongside integration. |
| Video | 1 min | **Max 8 min**, three parts: technical, application logic with `./emu`, pitch | Script in §2.4. |
| Report | cover, TOC, screenshots, one font | **Topics 1–5 of the guide, PDF, max 7 pages, max 10 MB** | Tight — outline in §2.3. |
| Firmware format | C or asm (open) | Organiser builder is **assembly** (`src/main.s`); firmware must be delivered in **binary and assembly** | Write the app in assembly. |
| App candidates | Vibration monitor with Goertzel + CWRU dataset replay | Each `./emu` run **resets the processor** and moves UART data in 1/2/4-byte chunks | Streaming thousands of samples through the emulator is impractical. Re-scored in §7. |
| Integrity | — | Code must be the team's own; copying from other teams → penalties/disqualification | Competitor repos below are for landscape only. **Do not reuse their code.** |

---

## 1. Scope and workflow for Stage 3

Official workflow (Submission Guide §1 figure):

`GPIO & UART integration → Official Firmware Testbench → [Application Definition → Application Firmware Development → Application Firmware Testbench] → Emulator Preview`

The bracketed part is the "Application guide scope". The guide says: *"Your
team's focus must be strictly on developing the application logic and the
firmware (AWS FPGA direct implementation will not be covered in this part)."*

| # | Step | Guide § | Our status |
|---|---|---|---|
| 1 | GPIO & UART integration (+ ChipInventor block diagram) | §2 | RTL + unit testbenches exist (`gpio.v`, `uart.v`, `uart_tx.v`, `uart_rx.v`, `testbench/gpio`, `testbench/uart`). ChipInventor integration still open per `chip-inventor/HANDOFF_ZHU_HENG.md`. Tests not re-run for this review. |
| 2 | Official Firmware Testbench | §3 | Not started |
| 3 | Application Definition | §4 | **Pending decision (§7)** |
| 4 | Application Firmware Development | §5 | Not started |
| 5 | Application Firmware Testbench (team's own) | §6 | Not started |
| 6 | Emulator Preview (`./emu` command set for our app) | §4, §7 | Not started. Organiser says full emulator instructions come "later in Stage 3". |

---

## 2. Deliverables checklist

### 2.1 Files to submit (guide §9)

1. Technical report — PDF, **≤ 7 pages, ≤ 10 MB**, covering guide topics 1–5.
2. GitHub link.
3. Video demo — YouTube link, **≤ 8 minutes**.
4. Project files: **all** source code (C, Verilog, …) and the complete firmware
   in **both binary and assembly** (`firmware.bin` + `main.s`; the builder also
   emits `firmware.txt` and `firmware.dmp`).

Evaluators may reproduce the simulation and execution flow on AWS from the
submitted files — **the repo must build and simulate from a clean checkout.**

### 2.2 Official Firmware Testbench (guide §3) — mandatory

Organiser firmware (`RVBL-GPIO-UART-Test-Firmware`) loops:
read P3–P0 → write them to P7–P4 (`DATADIR = 0xF0`) → wait for a UART byte → echo it.

Our testbench must:
- Load `firmware.txt` into IMEM.
- Apply `0xA` on P3–P0 and expect `0xA0` on DATAOUT (P7–P4 = `0xA`).
  GPIO stimulus must be stable **before** the firmware's GPIO read.
- Then send `0x30` on `rx_i` and expect `0x30` back on `tx_o`.
- Timeout detection, and clear log lines:
  ```
  [PASS] GPIO: P3-P0 = 0xA, P7-P4 = 0xA
  [PASS] UART: RX = 0x30, TX = 0x30
  [PASS] GPIO and UART firmware test completed successfully
  ```
- A waveform showing clock, reset, GPIO transitions, and UART byte timing — screenshot for the report.

### 2.3 Report outline (7 pages, topics 1–5 only)

| Page budget | Guide topic | Content |
|---|---|---|
| ~1 | 1. Project Overview | Goal, architecture, how the firmware uses UART + GPIO in a real-world scenario |
| ~1.5 | 2. GPIO & UART Integration | Integration design, address decoding, **ChipInventor block diagram** (mandatory) |
| ~1 | 3. Official Firmware Testbench | PASS log + waveform screenshot |
| ~1.5 | 4. Application Definition | Context / Input / Processing / Output, pin map, `./emu` values for our tests |
| ~2 | 5. Firmware Development and Processing | UART frame handling, **how CRC and Zmmul are used**, how GPIO control is driven. The guide names CRC/Zmmul explicitly — this is where the co-design numbers (L2) go |

Plus, from the earlier slide: cover (members, team, project name), table of
contents, legible screenshots, one font family. Check whether the cover/TOC
count towards the 7 pages — assume yes to be safe (§9, Q1).

### 2.4 Video (guide §7, ≤ 8 min) — suggested split

| Part | Time | Content |
|---|---|---|
| 1. Technical | ~3 min | Architecture, GPIO/UART integration, ChipInventor diagram, official testbench PASS, firmware structure, CRC/MUL usage with measured cycle numbers |
| 2. Application logic | ~3 min | Walk through `./emu` command lines → what the processor receives → what it computes → GPIO/UART results. Show the team testbench running the same vectors, including a rejected corrupted frame |
| 3. Pitch | ~1.5 min | Problem, value, who would use it, why this design |

From the earlier slides (still assumed valid): **human narration only (no AI
voice), mandatory subtitles**, professional tone.

---

## 3. Emulator (`./emu`) facts — these shape the application

From the organiser's `RVBL-Emulator/README.md`:

| Option | Meaning |
|---|---|
| `-d DIR` | GPIO direction, per bit: 0 = input driven by the emulator, 1 = output observed by the emulator |
| `-i DATA` | Drive an 8-bit value onto the processor's GPIO inputs |
| `-o DATA` | Read the processor's GPIO outputs and **verify** they equal `DATA` |
| `-t1 / -t2 / -t4 V` | Send 1, 2 or 4 bytes to the processor over UART, **least-significant byte first** |
| `-r1 / -r2 / -r4 V` | Read 1, 2 or 4 bytes from the processor and **verify** they equal `V` |

Rules:
- **All operations of one test go in one command, in the order the firmware expects.**
- **Each run resets the processor.** No state survives between commands.
- Numbers accept decimal or hex.

Consequences for the application:
1. **Transaction-based, not long-running.** One command = one scenario: set
   inputs, send a short packet, check outputs. Anything that needs history
   (trends, averages) must receive that history inside the same command.
2. **Keep packets short**, built from 4-byte and 2-byte chunks. A 10-byte
   packet is `-t4 -t4 -t2`; a 4-byte reply is `-r4`.
3. **LSB-first on the wire** — a 32-bit value sent with `-t4` arrives low byte first.
4. **An `./emu` command is itself a self-checking test vector** (`-o` and `-r`
   verify). So every vector in our Verilog testbench can be exported 1:1 as an
   `./emu` command line. This is our Emulator Preview deliverable, and a strong
   point for the video.

---

## 4. Hardware facts that constrain the application

| Resource | Fact | Source | Consequence |
|---|---|---|---|
| GPIO | 8 pins, `0xF0000000`: DATAOUT `+0x0`, DATAIN `+0x4`, DATADIR `+0x8` (1 = output) | Block Guide §1 | Pin map is a design decision to explain. |
| UART | 115200 8-N-1, `0xF1000000`: TXDATA `+0x0`, RXDATA `+0x4`, CONTROL `+0x8` (bit0 TRANSMIT, bit1 RXDONE, bit2 TXDONE). **Single-byte buffer, no flow control, no interrupts** | Block Guide §2 | Polling; firmware must read each byte before the next one lands. |
| Clock | 20 MHz (`CLOCK_PERIOD 50.0`) | `chip-inventor/config.json` | ≈5 MIPS peak. |
| CPI | ALU/MUL/CRC 4, branch 3, store 4, **load 6** | Handoff §2 | ~4 cycles/instruction. |
| Byte time | 10 × 174 = **1740 cycles/byte** | `uart.v` | ~400 instructions of budget per received byte. |
| DMEM | **8 words = 32 bytes** (organiser instruction, all teams) | `dmem_eq26.v` header | No buffers or lookup tables; state lives in registers. |
| IMEM | `case` ROM, ≤ 1024 words | `imem.v` | Plenty for an assembly app. |
| Timer / interrupts | None (no CSRs, no `rdcycle`) | ISA | Time comes from the data (sample index), not a clock. |
| Arithmetic | `mul/mulh/mulhsu/mulhu`, **no divide, no FP** | Handoff §8 | Fixed point; compare `a² ≥ k²·b` instead of dividing. |
| CRC | `crcb/crch/crcw`, CRC-16 poly `0x1021`, non-reflected, xorout 0, seed via second operand | `crc.eq26.v` | Seed `0xFFFF` = **CRC-16/IBM-3740 (CCITT-FALSE)**, check value `"123456789"` → **`0x29B1`**. |

**CRC byte-order gotcha:** `crcw` consumes bit 31 first; `lw` on
little-endian memory puts the first stream byte in bits [7:0]. So `crcw` on a
loaded word processes stream bytes in **reverse** order. And `./emu -t4` also
sends LSB first. Decide the byte order once, write it into the protocol spec,
and use `crcb` per byte if in doubt. Confirm the rs1/rs2 → `a_i`/`b_i`
operand mapping in `top.v` before writing firmware.

**Custom instructions in assembly:** the organiser builder assembles
`src/main.s` with the stock GNU toolchain, which does not know `crcb` & co.
Encode them with `.insn r` (or `.word`) using opcode/funct3/funct7 from the
handoff opcode table — never from memory. Check the builder's `-march` accepts
`mul` (Zmmul/M) or encode MUL the same way.

---

## 5. Competitive landscape

- **Every team builds the same RVBL-2 spec** (RV32I + Zmmul + Xicrc) — e.g.
  [Niccc8/rvbl2-riscv-cpu-core](https://github.com/Niccc8/rvbl2-riscv-cpu-core),
  [Lourencohg/championchip-rv32-riscv](https://github.com/Lourencohg/championchip-rv32-riscv).
  Having CRC/MUL is not a differentiator; **using them in the app and measuring
  the benefit is** — and guide §5 explicitly asks how CRC/Zmmul are used.
- The strongest visible competitor already has clean Sky130 sign-off and
  7,384+ checks over 15 testbenches. Verification rigour is table stakes.
- Likely crowd choices: drone, stock market, game (organiser examples),
  traffic lights, smart home, temperature monitor, ECU copies of the organiser
  sample. **Do not look at or reuse other teams' code** (guide Note 1).

---

## 6. Stand-out strategy — levers, re-ranked for 4 days

| # | Lever | Effort | Why it scores |
|---|---|---|---|
| L1 | Application outside the crowd, tied to a real problem and a cited standard | low | Pitch and "Application Definition" marks |
| L2 | **CRC + MUL in the hot path, with measured cycle counts.** GPIO probe-pin: firmware toggles a spare pin around a routine, testbench counts cycles. Compare `crcb` vs a bitwise software CRC (and note a table CRC needs 512 B = 16× our DMEM) | low–med | Guide §5 asks for exactly this |
| L3 | **CRC-protected packets** with a defined error response (bad CRC → error code on UART + fault pin), shown in the video | low | "Validation logic" and robustness |
| L4 | **Testbench vectors exported 1:1 as `./emu` commands** — one source of truth for simulation and emulator | low | Directly satisfies "Emulator Values (./emu)" and video part 2 |
| L5 | Self-checking team testbench: Python golden model → vectors → Verilog testbench with UART driver/monitor, PASS/FAIL log, requirement → test table | med | Guide §6 |
| L6 | Clean, reproducible repo: one `make`/script builds firmware and runs every testbench from a clean checkout | low | Evaluators may reproduce the flow |
| L7 | Presentation polish: human narration + subtitles, tight 8-min structure, 7-page report that reads well | med | Cheap marks careless teams lose |

Dropped for Stage 3 (no longer in scope or not feasible in 4 days): OpenLane
area/timing reporting, public-dataset replay through the emulator, Stage 4
FPGA top-adaptation prep.

---

## 7. Application candidates — re-scored

New filters: fits the `./emu` model (one command = one short transaction,
reset every run) and is buildable in assembly in ~1.5 days.

| Criterion (3 = best) | A′. Vibration severity monitor (lite) | B. EV battery-pack monitor | C. Solar PV protection relay | D. Flood early-warning |
|---|---|---|---|---|
| Distance from examples / ECU | 3 | 1 | 3 | 3 |
| Real MUL use | 3 (sum of squares, crest factor) | 2 (power, scaling) | 3 (P = V·I, V²/I² limits) | 1 |
| Natural CRC use | 3 | 3 | 3 | 3 |
| Fits `./emu` transaction model | 2 (short window per command) | 3 | 3 | 2 (history in one command) |
| Uses GPIO in and out meaningfully | 2 | 3 | 3 | 2 |
| 4-day feasibility | 2 | 3 | 3 | 3 |
| Demo clarity | 3 | 3 | 2 | 3 |
| Risk of looking "too simple" | 3 | 2 | 2 | 1 |
| **Total** | **21** | **20** | **22** | **18** |

### C. Solar PV grid-tie protection relay — **now recommended**

- **Context:** a rooftop-solar inverter's protection relay (Malaysia's NEM
  rooftop-solar programme). It decides whether the inverter may stay connected
  to the grid, per grid-code voltage/frequency/power limits.
- **Input** (one `./emu` command):
  - UART packet (10 bytes = `-t4 -t4 -t2`): voltage (int16), current (int16),
    frequency (uint16, 0.01 Hz), sequence/flags (uint16), CRC-16 (2 bytes).
  - GPIO in: P0 grid-breaker-closed feedback, P1 manual isolate/E-stop.
- **Processing:**
  1. Validate the CRC with `crcb` — bad CRC → error reply + fault pin, no action.
  2. P = V·I with `mul`; S² vs P² comparison for power-factor limit (no sqrt, no divide).
  3. Over/under-voltage, over/under-frequency, over-power checks against limits.
  4. Decision: CONNECT / DERATE / TRIP, with E-stop override.
- **Output:**
  - GPIO out: P4 connect relay, P5 derate flag, P6 trip/fault LED, P7 probe pin (cycle measurement).
  - UART reply (4 bytes = `-r4`): status code, fault bits, CRC-16 of the reply.
- **Why it moved to first:** every input fits in one short `./emu` command,
  GPIO is used both ways, the MUL use is genuine, and it is fully buildable in
  assembly within the deadline.
- **Weakness:** single-snapshot decisions (no RMS over a cycle), synthetic data only.

### A′. Vibration severity monitor (lite) — distinctive alternative

- Rev 1's recommendation, cut to fit the emulator: each command sends one
  short window (e.g. 8 int16 samples = 16 bytes + 2 CRC bytes = `-t4 ×4 -t2`).
  Firmware computes the sum of squares (`mul`/`mulh`), peak, and a crest-factor
  test without division, then maps RMS to ISO 20816 severity zones A/B/C/D.
  Output: zone LEDs + trip pin; reply with zone + RMS.
- Goertzel fault detection and CWRU dataset replay are **dropped** — not
  meaningful on 8 samples, not feasible in 4 days.
- Most novel of the four, but the "window per command" framing is a little
  artificial, and GPIO input use is thin.

### B. EV battery-pack monitor — lowest risk

- Packet: 4 cell voltages + pack current + CRC. Processing: min/max/imbalance,
  OV/UV/OC, pack power (`mul`), balancing decision. GPIO out: balance switches,
  contactor, fault; GPIO in: charger connected, E-stop.
- Very natural fit, but automotive — reads close to the organiser's ECU sample.

### D. Flood early-warning — weakest

- Needs history (rate of rise), so every command must carry several readings;
  computation is thin and MUL use is marginal.

### Recommendation

**C (solar protection relay)** for the deadline: best fit to `./emu`, strong
GPIO in/out story, genuine CRC + MUL use, low build risk. **A′** if the team
values novelty over fit. Either way, the protocol, CRC handling, testbench,
and `./emu` export (L2–L6) are identical, so the choice does not change the
day-1 and day-3 work.

---

## 8. Four-day plan (26 → 30 Sep, submit by the evening of 30 Sep with margin)

| Day | Date | Work |
|---|---|---|
| 1 | Sat 26 – Sun 27 | Finish ChipInventor GPIO/UART integration; export the block diagram. Build the organiser test firmware, run the **official testbench**, capture PASS log + waveform. Team picks the app (§7) and freezes the packet format. |
| 2 | Mon 28 | App firmware in assembly (`RVBL-Firmware-Builder`). Python golden model + vector generator (also emits `./emu` command lines). Check the CRC byte-order golden `0x29B1` first. |
| 3 | Tue 29 | Team testbench: all directed vectors + bad-CRC/E-stop cases, probe-pin cycle counts. Report draft (7 pages). Video script. |
| 4 | Wed 30 | Record video (human narration, subtitles, ≤ 8 min). Final report PDF (≤ 10 MB). Repo cleanup: firmware `.bin` + `.s`, all sources, README with build/run steps from a clean checkout. **Submit before 23:59 MYT.** |

---

## 9. Open questions — confirm with organisers

| # | Question | Why it matters |
|---|---|---|
| 1 | Do the cover and TOC count towards the 7-page limit? | Page budget in §2.3 |
| 2 | Is the "no AI narration / mandatory subtitles" slide rule still in force for the 8-minute video? | Recording plan |
| 3 | Does DMEM stay at 8 words for Stage 3? | Our design assumes yes |
| 4 | Full `./emu` instructions are promised "later in Stage 3" — any constraint on number of options per command or allowed chunk sizes beyond 1/2/4 bytes? | Packet format |
| 5 | Which `-march` does the Firmware Builder use (does it accept `mul`)? How do they expect custom Xicrc instructions to be written? | Firmware encoding |
| 6 | Where do the team testbench results (guide §6) go, given the report covers only topics 1–5? Video and repo only? | Report page budget |
