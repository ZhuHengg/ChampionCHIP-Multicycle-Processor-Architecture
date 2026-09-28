# Application protocol — grid-aware EV charging-station controller

This directory mirrors the organiser's `RVBL-Emulator/` for **our** application.
`RVBL-Emulator/README.md` asks each application to define six things before
FPGA integration. They are answered here in that order.

Firmware: `chip-inventor/firmware/src/main.s` (`FIRMWARE 5`).
Golden model: `chip-inventor/testbench/app/golden.py`.
Spec: `docs/STAGE3_STRATEGY.md` §7.

---

## 1. Which GPIO pins are inputs and outputs

`DATADIR = 0xF0` — P7–P4 outputs, P3–P0 inputs. The emulator therefore runs
with **`-d 0xF0`** (bit 1 = the emulator releases the line and observes the
processor output).

| Pin | Dir | Signal | Meaning |
|---|---|---|---|
| P2–P0 | in | `CP_STATE` | Control-pilot code: 0 = A (no car), 1 = B (connected), 2 = C (charge request), 3 = D (ventilation required), 4 = E (error), 5 = F (EVSE fault); 6, 7 invalid |
| P3 | in | `SAFETY_TRIP` | 1 = emergency stop pressed or RCD tripped |
| P4 | out | `CONTACTOR` | 1 = power on the cable |
| P5 | out | `CABLE_LOCK` | 1 = cable locked in the socket |
| P6 | out | `GRID_HOLD` | 1 = charging paused for grid support |
| P7 | out | `FAULT` | 1 = latched fault |

`-d 0xF0` must come first: `fpga_init` defaults the direction to `0x01`.

## 2. Is a GPIO input used as a trigger?

**No.** The control-pilot code and the safety pin are *levels*, polled
continuously in the main loop. Consequences for the emulator:

- `-i` may appear before or after any `-t`, as often as needed — one command can
  walk the car through a whole session.
- An `-o` immediately after an `-i` is valid: the firmware re-reads its inputs
  every loop pass, so it does not need a UART byte to make progress. (The
  organiser's own test firmware *does*, which is why their README example only
  passes when `IN` already holds the value at boot — see §"What we rely on".)
- The pilot/safety rules are re-applied until the state stops changing, so
  `-i 0x02` from IDLE settles straight to CHARGING (IDLE → CONNECTED →
  CHARGING) before the next option is processed.

## 3. How many bytes go to the processor over UART RX

**8 bytes per meter frame**, and any number of frames per command. There is no
header, length byte or resync marker: frames are aligned by byte count from
reset, because the emulator always sends whole frames.

## 4. The order and meaning of those bytes

One meter frame, all fields little-endian (which is the order `./emu -t` sends):

| Bytes | Field | Unit | Example |
|---|---|---|---|
| 0–1 | `V` voltage | 0.1 V | 2300 = 230.0 V |
| 2–3 | `I` current | 0.1 A | 160 = 16.0 A |
| 4–5 | `F` frequency | 0.01 Hz | 5000 = 50.00 Hz |
| 6–7 | `CRC` | CRC-16 over bytes 0–5 | — |

As emulator options, one frame is two words:

```shell
-t4 (I << 16 | V)   -t4 (CRC << 16 | F)
```

**The CRC chain is the point of the protocol.** The CRC-16 (poly `0x1021`,
non-reflected, xorout 0 — our `crcb` instruction) is seeded not with `0xFFFF`
every time, but with **the CRC field of the previous frame received**, valid or
not (`0xFFFF` after reset). The meter advances its chain on every frame it
sends.

Why: the emulator allows only 8 reply bytes per command, so there is no room
for per-frame acknowledgement — the meter cannot know which frames the charger
accepted. Seeding from the previous *transmitted* CRC makes the chain
self-resynchronising:

| Event | Cost |
|---|---|
| corrupted payload | exactly one rejected frame |
| dropped or re-ordered frame | one rejected frame (the one after the gap) |
| replayed frame, or corrupted CRC field | two rejected frames → `FAULT` |

Two consecutive rejected frames latch `FAULT` with the CRC-lost flag.

## 5. How many bytes the firmware returns

