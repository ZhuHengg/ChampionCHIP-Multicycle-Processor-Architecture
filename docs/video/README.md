# Stage 3 Video — Storyboard and Script

The complete plan for the Stage 3 video demo (guide §7, **max 8 minutes**,
YouTube link). Every slide is listed in order with what goes on screen, what
the presenter says, and which file or run produces the visual.

- **Recorded in:** Canva, "Present and record" (slides plus presenter camera)
- **Narration:** a human voice only, with subtitles added afterwards (see
  [Facts to confirm](#8-facts-to-confirm-before-recording))
- **Target length:** 7:40, leaving 20 s of margin under the 8:00 limit
- **Deadline:** 30 Sep 2026, 23:59 MYT, shared with the report

---

## 1. Fill in before recording

| Item | Used on | Value |
|---|---|---|
| Team name | Slides 0, 17 | _fill in_ |
| Team members (names, roles) | Slide 17 | _fill in_ |
| Product name (optional, recommended for the pitch) | Slides 0, 17 | _fill in_; suggestions: **GridStagger**, **CalmCharge**, **PulseGuard** |
| GitHub repository URL for the QR code | Slide 17 | https://github.com/ZhuHengg/ChampionCHIP-Multicycle-Processor-Architecture |

The script says "our chip" wherever the product name would go, so it reads
correctly with or without one.

---

## 2. What the judges are scoring, and where we answer it

The guide says the video must be *"dynamic, focused on presenting and
'selling' the idea, and strictly structured"* into three topics. Every slide
carries a small chapter tag in its top corner (**1 · Technical**,
**2 · Application Logic**, **3 · Pitch**), so the structure is visible the whole
way through without spending time on divider slides.

| Guide requirement | Where it is answered |
|---|---|
| §7.1 Technical Part: architecture, hardware design, firmware implementation | Slides 3, 4, 6, 7 |
| §7.2 Application Logic: working application, **connection logic between `./emu` and the RISC-V processor** | Slides 8–12 (slide 10 decodes one `./emu` line option by option) |
| §7.3 Pitch: **professional posture**, sell the concept, **value** and **practical functionality** | Slides 14–17; slide 15 uses the rubric's own words as its title; presenter is full frame for this chapter |
| §1 Project Overview: goal, architecture, general operation | Slides 1–2 (named "Project Overview", tagged 1 · Technical) |
| §2 GPIO & UART Integration: integration design, ChipInventor block diagram | Slide 3 (block diagram), slide 4 (integration design), slide 8 (how each peripheral carries the emulator's commands) |
| §3 Official Firmware Testbench | Slide 5 |
| §4 Application Definition: Context, Input, Processing, Output, Emulator Values | Slides 9–10, using those exact words |
| §5 Firmware: how UART data is handled, **how CRC/Zmmul is calculated**, how GPIO signals are sent | Slide 7, one line per item |
| §6 Team testbench and tested firmware | Slide 13. **§6 is not in the report** (report = topics 1–5), so this slide is its only place |

**Selling runs through all three chapters, not only the pitch.** Every
technical slide ends with a one-line *"so what"*: the feature, then the
benefit. These lines are marked **So what:** in the script below.

---

## 3. Running order

| # | Chapter tag | Slide | Time | Ends at |
|---|---|---|---|---|
| 0 | — | Title | 0:05 | 0:05 |
| 1 | 1 · Technical | Project Overview: the problem | 0:25 | 0:30 |
| 2 | 1 · Technical | Project Overview: our solution | 0:25 | 0:55 |
| 3 | 1 · Technical | Architecture (ChipInventor) | 0:25 | 1:20 |
| 4 | 1 · Technical | Hardware design: GPIO & UART integration | 0:30 | 1:50 |
| 5 | 1 · Technical | Official firmware testbench: PASS | 0:20 | 2:10 |
| 6 | 1 · Technical | Custom instruction `crcb` | 0:30 | 2:40 |
| 7 | 1 · Technical | Firmware implementation | 0:35 | 3:15 |
| 8 | 2 · Application Logic | System overview: how the emulator reaches our chip | 0:20 | 3:35 |
| 9 | 2 · Application Logic | Context → Input → Processing → Output | 0:25 | 4:00 |
| 10 | 2 · Application Logic | Emulator values (`./emu`) | 0:25 | 4:25 |
| 11 | 2 · Application Logic | Demo 1: normal charging session | 0:20 | 4:45 |
| 12 | 2 · Application Logic | **Demo 2: grid dip and staggered restart** | 0:40 | 5:25 |
| 13 | 2 · Application Logic | Validation: our testbench and results | 0:40 | 6:05 |
| 14 | 3 · Pitch | Competitive analysis: how we stand out | 0:25 | 6:30 |
| 15 | 3 · Pitch | Value & practical functionality | 0:35 | 7:05 |
| 16 | 3 · Pitch | Stage 4 FPGA roadmap | 0:15 | 7:20 |
| 17 | 3 · Pitch | Closing | 0:20 | 7:40 |

Pace: about 150 words per minute. Each script below is sized to its time
slot; lines marked *(cut if long)* can go if a rehearsal runs over.

---

## 4. Slide by slide

### Slide 0 — Title (0:05)

**On screen:** team name, product name, one line: *"A charger chip that keeps
the grid standing."* Background: the dark chip artwork, matching the report
cover.

**Camera:** small bubble.

**Say:**
> Hi, we're [team]. This is our chip: a charger controller that keeps the grid
> standing.

---

### Slide 1 — Project Overview: the problem (0:25) · 1 · Technical

**On screen:**
- Headline: **"7 pm. 1,000 chargers. One grid dip."**
- A simple animation or three-step graphic: chargers charging → grid dips,
  all stop → grid recovers, **all restart at once: 7 MW spike**.
- A second, smaller line: *"…and every session is billed from meter data nobody checks."*

**Say:**
> Picture 7 pm. A thousand electric cars are charging across the city. A power
> station trips and the grid frequency drops. Every charger does the safe thing
> and stops. Seconds later the grid recovers, and all thousand restart in the
> same instant: seven megawatts slammed back at once, enough to push a weak
> grid over again. And every one of those sessions is billed from meter data
> nobody checks.

---

### Slide 2 — Project Overview: our solution (0:25) · 1 · Technical

**On screen:**
- Headline: **"Check every frame. Restart at your own moment."**
- Left: two icons, *integrity-checked metering* and *staggered restart*.
- Right: `docs/figures/rebound.png`, captioned **"7.0 MW → 0.88 MW"**.
- Footer: *No network · No clock · No random numbers*

**Say:**
> So we built a charger controller on our own RISC-V chip. It checks every
> meter frame before it trusts it or bills it. And when the grid dips, it
> pauses, then restarts at its own moment, computed from its ID and the event
> itself. The same thousand chargers: the seven-megawatt spike becomes under
> one megawatt. No network, no clock, no random numbers.

---

### Slide 3 — Architecture (0:25) · 1 · Technical

**On screen:**
- The **ChipInventor block diagram** (canvas export), with coloured wires as
  the guide suggests: e.g. blue = instruction path, green = data memory,
  orange = GPIO, purple = UART.
- Labels: *RVBL-2 multicycle core · RV32I + Zmmul + Xicrc · GPIO (8 pins) ·
  UART 115200 8N1*

**Say:**
> This is our chip in ChipInventor. RVBL-2 is a multicycle RISC-V core: RV32I,
> plus Zmmul for multiply, plus our own Xicrc extension for CRC. Around it sit
> the instruction ROM, a 32-byte data memory, the address decoder, and the two
> Stage 3 peripherals: GPIO for eight pins, and a UART for serial data.

**So what:**
> Everything a charger controller needs, on one small chip.

---

### Slide 4 — Hardware design: GPIO & UART integration (0:30) · 1 · Technical

In Stage 3, "hardware design" means the peripheral integration (guide §2 and
the GPIO/UART block guide). The core itself was Stage 2 work, so it gets one
line on slide 3, not a slide of its own.

**On screen:**
- `figures/gpio_uart_integration_*.png`: core → load/store unit → address
  decoder → IMEM / DMEM / GPIO / UART → pins → emulator.
- Four short points: memory-mapped with no new instructions · GPIO as 8 pin
  cells with the tri-state moved to the pad (split `pins_i` / `pins_o` /
  `pins_oe_o`) · UART TX + RX at 115200 8N1, 174 clocks per bit, mid-bit
  sampling behind a 2-flop synchroniser · registered reads fit the Stage 2 load
  timing, so the core FSM is unchanged.
- Optional inset: `figures/gpio_pin_cell_*.png` (guide Figure 1 vs our pin
  cell), to show the one deliberate deviation and why.

**Say:**
> For Stage 3 we added GPIO and a UART to our core, with no new instructions.
> The address decoder maps GPIO at F0 and the UART at F1, so every pin and
> every serial byte is just a load or a store. The GPIO is eight pin cells,
> with the tri-state moved out to the pad as separate in, out and enable
> signals, which is what FPGAs and silicon expect. The UART runs at 115,200
> baud, 174 clocks per bit.

**So what:**
> Standard load-and-store control of real pins, portable from simulation to
> FPGA to silicon.

---

### Slide 5 — Official firmware testbench: PASS (0:20) · 1 · Technical

**On screen:**
- The PASS log lines:
  ```
  PASS [GPIO] P3-0 = 0xa, P7-4 = 0xa
  PASS [UART] RX = 0x30, TX = 0x30
  PASS [GPIO after UART] P3-0 = 0x5, P7-4 = 0x5
  PASS: GPIO and UART firmware test completed successfully
  ```
- A waveform: `pins_i`, `pins_o`, `rx_i`, `tx_o` showing the 0xA mirror and the
  0x30 echo byte.
- Badge: **"Passes on all 3 tops, including the ChipInventor export"**

**Say:**
> Before writing any application, we ran the organisers' official firmware on
> our integrated design. 0xA driven on pins 3 to 0 comes back on pins 7 to 4,
> and the byte 0x30 sent over UART is echoed back. It passes on all three
> versions of our top level, including the ChipInventor export.

---

### Slide 6 — Custom instruction `crcb` (0:30) · 1 · Technical

**On screen:**
- The instruction: `crcb rd, rs1, rs2` = CRC-16 of one byte (rs1) with seed
  (rs2), in **one instruction**.
- A bar chart: **software loop 1,276 cycles** vs **`crcb` 60 cycles** → **21×**
  (same meter frame, both give `0xCC77`).
- Three icons in a row: **① check the frame · ② chain the frames · ③ time the
  restart**.

**Say:**
> Our custom instruction, crcb, folds one byte into a CRC-16 in a single
> instruction. In software the same job is a loop of shifts and XORs: over one
> meter frame, 1,276 cycles against 60, 21 times faster. But speed isn't the
> point. In our charger this one instruction does three jobs: it checks each
> frame, it chains frames together so a missing or replayed one is caught, and
> it computes each charger's restart delay.

**So what:**
> The instruction that checks the data also protects the grid.

---

### Slide 7 — Firmware implementation (0:35) · 1 · Technical

**On screen:** three columns, matching guide §5 word for word.

| UART data handling | CRC / Zmmul calculation | GPIO control signals |
|---|---|---|
| Bytes collected into 8-byte meter frames: V, I, F, CRC | `crcb` folds each byte in as it arrives; the 8th byte is one compare | One `sw` to DATAOUT per state |
| RXDONE polled, cleared, RXDATA read | `mul` = V × I, added to the energy counter | 0x20 lock · 0x30 charge · 0x60 grid hold · 0x80 fault |

Footer: **264 instructions · all state in registers (no stack, no RAM) · app
state visible in `x4`**

**Say:**
> The firmware is 264 instructions of assembly, with all its state in
> registers: no stack, no RAM. Three paths, straight from the guide. UART in:
> bytes are collected into 8-byte meter frames, and crcb folds each byte into
> the running CRC as it arrives, so checking a frame is a single compare. Compute:
> mul multiplies voltage by current for the energy counter. GPIO out: each
> state writes one value to DATAOUT. Two state machines work together: the
> hardware FSM executes, and the application FSM decides. *(cut if long)*

**So what:**
> The whole controller runs without touching RAM, so it fits the smallest,
> cheapest chip.

---

### Slide 8 — System overview: how the emulator reaches our chip (0:20) · 2 · Application Logic

**On screen:** `figures/gpio_uart_process_*.png`. Three columns (emulator,
peripheral hardware, firmware) and two lanes (GPIO, UART), with numbered steps
1–10. Reveal the GPIO lane first, then the UART lane.
- GPIO lane: `-i 0x02` → `pins_i` → DATAIN → `lw` → app rules → `sw 0x30` →
  DATAOUT → `pins_o` → `-o 0x30`
- UART lane: `-t4` → `rx_i` → receiver → RXDATA → `lw`, `crcb`, `mul` →
  `sw TXDATA` → transmitter → `tx_o` → `-r`

This is the guide's "connection logic between the emulator and the RISC-V
processor" in one picture.

**Say:**
> Now the application. In Stage 4 our chip runs on an AWS FPGA, and the
> emulator plays the world around it. Everything it sends enters through a
> peripheral: the car and the emergency stop through GPIO, meter frames through
> the UART. Everything it checks leaves the same way.

---

### Slide 9 — Context → Input → Processing → Output (0:25) · 2 · Application Logic

**On screen:** four boxes, using the guide's exact words.

| System Context | System Input | System Processing | System Output |
|---|---|---|---|
| Public AC charging station | Pilot code P2–P0 (A…F) · E-stop P3 · 8-byte meter frame: V (0.1 V), I (0.1 A), F (0.01 Hz), CRC | Check each frame (chained CRC) · bill V × I · watch grid health · latch faults | Contactor P4 · lock P5 · grid hold P6 · fault P7 · 8-byte session record over UART |

**Say:**
> Context: a public AC charging station. Input: the pilot code from the car on
> pins 0 to 2, the emergency stop on pin 3, and an 8-byte meter frame with
> voltage, current, frequency and a CRC. Processing: check the frame, bill the
> energy, protect the grid, latch faults. Output: contactor, lock, grid-hold
> and fault on pins 4 to 7, plus an 8-byte session record over UART.

---

### Slide 10 — Emulator values (`./emu`) (0:25) · 2 · Application Logic

**On screen:** the start of scenario S1, one option per line, each with an
arrow to the pin or byte it drives. Highlight each line as it is spoken.

```
./emu -d 0xF0          P7–P4 = chip outputs (observed), P3–P0 = emulator drives
      -i 0x01          car plugged in (pilot B)
      -o 0x20          expect: lock closed
      -i 0x02          car asks to charge (pilot C)
      -o 0x30          expect: lock + contactor closed
      -t4 0x00A008FC   meter bytes FC 08 A0 00 → V = 230.0 V, I = 16.0 A
      -t4 0xCC771388   meter bytes 88 13 77 CC → F = 50.00 Hz, CRC = 0xCC77
      …
      -r4 0x000B3B00   read back: energy = 736,000
      -r2 0x0200       2 frames billed, no fault flags
      -r2 0xD05C       the record's own CRC
```

**Say:**
> This is how the emulator talks to our chip. Minus-d 0xF0 makes the top four
> pins outputs we watch. Minus-i 0x02 is the car asking to charge. Minus-t4
> sends four meter bytes, low byte first: 230 volts, 16 amps, then 50 hertz and
> the CRC. Minus-o checks the pins: 0x30 means the contactor is closed. Minus-r
> reads the session record back.

---

### Slide 11 — Demo 1: normal charging session (0:20) · 2 · Application Logic

**On screen:** the S1 command running in the terminal, next to a waveform or a
state diagram lighting up: IDLE → CONNECTED (0x20) → CHARGING (0x30) → IDLE
(0x00), then the record bytes on `tx_o`.

**Say:**
> A normal session. Plug in: the lock closes, 0x20. Ask to charge: the
> contactor closes, 0x30. Two good frames are billed. Unplug: the outputs go
> safe first, then the record goes out: energy 736,000, exactly two frames of
> 230 volts times 16 amps, two frames, no fault flags.

---

### Slide 12 — Demo 2: grid dip and staggered restart (0:40) · 2 · Application Logic

**This is the core demo of our innovation.**

**On screen:** a timeline of frames (from scenario S2), with the pin output
under each:

| Frame | V | F | What the chip does | Pins |
|---|---|---|---|---|
| 1 | 230.0 V | 50.00 Hz | Healthy, billed | 0x30 |
| 2 | 230.0 V | **49.20 Hz** | Below 49.50 → **grid hold**; restart delay = 2 + (CRC(charger ID, this frame's CRC) & 7) = **3** | **0x60** |
| 3 | 230.0 V | 49.40 Hz | Still weak → healthy count restarts | 0x60 |
| 4, 5 | 207.0 V | 49.50 Hz | Healthy 1, 2 of 3 | 0x60 |
| 6 | 207.0 V | 49.50 Hz | Healthy 3 of 3 → **charging resumes** | **0x30** |
| 7 | 230.0 V | 50.00 Hz | Billed | 0x30 |

Side panel: *"Another charger, or another event → a different delay from 2 to 9
frames → 1,000 restarts spread over 8 slots."*

**Say:**
> Now the grid dips. We're charging at 50 hertz. The next frame says 49.2
> hertz, below our 49.5 limit. The chip opens the contactor but keeps the car
> locked: 0x60, grid hold. It takes that frame's CRC, hashes our charger ID with
> crcb, and gets its restart delay: for this charger and this event, three
> healthy frames. At 49.4 the grid is still weak, so the count starts again.
> Then three healthy frames, and on the third, charging resumes. Another
> charger, or another event, gets a different number from 2 to 9. That's what
> spreads a thousand restarts across eight slots.

---

### Slide 13 — Validation: our testbench and results (0:40) · 2 · Application Logic

**On screen:**
- Left, **how the testbench works:** `scenarios.py` → `golden.py` (Python golden
  model computes every expected value) → `tb_app.v` (mirrors the emulator:
  each `-d/-i/-t/-o/-r` becomes a pin change, UART byte or check) → our RTL.
  The same scenarios are exported as real `./emu` lines.
- Right, **faults we inject:**

| Fault | Result |
|---|---|
| Corrupted frame / dropped frame | Not billed; charging continues |
| Two bad frames in a row | FAULT (0x80), link-lost flag |
| Replayed old frame | Rejected → FAULT |
| Emergency stop | FAULT, latched until released and unplugged |
| Over-current (32.1 A) | FAULT; exactly 32.0 A is still billed |
| Invalid pilot code / pilot E | FAULT, pilot-error flag |
| Stale pins at power-up, back-to-back UART bytes | Handled correctly |

- Badge row: **45 / 45 simulation runs · 38 / 38 model tests · official test
  PASS on 3 tops**

**Say:**
> How do we know it works? Our testbench mirrors the real emulator option by
> option, and a Python golden model computes every expected value, so nothing
> is typed by hand. We inject the faults a real charger meets. A corrupted or
> dropped frame is simply not billed. Two bad frames in a row, or a replayed
> frame, latch a fault. So do an emergency stop, over-current and an invalid
> pilot code. Twelve scenarios plus three harness checks, on three versions of
> the design: 45 out of 45 pass. One harness check is built to fail, to prove
> the testbench really catches mistakes. *(cut if long)*

---

### Slide 14 — Competitive analysis: how we stand out (0:25) · 3 · Pitch

**Camera:** switch to **presenter large / full frame** for the whole pitch
chapter.

**On screen:**

| How chargers restart today | Weakness |
|---|---|
| All at once when the grid recovers | The rebound spike can trip the grid again |
| Fixed delay | Everyone waits the same time, so they still restart together |
| Random delay (UK smart-charging rules) | Needs a random source; can't be checked afterwards |
| Central network scheduling | Fails when communications fail, often during the same event |
| **Ours: delay = CRC(charger ID, event frame)** | **Spread over 8 slots · offline · auditable** |

Second row: **Chip design:** a custom instruction usually does *one* job (speed).
Ours does **three**.

**Say:**
> Today chargers either restart together, wait a fixed time, which still
> restarts them together, or wait a random time, which the UK now requires.
> Random works, but it needs a random source and can't be checked afterwards.
> Network scheduling fails when communications fail. Ours is spread, offline
> and auditable. And on the chip side: where a custom instruction usually does
> one job, ours does three.

---

### Slide 15 — Value & practical functionality (0:35) · 3 · Pitch

**On screen:** the title uses the rubric's words. One row per stakeholder:

| Who | Value | Practical functionality |
|---|---|---|
| **Grid operator** | **7.94× lower** restart peak after a dip | Works with no network, so it still protects the grid when communications are down |
| **Charge-point operator** | **Integrity-checked billing:** corrupted, dropped and replayed frames are never billed | Uses the meter it already has; the session record comes out over UART |
| **Charger manufacturer** (buys the chip) | No real-time clock, random-number generator or modem needed | One small RISC-V chip, a 264-instruction program |
| **Regulator** | **Auditable:** any charger's delay can be recomputed | Same inputs always give the same delay |

**Say:**
> What does that mean in practice? For the grid operator: a restart peak
> nearly eight times lower, with no network needed. For the charge-point
> operator: corrupted, dropped or replayed frames are never billed, using the
> meter they already have. For the charger maker, who buys the chip: no clock,
> no random-number generator, no modem, just one small RISC-V chip. And for the
> regulator: every charger's delay can be recomputed from its ID and the event.
> The same inputs always give the same answer.

---

### Slide 16 — Stage 4 FPGA roadmap (0:15) · 3 · Pitch

**On screen:** a four-step roadmap arrow.

1. **Ready now:** 12 scenarios as real `./emu` commands, plus
   `run_scenarios.sh` to run them on the AWS FPGA
2. **Stage 4:** run on the AWS FPGA with the real emulator
3. **Next:** real meter and PWM pilot, thresholds from the grid code, a
   cryptographic check for billing
4. **Then:** Sky130 silicon

**Say:**
> For Stage 4 we're ready: every scenario is already a real emu command, with
> a script to run them on the AWS FPGA. Today our thresholds are placeholders,
> and a CRC catches faults, not a deliberate forger. So next come a real meter,
> grid-code thresholds and a cryptographic check, then Sky130 silicon.

---

### Slide 17 — Closing (0:20) · 3 · Pitch

**On screen:** the rebound figure again, the spike shrinking from 7.0 MW to
0.88 MW. The pitch line in large type. Team names, GitHub QR code.

**Say:**
> We turned one CRC instruction into grid protection that needs no network, no
> clock and no random numbers. Every charger restarts at its own predictable,
> auditable moment, on a chip with just 32 bytes of RAM. Seven megawatts, down
> to under one. One chip, ready for the FPGA, ready for chargers. We're [team].
> Thank you.

---

## 5. Assets to prepare

| Slide | Asset | How to get it |
|---|---|---|
| 2, 17 | Rebound figure | `docs/figures/rebound.png` (regenerate: `python chip-inventor/testbench/app/evidence/rebound_sim.py`) |
| 3 | ChipInventor block diagram | Export from the ChipInventor canvas (after the imem re-upload); colour the wires |
| 4 | GPIO & UART integration figure; optional pin-cell inset | `docs/video/figures/gpio_uart_integration_{dark,light}.png`, `gpio_pin_cell_{dark,light}.png` (regenerate: `python docs/video/figures/make_figures.py --png`) |
| 8 | Emulator ↔ peripheral ↔ firmware flow figure | `docs/video/figures/gpio_uart_process_{dark,light}.png` |
| 5 | Official test log and waveform | `python chip-inventor/testbench/organiser/run_tests.py`; waveform: `chip-inventor/sim/organiser/testbench.vcd` in GTKWave |
| 6 | Cycle bar chart | `python chip-inventor/testbench/app/evidence/run_crc_bench.py` (prints 60 / 1276 / 21×); waveform: `chip-inventor/sim/crc_bench/crc_bench.vcd` |
| 7 | Code snippets | `chip-inventor/firmware/src/main.s`: `poll_uart` (UART in), `of_charging` (`mul`), `set_state` (GPIO out) |
| 10, 11 | S1 command and run | `chip-inventor/emulator/emu_commands.txt` (S1); run: `python chip-inventor/testbench/app/run_tests.py --top hdl.v --scenario S1`; waveform: `chip-inventor/sim/app/hdl_S1/app.vcd` |
| 12 | S2 run and waveform | `python chip-inventor/testbench/app/run_tests.py --top hdl.v --scenario S2`; waveform: `chip-inventor/sim/app/hdl_S2/app.vcd`. Show `rx_i`, `pins_o`, `x4_dbg_o` |
| 13 | Regression output | `python chip-inventor/testbench/app/run_tests.py` (ends `45/45 runs as expected`); `python -m pytest chip-inventor/testbench/app -q` (38 passed) |
| 16 | Emulator package | `bash chip-inventor/emulator/run_scenarios.sh --dry-run` |

Waveform signals to add in GTKWave for the application scenes: `clk_i`,
`pins_i[7:0]`, `pins_o[7:0]`, `rx_i`, `tx_o`, `x4_dbg_o` (application state:
0 IDLE, 1 CONNECTED, 2 CHARGING, 3 GRID_HOLD, 4 FAULT), and the core's control
FSM state for the two-FSM view. Show values in hex.

---

## 6. Numbers used in the script, and where each comes from

Every number said on camera traces to a run or a file.

| Number | Meaning | Source |
|---|---|---|
| 1,000 × 7 kW = 7.0 MW → 0.882 MW, 7.94× | Fleet rebound, synchronised vs staggered | `rebound_sim.py` output |
| 60 vs 1,276 cycles, 21× | `crcb` vs software CRC over one meter frame | `run_crc_bench.py` output |
| `0xCC77` | CRC of the S1 meter payload, same from both methods | `run_crc_bench.py`, `golden.py` |
| 264 instructions | Firmware size (`firmware.bin` = 1,056 bytes) | `chip-inventor/firmware/build/` |
| 9 FSM states; 4 / 3 / 4 / 6 cycles | Control FSM; ALU-MUL-CRC / branch / store / load | `control_unit_eq26.v`, handoff doc |
| 20 MHz, 115,200 baud, 174 clocks/bit | Core clock and UART timing | `CLOCK_PERIOD` 50 ns; `uart.v` |
| 49.50 Hz, 207.0 V, 32.0 A | Grid-health and over-current limits (placeholders) | `main.s` / `golden.py` constants |
| Delay 2–9 frames; 3 in the S2 demo | `2 + (crc16(ID, trigger CRC) & 7)`; S2 trigger CRC `0x13EB` | `golden.restart_delay` |
| 736,000 | S1 energy = 2 × (2300 × 160) | S1 record |
| 45/45, 38/38 | App simulation runs; golden-model tests | `run_tests.py`, pytest |

---

## 7. Delivery

**Canva setup**
- Slides 0–13: camera as a small bubble in a corner that doesn't cover
  content.
- Slides 14–17: camera **large or full frame**. This is where the "professional
  posture" is scored.
- Embed the terminal and waveform clips as videos in slides 5, 11, 12 and 13;
  speed up simulation clips and label them *"RTL simulation, sped up"*.

**Posture and voice**
- Stand if possible; smart-casual or formal clothes; plain, tidy background;
  face lit from the front.
- Look into the lens, not at the slide. Keep bullet notes just below the camera,
  not a script to read.
- Use a clip-on or USB microphone and record in a quiet room.
- Slow down in the pitch chapter and pause for a beat after each number.

**Editing**
- Add subtitles after recording (Canva auto-captions, then correct technical
  words: crcb, Zmmul, 0x30, `./emu`).
- Keep it at or under 7:45 after edits. Hard limit 8:00.
- Upload to YouTube (unlisted is fine unless the platform says otherwise) and
  check the link in a private window.

**Rehearse** at least twice with a stopwatch against the running order in §3.
If a rehearsal runs long, cut the lines marked *(cut if long)* first.

---

## 8. Facts to confirm before recording

| Claim | Where | Action |
|---|---|---|
| The UK requires a randomised delay on smart chargers | Slide 14 | Confirm against the UK *Electric Vehicles (Smart Charge Points) Regulations 2021* before saying "by law"; if in doubt, say "the UK's smart-charging rules use a random delay" |
| "Human narration only, subtitles mandatory" | §7 Delivery | From earlier competition slides, not in the Stage 3 guide. Confirm with the organisers; human narration plus subtitles is safe either way |
| Any Malaysian EV statistic added to slide 1 | Slide 1 | Only use a figure with a source you can cite |
| YouTube visibility (public or unlisted) | Upload | Check the submission platform's instructions |

**Wording rule.** Say *integrity-checked* billing, never *tamper-proof* or
*secure*. The chained CRC catches corrupted, dropped and replayed frames from a
faulty link, but a deliberate attacker can compute a CRC too. Slide 16 says
this openly, which pre-empts the judges' question.
