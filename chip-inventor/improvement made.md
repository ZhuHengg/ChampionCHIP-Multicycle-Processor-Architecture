## Stage 4 timing update ? 11 October 2026

The active demonstration defaults are now **4000 ms for meter freshness** and
**400 ms for an unfinished UART frame**, replacing the 500/100 ms defaults in
the historical entries below. Stock host access delays require about 1.2 s per
nominal meter frame and about 2.5 s between accepted frames in the recovery
scenarios. The state machine and fault latch rules are unchanged. Firmware,
Python model/boundary tests, frontend model, ROMs, and AWS images were updated
together. See `new change.md` and the current handoff follow-up for validation
and remaining host/hardware work.

## Integration onto latest main ? 7 October 2026

Applied both improvements to `chip-inventor/` on top of upstream main
`4f230410aed9e380def1da6eb26ed907f185e9fb` from
https://github.com/ZhuHengg/ChampionCHIP-Multicycle-Processor-Architecture.git.
Local branch: `improvements/meter-watchdog-uart-recovery`.
The original downloaded project and its backup remain separate.

Paths and commands in the earlier entries below are relative to `chip-inventor/`;
run `cd chip-inventor` from the repository root first. Upstream's repository
layout and other build tracks are preserved. These changes apply to the active
`chip-inventor/hdl.v` and `chip-inventor/rtl/top.v` application build (FIRMWARE=5).
The `legacy/` and `v2-chip-inventor-synth/` tracks have not been migrated.

## Frontend migration — 8 October 2026

The frontend's data layer (`frontend/src/data/{charger,meter,scenarios}.ts`)
and the components that read frame bytes directly (`CRCChainViz.tsx`,
`FrameInspector.tsx`, `StationView.tsx`, `StateIndicator.tsx`,
`ScenarioPicker.tsx`) have been migrated to match this integration:
protocol-v2 framing (`data/meterProtocol.ts`, a port of
`emulator/meter_protocol.py`), the 9-byte sequence-numbered frame body in
place of the old 8-byte chained-CRC frame, and the new `METER_TIMEOUT`
state with a `tick()` scenario step for time-driven watchdog demos. A new
`S12` scenario (not in `scenarios.py`, which covers the watchdog in
`test_watchdog.py` instead) demonstrates the 500 ms silence-to-fault path
for the viewer. Verified against `test_watchdog.py` and `test_resync.py`
cases (startup timeout, silence-after-charging latch, refresh-on-valid-
frame, dropped-byte recovery, noise/empty-marker tolerance) ported
ad hoc into TypeScript and run with `tsx` — all passed; `tsc --noEmit` and
`vite build` both pass clean. Hardware/FPGA validation remains separate
work.

Firmware was rebuilt to 370 instructions. All 78 Python tests passed in this
checkout. The merged firmware and both flattened RTL designs have the same
executable code as the previously validated improvements; upstream documentation
and path updates were retained. The timer unit test and all 14 watchdog RTL cases also passed in this checkout.
The validation entries below describe the original implementation runs; current
integration results are recorded in `testbench/app/evidence/main_integration_validation.log`.
All 44 UART recovery RTL cases passed on the merged checkout as well.

# Improvement made: meter-data watchdog

Implemented on 7 October 2026.

## Problem addressed

Previously, the controller could close the contactor before receiving a meter
measurement. If the meter then stopped transmitting, charging could continue
indefinitely. The two-invalid-CRC-frame rule detected bad frames, but not silence.

## New behavior

| Situation | Controller behavior |
|---|---|
| Vehicle connects, including CP C already asserted at boot | Stay CONNECTED, cable locked, contactor open (`0x20`) |
| First CRC-valid, healthy measurement arrives while CP C is requested | Enable charging (`0x30`) |
| First measurement indicates low voltage/frequency or overcurrent | Enter GRID_HOLD or FAULT before closing the contactor |
| Complete CRC-valid frame with acceptable sequence arrives | Restart the meter-age timer |
| Corrupt frame or only part of a frame arrives | Do not restart the timer |
| No valid frame for 500 ms in CONNECTED, CHARGING, or GRID_HOLD | Enter METER_TIMEOUT, open the contactor, illuminate fault LED (`0x80`), send one report |
| No meter frames while IDLE | Remain IDLE; do not send a fault report |
| Meter resumes after timeout | Remain faulted; do not automatically restart or send another report |
| Emergency input is clear and pilot becomes A / unplugged | Release the latch; next session requires a new healthy measurement |