**Exactly 8, once per session.** `fpga_read_uart` keeps one static byte pointer
across all `-r` options and the window is 64 bits, so a command may never read
more than 8 bytes. The firmware sends its record when the session ends (car
unplugged) or when a fault latches — never one reply per frame.

`chip-inventor/testbench/app/test_scenarios.py::test_every_scenario_reads_exactly_8_bytes`
holds every scenario to this limit, and the testbench fails a run that
transmits a 9th byte.

## 6. The meaning of the GPIO and UART results

GPIO output byte per state:

| State | `-o` value | P7–P4 |
|---|---|---|
| `IDLE` | `0x00` | — |
| `CONNECTED` | `0x20` | lock |
| `CHARGING` | `0x30` | lock + contactor |
| `GRID_HOLD` | `0x60` | lock + grid-hold |
| `FAULT` | `0x80` | fault (latched) |

The session record (UART TX), 8 bytes:

| Bytes | Field |
|---|---|
| 0–3 | `ENERGY`, Σ V·I over billed frames, mod 2³² (`mul`) |
| 4 | `STATUS`: bits [2:0] end state, bits [7:3] cause flags |
| 5 | `FRAMES`: billed frames, saturating at 255 |
| 6–7 | `CRC` over bytes 0–5, seed `0xFFFF` |

As options: `-r4 ENERGY -r2 (FRAMES << 8 | STATUS) -r2 CRC`.

Cause flags: `0x08` E-stop, `0x10` CP error, `0x20` over-current, `0x40` CRC
chain lost, `0x80` grid hold occurred.

---

## Scenarios

`emu_commands.txt` holds one `./emu` command per scenario, generated from the
golden model. Run them all with `run_scenarios.sh`.

| # | Scenario |
|---|---|
| S1 | Normal session: plug in, charge two frames, unplug |
| S1X | S1 with back-to-back UART bytes (no gap between bytes or frames) |
| S2 | Grid under-frequency → hold → CRC-timed restart on the predicted frame |
| S3 | Corrupted frame and dropped frame each cost one frame; chain resynchronises |
| S4 | Meter link lost: two bad frames in a row latch `FAULT` |
| S5 | E-stop while charging, latched until released **and** unplugged |
| S6 | Plug straight into CP C, unplug while charging |
| S7 | Frame exactly on every limit is billed; `I_MAX + 1` faults |
| S8 | Ventilation (CP D) refused; CP E latches `FAULT` |
| S9 | Invalid pilot code 7 latches `FAULT` |
| S10 | Replayed frame rejected, and the next one too → `FAULT` |
| S11 | Stale pins at boot: CP C already asserted, settles to CHARGING |

## What we rely on in the emulator

Verified by reading `RVBL-Emulator/src/emu.c` in full:

1. **Every command resets the processor** (`fpga_init`: reset 1 → 0 → 1). No
   state survives between commands, so each scenario is one self-contained
   command.
2. **The GPIO input value persists across that reset.** `-d` is a
   read-modify-write of the high byte of the `IN` register, so the low byte
   (the input value) keeps whatever the previous run left. The firmware can
   therefore boot with pins already asserted — scenario S11 pins this
   deliberately, and it is why the organiser's README example passes.
3. **Options run strictly in order, and the first mismatch aborts the rest**
   (`goto main_end`).
4. **At most 8 reply bytes per command**, through a running pointer (§5).
5. **`-t` sends multi-byte values low byte first.**
6. **The exit code is inverted** (`return err ? EXIT_SUCCESS : EXIT_FAILURE`):
   a clean run reports failure. `run_scenarios.sh` therefore judges pass/fail
   from the `[ok]` / `[error]` lines and ignores `$?`. Worth reporting to the
   organisers.
7. **Each AXI access sleeps 50 ms**, so the host is far slower than the chip;
   the firmware never races the emulator.

## How `emu_commands.txt` is generated

```bash
python chip-inventor/testbench/app/scenarios.py
```

`scenarios.py` builds each scenario against `golden.py`, so every expected
`-o` and `-r` value is computed by the model rather than written by hand. The
same scenario objects drive the Verilog testbench
(`chip-inventor/testbench/app/`), where each `emu_*` task mirrors one emulator
option — so a passing simulation is a passing `./emu` command against our RTL,
and the same lines should run unchanged on the FPGA.
