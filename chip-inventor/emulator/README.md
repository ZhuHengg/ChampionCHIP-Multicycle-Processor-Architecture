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
- A charge request stays CONNECTED (`0x20`) until a healthy meter frame arrives.
  The 500 ms meter watchdog requires regular accepted frames during a session.

## 3. How many bytes go to the processor over UART RX

Protocol v2 uses **11?20 wire bytes per frame**: two `0x7E` markers surrounding
an escaped nine-byte body. Send both markers for every frame. Adjacent frames may
share a marker, but a fresh start marker is required after a long pause.
The old unframed eight-byte application input format is no longer supported.
The organiser's separate FIRMWARE 4 UART echo protocol is unchanged.

## 4. The order and meaning of those bytes

Unescaped body, with all multibyte values little-endian:

| Bytes | Field | Unit |
|---|---|---|
| 0 | Sequence | Increment modulo 256 for every generated measurement |
| 1?2 | Voltage | 0.1 V |
| 3?4 | Current | 0.1 A |
| 5?6 | Frequency | 0.01 Hz |
| 7?8 | CRC-16 | Covers bytes 0?6, fixed seed `0xFFFF`, poly `0x1021`, no reflection/xorout |

Escape **every** body byte equal to `0x7E` or `0x7D` as `0x7D` followed by that
byte XOR `0x20`. This includes sequence and CRC bytes. Other escape pairs are
invalid. The receiver accepts exactly nine decoded bytes followed by a marker;
short or oversized bodies cannot be billed. It never waits indefinitely for a
missing byte: **100 ms without another byte discards an unfinished frame**.
That byte timer is separate from the 500 ms accepted-meter-data watchdog.

The first accepted frame establishes sequence after processor reset or a new
vehicle session. Thereafter `delta = (sequence - previous) & 255` is used:

| Delta | Action |
|---|---|
| 1 | Accept normal next frame |
| 2?127 | Accept current frame, flag a gap with status bit `0x40`; missing measurements are not billed |
| 0 or 128?255 | Reject duplicate/backward/ambiguous sequence; do not refresh the watchdog |

Only valid CRC and acceptable sequence refresh meter freshness. Bad CRC, bad
framing, sequence rejection, or a partial timeout count as rejected frames.
Two consecutive rejections latch FAULT, reusing link-error bit `0x40`.
A successful frame clears that consecutive-error count but never releases a
latched FAULT or METER_TIMEOUT. A new session resets the sequence baseline and
parser, allowing a restarted sender to begin at zero. An 8-bit sequence is not
cryptographic replay protection and cannot distinguish every old replay after wrap.

Example: sequence 0, 230.0 V, 16.0 A, 50.00 Hz:

```text
7E 00 FC 08 A0 00 88 13 A9 33 7E
```

Generate bytes or emulator transmit options with the actual sender helper:

```sh
python emulator/meter_protocol.py --sequence 0 --voltage 2300 --current 160 --frequency 5000
python emulator/meter_protocol.py --sequence 0 --voltage 2300 --current 160 --frequency 5000 --format emu
```

The second command prints:

```text
-t4 0x08FC007E -t4 0x138800A0 -t4 0x7E7E33A9
```

Append those options to the same `./emu` invocation as the GPIO/session commands;
starting another invocation resets the processor. Keep every inter-byte/host gap
below 100 ms, and accepted complete frames within the 500 ms watchdog deadline.
Use `frame_body` and `encode_frame` from `meter_protocol.py` in a real meter sender.

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
| `FAULT` | `0x80` | fault (latched), state code 4 |
| `METER_TIMEOUT` | `0x80` | meter timeout (latched), state code 5 |

The session record (UART TX), 8 bytes:

| Bytes | Field |
|---|---|
| 0–3 | `ENERGY`, Σ V·I over billed frames, mod 2³² (`mul`) |
| 4 | `STATUS`: bits [2:0] end state, bits [7:3] cause flags |
| 5 | `FRAMES`: billed frames, saturating at 255 |
| 6–7 | `CRC` over bytes 0–5, seed `0xFFFF` |

As options: `-r4 ENERGY -r2 (FRAMES << 8 | STATUS) -r2 CRC`.

Cause flags: `0x08` E-stop, `0x10` CP error, `0x20` over-current, `0x40` link error / sequence gap, `0x80` grid hold occurred.

---

## Scenarios

`emu_commands.txt` holds one `./emu` command per scenario, generated from the
golden model. Run them all with `run_scenarios.sh`.

| # | Scenario |
|---|---|
| S1 | Normal session: plug in, charge two frames, unplug |
| S1X | S1 with back-to-back UART bytes (no gap between bytes or frames) |
| S2 | Grid under-frequency → hold → CRC-timed restart on the predicted frame |
| S3 | Corrupted/missing frames; next intact frame is accepted, gap flagged |
| S4 | Meter link lost: two bad frames in a row latch `FAULT` |
| S5 | E-stop while charging, latched until released **and** unplugged |
| S6 | Plug straight into CP C, unplug while charging |
| S7 | Frame exactly on every limit is billed; `I_MAX + 1` faults |
| S8 | Ventilation (CP D) refused; CP E latches `FAULT` |
| S9 | Invalid pilot code 7 latches `FAULT` |
| S10 | Replayed frame rejected, and the next one too → `FAULT` |
| S11 | Stale pins at boot: CP C already asserted, waits for healthy data |

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
   Because the input value is whatever the *previous* command left, S11 is
   preceded by an "S11 setup" line that leaves IN = 0x02 for the reset that
   starts S11 (so `run_scenarios.sh` runs 13 lines for 12 scenarios).
3. **Options run strictly in order, and the first mismatch aborts the rest**
   (`goto main_end`).
4. **At most 8 reply bytes per command**, through a running pointer (§5).
5. **`-t` sends multi-byte values low byte first.**
6. **The exit code is inverted** (`return err ? EXIT_SUCCESS : EXIT_FAILURE`):
   a clean run reports failure. `run_scenarios.sh` therefore judges pass/fail
   from the `[ok]` / `[error]` lines and ignores `$?`. Worth reporting to the
   organisers.
7. **Each AXI access sleeps 50 ms**, so the host is far slower than the chip;
   those delays must stay below the configured inter-byte and meter deadlines.

## How `emu_commands.txt` is generated

```bash
python chip-inventor/testbench/app/scenarios.py
```

`scenarios.py` builds each scenario against `golden.py`, so every expected
`-o` and `-r` value is computed by the model rather than written by hand. The
same scenario objects drive the Verilog testbench
(`chip-inventor/testbench/app/`), where each `emu_*` task mirrors one emulator
option — simulation verifies the command sequence against RTL. Real FPGA host pacing
and hardware operation still require validation.


Emulator word packing appends up to three harmless `0x7E` end markers so each
write uses `-t4`. For the nominal frame this reduces four host writes to three,
leaving more margin below the meter watchdog when one frame is corrupted. The
plain hex encoder still emits the canonical 11-byte nominal frame. A Python
regression checks nominal good/bad/good frames with 50 ms host access delays.