The initial deadline starts when the vehicle session begins. Subsequent deadlines
start when the firmware validates a complete frame and its sequence. A CRC-valid but unhealthy
measurement with acceptable sequence refreshes communication freshness; the existing voltage, frequency,
and current rules separately determine charging behavior.

The first healthy frame is included in the existing `V × I` sample accumulator,
preserving the application's accounting convention. This change does not convert
that accumulator into Wh.

## Hardware and firmware implementation

- Added `rtl/meter_timer.v`: a clock-derived, saturating 32-bit millisecond counter.
- Added the timer register at **`0xF2000000`** to `rtl/address_decoder.v`.
  `lw` reads elapsed milliseconds; a full-word `sw` restarts both the counter and
  divider. Byte/halfword stores do not refresh it. No CSR or new instruction is used.
- At the default 20 MHz clock, 20,000 clocks equal one millisecond. The divider
  follows `CLK_HZ`; use a clock frequency divisible by 1,000 for exact milliseconds.
- Updated `firmware/src/main.s` to check age in the main loop before polling UART,
  gate charging on fresh healthy data, and report timeout after setting safe outputs.
- The counter saturates at `0xFFFFFFFF`; it cannot wrap and make stale data appear
  fresh. No extra stack or DMEM is required. Register `sp/x2` is used as a healthy-data
  flag; this remains a stackless application.
- Updated both flattened designs, `hdl.v` and `rtl/top.v`, and regenerated their
  application ROMs plus `rtl/imem.v`. The application now occupies **370 words** (including protocol v2 below)
  of the 1,024-word instruction ROM.
- Rebuilt `firmware/build/firmware.bin`, `.elf`, `.txt`, and `.dmp`.

## Timeout configuration and timing

Edit `METER_TIMEOUT_MS` in `firmware/src/main.s`, then rebuild. **500 ms is a
configurable demonstration default**, chosen for this improvement because the
real meter's update period has not been specified. Select the final value from
the expected complete-frame interval plus communication and processing margin.
Keep the corresponding constant in `testbench/app/golden.py` and the deadline
boundary tests aligned when changing this setting.

The timer measures clock time rather than loop iterations. The GPIO output opens
on the first watchdog check after the deadline, with firmware polling latency.
The contactor-open command precedes UART report transmission. Actual mechanical
opening time depends on the external contactor.

This is a firmware watchdog: the CPU must continue running. It does not add an
independent hardware contactor interlock. UART byte-loss resynchronization is implemented in improvement 2 below.
Nonblocking report transmission remains a separate improvement.

## Report compatibility

The report remains eight bytes:

```text
Accumulator u32 LE | Status u8 | Frame count u8 | CRC-16 u16 LE
```

All five existing cause-flag bits are occupied. Instead of overlapping a flag,
the new **METER_TIMEOUT state uses low-three-bit state code `5`**; its GPIO output
is the same as FAULT. Existing states 0–4 and cause flags retain their encodings.

- Timeout with no earlier flags: status `0x05`.
- Timeout following a grid hold: status `0x85`.

Report consumers must recognize `(status & 0x07) == 5` as a latched meter timeout.
This is an application-protocol extension to the original five-state behavior.

## Build and verification

The new portable helper builds with RISC-V GNU binutils and synchronizes ROMs:

```sh
python firmware/scripts/build.py --tool-prefix /path/to/riscv-none-elf-
```

The original organiser Makefile/linker script/converter remain available and
unmodified. With their toolchain installed, `make` in `firmware/` followed by
`python testbench/gen_imem.py` is still supported.

```sh
python -m pytest testbench/app -q
python testbench/app/run_tests.py --no-vcd
python testbench/app/run_watchdog_tests.py
python testbench/uart/run_tests.py
```

Both RTL runners accept `--iverilog PATH --vvp PATH`. The focused watchdog tests
verify startup gating, missing initial data, silence after charging, corrupt and
partial frames, deadline refresh, fault latching, reset, and silence in GRID_HOLD
and IDLE. They also check that the contactor is open before report transmission.

The timer unit test checks the real 20 MHz divider, MMIO routing, full-word refresh,
reset, and saturation. The focused SoC tests accelerate only the timer divider
100× for runtime, retaining the production firmware's 500-tick comparison. They
are not a wall-clock-length 500 ms SoC simulation. The ordinary application
regressions use the production divider.

