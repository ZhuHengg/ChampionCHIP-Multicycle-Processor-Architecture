# Submission Evidence Screenshot Checklist

Use this checklist for the official GPIO/UART firmware validation and the two Gripple application demos. Keep the complete submission below **20 MB**.

All paths below are relative to the project folder:

```text
C:\Users\SHIYI\Documents\ChampionCHIP-Stage3-main\ChampionCHIP-Stage3-main
```

## 1. Prepare the evidence folders

Save the screenshots and copies of the existing logs in this structure:

```text
evidence/
  official_firmware/
    waveform.png
    pass_log.png
    sim_testbench_output.log
  demo1_normal_charging/
    waveform.png
    pass_log.png
    run.log
  demo2_grid_recovery/
    waveform.png
    restart_detail.png       (if the internal counters are available)
    pass_log.png
    run.log
```

- [ ] Use PNG screenshots with readable text.
- [ ] Keep signal names, values, and the time axis visible.
- [ ] Add captions explaining the inputs and expected response.
- [ ] Copy the actual simulation logs; do not replace them with manually typed PASS messages.
- [ ] Unless required by the submission rules, omit the large application VCD files from the submission package. Demo 1 is about 365.6 MB and Demo 2 about 685.8 MB.
- [ ] Keep the source code and test scripts needed to regenerate the waveforms.
- [ ] Check the size of the final submission package, including the report and source files.

## 2. Official firmware validation

This validates the organiser's GPIO/UART echo firmware, separate from the Gripple application.

### Open the waveform

Open this file in GTKWave:

```text
testbench/testbench.vcd
```

Select the `testbench` scope in the hierarchy. Select the following signals and click **Append**. Set the multi-bit GPIO signals to hexadecimal using **Data Format → Hex**.

| Signal | Meaning |
| --- | --- |
| `sw_p3_0` | External GPIO input nibble |
| `pins_o` | GPIO output byte |
| `pins_oe_o` | GPIO output-enable mask |
| `rx` | UART input to the processor |
| `tx` | UART output from the processor |

### Capture `waveform.png`

- [ ] Show the initial input `sw_p3_0 = A` and output `pins_o = A0`.
- [ ] Show `pins_oe_o = F0`, confirming P7–P4 are outputs.
- [ ] Show the UART RX and TX activity.
- [ ] Show the input changing to `5` and the output subsequently becoming `50`.

The firmware reads GPIO, writes the shifted value to the output, then waits for a UART byte before starting its echo and returning to the next GPIO read. Changing the GPIO input alone while it waits for UART does not advance the loop. The GPIO update can occur before UART transmission finishes.

Suggested caption:

> Official firmware validation: P3–P0 = 0xA is copied to P7–P4 (output 0xA0). Following UART input, the next loop copies input 0x5 to output 0x50. The output-enable mask is 0xF0.

### Capture `pass_log.png`

Open and screenshot the existing log:

```text
testbench/sim_testbench_output.log
```

Include all four result lines:

```text
PASS [GPIO] P3-0 = 0xa, P7-4 = 0xa (0 clocks)
PASS [UART] RX = 0x30, TX = 0x30
PASS [GPIO after UART] P3-0 = 0x5, P7-4 = 0x5 (0 clocks)
PASS: GPIO and UART firmware test completed successfully
```

- [ ] Copy this log into `evidence/official_firmware/`.
- [ ] Use the log to establish the UART byte value of `0x30`; undecoded RX/TX pulses alone do not establish the byte value.

## 3. Demo 1 — Normal charging

### Open the waveform

```text
sim/app/hdl_S1/app.vcd
```

In the `testbench` scope, append:

| Signal | Format | Meaning |
| --- | --- | --- |
| `emu_in` | Hexadecimal | Vehicle and safety input stimulus |
| `pins_o` | Hexadecimal | Controller GPIO outputs |
| `x4_dbg` | Decimal | Application state |
| `rx` | Binary | Incoming meter data |
| `tx` | Binary | Outgoing session record |

Use Zoom Fit, then adjust the zoom until the complete sequence and UART activity are readable. Loading the full VCD may take time.

### Capture `waveform.png`

- [ ] Show the following transitions and the two incoming meter frames during charging.
- [ ] Show UART TX activity after unplugging.

