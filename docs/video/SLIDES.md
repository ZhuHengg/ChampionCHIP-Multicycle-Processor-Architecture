# Stage 3 Video — Slide Content

On-screen text only, ready to copy into Canva. Narration and timing are in
[README.md](README.md).

- `[TAG]` = small chapter tag in the top corner of the slide
- `[Visual: …]` = an image, chart or clip to place, not text to type

---

## Slide 0 — Title

**[Team name]**

# [Product name]

A charger chip that keeps the grid standing.

Grid-aware EV charging controller on the RVBL-2 RISC-V core

[Visual: dark chip artwork, same as the report cover]

---

## Slide 1 — Project Overview: The Problem

`[TAG] 1 · Technical`

# 7 pm. 1,000 chargers. One grid dip.

1. Grid frequency drops → every charger stops
2. Grid recovers → **all restart at once**
3. **7 MW** slams back → the grid can trip again

…and every session is billed from meter data nobody checks.

[Visual: three-step graphic: charging → all stop → spike]

---

## Slide 2 — Project Overview: Our Solution

`[TAG] 1 · Technical`

# Check every frame. Restart at your own moment.

**Integrity-checked metering**
Every meter frame is verified before it is trusted or billed.

**Staggered restart**
Each charger restarts at its own moment, computed from its ID and the grid event.

**7.0 MW → 0.88 MW**

No network · No clock · No random numbers

[Visual: docs/figures/rebound.png]

---

## Slide 3 — Architecture

`[TAG] 1 · Technical`

# One chip, everything a charger needs

- **RVBL-2** multicycle RISC-V core (Stage 2): 9-state FSM, 20 MHz
- **RV32I + Zmmul + Xicrc** (our custom CRC extension)
- Instruction ROM · 32-byte data memory · address decoder
- **GPIO**: 8 pins
- **UART**: 115200 baud, 8N1

[Visual: ChipInventor block diagram, colour-coded wires:
blue = instruction path, green = data memory, orange = GPIO, purple = UART]

---

## Slide 4 — Hardware Design: GPIO & UART Integration

`[TAG] 1 · Technical`

# Hardware design: GPIO & UART integration

**Memory-mapped, no new instructions**
`0xF0000000` GPIO · `0xF1000000` UART, reached with plain `lw` / `sw`

**GPIO**
8 pin cells: DATADIR · DATAOUT · DATAIN
Tri-state moved to the pad → split bus `pins_i` / `pins_o` / `pins_oe_o`

**UART**
TX + RX · 115200 baud, 8N1 · 174 clocks per bit
Mid-bit sampling behind a 2-flop synchroniser

**Fits the Stage 2 core unchanged**
Registered reads match the multicycle load timing

Standard load/store control of real pins, portable from simulation to FPGA to silicon

[Visual: docs/video/figures/gpio_uart_integration_dark.png (or _light)]
[Optional inset: docs/video/figures/gpio_pin_cell_dark.png, guide vs our pin cell]

---

## Slide 5 — Official Firmware Testbench

`[TAG] 1 · Technical`

# Official test: PASS

```
PASS [GPIO] P3-0 = 0xa, P7-4 = 0xa
PASS [UART] RX = 0x30, TX = 0x30
PASS [GPIO after UART] P3-0 = 0x5, P7-4 = 0x5
PASS: GPIO and UART firmware test completed successfully
```

✔ GPIO: input pins mirrored to output pins
✔ UART: byte 0x30 received and echoed

**Passes on all 3 tops, including the ChipInventor export**

[Visual: waveform: pins_i, pins_o, rx_i, tx_o]

---

## Slide 6 — Custom Instruction `crcb`

`[TAG] 1 · Technical`

# One instruction. Three jobs.

`crcb rd, rs1, rs2`: CRC-16 of one byte, in a single instruction

**Build 1: speed (left column)**

Chart title: Cycles to CRC one meter frame

| Method | Cycles |
|---|---|
| Software loop | 1,276 |
| `crcb` | 60 |