Initial watchdog-only validation completed successfully (before protocol v2):

- **49/49 Python tests passed.**
- **30/30 application regression runs behaved as expected** across both tops;
  this includes the deliberately rejected H1 harness mismatch on each top.
- **14/14 focused watchdog SoC runs passed.**
- **Timer divider/MMIO/refresh/saturation/reset unit test passed.**
- **5/5 UART and 5/5 GPIO regression runs passed**, including organiser firmware.
- Timer, address decoder, and ROM module copies match their canonical RTL sources.

Summary evidence: [watchdog_validation.log](testbench/app/evidence/watchdog_validation.log).
Detailed simulation logs are in `sim/app/` (ignored build output).

## Loading the application

As before, application firmware is **FIRMWARE 5**; the default ROM selection
remains the original Stage 2 validation program (FIRMWARE 0). Select FIRMWARE 5
when building a charging-controller image. No FPGA programming or physical
implementation run was performed for this change.

`convertion/diagram.json` is the previous canvas diagram. The updated flattened
Verilog contains the new timer wiring. Before regenerating Verilog from that
older canvas, add the timer block and the decoder's `timer_data_i`, `timer_we_o`,
and `timer_oe_o` connections, or the new wiring would be lost.


# Improvement 2: UART frame resynchronization

Implemented on 7 October 2026. This section describes the current **protocol v2**
application input. It supersedes the previous unframed eight-byte, CRC-chained
meter format. The eight-byte output session report is preserved.

## Problem addressed

Counting every eight received bytes from reset could permanently shift frame
boundaries after a dropped byte. CRC detected the errors but could not locate the
next frame. A missing frame also disrupted the old CRC chain. The meter watchdog
stopped stale charging, but did not repair communication alignment.

## New wire format

```text
7E | escaped [Sequence u8 | Voltage u16 | Current u16 | Frequency u16 | CRC u16] | 7E
```

- The decoded body is exactly nine bytes. Multibyte fields are little-endian;
  voltage/current/frequency units are unchanged.
- Body bytes `7E` and `7D` become `7D 5E` and `7D 5D`, respectively. Escape the
  sequence and CRC too. Other escape pairs are rejected.
- CRC-16 uses polynomial `0x1021`, seed `0xFFFF`, no reflection or final XOR,
  covering sequence plus the six measurement bytes. It is independent for every
  frame, so losing a frame no longer breaks later CRC checks.
- Each frame is 11?20 wire bytes. The closing marker validates the exact length;
  an oversized frame cannot bill an apparently valid prefix.
- A marker ends the current candidate and starts a new one. Repeated empty
  markers are harmless. After an error, the parser recovers at the next marker.

Example for sequence 0, 230.0 V, 16.0 A, 50.00 Hz:

```text
7E 00 FC 08 A0 00 88 13 A9 33 7E
```

## Sequence and fault behavior

The sender increments an eight-bit sequence modulo 256 for each measurement.
The first accepted frame after CPU reset or a new vehicle session establishes
its baseline. For later frames, delta is `(received - last accepted) & 255`:

| Delta | Result |
|---|---|
| 1 | Accept normally, including 255 ? 0 wraparound |
| 2?127 | Accept the intact current frame; set existing link-error status bit `0x40` to record a gap |
| 0 or 128?255 | Reject duplicate, backward, or ambiguous sequence |

Missing measurements are never billed. CRC-invalid or sequence-rejected frames
never advance the accepted sequence and never refresh the 500 ms watchdog.
Sequence checks are not authentication; eight-bit numbering cannot identify
all old replays after wraparound. A sender restart/long ambiguous sequence gap
requires a new vehicle session or processor reset to reestablish the baseline.

Malformed length/escaping, CRC errors, rejected sequences, and unfinished-frame
timeouts count as failed frames. **Two consecutive failures still latch FAULT**
and send one link-error report. The failure count saturates at two. A successful
frame clears this count and refreshes meter age, but **does not clear a latched
FAULT or METER_TIMEOUT**. Release still requires emergency input clear and pilot A.
A new session discards any previous partial frame and requires fresh healthy data.

Status bit `0x40` can now appear on a normal end-of-session report to indicate a
sequence gap. It does not by itself mean the final state is FAULT; consumers
should decode state separately using `status & 7`.

## Partial-frame timer

