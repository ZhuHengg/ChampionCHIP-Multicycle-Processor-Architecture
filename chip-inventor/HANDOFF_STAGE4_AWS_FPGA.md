# Handoff: Stage 4 AWS FPGA integration

## Follow-up: stock-host timeout configuration (2026-10-11)

Implemented the original handoff's Option A for the demonstration firmware:
`RX_TIMEOUT_MS = 400` and `METER_TIMEOUT_MS = 4000`. No state-machine or latch
semantics changed. Loss of meter data now takes four seconds to trip instead
of half a second; these are host-paced demonstration limits, not production
charger requirements.

The emulator takes two delayed AXI accesses per transmitted byte. A nominal
padded frame takes about 1.2 s; the existing recovery scenarios reach about
2.5 s between accepted frames. The previous Python pacing test incorrectly
charged one delay per word and has been corrected. New model regressions replay
all application scenarios at 50 ms and 60 ms per access.

Firmware, Python model and boundary tests, frontend timeout behavior/text,
documentation, both Stage 3 ROMs, and all AWS images are synchronized. Firmware
now occupies 372 instruction words. See `new change.md` for the detailed record.

**Validation complete for this local timing change:**

- 102 Python tests pass, including per-byte host timing at 50 ms and 60 ms.
- Timer/MMIO unit test, 14/14 watchdog RTL cases, and 44/44 UART recovery RTL
  cases pass on the two Stage 3 designs.
- **30/30 AWS runs behave as expected** at stock 50 ms per AXI access, time scale
  100, both core clocks, and the corrected host initialization (`0xF0`). The two
  H1 negative harness cases correctly fail their intentional output check.
- Direct frontend-model execution passes the 3999/4000 ms boundary and constructs
  all 13 scenarios. A full frontend build has not been run.
- AWS image generation is deterministic.

Evidence summary: `testbench/app/evidence/stage4_timing_validation.log`.
Per-scenario logs: `sim/aws/timing_fixed_{250,50}mhz_<scenario>/run.log`.
The last 250 MHz S2 run completed successfully; its long runtime was computation,
not a stall. The local timeout mismatch is resolved for this tested configuration;
physical FPGA behavior and unbounded host delays remain unverified.

Run the real-pacing gate from the repository root:

```sh
python chip-inventor/aws/run_aws_tests.py --clk all --init-direction 0xF0 --tag timing_fixed -j 8
```

On this Windows machine the full run takes substantially longer than the
historical 15-minute estimate below. S2 sends 156 bytes over 13 frames and is
the longest case. The runner captures each simulator's output until it exits,
so a quiet terminal does not by itself indicate a hang.

The `0xF0` initialization models a necessary host fix; it does not modify the
emulator deployed on AWS. That source is absent from this checkout. After
simulation validation, the next steps are to apply/rebuild that host change,
synthesize on AWS, inspect WNS, and run the hardware scenarios with saved logs.

---

## Follow-up: startup report investigation (2026-10-11)

The historical Blocker 2 diagnosis below has been narrowed down with S6 tracing.
The extra report is an **empty report before the requested session**, not a
second report after it. Stock host initialization sets direction to `0x01`,
leaving pilot bit 0 undriven. The simulation enters CONNECTED; the subsequent
`-d 0xF0` supplies zero pilot inputs, causing an unplug report.

Configure the application host's initial direction as `0xF0` before releasing
processor reset. The host emulator source is absent from this checkout; apply
this change to its `fpga_init` direction setup and rebuild it on the host.
The local runner now exposes `--init-direction 0xF0` to model that change and
`--trace-rx` to log the evidence. Its default stays `0x01` so stock-host failures
remain reproducible. See `aws/README.md` for the comparison commands.

Verified S6 at both 250 MHz and 50 MHz with 5 ms AXI pacing and time scale 10:
stock initialization fails with 16 report bytes at both clocks; `0xF0`
initialization passes with exactly eight bytes at both clocks. Logs are under
`sim/aws/startup_stock_{250,50}mhz_S6/` and
`sim/aws/startup_fixed_{250,50}mhz_S6/` (ignored build output).

This does not resolve Blocker 1 (real host pacing versus firmware timeouts).
The original handoff below is historical; its claim that AWS files are
uncommitted is also outdated, since they were pulled in commit `a295f74`.

---

**Date:** 2026-10-11 | **State:** integration built and verified in simulation;
application **not yet ready** for FPGA (see Blocker 1). Nothing is committed yet.

## TL;DR

- **Built:** everything needed to upload the processor to the ChipInventor AWS FPGA area.
  It lives in [`aws/`](aws/). Upload procedure: [`aws/README.md`](aws/README.md).