Badge: **21× fewer cycles**
Small text: Code size: 11 → 2 instructions per byte
Caption: Measured in RTL simulation · same data · both give 0xCC77

[Visual: Canva horizontal bar chart, linear scale; software bar muted grey,
crcb bar in the accent colour; no gridlines or axes]

**Build 2: three jobs (right column, cards appear one by one)**

① **CHECK**
Every reading is checked on arrival
Damaged readings are never trusted or billed, and checking uses just 0.2% of the chip's time.

② **CHAIN**
Every reading is linked to the last one
Missing or repeated readings are caught without sending any extra data.

③ **TIME**
Every charger gets its own restart moment
Chargers restart in turns instead of all at once, cutting the restart surge nearly 8× (7 MW → 0.88 MW) so the grid isn't knocked down a second time.

**Build 3: anatomy (footer strip)**

| 1000000 | rs2 | rs1 | 000 | rd | 0110011 |
|---|---|---|---|---|---|
| Xicrc | seed | data | crcb | result | R-type |

Hardware does all 8 bit-steps at once, so a CRC is as fast as an add
Same instruction format as add / mul · crcb = 1 byte · crch = 2 bytes · crcw = 4 bytes

► **Every RVBL-2 chip has a CRC instruction. We turned ours into grid protection.**

---

## Slide 7 — Firmware Implementation

`[TAG] 1 · Technical`

# Firmware: 264 instructions, zero RAM

| UART data handling | CRC / Zmmul calculation | GPIO control signals |
|---|---|---|
| Bytes collected into 8-byte meter frames (V, I, F, CRC) | `crcb` folds in each byte as it arrives; the 8th byte is one compare | One `sw` to DATAOUT per state |
| Poll RXDONE → clear → read RXDATA | `mul`: V × I added to the energy counter | 0x20 lock · 0x30 charge · 0x60 grid hold · 0x80 fault |

**Two FSMs:** the hardware FSM executes · the application FSM decides

All state in registers · no stack · application state visible in `x4`

Runs without RAM = fits the smallest, cheapest chip

[Visual: short code snippets from main.s: poll_uart, mul, set_state]

---

## Slide 8 — Application Definition

`[TAG] 2 · Application Logic`

# What our charger controller does

| System Context | System Input | System Processing | System Output |
|---|---|---|---|
| A public AC EV charging station, with our chip as its controller | **Pilot signal** from the car (P2–P0): A unplugged · B plugged in · C wants charge · D ventilation · E/F error | **Check** every meter reading (chained CRC) | **Contactor** (P4): power on/off |
| | **Emergency stop** (P3) | **Bill** energy: voltage × current | **Lock** (P5): holds the plug |
| | **Meter reading** over UART, 8 bytes: voltage · current · frequency · CRC | **Watch the grid**: below 49.50 Hz or 207 V → hold | **Grid hold** (P6) |
| | | **Latch faults**: E-stop · over 32 A · lost meter link · bad pilot | **Fault** (P7) |
| | | | **Session record** over UART, 8 bytes: energy · status · readings · CRC |

