# ChampionCHIP RVBL-2 — Stage 3 Submission

Multicycle RISC-V processor (RV32I + Zmmul + Xicrc) with GPIO and UART
peripherals, running a **grid-aware EV charging-station controller**
application. Built with ChipInventor, validated in simulation, targeting
Sky130 via OpenLane.

**Team:** Zhu Heng  
**Application:** IEC 61851 control-pilot FSM with autonomous grid support,
CRC-checked, sequence-numbered metering, and fleet-staggered restart.

**Meter-data watchdog update:** charging now requires a healthy initial meter
frame. A 4000 ms absence of valid frames latches METER_TIMEOUT and sends one report
after opening the contactor. See [improvement made.md](improvement%20made.md) for
configuration, report state code 5, updated hardware, and verification.

**UART protocol v2:** meter frames now use escaped `0x7E` delimiters, sequence
numbers, an independent CRC, and a 400 ms partial-frame timeout. Senders must
use the new format; see [emulator/README.md](emulator/README.md).

---

## Contents

```
rtl/                 Verilog modules, one per file
  alu_eq26.v           ALU (RV32I arithmetic/logic)
  branch_comparator_eq26.v
  control_unit_eq26.v  Multicycle FSM controller
  crc.eq26.v           CRC-16 custom instruction (Xicrc)
  mult_eq26.v          32×32 multiplier (Zmmul)
  lsu_eq26.v           Load/store unit
  regfile_eq.v         32×32 register file
  dmem_eq26.v          Data memory (32 bytes)
  imm_extend_eq26.v    Immediate generator
  address_decoder.v    Memory-mapped peripheral routing
  gpio.v               8-pin GPIO peripheral (Stage 3)
  uart.v               UART controller (Stage 3)
  uart_tx.v            UART transmitter (115200 8-N-1)
  uart_rx.v            UART receiver
  meter_timer.v        Independent meter-age and UART inter-byte timers
  imem.v               Instruction memory (ROM)
  top.v                Top-level SoC integration
  fetch_registers.v    PC and instruction registers
  ir_splitter_eq26.v   Instruction field splitter
  mux_alu_a.v          ALU operand A mux
  mux_alu_b.v          ALU operand B mux
  mux_result.v         Write-back result mux
  mux_mem_addr.v       Memory address mux
  mux_pc_next.v        Next-PC mux
  alu_out_reg.v        ALU output register
  reg32_dff_eq26.v     Generic 32-bit register

hdl.v                Flattened canvas netlist (all modules in one file)
simulate.v           ChipInventor simulation harness
config.json          OpenLane synthesis configuration
front.hex            Firmware hex image
fpga_exec.sh         FPGA execution script

firmware/            Application firmware (Stage 3)
  src/main.s           Assembly source (grid-aware EV charger)
  build/firmware.bin   Raw binary
  build/firmware.txt   Verilog ROM image
  build/firmware.dmp   Disassembly listing
  build/firmware.elf   Linked ELF
  Makefile             Build via RVBL-Firmware-Builder toolchain
  bsp/custom.ld        Linker script
  scripts/bin2rom.py   Binary-to-ROM converter

testbench/           Simulation and validation evidence
  testbench.v                  Official Stage 3 GPIO/UART firmware testbench
  run_tests.py                 Runs testbench.v against both top-level designs
  gen_imem.py                  Regenerates rtl/imem.v and syncs hdl.v, rtl/top.v
  sim_testbench_output.log     Console output (PASS)
  testbench.vcd                Full waveform dump
  full_firmware_waveform/      Waveform screenshots
  module_testbench/            Per-module directed testbenches:
    alu/                         ALU — all ops
    branch_comparator/           All 6 branch conditions
    control_unit/                15 instruction types
    crc/                         CRCB/CRCH/CRCW
    imm/                         I/S/B/U immediates
    lsu/                         SW/SB/LW/LB/LBU
    memory_mapping/              Address decoder + DMEM/IMEM
    multiplier/                  MUL/MULH/MULHSU/MULHU
    regfile/                     Read/write + x0 protection
  gpio/                Stage 3 GPIO testbench + runner
  uart/                Stage 3 UART testbench + runner
  app/                 Application testbench (emulator model)
    golden.py            Bit-exact Python golden model
    test_golden.py       pytest for golden model
    scenarios.py         12 scenarios (S1–S11, S1X) + 3 harness (H0–H2)
    test_scenarios.py    pytest for scenarios
    tb_app.v             Verilog emulator + FPGA wrapper model
    run_tests.py         Builds and runs all scenarios × all tops
    evidence/            Rebound simulation + CRC benchmark

emulator/            Emulator interface
  emu_commands.txt     Generated ./emu command lines for all scenarios
  run_scenarios.sh     Shell script to run on FPGA
  README.md

convertion/          ChipInventor converter output
  diagram.json         Block diagram source
  logs/converter.log

sim/                 Simulation scratch (gitignored)
  gpio/                GPIO simulation runs
  uart/                UART simulation runs
  system/              Full system simulation runs
  app/                 Application scenario runs
```