- **The integration works in simulation.** The organiser's own `top.sv`, unmodified,
  plus our generated `riscv.sv` passes the organiser test-firmware scenarios at 250 MHz
  and 50 MHz. That covers AXI registers, reset, GPIO, both UART directions and PC readback.
- **Blocker 1: our EV-charger firmware fails at real `./emu` speed.** Every app scenario
  latches FAULT before charging starts. Cause: the firmware timeouts (100 ms byte gap,
  500 ms meter watchdog) are shorter than real `./emu` pacing (~100 ms per byte,
  ~1.2 s per meter frame). This needs a **team decision** before anyone changes firmware.
- **Blocker 2 (unexplained):** with a faster host, every `./emu` step passes, but most
  scenarios then transmit a second 8-byte report. Root cause not found yet.
- **Not done yet:** no AWS synthesis run, so timing (WNS) and Vivado elaboration are unverified.

---

## 1. What Stage 4 is

Run our Stage 3 SoC on a real Xilinx FPGA through ChipInventor's **AWS FPGA** area.

Sources:
- `docs/AWS Guide.pdf`: GUI walkthrough slides.
- The organiser's repo
  [CCX_Malaysia_Edition_Stage_4](https://github.com/championchip-experience-community/CCX_Malaysia_Edition_Stage_4):
  `README.md` and `src/top.sv`. The repo is not vendored; `aws/top.sv` is a verbatim copy
  of commit `b748304`.

Contract from the organiser README:
- **Upload** `top.sv` (theirs) and `riscv.sv` (ours, the whole processor in one file).
  `cl_ports.vh` is provided by AWS; never edit it.
- **`top.sv` edits:** only the `RISCV riscvtop(...)` instance and the `3'b111` PC
  readback line may be changed. Our build needs **neither**.
- **`riscv.sv` contents:** it must also define `Transmitter` and `Receiver`, because
  `top.sv` instantiates them.
- **Clock:** `clk_main_a0` = **250 MHz**. top.sv's UART uses `p_CLKS_PER_BIT = 2170`
  (115200 baud).
- **Host register map (OCL AXI-Lite):**

  | Address | Register |
  |---|---|
  | 0x00 | reset |
  | 0x04 | IN + direction |
  | 0x08 | OUT |
  | 0x0C | TX |
  | 0x10 / 0x14 | 8-byte RX window |
  | 0x18 | RX count |
  | 0x1C | PC |

## 2. What was built (all under `chip-inventor/aws/`, uncommitted)

| File | Purpose |
|---|---|
| `gen_riscv_sv.py` | Generates `riscv.sv` from `rtl/top.v` (the file all Stage 3 tests ran on) |
| `riscv.sv` | **Primary upload**: FIRMWARE 5 (EV charger), core at 250 MHz |
| `variants/riscv_fw5_50mhz.sv` | Fallback if 250 MHz fails timing (core at 50 MHz via `BUFGCE_DIV`) |
| `variants/riscv_fw4_250mhz.sv`, `riscv_fw4_50mhz.sv` | Bring-up images with the organiser's test firmware |
| `top.sv` | Organiser's wrapper, unchanged |
| `sim/stubs/` | **Simulation-only** stand-ins for AWS files (`cl_ports.vh`, `sh_ddr`, `BUFGCE_DIV`). Never upload. |
| `tb/tb_aws.sv` | System testbench: real `top.sv` + `riscv.sv`, host side copies `emu.c` call for call |
| `run_aws_tests.py` | Runs every Stage 3 scenario through `tb_aws.sv` |
| `README.md` | Upload/run procedure and assumptions |

Also changed: `.gitignore` now ignores `chip-inventor/sim/aws/`.

### What the generator changes (and nothing else)

The diff against `rtl/top.v` was checked line by line; only these differences exist.

1. **SoC module renamed** `top` to `rvbl2_soc`. AWS's wrapper is also named `top`, so
   two modules would collide.
2. **Every other module prefixed** with `rvbl2_` (`uart`, `gpio`, `imem`, …) to avoid
   clashes with AWS HDK files.
3. **imem `FIRMWARE` default set to 5.** The repo default is 0, the *Stage 2* ROM. The
   SoC instantiates imem without a parameter, so the default is what gets synthesised.
4. **`wire [31:0] w_PC_Output = pc_dbg_o;` added** inside the SoC, so top.sv's
   hard-coded `riscvtop.e_PROCESSOR.w_PC_Output` works without edits.
5. **Adapters appended:**
   - `RISCV`, with the reference processor's exact ports (`i_Clk`, `i_nRst`,
     `i_Rx_Serial`, `o_Tx_Serial`, inout `io_Pins`). It inverts reset, drives the
     tristate pads, and sets `CLK_HZ = 250e6` (or 50e6).
   - `Transmitter` / `Receiver`: thin wrappers on our `uart_tx` / `uart_rx`.