| Event | `emu_in` | `pins_o` | `x4_dbg` |
| --- | --- | --- | --- |
| Idle | `00` | `00` | 0 |
| Vehicle connected | `01` | `20` | 1 |
| Charging requested | `02` | `30` | 2 |
| Two valid meter frames received | `02` | `30` | 2 |
| Charging stopped | `01` | `20` | 1 |
| Vehicle unplugged | `00` | `00` | 0 |

Suggested caption:

> Demo 1: the controller progresses from IDLE to CONNECTED and CHARGING, accepts two valid meter frames, returns to CONNECTED when charging stops, and enters IDLE on unplugging before transmitting the session record.

### Capture `pass_log.png`

Open:

```text
sim/app/hdl_S1/run.log
```

- [ ] Capture the GPIO checks, UART record checks, and `SCENARIO RESULT: PASS`.
- [ ] Include the session-total check for `0x000B3B00` (736,000) if visible in the log.
- [ ] Copy this log into `evidence/demo1_normal_charging/`.

## 4. Demo 2 — Grid disturbance and staggered restart

### Open the waveform

```text
sim/app/hdl_S2/app.vcd
```

Append the same five signals used for Demo 1: `emu_in`, `pins_o`, `x4_dbg`, `rx`, and `tx`.

### Capture `waveform.png`

- [ ] Show the controller charging before the disturbance.
- [ ] Show entry into GRID_HOLD following the disturbance frame.
- [ ] Show the controller remaining in GRID_HOLD while receiving subsequent frames.
- [ ] Show the return to CHARGING after the required healthy frames.

| State | `pins_o` | `x4_dbg` |
| --- | --- | --- |
| CHARGING | `30` | 2 |
| GRID_HOLD | `60` | 3 |
| CHARGING after recovery | `30` | 2 |

The S2 test sequence sends a 49.20 Hz disturbance frame, a still-unhealthy 49.40 Hz frame, and then healthy frames. These values come from `testbench/app/scenarios.py`; plain UART traces require decoding to display those values directly.

Suggested caption:

> Demo 2: the under-frequency frame causes CHARGING → GRID_HOLD, changing GPIO output from 0x30 to 0x60. After the required consecutive healthy frames, the controller resumes CHARGING and restores output 0x30.

### Optional `restart_detail.png`

Expand `testbench → dut` and locate the register-file instance. Signal names depend on how the register file is exposed in GTKWave.

- [ ] If available, append register **x23 / s7**, the healthy-frame counter, and **x24 / s8**, the calculated restart delay. Display them in decimal.
- [ ] Keep `x4_dbg`, `pins_o`, and `rx` visible alongside the counters.
- [ ] Capture the counter reaching the calculated delay and the transition back to CHARGING.

For the report's S2 sequence, the expected delay is three healthy frames. Verify the displayed value against the actual waveform before labelling the screenshot. The unhealthy frame keeps or resets the counter to zero; S2 does not demonstrate a nonzero counter being reset because no healthy recovery frame precedes that unhealthy frame.

This single-controller waveform demonstrates the calculated restart delay. It does not by itself demonstrate the fleet-wide peak-power reduction.

### Capture `pass_log.png`

Open:

```text
sim/app/hdl_S2/run.log
```

- [ ] Capture the checks for GPIO outputs `0x30`, `0x60`, and the return to `0x30`.
- [ ] Include the UART record checks and `SCENARIO RESULT: PASS`.
- [ ] Copy this log into `evidence/demo2_grid_recovery/`.

## 5. Final submission check

- [ ] Official validation has a GPIO/UART waveform screenshot and PASS log.
- [ ] Demo 1 has a normal-charging waveform screenshot and PASS log.
- [ ] Demo 2 has a grid-hold/recovery waveform screenshot and PASS log.
- [ ] Screenshot captions agree with the actual traces and logs.
- [ ] The report points to the correct evidence filenames.
- [ ] The submitted package is below 20 MB.

A `.gtkw` file saves signal selections and viewing settings; it does not contain the waveform data. It is useful locally but cannot replace the VCD when a judge needs to open an interactive waveform. PNGs plus the text logs provide compact static evidence.