**Application states (shown on the chip's debug register x4)**
IDLE **0x00** → CONNECTED **0x20** → CHARGING **0x30** ⇄ GRID HOLD **0x60**
Any state → FAULT **0x80** (on E-stop, over-current, lost link or bad pilot)

[Visual: the state strip as a simple left-to-right diagram under the table]

---

## Slide 9 — Connection Logic: `./emu` ↔ RISC-V

`[TAG] 2 · Application Logic`

# Connection logic: ./emu ↔ RISC-V

The emulator plays the car, the safety button and the meter.
Everything it sends enters through GPIO or UART; everything it checks leaves the same way.

**GPIO lane**
① Emulator sets the input pins → ② firmware reads DATAIN → ③ decides → ④ writes DATAOUT → ⑤ emulator checks the output pins

**UART lane**
⑥ Emulator sends meter bytes → ⑦ firmware reads RXDATA and folds each byte with `crcb` → ⑧ decides → ⑨ writes TXDATA → ⑩ emulator reads the session record

The chip only ever uses `lw` and `sw`: no special hooks for the emulator, so the same firmware runs on the FPGA unchanged.

[Visual: docs/video/figures/gpio_uart_process_dark.png (or _light);
reveal the GPIO lane first, then the UART lane]

---

## Slide 10 — Emulator Values: One Real Command

`[TAG] 2 · Application Logic`

# One real ./emu command, step by step

| `./emu` option | Step | What it means |
|---|---|---|
| `-d 0xF0` | setup | P7–P4 = chip outputs (watched) · P3–P0 = driven by the emulator |
| `-i 0x01` | ① | Car plugged in (pilot B) |
| `-o 0x20` | ⑤ | Expect: lock closed |
| `-i 0x02` | ① | Car asks to charge (pilot C) |
| `-o 0x30` | ⑤ | Expect: lock + contactor closed |
| `-t4 0x00A008FC` | ⑥ | Meter: 230.0 V, 16.0 A |
| `-t4 0xCC771388` | ⑥ | Meter: 50.00 Hz, CRC 0xCC77 |
| … | | second reading, then unplug (`-i 0x00`, `-o 0x00`) |
| `-r4 0x000B3B00` | ⑩ | Record: energy 736,000 |
| `-r2 0x0200` | ⑩ | Record: 2 readings billed, no faults |
| `-r2 0xD05C` | ⑩ | Record: its own CRC |

`-t4` sends 4 bytes, low byte first · Excerpt of scenario S1 in `emu_commands.txt` · all 12 scenarios pass in simulation

[Visual: optional small copy of the slide 9 figure in a corner, with the
current step number highlighted as each row is revealed]

---

## Slide 11 — Demo 1: Normal Charging Session

`[TAG] 2 · Application Logic`

# Demo 1: a normal session

IDLE **0x00** → Plug in → CONNECTED **0x20** → Charge → CHARGING **0x30** → Unplug → IDLE **0x00**

2 meter frames billed

Session record: **energy 736,000 · 2 frames · no faults**

[Visual: terminal clip of scenario S1 + waveform or state diagram]

---

## Slide 12 — Demo 2: Grid Dip & Staggered Restart

`[TAG] 2 · Application Logic`

# Demo 2: the grid dips

| Frame | Voltage | Frequency | Chip decision | Pins |
|---|---|---|---|---|
| 1 | 230.0 V | 50.00 Hz | Healthy → billed | 0x30 |
| 2 | 230.0 V | **49.20 Hz** | Below 49.50 Hz → **GRID HOLD** · delay = **3** | **0x60** |
| 3 | 230.0 V | 49.40 Hz | Still weak → count restarts | 0x60 |
| 4 | 207.0 V | 49.50 Hz | Healthy 1 of 3 | 0x60 |
| 5 | 207.0 V | 49.50 Hz | Healthy 2 of 3 | 0x60 |
| 6 | 207.0 V | 49.50 Hz | Healthy 3 of 3 → **CHARGING resumes** | **0x30** |
| 7 | 230.0 V | 50.00 Hz | Billed | 0x30 |

**Restart delay = 2 + (CRC(charger ID, event frame) & 7)**

Another charger or another event → a different delay (2–9 frames)
→ 1,000 restarts spread over 8 slots

[Visual: waveform of scenario S2: rx_i, pins_o, x4_dbg_o]

---

## Slide 13 — Validation: Our Testbench & Results

`[TAG] 2 · Application Logic`

# Validated: every value computed, every fault injected

**Our testbench**
`scenarios.py` → `golden.py` (Python model computes every expected value) → `tb_app.v` (mirrors the real emulator) → our RTL
Same scenarios exported as real `./emu` commands

| Fault injected | Result |
|---|---|
| Corrupted or dropped frame | Not billed, charging continues |
| Two bad frames in a row | FAULT, link-lost flag |
| Replayed old frame | Rejected → FAULT |
| Emergency stop | FAULT, latched until released and unplugged |
| Over-current (32.1 A) | FAULT; exactly 32.0 A still billed |
| Invalid pilot code / pilot E | FAULT, pilot-error flag |
| Stale pins at power-up · back-to-back UART bytes | Handled |

**45 / 45** simulation runs · **38 / 38** model tests · Official test **PASS** on 3 tops

---

## Slide 14 — Competitive Analysis: How We Stand Out

`[TAG] 3 · Pitch`

# How we stand out

How today's chargers handle a grid dip:

| | Basic wallbox | Timer charger | Smart charger | Networked charger | **Ours** |
|---|---|---|---|---|---|
| *How it restarts* | *at once* | *after a fixed or scheduled delay* | *after a random delay* | *when the back-end server says* | ***at its own CRC-timed moment*** |
| Spreads the restart surge | ✗ | ✗ | ✓ | ✓ | **✓** |
| Senses grid trouble itself (frequency, voltage) | ✗ | ✗ | ◐ | ◐ | **✓** |
| Still protects the grid when the network is down | — | — | ✓ | ✗ | **✓** |
| No random-number source needed | ✓ | ✓ | ✗ | ✓ | **✓** |
| Restart moment can be re-checked afterwards | ✓ | ✓ | ✗ | ◐ | **✓** |
| Extra parts needed | none | real-time clock | random source | modem + cloud server | **none: one small chip** |

✓ yes · ✗ no · ◐ some models, or only via the operator · — no grid protection to lose
Typical behaviour of each product type; individual models vary.

Only ours ticks every box.

**Chip design:** every RVBL-2 chip has a CRC instruction. Most use it for 1 job (checking data). Ours does **3**.

[Design: highlight the "Ours" column (accent colour background or border);
✗ in muted red, ✓ in green; reveal the rows one by one]

---

## Slide 15 — Value & Practical Functionality

`[TAG] 3 · Pitch`

# Value & practical functionality

**Three impact tiles (top row)**

| Protects the grid | No hassle for drivers | Fair bills |
|---|---|---|
| **8× smaller power surge** | **Charging restarts by itself** | **Only real readings are billed** |
| After a power dip, chargers switch back on in turns, not all at once. | The car stays plugged in and locked, with no need to replug. | Broken, missing or repeated meter readings are never charged. |
| *(small: 7 MW → 0.88 MW per 1,000 chargers)* | | |

**Who benefits (table below, rows appear one by one)**

| Who | Impact | How our chip delivers it |
|---|---|---|
| **Grid operator** | Lower risk of a second blackout after a dip, and room for more chargers on the same grid | Staggered restarts; works with no network |
| **Driver** | No replugging after a grid hiccup, and never charged for a reading that didn't happen | Car stays locked and resumes automatically; only verified readings are billed |
| **Charge-point operator** | Fewer grounds for billing disputes and refunds | Uses its existing meter; the session record leaves sealed |
| **Charger maker** | Grid support even in cheap chargers with no internet connection | No clock, random-number chip or modem; one small chip |
| **Regulator** | Rules that can be enforced after the event | Any charger's delay can be recomputed from its ID and the event |

If the slide feels crowded, keep the three tiles and drop the table.

---

## Slide 16 — Stage 4 FPGA Roadmap

`[TAG] 3 · Pitch`

# Roadmap

1. **Ready now:** 12 scenarios as real `./emu` commands + `run_scenarios.sh`
2. **Stage 4:** run on the AWS FPGA with the real emulator
3. **Next:** real meter & PWM pilot · grid-code thresholds · cryptographic billing check
4. **Then:** Sky130 silicon

Today: thresholds are placeholders · CRC catches faults, not a deliberate forger

[Visual: four-step roadmap arrow]

---

## Slide 17 — Closing

`[TAG] 3 · Pitch`

# One CRC instruction. Grid protection built in.

No network · No clock · No random numbers

**7.0 MW → 0.88 MW**

One chip, ready for the FPGA, ready for chargers.

**[Team name]**
[Member 1] · [Member 2] · [Member 3] · [Member 4]

github.com/ZhuHengg/ChampionCHIP-Multicycle-Processor-Architecture

[Visual: rebound figure + GitHub QR code]
