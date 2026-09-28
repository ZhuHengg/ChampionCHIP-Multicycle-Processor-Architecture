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

- **RVBL-2** multicycle RISC-V core
- **RV32I + Zmmul + Xicrc** (our custom CRC extension)
- Instruction ROM · 32-byte data memory · address decoder
- **GPIO**: 8 pins
- **UART**: 115200 baud, 8N1

[Visual: ChipInventor block diagram, colour-coded wires:
blue = instruction path, green = data memory, orange = GPIO, purple = UART]

---

## Slide 4 — Hardware Design

`[TAG] 1 · Technical`

# How the core runs

**Control FSM: 9 states**
RESET → FETCH → DECODE → EXECUTE → WRITE_BACK
MEM_ADDR → MEM_ACCESS_ADDR / DATA / STORE

| Instruction | Cycles |
|---|---|
| ALU / MUL / CRC | 4 |
| Branch | 3 |
| Store | 4 |
| Load | 6 |

**Memory map**

| Address | Peripheral | Registers |
|---|---|---|
| `0xF0000000` | GPIO | DATAOUT · DATAIN · DATADIR |
| `0xF1000000` | UART | TXDATA · RXDATA · CONTROL |

20 MHz · split pin bus (in / out / output-enable) · UART 174 clocks per bit

Small multicycle core = small chip area = low-cost charger

[Visual: FSM state diagram]

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

`crcb rd, rs1, rs2`
CRC-16 of one byte, in a single instruction

**21× faster**
Software loop: **1,276 cycles** · `crcb`: **60 cycles**
(one meter frame, both give `0xCC77`)

① **Check** each meter frame
② **Chain** frames, so a missing or replayed one is caught
③ **Time** each charger's restart after a grid dip

The instruction that checks the data also protects the grid.

[Visual: bar chart, 1,276 vs 60 cycles]

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

## Slide 8 — System Overview

`[TAG] 2 · Application Logic`

# The emulator plays the world around our chip

**The car** → pilot signal → pins P2–P0
**The safety button** → emergency stop → pin P3
**The energy meter & grid** → meter frames → UART rx

**Our chip** (Stage 4: on the AWS FPGA)

→ Contactor · Lock · Grid hold · Fault (pins P4–P7)
→ Session record → UART tx

[Visual: system diagram, chip in the centre, emulator roles around it]

---

## Slide 9 — Context → Input → Processing → Output

`[TAG] 2 · Application Logic`

# How the application works

| System Context | System Input | System Processing | System Output |
|---|---|---|---|
| Public AC EV charging station | Pilot code (P2–P0) | Check each frame (chained CRC) | Contactor (P4) |
| | Emergency stop (P3) | Bill energy: V × I | Lock (P5) |
| | 8-byte meter frame: V · I · F · CRC | Watch grid health | Grid hold (P6) |
| | | Latch faults | Fault (P7) |
| | | | 8-byte session record (UART) |

---

## Slide 10 — Emulator Values (`./emu`)

`[TAG] 2 · Application Logic`

# Emulator values: one command, decoded

| `./emu` option | What it means |
|---|---|
| `-d 0xF0` | P7–P4 = chip outputs (watched) · P3–P0 = driven by emulator |
| `-i 0x01` | Car plugged in (pilot B) |
| `-o 0x20` | Expect: lock closed |
| `-i 0x02` | Car asks to charge (pilot C) |
| `-o 0x30` | Expect: lock + contactor closed |
| `-t4 0x00A008FC` | Meter: V = 230.0 V, I = 16.0 A |
| `-t4 0xCC771388` | Meter: F = 50.00 Hz, CRC = 0xCC77 |
| `-r4 0x000B3B00` | Read back: energy = 736,000 |
| `-r2 0x0200` | 2 frames billed, no fault flags |
| `-r2 0xD05C` | Record's own CRC |

`-t4` sends 4 bytes, low byte first

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

| How chargers restart today | Weakness |
|---|---|
| All at once | Rebound spike can trip the grid again |
| Fixed delay | Everyone still restarts together |
| Random delay | Needs a random source · can't be checked afterwards |
| Central network scheduling | Fails when communications fail |
| **Ours: delay = CRC(charger ID, event)** | **Spread · offline · auditable** |

**Chip design:** a custom instruction usually does 1 job. Ours does **3**.

---

## Slide 15 — Value & Practical Functionality

`[TAG] 3 · Pitch`

# Value & practical functionality

| Who | Value | Practical functionality |
|---|---|---|
| **Grid operator** | **7.94× lower** restart peak | Works with no network |
| **Charge-point operator** | Integrity-checked billing: bad, dropped and replayed frames never billed | Uses the meter it already has |
| **Charger manufacturer** | No clock, random-number generator or modem needed | One small RISC-V chip, 264 instructions |
| **Regulator** | **Auditable:** any delay can be recomputed | Same inputs → same delay, always |

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
