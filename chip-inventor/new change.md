# New change: investigating the extra AWS session report

Date: 11 October 2026

## Completed: rebuild and pass the full simulation gate

**Status: DONE — local simulation validation completed.**

- Rebuilt the firmware and synchronized both instruction ROMs.
- Regenerated all four AWS processor images.
- Passed 102 Python tests, the timer/MMIO unit test, 14 watchdog RTL tests,
  and 44 UART recovery RTL tests.
- Completed all 30 AWS simulation runs at 250 MHz and 50 MHz with the default
  50 ms AXI-access pacing and corrected `0xF0` startup direction. Every run
  behaved as expected, including the report-count checks.

`PASS 50MHz H1: expected-FAIL` is a successful test of the test harness.
H1 deliberately expects GPIO output `0xB0` when the correct value is `0xA0`.
Detecting that intentional mismatch is the expected result, not a processor
failure. The same applies to H1 at 250 MHz.

Evidence: [stage4_timing_validation.log](testbench/app/evidence/stage4_timing_validation.log).

**Next outstanding step:** apply and rebuild the real host emulator's `0xF0`
initialization change, then perform AWS synthesis, timing checks, and physical
FPGA validation. Completion above refers to local simulation, not deployment.

## Completed change: allow for stock emulator pacing

The startup investigation below is retained as a record of the first change.
The subsequent handoff task changes the demonstration firmware's deadlines:

| Setting | Previous | New |
|---|---|---|
| UART partial-frame timeout | 100 ms | 400 ms |
| Accepted-meter-data watchdog | 500 ms | 4000 ms (4 seconds) |

Each host-transmitted byte requires an AXI write and a done-poll read, each with
about 50 ms delay. A padded 12-byte nominal frame therefore takes about 1.2 s.
Replaying the existing scenarios gives a longest meter-age gap of approximately
2.5 s (a rejected frame between accepted frames). Four seconds gives these
demonstrations margin; 400 ms allows margin over the approximately 100 ms byte
gap. These are demonstration defaults, not a guarantee for arbitrary host stalls,
maximum-length escaped traffic, or a production charging-system specification.

The watchdog still applies in CONNECTED, CHARGING, and GRID_HOLD. It still opens
the contactor, latches METER_TIMEOUT, and reports once. The tradeoff is that loss
of meter data now takes up to four seconds to trigger the watchdog instead of
half a second. Two consecutive rejected frames still latch FAULT independently.

Changes include firmware constants, the Python model, exact-boundary tests,
per-byte host-pacing tests, the frontend model/demo text, and current documentation.
The firmware was rebuilt to 372 instructions, both Stage 3 ROMs were synchronized,
and all four AWS images were regenerated. Generated files were not hand-edited.

The earlier pacing regression incorrectly delayed per command-line word instead
of per byte. It now accounts for every byte's write and poll. Added tests replay
all twelve application scenarios at 50 ms and 60 ms per access (20% extra delay).
All 102 Python tests pass. A direct execution of the frontend TypeScript model
checks the 3999/4000 ms boundary and constructs all thirteen frontend scenarios.
This is not a full frontend build.

Validation also passed the timer/MMIO unit test, all 14 watchdog RTL cases,
all 44 UART recovery RTL cases, and **30/30 AWS runs as expected** at both
clock speeds with stock host pacing and corrected startup direction. This includes
intentional H1 harness failures being detected correctly. See
`testbench/app/evidence/stage4_timing_validation.log` and the handoff follow-up.
The AWS test must include `--init-direction 0xF0`, since the host startup fix
remains necessary:

```powershell
python aws/run_aws_tests.py --clk all --init-direction 0xF0 --tag timing_fixed -j 8
```

This uses the default 50 ms per AXI access and time scale 100. The timing scale
compresses both host waits and millisecond timers; UART bit timing stays intact.
Applying the startup direction change to the deployed host, AWS synthesis,
timing closure, and physical FPGA validation remain outstanding.

---

The remaining sections describe the earlier startup-only investigation, before
the timeout changes above.

## Current status

The cause of the extra report was identified in simulation. Configuring the
host's initial GPIO direction as `0xF0` instead of `0x01` makes scenario S6 pass
at both 250 MHz and 50 MHz, with exactly one eight-byte report.

The local changes add diagnostics and a configurable host-initialization setting
to the simulation. They **do not change the processor firmware, generated FPGA
images, organiser's `top.sv`, or the emulator deployed on AWS**. The actual host
emulator still needs the corresponding source change and rebuild.

## What the simulation does

`aws/tb/tb_aws.sv` runs a virtual processor and AWS wrapper on the computer. It
executes the EV-charger firmware and mimics the host's AXI register accesses.
It does not upload anything to AWS or a physical FPGA.

Scenario S6 performs this sequence:

1. Reset and initialize the processor.
2. Set the control pilot to request charging.
3. Send one healthy meter frame; the processor starts charging.
4. Unplug the simulated car; the processor opens the contactor and returns to IDLE.
5. Read one eight-byte session report.

The report contains four energy bytes, one state/flags byte, one accepted-frame
count byte, and two CRC bytes. The simulation takes time because it computes
the circuit's behavior clock cycle by clock cycle.

## What went wrong

The original trace showed two reports, but the extra report came **before** the
intended charging session, not after it:

| Approximate trace time | Report bytes | Meaning |
|---|---|---|
| 35–41 ms | `00 00 00 00 00 00 10 0E` | Empty session: zero energy, zero frames, IDLE |
| 185–191 ms | `80 9D 05 00 00 01 A4 71` | Expected report after charging and unplugging |

Times above are from the 250 MHz fast-host trace. The 50 MHz trace ends each
report about one displayed millisecond later.

