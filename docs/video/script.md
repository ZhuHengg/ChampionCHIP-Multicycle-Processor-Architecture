# Stage 3 Video — Narration Script

Matches the 19-slide Canva deck. Target **7:00 spoken**, which leaves about
55 s for clicks, pauses and demo clips under the 8:00 limit.

Pace: about 150 words per minute. Each slide shows its time slot and word
budget. Lines marked *(cut if long)* go first if a rehearsal runs over.

## Running order

| # | Chapter | Slide | Time | Ends at |
|---|---|---|---|---|
| 1 | — | Title | 0:10 | 0:10 |
| 2 | 01 · Technical | Project architecture (ChipInventor) | 0:15 | 0:25 |
| 3 | 01 · Technical | Project architecture (block diagram) | 0:12 | 0:37 |
| 4 | 01 · Technical | Hardware design | 0:20 | 0:57 |
| 5 | 01 · Technical | Firmware implementation | 0:30 | 1:27 |
| 6 | 01 · Technical | Official firmware testbench | 0:20 | 1:47 |
| 7 | 02 · Application Logic | Problem statement | 0:28 | 2:15 |
| 8 | 02 · Application Logic | Proposed solution | 0:22 | 2:37 |
| 9 | 02 · Application Logic | Custom instruction `crcb` | 0:28 | 3:05 |
| 10 | 02 · Application Logic | System overview | 0:25 | 3:30 |
| 11 | 02 · Application Logic | Application logic | 0:22 | 3:52 |
| 12 | 02 · Application Logic | Emulator | 0:22 | 4:14 |
| 13 | 02 · Application Logic | Demo 1: normal session | 0:25 | 4:39 |
| 14 | 02 · Application Logic | Demo 2: grid dip | 0:38 | 5:17 |
| 15 | 02 · Application Logic | Validation | 0:25 | 5:42 |
| 16 | 03 · Pitch | Competitive analysis | 0:22 | 6:04 |
| 17 | 03 · Pitch | Value & practical functionality | 0:28 | 6:32 |
| 18 | 03 · Pitch | Stage 4 roadmap | 0:12 | 6:44 |
| 19 | 03 · Pitch | Closing | 0:18 | 7:02 |

Chapter split: Technical 1:37 · Application Logic 3:35 · Pitch 1:20
(plus a 0:30 selling hook across slides 7 and 8).

---

## 1 · Title (0:10, ~30 words)

> Hi, we're Equipe 26, and this is Gripple: a RISC-V chip that runs an
> electric car charger and helps keep the power grid standing.
> Let's start with what's inside.

*Camera: small bubble. Smile, then go.*

---

## 01 · TECHNICAL

### 2 · Project architecture, ChipInventor (0:15, ~38 words)

> This is our full chip, built in ChipInventor. In orange, our RVBL-2
> processor from Stage 2. On the right, the two new peripherals: GPIO for
> eight pins, and a UART serial port. Core, memory and peripherals, all on
> one die.

*Cue: point or highlight each coloured box as it is named.*

---

### 3 · Project architecture, block diagram (0:12, ~30 words)

> Here's the same chip, simplified. The core is controlled by a nine-state
> FSM, and it runs RV32I, plus Zmmul for multiply, plus Xicrc, our own CRC
> extension.

---

### 4 · Hardware design (0:20, ~50 words)

> To the processor, the peripherals are just memory. The GPIO sits at
> addresses starting F0, the UART at F1. So the firmware reaches the outside
> world with ordinary load and store instructions. No new instructions needed.
> On the right is the emulator. It plays the outside world: the car, the
> emergency stop, and the energy meter.

---

### 5 · Firmware implementation (0:30, ~78 words)

> The firmware is 264 instructions of assembly, doing three jobs.
> **Read:** it polls the UART and collects each 8-byte meter reading:
> voltage, current, frequency, and a checksum.
> **Check and calculate:** our `crcb` instruction verifies every byte as it
> arrives, and a multiply turns voltage times current into energy.
> **Control:** one store to the GPIO sets the lock, the power contactor,
> grid hold, or fault.
> Everything lives in registers. No RAM at all, so it fits the cheapest chip.

*Cue: highlight each column in turn.*

---

### 6 · Official firmware testbench (0:20, ~50 words)

> Before building anything on top, we ran the organisers' official test.
> A value on the input pins comes back on the output pins, and a byte sent
> over UART is echoed straight back. Every check passes, on all three versions
> of our top level. The hardware works. Now, what do we use it for?

*The question at the end is the bridge into chapter 2. Pause after it.*

---

## 02 · APPLICATION LOGIC

### 7 · Problem statement (0:28, ~72 words)

> Picture 7 pm. A thousand electric cars are charging, seven kilowatts each.
> A power station trips, grid frequency drops, and every charger does the
> right thing: it stops.
> Seconds later the grid recovers, and all thousand restart in the same
> instant. Seven megawatts slams back onto a grid that has only just
> recovered, and it trips again.
> Stopping is safe. Restarting together is the danger.

*Slow down here. Pause for a beat after "trips again".*

---

### 8 · Proposed solution (0:22, ~58 words)

> Gripple fixes this. **Staggered restart:** each charger works out its own
> restart moment from its ID and the grid event, so a thousand chargers come
> back across eight time slots, not one instant. No network, no clock, no
> random numbers.
> **Integrity-checked metering:** a corrupted, missing or replayed meter
> reading is never billed.

---

### 9 · Custom instruction `crcb` (0:28, ~72 words)

> Both come from one instruction. `crcb` folds one byte into a CRC-16
> checksum. In software, that's a loop of shifts and XORs: 1,276 cycles for
> one meter reading. With `crcb`: 60. Twenty-one times faster.
> And it does three jobs. **Check:** every reading is verified on arrival.
> **Chain:** each reading's checksum seeds the next, so a missing or replayed
> one breaks the chain. **Time:** the same instruction computes each charger's
> restart delay.