---

## 1. Processor Architecture

Multicycle RISC-V core with a 7-state hardware FSM
(FETCH, DECODE, EXECUTE, MEM_ACCESS_ADDR, MEM_ACCESS_DATA, WRITE_BACK, HALT).
All 47 instructions execute in 3–6 cycles.

| Extension | Instructions | Module |
|---|---|---|
| RV32I | 40 (arithmetic, logic, load, store, branch, jump, upper-imm, system) | `alu_eq26`, `branch_comparator_eq26`, `control_unit_eq26`, `lsu_eq26` |
| Zmmul | 4 (MUL, MULH, MULHSU, MULHU) | `mult_eq26` |
| Xicrc | 3 (CRCB, CRCH, CRCW) | `crc.eq26` |

Memory map:
- `0x00400000` — IMEM (instruction ROM, up to 1024 words)
- `0x10010000` — DMEM (32 bytes SRAM)
- `0xF0000000` — GPIO (DATAOUT +0, DATAIN +4, DATADIR +8)
- `0xF1000000` — UART (TXDATA +0, RXDATA +4, CONTROL +8)
- `0xF2000000` — elapsed timers (+0 meter age, +4 UART byte age; word write refreshes selected timer)

---

## 2. GPIO & UART Integration (Stage 3)

### GPIO (Block Guide §1)

Eight bidirectional pins with independent direction control. Memory-mapped
registers at `0xF0000000`. Tri-state pads are external; GPIO exposes
`pins_i`, `pins_o`, `pins_oe_o`.

- DATAOUT (+0x00): drive output pin values
- DATAIN (+0x04): read input pin levels
- DATADIR (+0x08): 0 = input, 1 = output per pin

### UART (Block Guide §2)

Full-duplex 115200 baud 8-N-1 serial controller at `0xF1000000`.
Independent TX/RX shift registers. Two-flop synchronizer on RX.

- TXDATA (+0x00): byte to transmit
- RXDATA (+0x04): received byte
- CONTROL (+0x08): TRANSMIT (bit 0, W), RXDONE (bit 1, RW), TXDONE (bit 2, R)

### Integration

Both peripherals connect through `address_decoder.v`, which routes
load/store operations based on the upper address bits. No new control-unit
states or instructions were needed — GPIO and UART are accessed with
standard `lw`/`sw` instructions to their memory-mapped addresses.

---

## 3. Official Firmware Testbench — PASS