All expected GPIO and report-value checks passed, but the final testbench check
found 16 received bytes instead of eight. The AWS wrapper's receive buffer holds
only eight bytes and wraps around, so the valid report replaced the earlier
empty report. That explains why the expected data could still be read correctly.

## Why `0x01` and `0xF0` matter

These hexadecimal values configure the AWS wrapper's GPIO direction register.
For each bit in this register:

- **0:** the host drives the pin, providing an input to the processor.
- **1:** the host releases the pin, allowing the processor to drive an output.

| Value | Binary, pins 7 through 0 | Host behavior |
|---|---|---|
| `0x01` | `0000 0001` | Releases pin 0; drives pins 1–7 |
| `0xF0` | `1111 0000` | Releases pins 4–7; drives pins 0–3 |

The charger uses pins 0–3 for control-pilot and emergency-stop inputs, and pins
4–7 for lock, contactor, and status outputs. Its processor GPIO direction is
already `0xF0`, where a processor direction bit of 1 enables its output driver.
The matching host setting is therefore also `0xF0`: the host drives the lower
four pins and releases the upper four.

The stock emulator's initialization uses `0x01` before releasing processor reset.
This leaves pin 0 released by both sides. Its simulated value is high impedance
(`Z`), not a defined zero or one. Startup tracing showed:

1. At approximately 25 ms, direction is `0x01` and the processor enters CONNECTED
   while the pad bus contains undefined/high-impedance values.
2. At approximately 35 ms, the later `-d 0xF0` command supplies defined zero pilot
   inputs.
3. The processor interprets this as an unplug, returns to IDLE, and sends the
   empty report.

This is a simulated false session caused by startup pin configuration. It is
not evidence of a real car connection, and the exact behavior of floating
inputs on physical hardware has not been validated.

## Files changed locally

| File | Change |
|---|---|
| `aws/tb/tb_aws.sv` | Added configurable `INIT_DIRECTION` and startup state/direction/pad tracing under `TRACE_RX` |
| `aws/run_aws_tests.py` | Added `--trace-rx` and `--init-direction` options, including byte-range validation |
| `aws/README.md` | Documented the startup cause, comparison commands, and required host change |
| `HANDOFF_STAGE4_AWS_FPGA.md` | Added findings and validation results ahead of the historical handoff |
| `new change.md` | This explanation |

The default initial direction remains `0x01` so that the stock emulator's
behavior and failure can still be reproduced. Passing `--init-direction 0xF0`
models the corrected host initialization; it does not patch an external emulator.

No timeout values or report-count checks were weakened to make the test pass.

## Validation results

S6 was run with 5 ms per AXI access and time scale 10:

| Initial direction | 250 MHz | 50 MHz |
|---|---|---|
| Stock `0x01` | FAIL: 16 report bytes | FAIL: 16 report bytes |
| Corrected `0xF0` | PASS: exactly 8 report bytes | PASS: exactly 8 report bytes |

Evidence is saved in these ignored simulation-output directories:

- `sim/aws/startup_stock_250mhz_S6/run.log`
- `sim/aws/startup_stock_50mhz_S6/run.log`
- `sim/aws/startup_fixed_250mhz_S6/run.log`
- `sim/aws/startup_fixed_50mhz_S6/run.log`

The Python runner also passed a syntax-compilation check, and `git diff --check`
reported no whitespace errors before this note was added. This investigation
did not rerun the full scenario suite or perform hardware validation.

## How to reproduce on this Windows computer

Icarus Verilog is installed in a custom directory. Add it to the current
PowerShell session's PATH, then enter the project directory:

```powershell
$env:Path = "C:\Users\SHIYI\.cache\championchip-tools\iverilog\bin;$env:Path"
cd C:\Users\SHIYI\Downloads\ChampionCHIP-Stage3-main\ChampionCHIP-latest\chip-inventor
```

Reproduce the original startup failure:

```powershell
python aws/run_aws_tests.py --scenario S6 --clk all --axi-delay-ms 5 --time-scale 10 --trace-rx --tag startup_stock
```

Test the corrected startup:

```powershell
python aws/run_aws_tests.py --scenario S6 --clk all --axi-delay-ms 5 --time-scale 10 --trace-rx --init-direction 0xF0 --tag startup_fixed
```

The runner compiles and runs the testbench, then saves traces to `run.log` in the
directories listed above. It may be quiet for several minutes because it captures
the simulator's output until the run completes. The corrected run should finish
with both S6 results passing and `2/2 runs as expected`.

For manual compilation, `-DTRACE_RX` enables the trace and
`-DINIT_DIRECTION=240` selects `0xF0` (240 decimal).

## What still needs to be done

### Apply the initialization fix to the real host emulator

Locate the direction setup in the host emulator's `fpga_init` and change its
initial direction value from `0x01` to `0xF0` for this charger application,
before releasing processor reset. Rebuild the emulator and verify the actual
host behavior. The emulator C source is not present in this checkout, so this
deployment change has not been applied here.

Adding `-d 0xF0` to the command line alone is insufficient: that option executes
after initialization, when the false session has already begun. Do not hide the
problem by discarding the first report or forcing unknown simulation inputs to zero.

### Resolve the separate real-host timing problem

The successful tests above deliberately use the fast host configuration.
The stock host uses about 50 ms per AXI access, or about 100 ms per transmitted
byte and 1.2 seconds for a padded meter frame. Current firmware allows only
100 ms between bytes and 500 ms without an accepted meter frame.

The GPIO fix does not resolve that mismatch. Choose and validate an appropriate
timeout policy, update firmware/model/tests together if needed, regenerate the
FPGA images, and run the full suite at real host pacing. AWS synthesis, timing
checks, and physical FPGA testing are still separate remaining steps.