6. **Core macros `undef`'d** at the end of the file.

Rerun `python chip-inventor/aws/gen_riscv_sv.py` after **any** `rtl/` or firmware
change. Output is deterministic (verified). Never hand-edit a generated `.sv`.

The 50 MHz images keep the baud rate exact: 2170 = 5 × 434, so our UART at 50 MHz
counts 434 clocks per bit and top.sv's counts 2170 at 250 MHz.

## 3. How to test

```bash
python chip-inventor/aws/run_aws_tests.py                       # 250 MHz, real 50 ms emu pacing
python chip-inventor/aws/run_aws_tests.py --clk all -j 12       # both clocks
python chip-inventor/aws/run_aws_tests.py --scenario S1 --axi-delay-ms 5 --time-scale 10 --tag fasthost
```

How `tb_aws.sv` copies `./emu` (from `external/.../RVBL-Emulator/src/emu.c`):
- **Delay:** 50 ms `usleep` before **every** AXI access.
- **Init:** `fpga_init` writes direction 0x01, then reset 1, 0, 1.
- **IN register:** `-i`/`-d` are read-modify-write.
- **UART send:** each `-t` byte is a write followed by a done-poll read, so ~100 ms per byte.
- **UART receive:** `-r` reads the 64-bit window through a static pointer.
- **Errors:** the first `[error]` stops the run.

Simulated time is compressed (`--time-scale`, default 100×) for **both** the host delay
and the firmware's millisecond timer, so timeouts keep their real ratio to host pacing.
UART bit timing is not compressed.

Runtime: about 2 min for a short scenario, up to about 15 min for the full set with `-j 12`.
Logs are in `chip-inventor/sim/aws/<tag>_<clk>_<scenario>/run.log`.

## 4. Results

### 4a. Real pacing (50 ms per AXI access, as `./emu` ships): 6/30 as expected

| Scenario | 250 MHz | 50 MHz |
|---|---|---|
| H0 organiser echo | PASS | PASS |
| H1 harness catches mismatch (expected FAIL) | as expected | as expected |
| H2 organiser README example | PASS | PASS |
| S1–S7, S1X, S10, S11 | FAIL: `-o` expected 0x30, got **0x80** (FAULT) | same |
| S8 | FAIL: state 5 (METER_TIMEOUT), expected 4 | same |
| S9 | FAIL: 16 bytes transmitted | same |

### 4b. Control run (fast host: 5 ms per access, scale 10×): 8/30 as expected

| Scenario | 250 MHz | 50 MHz |
|---|---|---|
| H0, H1, H2 | as expected | as expected |
| S11 | **PASS** | **PASS** |
| S1, S1X, S3–S10 | every `./emu` step `[ok]`, then `[tb] FAIL 16 bytes transmitted; top.sv keeps only 8` | same (S2 too) |
| S2 | no result (run stopped at session end) | 16-byte FAIL |

What the two runs prove:

- **Integration is correct.** The organiser firmware passes at both clocks. With a fast
  host, every app `-o` and `-r` value matches the Stage 3 golden model through the real
  `top.sv`.
- **Both core clocks behave identically.** The `BUFGCE_DIV` 50 MHz path works in simulation.

## 5. Open issues

### Blocker 1: firmware timeouts shorter than real `./emu` pacing (decision needed)

Real `./emu` costs, from `emu.c`:

| Operation | Approximate time |
|---|---|
| Each AXI access | ≥ 50 ms |
| `-i` / `-d` | ~100 ms |
| `-o` | ~50 ms |
| Each `-t` byte | ~100 ms |
| One meter frame (3 × `-t4` = 12 bytes) | **~1.2 s** |

Firmware constants in `firmware/src/main.s`:
- `RX_TIMEOUT_MS = 100`: discards a partial frame when no byte arrives for 100 ms. The real byte gap is ≈ 100 ms plus OS overshoot, so this is borderline.
- `METER_TIMEOUT_MS = 500`: armed in **every non-IDLE state, including CONNECTED**
  (`check_meter_timeout`). It fires during the first frame (1.2 s).

Stage 3 simulation used ~1 ms gaps (`tb_app.v` `EMU_GAP`), so this never showed up.
`improvement made.md` already noted "actual hardware pacing still needs checking".

Options:
- **A (recommended): resize the constants for real `./emu` pacing.** For example
  `RX_TIMEOUT_MS` about 400 and `METER_TIMEOUT_MS` about 3000–4000. The exact values
  should come from the worst gap between accepted frames in S2/S3 (bad frames between
  good ones mean about 2 frame times between accepted ones). Change the firmware,
  `golden.py`, `scenarios.py` and the watchdog/resync boundary tests together, as the
  Stage 3 doc requires.
  Side effect: demonstrating the watchdog on the FPGA then needs many `-o` options in
  one `./emu` call, about 60–80 at 50 ms each, because `./emu` has no sleep option.