Added an independent elapsed timer at **`0xF2000004`**. A full-word write resets
only this inter-byte timer; reading returns elapsed milliseconds. The existing
meter-validity timer stays at `0xF2000000`.

`RX_TIMEOUT_MS = 100` in `firmware/src/main.s` discards unfinished parser state
when no byte arrives for 100 ms. An unfinished nonempty frame or dangling escape
counts once, then the receiver ignores remaining tail bytes until another marker.
An empty marker wait simply expires without a framing error. Byte activity resets
only the inter-byte timer, so noise cannot keep the meter watchdog fresh.

Both counters saturate rather than wrap. Firmware remains stackless and uses no
DMEM: parser count/flags share `s9`, last accepted sequence uses `s2`, and the
candidate sequence/CRC share `gp`. Both flattened top-level files include the
updated timer ports and address decoder. Rebuilt firmware occupies **370 words**.

## Sender migration and affected files

This is an intentional application protocol change. **An existing meter sender
must be updated before using FIRMWARE 5.** The organiser's FIRMWARE 4 GPIO/UART
protocol and peripheral registers are unchanged.

- `emulator/meter_protocol.py`: reusable encoder, CRC, measurement-body builder,
  and CLI for real sender integration or emulator transmit options.
- `firmware/src/main.s`: escaped-frame parser, sequence checks, timeout handling.
- `rtl/meter_timer.v`, `rtl/address_decoder.v`, `hdl.v`, `rtl/top.v`: two independent
  timers and their routing. The timer now also needs the raw `addr_i` bus when
  updating the older ChipInventor canvas diagram.
- `testbench/app/golden.py`, `scenarios.py`, `emulator/emu_commands.txt`: updated
  reference model and complete generated protocol-v2 scenario commands.
- `firmware/build/` and all application ROM copies: rebuilt and synchronized.

```sh
python emulator/meter_protocol.py --sequence 0 --voltage 2300 --current 160 --frequency 5000 --format emu
```

Outputs transmit options `-t4 0x08FC007E -t4 0x138800A0 -t4 0x7E7E33A9`.
Append these to the same emulator invocation as the GPIO/session actions; a new
invocation resets the processor. Keep host and wire gaps below 100 ms between
bytes and below 500 ms between accepted frames. The 100 ms demonstration default
allows the documented 50 ms host access delay but actual hardware pacing still
needs checking. Change the firmware/model constants and boundary tests together
if the real sender needs a different timing budget.

Full format and usage: [emulator/README.md](emulator/README.md).

## Protocol-v2 verification

```sh
python -m pytest testbench/app -q
python testbench/app/run_resync_tests.py
python testbench/app/run_watchdog_tests.py
python testbench/app/run_tests.py --no-vcd
```

Both tops are tested for every dropped body-byte position, inserted bytes, noise,
shared/missing delimiters, invalid/dangling escapes, partial timeout and late tail,
escaped measurement/sequence bytes, sequence wraparound, duplicate recovery, and
fault latching after communication recovers. The existing charging, grid hold,
emergency-stop, and organiser peripheral tests are also rerun.

Protocol-v2 validation completed successfully:

- **78 Python tests passed**, including exact partial-timeout boundaries, sequence
  window limits, sender restart, and nominal 50 ms emulator pacing.
- **44/44 UART recovery RTL runs passed** (22 cases on each top).
- **14/14 watchdog RTL runs passed** with the new protocol.
- **30/30 full application regression runs behaved as expected**, including the
  two deliberately failing H1 harness checks. These used unpadded v2 packets.
- **4/4 additional padded-command runs passed**: S1X streaming and S3 recovery on
  each top, verifying the final emulator word-packing change.
- **Timer unit, 5/5 UART, and 5/5 GPIO regression runs passed.**
- Canonical timer, decoder, and ROM modules match both flattened designs.

Detailed result summary and source hashes:
[resync_validation.log](testbench/app/evidence/resync_validation.log).
The focused partial-timeout cases accelerate the divider 100x; the unit test
checks the production 20 MHz divider. UART byte timing is unchanged.
As with improvement 1, these are simulation results; no FPGA programming or
physical implementation verification is claimed.


Emulator word packing appends up to three harmless `0x7E` end markers so each
write uses `-t4`. For the nominal frame this reduces four host writes to three,
leaving more margin below the meter watchdog when one frame is corrupted. The
plain hex encoder still emits the canonical 11-byte nominal frame. A Python
regression checks nominal good/bad/good frames with 50 ms host access delays.