The organiser's official GPIO/UART test firmware
([RVBL-GPIO-UART-Test-Firmware](https://github.com/championchip-experience-community/CCX_Malaysia_Edition_Stage_3/tree/main/RVBL-GPIO-UART-Test-Firmware),
FIRMWARE 4, loaded verbatim from `external/CCX_Malaysia_Edition_Stage_3/`)
is validated by `testbench/testbench.v` against the organiser's own minimum
test: P3-0 = 0xA must appear as P7-4 = 0xA (DATAOUT = 0xA0), and a byte sent
on UART RX (0x30) must be echoed back on UART TX. It is also exercised
through the application testbench's harness scenarios (H0, H2). Additionally,
dedicated GPIO and UART testbenches (`testbench/gpio/`, `testbench/uart/`)
validate each peripheral in isolation and as part of the full system.

```
PASS [GPIO] P3-0 = 0xa, P7-4 = 0xa (0 clocks)
PASS [UART] RX = 0x30, TX = 0x30
PASS [GPIO after UART] P3-0 = 0x5, P7-4 = 0x5 (0 clocks)
PASS: GPIO and UART firmware test completed successfully
```

Evidence:
- `testbench/testbench.v` — Official Stage 3 firmware testbench (FIRMWARE 4)
- `testbench/run_tests.py` — Runs it against both top-level designs (hdl.v, rtl/top.v)
- `testbench/sim_testbench_output.log` — Console output (PASS)
- `testbench/testbench.vcd` — Waveform dump
- `sim/organiser/` — Organiser firmware simulation runs (gitignored)
- `sim/gpio/` — GPIO simulation waveforms and logs
- `sim/uart/` — UART simulation waveforms and logs
- `sim/system/` — Full system simulation
- `testbench/gpio/README.md` — GPIO test details (5 simulations)
- `testbench/uart/README.md` — UART test details

---

## 4. Application — Grid-Aware EV Charging-Station Controller

### System Context

A Level 2 AC charging station that autonomously manages vehicle charging
while responding to real-time grid conditions (frequency dips, voltage sags).

### System Input

- **GPIO inputs (P0–P3):** IEC 61851 control-pilot state (3-bit code) and
  emergency-stop trip signal
- **UART input:** escaped protocol-v2 frames (11?20 wire bytes) containing a
  sequence number, voltage (0.1V), current (0.1A), frequency (0.01Hz), and CRC-16

### System Processing

1. **Control-pilot FSM** — six states (IDLE, CONNECTED, CHARGING, GRID_HOLD,
   FAULT, METER_TIMEOUT) driven by GPIO inputs, with stabilisation loop for multi-step
   transitions
2. **CRC-16 frame validation** — hardware `crcb` instruction (Xicrc) verifies
   each meter frame including its sequence; sequence checks detect gaps and reject
   recent duplicate/out-of-order frames, while delimiters recover byte alignment
3. **Grid health monitoring** — frequency and voltage thresholds trigger
   GRID_HOLD with contactor open
4. **Staggered restart** — CRC hash of charger ID produces per-charger delay
   (2–9 frames), preventing fleet-wide rebound when the grid recovers
5. **Energy metering** — `mul` instruction (Zmmul) accumulates V×I per valid
   frame; frame counter saturates at 255

### System Output

- **GPIO outputs (P4–P7):** contactor control, cable lock, grid-hold LED,
  fault LED — output pattern encodes FSM state
- **UART output:** 8-byte session record on session end (energy, status flags,
  frame count, CRC-16)

### Emulator Values

Each `./emu` command maps to one scenario:
- `-d 0xF0` — direction: P7–P4 output, P3–P0 input
- `-i <hex>` — set GPIO input (control pilot + safety trip)
- `-o <hex>` — check GPIO output (state-dependent pattern)
- `-t8 <bytes>` — send meter frame via UART (8 bytes, LE)
- `-r8 <bytes>` — read session record via UART (8 bytes, LE)

Full command lines in `emulator/emu_commands.txt`.

---

## 5. Firmware Development

Assembly source: `firmware/src/main.s` (372 instruction words, 36% of IMEM).

**Architecture:** register-only, stackless, polling-based. All state lives in
CPU registers (32 bytes of DMEM is unused). Main loop: `apply_pins` (GPIO FSM)
then `check_meter_timeout`, then `poll_uart` (byte-by-byte UART receive with incremental CRC).

**Build pipeline:**
```
main.s → as → main.o → gcc -nostdlib → firmware.elf → objcopy → firmware.bin → bin2rom.py → firmware.txt
```

**Three uses of the Xicrc `crcb` instruction:**
1. Frame integrity — CRC each payload byte, compare computed vs received
2. Chain continuity — seed from previous frame's CRC field detects drops/replays
3. Restart hash — CRC of charger ID produces staggered grid-hold delay

**CRC performance:** hardware `crcb` is 21× faster than software shift-XOR
(~60 vs ~1,276 cycles for 6 bytes), critical for the 1,740-cycle inter-byte
budget at 115200 baud.

---

## 6. Custom Firmware Validation

### Golden Model

`testbench/app/golden.py` is a bit-exact Python implementation of the
firmware's FSM, framed UART parser, sequence checks, energy metering, and session record generation.
Standard emulator scenario expectations come from the model. Focused UART
fault-injection tests use independent expected states and accounting values.
102 Python tests cover the model, scenario expectations, meter watchdog, and rebound evidence.

### Scenario Coverage

12 application scenarios + 3 harness scenarios, each run against 2 top-level
designs (hdl.v, rtl/top.v) = **30 simulation runs**.

| Scenario | Tests |
|---|---|
| H0 | organiser echo via emu model |
| H1 | harness catches a mismatch |
| H2 | organiser README example, verbatim (needs IN=0x02 at boot) |
| S1 | normal session: plug in, charge two frames, unplug |
| S1X | stress: S1 with back-to-back UART bytes |
| S2 | grid under-frequency: hold, then CRC-timed restart |
| S3 | corrupted and missing frames: next valid frame recovers |
| S4 | meter link lost: two bad frames in a row latch FAULT |
| S5 | E-stop while charging latches FAULT until released and unplugged |
| S6 | plug straight into CP C, then unplug while charging |
| S7 | frame exactly on every limit is billed; I_MAX+1 faults |
| S8 | ventilation (CP D) refused; CP E latches FAULT |
| S9 | invalid pilot code 7 latches FAULT with the CP-error flag |
| S10 | two replayed frames rejected -> FAULT |
| S11 | stale pins at boot: CP C waits for healthy meter data |

Run: `python testbench/app/run_tests.py`

### Rebound Simulation

1,000 chargers through a grid dip: **7.94× peak-load reduction** vs
simultaneous restart. Evidence in `testbench/app/evidence/`.

---

## 7. Stage 2 Validation — PASS

The official Stage 2 validation firmware
([CCX_Malaysia_Edition_Firmware_Stage_2](https://github.com/championchip-experience-community/CCX_Malaysia_Edition_Firmware_Stage_2))
is baked into `imem` as FIRMWARE 0 (the default) and confirmed word-for-word
identical. `top` exposes both the original debug ports (`pc_dbg_o`,
`x4_dbg_o`, `halt_o`) and the Stage 3 GPIO/UART ports
(`pins_i`/`pins_o`/`pins_oe_o`, `rx_i`/`tx_o`) side by side, so the
Stage 2 self-check (entry PC `0x00400000`, terminal self-loop
`0x004003ec`, x4 sentinel `0x00000000`) remains reproducible against the
debug ports at any time; `testbench/testbench.v` was repointed to the
Stage 3 organiser firmware check (§3) as the primary evidence file.

```
t=9996: pc=004003ec x4=00000000 (after 999 cycles)
PASS [organiser firmware self-check] x4 = 0x00000000 (PASS)
ALL TESTS PASSED
```

Evidence: `testbench/full_firmware_waveform/`

### Per-Module Testbenches — All PASS

| Module | Testbench | Result |
|---|---|---|
| ALU | `module_testbench/alu/` | PASS — all ops |
| Branch comparator | `module_testbench/branch_comparator/` | PASS — BEQ/BNE/BLT/BGE/BLTU/BGEU |
| Control unit | `module_testbench/control_unit/` | PASS — 15 instruction types |
| CRC (Xicrc) | `module_testbench/crc/` | PASS — CRCB/CRCH/CRCW |
| Immediate extend | `module_testbench/imm/` | PASS — I/S/B/U |
| LSU | `module_testbench/lsu/` | PASS — SW/SB/LW/LB/LBU |
| Memory mapping | `module_testbench/memory_mapping/` | PASS — DMEM + IMEM |
| Multiplier (Zmmul) | `module_testbench/multiplier/` | PASS — MUL/MULH/MULHSU/MULHU |
| Register file | `module_testbench/regfile/` | PASS — incl. x0 protection |

### ISA Coverage — 47/47

| Category | Count |
|---|---|
| Arithmetic and Logic (Register) | 10/10 |
| Arithmetic and Logic (Immediate) | 9/9 |
| Load | 5/5 |
| Store | 3/3 |
| Branch | 6/6 |
| Jump | 2/2 |
| Upper Immediate | 2/2 |
| System / Synchronization | 3/3 |
| Multiplication (Zmmul) | 4/4 |
| CRC (Xicrc) | 3/3 |

---

## 8. Reproducing

### Official Stage 3 firmware simulation
```bash
cd chip-inventor
iverilog -g2012 -o testbench/sim_testbench.vvp hdl.v testbench/testbench.v
vvp testbench/sim_testbench.vvp
```
Or across both top-level designs: `python testbench/run_tests.py`

### Per-module testbenches
Each module under `testbench/module_testbench/` has its own `.v` file,
output log, and waveform screenshot.

### GPIO / UART peripheral tests
```bash
python testbench/gpio/run_tests.py
python testbench/uart/run_tests.py
```

### Application scenarios (all 30 runs)
```bash
python testbench/app/run_tests.py
```

### Golden model tests
```bash
python -m pytest testbench/app -q
```

### Firmware build (requires RISC-V toolchain)
```bash
cd firmware && make
```