*Say `crcb` as "C-R-C-B". Reveal the three cards one at a time.*

---

### 10 · System overview (0:25, ~62 words)

> Here's the charger around our chip.
> **In:** the car's pilot signal on three pins, the emergency stop on one,
> and meter readings over UART.
> **Out:** contactor, lock, grid hold and fault on four pins, and a session
> record over UART at the end.
> Inside, the firmware runs a state machine: idle, connected, charging, grid
> hold, and fault, which can be reached from any state.

---

### 11 · Application logic (0:22, ~55 words)

> And this is how the emulator talks to our chip. Two lanes.
> **Pins:** the emulator sets the inputs, the firmware reads them, decides,
> and writes the outputs, which the emulator checks.
> **Serial:** the emulator sends meter bytes, the firmware checks and bills
> them, and sends back a record.
> Only loads and stores, so nothing is emulator-specific.

*Reveal the GPIO lane first, then the UART lane.*

---

### 12 · Emulator (0:22, ~57 words)

> One real command, read left to right. Minus d sets which pins the emulator
> watches. Minus i: the car plugs in. Minus o: we expect the lock to close.
> Minus t4 sends four meter bytes. Minus r reads the record back.
> Options run in order, and the first wrong answer stops the test. So a pass
> means every single step was right.

*(cut if long): "So a pass means every single step was right."*

---

### 13 · Demo 1: normal session (0:25, ~60 words)

> Demo one: a normal session, running on our RTL.
> Plug in: the lock closes. Ask to charge: the contactor closes. Two good
> meter readings arrive and are billed.
> Unplug: the outputs go safe first, then the chip sends its record: the
> energy, two readings billed, no faults, and its own checksum. Every value
> matches what the emulator expects.

*Clip label on screen: "RTL simulation, sped up". Time each sentence to the
matching moment in the clip.*

---

### 14 · Demo 2: grid dip and staggered restart (0:38, ~98 words)

> Demo two is the heart of our idea.
> The car is charging normally. Then the grid dips: frequency falls to 49.2
> hertz, below our 49.5 limit. The chip opens the contactor and goes into grid
> hold, but keeps the car locked, so the driver never has to replug.
> It works out its restart delay from its ID and this event: three healthy
> readings. The next reading is still weak, so the count starts again. Then
> three healthy readings, and charging resumes on its own.
> Another charger gets a different delay. That's how a thousand chargers come
> back in turns.

*This is the most important 40 s of the video. Slow down. Point at each
table row as it happens.*

---

### 15 · Validation (0:25, ~62 words)

> How do we know it's right? A Python model computes every expected value,
> and our testbench mirrors the real emulator, option by option.
> We inject faults: corrupted, dropped and replayed readings, emergency stop,
> over-current, bad pilot signals.
> Fifteen scenarios on three versions of the chip: 45 out of 45 runs pass,
> and 38 out of 38 model tests.

*Pause after "45 out of 45".*

---

## 03 · PITCH

*Camera: switch to large or full frame for this chapter. Stand, look into the
lens, slower pace.*

### 16 · Competitive analysis (0:22, ~55 words)

> So why would anyone choose Gripple?
> Basic chargers restart all at once. Timer chargers all wait the same time.
> Smart chargers need a random-number source, and their delay can't be checked
> afterwards. Networked chargers fail exactly when the network does.
> Gripple spreads the surge, senses the grid itself, and needs nothing extra:
> just one small chip.

---

### 17 · Value & practical functionality (0:28, ~66 words)

> In practice, that means three things.
> **For the grid:** a restart surge nearly eight times smaller, and room for
> more chargers on the same network.
> **For drivers:** charging pauses and resumes by itself. No replugging.
> **For operators:** only verified readings are billed, so fewer disputes.
> And for regulators, any charger's delay can be recomputed after the event.

*(cut if long): the regulator sentence.*

---

### 18 · Stage 4 roadmap (0:12, ~28 words)

> Next: Stage 4 on the AWS FPGA with the real emulator. Then real meters and
> grid-code limits, a Sky130 tapeout, and a pilot on real chargers.

---

### 19 · Closing (0:18, ~38 words)

> Remember 7 pm: seven megawatts slamming back at once.
> With Gripple, it's under one megawatt, coming back in turns.
> One CRC instruction. Grid protection built in.
> We're Equipe 26. Thank you.

*Hold eye contact for two seconds after "Thank you" before the video ends.*

---

## Words the script avoids on purpose

These appear on the current slides but can't be backed up or are overstated.
Don't say them on camera.

| On slide | Why not |
|---|---|
| "0.2% of the chip's time" (slide 9) | No run or file backs this number |
| "Same firmware runs on the FPGA unchanged" (slides 5, 11) | Not yet run on the FPGA. The script says "nothing is emulator-specific" instead |
| "Only ours ticks every box" (slide 16) | Our own comparison table; the script lets the rows speak |
| "Tamper-proof" / "secure" billing | CRC catches faulty links, not a deliberate forger. Say "verified" or "integrity-checked" |

## Recording notes

- **Speakers.** If more than one person narrates, hand over only at chapter
  breaks (after slide 6 and after slide 15). Mid-chapter handovers break the
  flow.
- **Pronunciation.** `crcb` = "C-R-C-B" · Zmmul = "Z-M-M-U-L" · `./emu` =
  "the emulator" · RISC-V = "risk five".
- **Rehearse twice** with a stopwatch against the "Ends at" column. If you are
  past 5:20 at the end of Demo 2, cut the *(cut if long)* lines.
- **Keep the final cut at or under 7:45.**