- **B: change watchdog semantics**, for example arm it only in CHARGING / GRID_HOLD.
  This is a bigger application change and also needs a spec update.

After the change: rebuild the firmware, run `testbench/gen_imem.py`, run
`aws/gen_riscv_sv.py`, then `run_aws_tests.py --clk all` at **real pacing**. That last
run is the gate.

### Blocker 2: extra 8-byte report in the fast-host control run (unexplained)

With a fast host, the app scenarios that end a session pass every `./emu` step but
transmit **16 bytes instead of 8**. The first 8 bytes match the expected report, since
the `-r` checks pass. S11 does not end with a report and passes. The Stage 3 `tb_app.v`
checks the same rule and passes, so the trigger is something that differs here:
- host pacing and the order of IN register updates (read-modify-write via AXI);
- the timer scale (1 ms = 25 000 cycles at scale 10);
- or a testbench artefact.

On the FPGA this matters: top.sv's RX window holds only 8 bytes, so a 9th byte
overwrites byte 0.

Next step: `tb_aws.sv` has a `TRACE_RX` define that prints every byte the core sends,
with the time, state (x4) and pins. Run:

```bash
cd chip-inventor
W=sim/aws/trace_S6; mkdir -p $W
python -c "import sys; sys.path.insert(0,'testbench/app'); from scenarios import SCENARIOS; open('$W/scenario.vh','w').write(SCENARIOS['S6'].to_vh())"
iverilog -g2012 -s tb_aws -I $W -I aws/sim/stubs -DTRACE_RX -DCORE_DIV=1 -DAXI_DELAY_MS=5 -DTIME_SCALE=10 \
  -o $W/a.vvp aws/sim/stubs/BUFGCE_DIV.v aws/sim/stubs/sh_ddr.sv aws/top.sv aws/riscv.sv aws/tb/tb_aws.sv
vvp $W/a.vvp
```

Check when the second record is sent and in which state. Then decide whether it's a
firmware path (for example a second `send_record`) or a testbench artefact. Investigate
this **before** or together with Blocker 1, because the Blocker 1 fix changes the same
timing.

### Open: never synthesised in Vivado
- **Timing at 250 MHz unknown.** The single-cycle 32×32 multiplier (by design, no
  MUL_WAIT) is the expected critical path; my estimate is that it needs more than the
  4 ns available. After the first AWS synthesis, search the log for `WNS`. If WNS < 0,
  upload `variants/riscv_fw5_50mhz.sv` as `riscv.sv`.
- **Vivado elaboration risks:**
  - internal tristate on `io_Pins` (same pattern as the organiser's reference design);
  - the hierarchical PC reference (also the reference's own);
  - `BUFGCE_DIV` driven from `clk_main_a0` (50 MHz images only);
  - `SYNTHESIS` macros are not used anywhere.
- One build is about 40 min of synthesis plus about 15 min until the AFI is `available`
  (from the guide's screenshots). Catch bugs in simulation first.

### Assumptions (documented in `aws/README.md`)
- **OUT bits whose direction is input** read as z from top.sv in simulation. The
  testbench reads them as 0, as on the FPGA. The organiser's example
  (`-i 0x02 … -o 0x20`) confirms this.
- **Power-on:** top.sv's `riscv_nreset` resets to 1, so the core runs from FPGA
  power-on state until the first reset. Every `./emu` call resets first.
- **Guide conflict:** AWS Guide slide 4 says to rename the instance `riscvtop`; the
  organiser README says to keep it. We keep it (the README wins).

### Unknown
- Stage 4 submission deliverables and deadline. Neither guide says what to submit
  (report, video, FPGA logs?). Ask the organisers or check the platform.

## 6. Suggested order for the next person

1. Resolve **Blocker 2** with the `TRACE_RX` run (small, and it may change the Blocker 1 fix).
2. Get the team decision on **Blocker 1** (option A or B); implement it; get the real-pacing run passing.
3. Optional low-risk first AWS build: `variants/riscv_fw4_250mhz.sv` as `riscv.sv`.
   Run the organiser example `./emu -d 0xF0 -i 0x02 -t1 0x30 -r1 0x30 -o 0x20`.
   This proves the platform flow and gives the first **WNS** reading while the
   firmware is being fixed.
4. Upload the fixed `riscv.sv` (or the 50 MHz variant, depending on WNS). Run
   `emulator/run_scenarios.sh` on the FPGA and keep the logs as evidence.
5. Commit `chip-inventor/aws/` and `.gitignore` on `main` (team rule: no feature
   branches). The stubs stay in the repo; they are for simulation only.
