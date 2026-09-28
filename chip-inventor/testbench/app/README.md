# Application testbench — `./emu` model against our RTL

Each test here is one `./emu` command, played against the RTL by a Verilog
model of the emulator and the AWS FPGA wrapper. The `emu_d / emu_i / emu_o /
emu_t / emu_r` tasks mirror the emulator options 1:1, so **a passing simulation
is a passing `./emu` command** — and the same command lines, exported to
`chip-inventor/emulator/emu_commands.txt`, should run unchanged on the FPGA.

## Files

| File | Role |
|---|---|
| `golden.py` | the golden model: frame/record formats, CRC chain, FSM (spec §7.4–7.6) |
| `test_golden.py` | pytest for the model |
| `scenarios.py` | scenario DSL, harness scenarios H0–H2, application scenarios S1–S11 + S1X; exports `emu_commands.txt` |
| `test_scenarios.py` | pytest for the scenario set |
| `tb_app.v` | the emulator + wrapper model |
| `run_tests.py` | builds and runs every top × scenario |

The golden model is the single source of truth: every expected `-o` and `-r`
value is computed by it, never written by hand, so the scenarios cannot drift
from the specification.

## What the testbench models

Taken from `external/CCX_Malaysia_Edition_Stage_3/RVBL-Emulator/src/emu.c`
(read in full) and its `README.md`:

- **A reset at the start of every command**, with the **GPIO input value
  persisting across it** — `-d` is a read-modify-write of the direction byte
  only, so the input byte keeps its previous value. `PRESET_IN` models this.
- **`-d` bit semantics**: 0 = the emulator drives the pin, 1 = it releases the
  line and observes the processor output. Driving a line the chip also drives is
  reported as `[tb] FAIL contention`.
- **Options strictly in order, first mismatch aborting the rest** (emu.c's
  `goto main_end`).
- **An 8-byte reply window read through a running pointer.** A 9th transmitted
  byte fails the run, as does an `-r` that would read past byte 8 (emu.c's
  `fpga_read_uart` returns 1 there).
- **`-t` sends multi-byte values low byte first.**
- **A 50 ms AXI delay per access**, scaled down to `EMU_GAP` cycles.
- **emu.c's own log text**, so a simulation log reads like a real `./emu` run.

Beyond the emulator, the testbench also checks what the FPGA cannot: `x4_dbg_o`
must equal the expected application state at every `-o` (the firmware keeps the
state code in `tp`/`x4`), `halt_o` must never assert, and every byte the
firmware transmits must be read by some `-r`.

## Running

```bash
# everything: 3 tops x 15 scenarios
python chip-inventor/testbench/app/run_tests.py

# filter by scenario and/or top
python chip-inventor/testbench/app/run_tests.py --scenario S2 --top rtl/top.v

# the Python side
python -m pytest chip-inventor/testbench/app -q
```

Builds land in `chip-inventor/sim/app/<toptag>_<scenario>/` (gitignored), each
with the generated `scenario.vh`, the compiled `app.vvp`, `run.log` and
`app.vcd` for GTKWave.

`run_tests.py` exits non-zero if any run does not come out as expected. An
`expect_fail` scenario (H1) is *expected* to fail — it must produce exactly one
`[error]` and no `[tb] FAIL`.

### Timing knobs

| Define | Default | Meaning |
|---|---|---|
| `EMU_GAP` | 20000 cycles | gap before each option; a scaled-down 50 ms, deliberately ≥ one record's TX time (8 × 1740 = 13,920 cycles) so ordering matches the real emulator |
| `EMU_T_GAP` | `EMU_GAP` | gap before each `-t` |
| `EMU_BYTE_GAP` | 2000 cycles | gap between bytes inside one `-t` |
| `PRESET_IN` | 0 | GPIO input value already present at boot |
| `FIRMWARE_SEL` | 5 | imem program (4 = organiser's, 5 = our application) |
| `IMEM_INST` | `blk3564_70` | imem instance name; `run_tests.py` sets it per top |

A scenario with `stream=True` (S1X) is compiled with `EMU_T_GAP=0
EMU_BYTE_GAP=0`, so its frames arrive with no gap at all — that is the test of
the one-byte-time (1740-cycle) end-of-frame budget.

## Reading the log

```
[ok] RISC-V started!                        reset released
[ok] Written 0x000000f0 to DIRECTION        -d
[ok] Written 0x00000002 to INPUT PINS       -i
[ok] Read 0x00000030 from OUTPUT PINS       -o matched
[ok] Written 0x00a008fc to UART RX          -t4
[ok] Read 0x000b3b00 from UART TX           -r4 matched
SCENARIO RESULT: PASS
```

`[error] …` lines are the emulator's own mismatch messages; `[tb] FAIL …` lines
are checks the real emulator cannot make (x4, halt, contention, unread bytes).
After the first `[error]`, every later option is skipped — exactly as `./emu`
behaves.

## Harness scenarios

H0–H2 run the **organiser's** firmware (`FIRMWARE 4`), not ours. They validate
the testbench itself before it is trusted to judge our application:

- **H0** — their GPIO/UART echo through the emulator model. Note the order: the
  organiser firmware re-reads GPIO only after a UART echo completes, so the
  `-o` has to come after the `-r`.
- **H1** — the same run with a deliberately wrong `-o`. Proves the harness
  reports exactly one `[error]` and skips the rest.
- **H2** — `RVBL-Emulator/README.md`'s own example, verbatim:

  ```shell
  ./emu -d 0xF0 -i 0x02 -o 0x20 -t1 0x30 -r1 0x30
  ```

  This expects `-o 0x20` immediately after `-i 0x02`, but their firmware reads
  GPIO once and then blocks on UART — it cannot see an input that arrives after
  boot. **It passes only because the emulator's `IN` register still holds
  `0x02` from a previous run**, which is why the scenario sets
  `PRESET_IN=0x02`. Our own firmware polls its inputs continuously, so for us
  `-i` and `-o` work in any order.
