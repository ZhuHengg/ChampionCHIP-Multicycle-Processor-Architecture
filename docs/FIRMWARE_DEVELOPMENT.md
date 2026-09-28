# 5. Firmware Development and Processing

Grid-aware EV charging-station controller firmware for the ChampionCHIP RVBL-2 multicycle RISC-V processor (RV32I + Zmmul + Xicrc), written in RISC-V assembly with no C runtime, no stack, and no data memory.

---

## 5.1 Toolchain and Build Pipeline

The firmware is built using the organiser-provided **RVBL-Firmware-Builder** toolchain, which assembles RISC-V assembly into a Verilog-compatible ROM image. The entire pipeline runs from a single `make` invocation.

### Build Flow

```
                        ┌─────────────┐
                        │  custom.ld  │ (linker script)
                        └──────┬──────┘
                               │
  ┌──────────┐    as     ┌─────┴────┐   gcc -nostdlib   ┌──────────────┐
  │ main.s   │ ────────► │ main.o   │ ────────────────► │ firmware.elf │
  │ (source) │           │ (object) │    -T custom.ld   │  (linked)    │
  └──────────┘           └──────────┘                   └──────┬───────┘
                                                               │
                                                        objcopy -O binary
                                                               │
                                                        ┌──────▼───────┐
                              ┌──────────────┐          │ firmware.bin │
                              │ firmware.txt │ ◄─────── │   (raw)      │
                              │ (Verilog ROM)│ bin2rom  └──────┬───────┘
                              └──────────────┘                 │
                                                        objdump -D
                                                               │
                                                        ┌──────▼───────┐
                                                        │ firmware.dmp │
                                                        │ (disassembly)│
                                                        └──────────────┘
```

**Figure 5.1** — Firmware build pipeline from assembly source to Verilog ROM image.

| Stage | Tool | Flags / Notes |
|---|---|---|
| Assemble | `riscv64-unknown-elf-as` | `-march=rv32i_zmmul -mabi=ilp32` |
| Link | `riscv64-unknown-elf-gcc` | `-nostdlib -T bsp/custom.ld` — no C runtime |
| Extract binary | `objcopy -O binary` | Strips ELF headers, produces raw instruction bytes |
| Generate ROM | `bin2rom.py` | Converts binary to Verilog `case` statements for IMEM |
| Disassemble | `objdump -D` | Human-readable listing for debugging |

> **Toolchain validation:** The organiser's official GPIO/UART test firmware was rebuilt through this pipeline and verified byte-for-byte identical (21/21 instruction words matched), confirming the toolchain produces correct output.

### ROM Output Format

The `bin2rom.py` script converts each 4-byte instruction into a Verilog `case` entry. The firmware compiles to **265 instruction words** (1,060 bytes), well within the 1,024-word IMEM capacity.

```verilog
32'h00400000: r_Instruction = 32'hF00002B7;  // lui   s0, 0xF0000
32'h00400004: r_Instruction = 32'hF10003B7;  // lui   s1, 0xF1000
32'h00400008: r_Instruction = 32'h0F000293;  // li    t0, 0xF0
...
```

---

## 5.2 Processor Memory Map and Peripheral Registers

```
  Address Space                    Register Detail
  ─────────────────────────────────────────────────────────────────
  0x00400000 ┌──────────────────┐
             │   IMEM (FLASH)   │  Instruction memory, case ROM
             │   16 MB          │  Up to 1024 words
             └──────────────────┘

  0x10010000 ┌──────────────────┐
             │   DMEM (SRAM)    │  Data memory (UNUSED by firmware)
             │   32 bytes       │  All state lives in registers
             └──────────────────┘

  0xF0000000 ┌──────────────────┐  +0x00 DATAOUT   Write output pin values
             │   GPIO           │  +0x04 DATAIN    Read input pin values
             │   12 bytes       │  +0x08 DATADIR   0=input, 1=output per pin
             └──────────────────┘

  0xF1000000 ┌──────────────────┐  +0x00 TXDATA    Byte to transmit
             │   UART           │  +0x04 RXDATA    Received byte
             │   12 bytes       │  +0x08 CONTROL   b0:TX b1:RXDONE b2:TXDONE
             └──────────────────┘
```

**Figure 5.2** — Processor memory map with peripheral register details.

> **Key constraint:** Physical DMEM is only 32 bytes (8 words), mandated by the organiser for all teams. The firmware stores **all state in CPU registers** — no variables in memory, no stack, no heap.

---

## 5.3 Firmware Architecture Overview

The firmware implements a **register-only, stackless, polling-based** architecture. All application state resides in the 32 general-purpose RISC-V registers. The main loop alternates between two tasks: applying GPIO input rules and polling for UART data.

### Main Loop Call Graph

```
                         ┌──────────────────────┐
                         │  _start (init GPIO,   │
                         │  UART, clear regs)    │
                         └──────────┬─────────────┘
                                    │
                         ┌──────────▼─────────────┐
                    ┌───►│      main_loop          │◄──────────┐
                    │    └────┬─────────────┬──────┘           │
                    │         │             │                   │
                    │   ┌─────▼──────┐ ┌────▼───────┐         │
                    │   │ apply_pins │ │ poll_uart   │         │
                    │   │ (GPIO FSM) │ │ (UART byte) │         │
                    │   └─┬────┬─────┘ └──┬─────┬───┘         │
                    │     │    │          │     │              │
                    │  ┌──▼──┐ ┌──▼────────┐ ┌──▼──────┐ ┌───▼────────┐
                    │  │set_ │ │enter_     │ │on_frame │ │send_record │
                    │  │state│ │fault      │ │(CRC +   │ │(8-byte TX) │
                    │  └─────┘ └───────────┘ │ rules)  │ └──┬─────────┘
                    │                        └─────────┘    │
                    │                                  ┌────▼────────┐
                    │                                  │uart_tx_byte │
                    │                                  └─────────────┘
                    └──────────────────────────────────────────────────┘
                                       (loop back)
```

**Figure 5.3** — Firmware call graph and main loop structure.

### Register Allocation Map

With only 32 bytes of DMEM and no stack pointer, every piece of application state lives in a dedicated CPU register:

| Register | RISC-V Name | Purpose |
|---|---|---|
| x4 | `tp` | Application FSM state (0–4), observable via `x4_dbg_o` |
| x8 | `s0` | GPIO base address (`0xF0000000`) |
| x9 | `s1` | UART base address (`0xF1000000`) |
| x18 | `s2` | CRC chain seed (starts `0xFFFF`) |
| x19 | `s3` | Accumulated energy (Σ V×I) |
| x20 | `s4` | Billed frame count (saturates at 255) |
| x21 | `s5` | Status flags (fault cause bits) |
| x22 | `s6` | Consecutive bad frame counter |
| x23 | `s7` | GRID_HOLD healthy frame count |
| x24 | `s8` | Restart delay target |
| x25 | `s9` | Frame byte index (0–7) |
| x14 | `a4` | Running CRC of current frame payload |
| x15–x17 | `a5, a6, a7` | Current frame fields: Voltage, Current, Frequency |
| x3 | `gp` | CRC field of frame being received |

---

## 5.4 Application Finite State Machine

The firmware implements a five-state IEC 61851-derived control-pilot state machine. State transitions are driven by two input sources: GPIO pins (control pilot and safety trip) and UART frames (energy meter readings). The FSM state is stored in register `tp` (x4), making it directly observable on the processor's debug port.

### State Diagram

```
                CP=A (no car, safety clear)
     ┌─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─┐
     ▼                                                            │
  ┌──────┐  CP=B,C,D   ┌───────────┐  CP=C   ┌──────────┐     ┌─┴────┐
  │ IDLE │ ──────────►  │ CONNECTED │ ──────► │ CHARGING │     │FAULT │
  │ 0x00 │              │   0x20    │         │   0x30   │     │ 0x80 │
  └──────┘              └─────┬─────┘         └──┬───┬───┘     └──────┘
     ▲                    CP=A│(unplug)          │   │              ▲
     │   ◄────────────────────┘           F<4950 │   │ CP=B,D      │
     │                                   V<2070  │   │   ┌─────────┘
     │   CP=A (unplug, sends record)             │   ▼   │
     │◄──────────────────────────────────────────┤  ┌─┴──┴───────┐
     │                                           │  │ CONNECTED  │
     │                N healthy frames           │  │  (drop back)│
     │                     ┌─────────────────────┘  └────────────┘
     │                     ▼
     │              ┌───────────┐
     │              │ GRID_HOLD │
     │              │   0x60    │
     │              └───────────┘
     │
     └────── E-stop / Overcurrent / 2× bad CRC  (from any non-FAULT state)
             ──────────────────────────────────► FAULT
```

**Figure 5.4** — Application FSM state diagram (IEC 61851-derived control-pilot state machine).

### State Descriptions

| State | Code | GPIO Output | Description |
|---|---|---|---|
| **IDLE** | 0 | `0x00` | No vehicle connected. All outputs de-asserted. Counters reset on next connection. |
| **CONNECTED** | 1 | `0x20` | Vehicle detected (CP state B/C/D). Cable lock engaged. Energy and frame counters cleared. |
| **CHARGING** | 2 | `0x30` | Active power delivery. Energy metering and billing active. Grid health monitored per frame. |
| **GRID_HOLD** | 3 | `0x60` | Grid unhealthy — contactor open, waiting for staggered restart. Over-current ignored (contactor already open). |
| **FAULT** | 4 | `0x80` | Latched fault. Clears only when safety trip de-asserts AND control pilot returns to state A (no car). No session record sent on recovery. |

---

## 5.5 UART Data Handling — Receiving Meter Frames

The energy meter sends 8-byte frames over UART at 115200 baud (8-N-1). Each frame contains voltage, current, and frequency measurements plus a CRC-16 integrity check. The firmware receives frames byte-by-byte using non-blocking polling, processing each byte as it arrives to stay within the 1,740-cycle inter-byte budget.

### Meter Frame Format (8 bytes, little-endian)

```
  ◄────── CRC computed over bytes 0–5 (payload) ──────►

  ┌─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┐
  │ Byte 0  │ Byte 1  │ Byte 2  │ Byte 3  │ Byte 4  │ Byte 5  │ Byte 6  │ Byte 7  │
  │ V low   │ V high  │ I low   │ I high  │ F low   │ F high  │ CRC low │ CRC high│
  └────┬────┴────┬────┴────┬────┴────┬────┴────┬────┴────┬────┴────┬────┴────┬────┘
       └────┬────┘         └────┬────┘         └────┬────┘         └────┬────┘
        Voltage (0.1V)    Current (0.1A)     Frequency (0.01Hz)     CRC-16
```

**Figure 5.5** — Meter frame byte layout (8 bytes, little-endian, CRC-16 over payload).

### Byte-by-Byte Receive Processing

The firmware processes each received byte immediately, avoiding the need to buffer the entire frame. This is critical because the 32-byte DMEM cannot hold frame buffers.

```
                    ┌────────────┐
                    │ poll_uart  │
                    └──────┬─────┘
                           │
                    ┌──────▼──────┐
                    │  RXDONE ?   │──── No ───► return
                    └──────┬──────┘
                           │ Yes
                    ┌──────▼──────────────┐
                    │ Clear RXDONE,       │
                    │ read byte from      │
                    │ RXDATA              │
                    └──────┬──────────────┘
                           │
                    ┌──────▼──────┐
                    │ index < 6 ? │
                    └───┬─────┬───┘
                   Yes  │     │  No
              ┌─────────▼┐  ┌─▼──────────┐
              │ crcb fold │  │ index = 6? │
              │ + extract │  │ Store CRC  │
              │ V/I/F     │  │ low byte   │
              └───────────┘  ├────────────┤
                             │ index = 7? │
                             │ Complete   │
                             │ CRC field  │──► on_frame
                             │ Reset idx  │    (validate + rules)
                             └────────────┘
```

**Figure 5.6** — UART receive processing flow (one byte per call).

> **Why process byte-by-byte?** At 115200 baud, one byte takes 1,740 clock cycles (~400 instructions at ~4 CPI). Processing during reception ensures the firmware is ready for the next byte with no risk of overrun, and avoids the need for a frame buffer in the 32-byte DMEM.

---

## 5.6 CRC Processing with the Xicrc Custom Instruction

The `crcb` custom instruction computes CRC-16/IBM-3740 (polynomial `0x1021`, initial value `0xFFFF`, non-reflected, XOR-out 0) on a single byte in one instruction cycle. It serves **three distinct purposes** in the firmware:

### Three Uses of a Single CRC Instruction

```
                              ┌──────────────────────────┐
                              │  crcb rd, rs1, rs2       │
                              │  CRC-16/IBM-3740         │
                              │  1 cycle per byte        │
                              └───┬──────────┬───────┬───┘
                                  │          │       │
                 ┌────────────────▼┐   ┌─────▼─────┐ ┌▼─────────────────┐
                 │ 1. FRAME        │   │ 2. CHAIN  │ │ 3. RESTART       │
                 │    INTEGRITY    │   │CONTINUITY │ │    HASH           │
                 ├─────────────────┤   ├───────────┤ ├──────────────────┤
                 │ CRC each payload│   │ Seed =    │ │ CRC(charger ID,  │
                 │ byte; compare   │   │ previous  │ │ frame CRC)       │
                 │ computed vs     │   │ frame's   │ │                  │
                 │ received        │   │ CRC field │ │ Staggered grid-  │
                 │                 │   │           │ │ hold restart     │
                 │ Detects         │   │ Detects   │ │                  │
                 │ corrupted       │   │ dropped,  │ │ No timer or RNG  │
                 │ frames          │   │ replayed  │ │ needed           │
                 └─────────────────┘   └───────────┘ └──────────────────┘
```

**Figure 5.7** — Three uses of the `crcb` custom instruction in the firmware.

**Instruction encoding** via `.insn r` macro:

```asm
.macro crcb rd, rs1, rs2
.insn r 0x33, 0x0, 0x40, \rd, \rs1, \rs2
.endm
```

- Xicrc encoding: opcode `0110011`, funct7 `1000000`, funct3 `000` (crcb)
- Operands: `rs1` = data byte, `rs2` = seed / running CRC, `rd` = result

### CRC Chain Mechanism

The CRC chain links consecutive frames without adding a sequence number (keeping frames at the emulator's 8-byte limit). Each frame's CRC is seeded from the CRC field of the *previous frame received* (not the last accepted frame).

```
  seed: 0xFFFF
       │
  ┌────▼─────────┐         ┌──────────────┐         ┌──────────────┐
  │  Frame N-1   │         │   Frame N    │         │  Frame N+1   │
  │  CRC=0xA1B2  │         │ seed=0xA1B2  │         │ seed=N's CRC │
  └──────┬───────┘         └──────┬───────┘         └──────────────┘
         │    s2 ← CRC field     │    s2 ← CRC field
         └────────────────────────┘────────────────────► ...
```

**Figure 5.8** — CRC chain continuity: each frame's seed is the previous frame's CRC field.

This ensures:

- **Dropped frames:** The seed diverges from what the meter sent, so the next frame fails CRC.
- **Replayed frames:** A replayed frame has the wrong seed context.
- **Re-ordered frames:** The chain breaks if frames arrive out of order.

### Performance: Hardware CRC vs Software CRC

A benchmark testbench (FIRMWARE 6) measured the cycle cost of computing CRC-16 over a 6-byte payload:

| Method | Cycles | Instructions |
|---|---|---|
| Hardware `crcb` (6 invocations) | **~60** | ~15 |
| Software shift-XOR loop | ~1,276 | ~320 |

> **21× speedup.** The hardware `crcb` instruction completes in one processor cycle per byte, versus ~213 cycles per byte for the software implementation. This is critical for meeting the 1,740-cycle inter-byte timing budget.

---

## 5.7 Energy Metering with Zmmul Multiplication

The Zmmul extension provides single-cycle 32×32-bit hardware multiplication. The firmware uses `mul` for energy accumulation on every valid meter frame during CHARGING:

```asm
    mul  t0, a5, a6        // t0 = V × I  (0.01W units)
    add  s3, s3, t0        // energy += V × I (wraps mod 2³²)
```

Integer units are chosen to avoid division entirely: voltage in 0.1V, current in 0.1A, producing energy in 0.01W units. The host backend converts to kWh using the known metering interval. The frame counter `s4` saturates at 255 (one byte in the session record), preventing overflow without needing a branch to a wider counter.

> **No division, no floating point.** By choosing integer units (0.1V × 0.1A = 0.01W), the firmware avoids the RV32I's lack of a divide instruction and floating-point hardware. All unit conversion happens on the host side.

---

## 5.8 GPIO Control Signal Processing

### Pin Assignment Map

```
                         ┌──────────────────┐
        INPUTS           │                  │          OUTPUTS
  ──────────────────►    │                  │    ────────────────────►
                         │                  │
  P0 ─── CP bit 0 ────► │                  │ ────► P4 ─── Contactor
  P1 ─── CP bit 1 ────► │    RVBL-2 Core   │ ────► P5 ─── Cable lock
  P2 ─── CP bit 2 ────► │  DATADIR = 0xF0  │ ────► P6 ─── Grid-hold LED
  P3 ─── Safety trip ──► │  P7-P4 output    │ ────► P7 ─── Fault LED
                         │  P3-P0 input     │
                         │                  │
                         └──────────────────┘
```

**Figure 5.9** — GPIO pin assignment: 4 inputs (control pilot + safety) and 4 outputs (actuators + indicators).

### Control Pilot Decode

Pins P2–P0 encode the IEC 61851 control-pilot state as a 3-bit value. The firmware reads `DATAIN`, masks bits [2:0], and maps the value to an FSM action:

| CP Code (P2:P0) | IEC 61851 State | Meaning | Firmware Action |
|---|---|---|---|
| `000 (0)` | A | No vehicle | End session / clear fault |
| `001 (1)` | B | Vehicle detected | Start session (CONNECTED) |
| `010 (2)` | C | Charging request | Begin charging |
| `011 (3)` | D | Ventilation request | Treated as B (no ventilation) |
| `≥ 100` | E/F/invalid | Error condition | Enter FAULT |

### Stabilisation Loop

The `apply_pins` function re-applies rules in a loop until the state stops changing. This allows a direct transition from IDLE through CONNECTED to CHARGING in a single pass when the control pilot is already at state C on first read — matching real-world behaviour where a car may be plugged in and requesting charge simultaneously.

---

## 5.9 UART Transmission — Session Records

When a session ends (unplug or fault), the firmware sends an 8-byte session record back to the operator backend via UART.

### Session Record Format

```
  ┌─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┬─────────┐
  │ Byte 0  │ Byte 1  │ Byte 2  │ Byte 3  │ Byte 4  │ Byte 5  │ Byte 6  │ Byte 7  │
  │Energy   │Energy   │Energy   │Energy   │ STATUS  │ FRAMES  │CRC low  │CRC high │
  │ [7:0]   │ [15:8]  │ [23:16] │ [31:24] │         │         │         │         │
  └─────────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────┴─────────┘
  ◄──────── Energy (u32 LE, 0.01W units) ─────────► ◄State|Flags►
```

**Figure 5.10** — Session record byte layout (8 bytes, sent on session end).

### STATUS Byte Encoding

The STATUS byte combines the current FSM state (bits 2:0) with fault cause flags (bits 7:3):

| Bit | Flag | Meaning |
|---|---|---|
| 2:0 | State | FSM state at time of record (0–4) |
| 3 | `F_ESTOP` | Emergency stop triggered |
| 4 | `F_CP_ERROR` | Invalid control pilot (E/F) |
| 5 | `F_OVERCURRENT` | Current exceeded 32.0 A |
| 6 | `F_CRC_LOST` | Two consecutive bad CRC frames |
| 7 | `F_GRID_HOLD` | Grid-hold was active during session |

### UART Transmission Protocol

The `uart_tx_byte` routine uses careful read-modify-write on the UART CONTROL register to preserve the RXDONE flag while setting TRANSMIT. This prevents a race where clearing CONTROL would lose an unread received byte:

```asm
uart_tx_byte:
    lw   t0, UART_CONTROL(s1)     // Wait for TXDONE
    andi t0, t0, UART_TXDONE
    beqz t0, tx_wait
    sw   a0, UART_TXDATA(s1)      // Write byte to transmit
    lw   t0, UART_CONTROL(s1)     // Read-modify-write: preserve RXDONE
    ori  t0, t0, UART_TRANSMIT    // Set TRANSMIT bit
    sw   t0, UART_CONTROL(s1)
    ret
```

---

## 5.10 Grid-Hold and Staggered Restart

When the grid becomes unhealthy (frequency < 49.50 Hz or voltage < 207.0 V), the charger enters GRID_HOLD and opens the contactor. The key innovation is **how it decides when to restart**: using a CRC-derived hash to stagger restart times across a fleet of chargers, preventing the "rebound" spike where thousands of chargers resume simultaneously.

### Restart Delay Computation

```
  ┌───────────────┐       ┌───────────────────────┐       ┌───────────────┐       ┌───────────┐
  │  1. SEED      │       │  2. HASH CHARGER ID   │       │ 3. EXTRACT    │       │  RESULT   │
  │               │       │                       │       │    DELAY      │       │           │
  │ gp = trigger  │──────►│ crcb(0x01, gp)        │──────►│ hash & 7     │──────►│ Restart   │
  │ frame's CRC   │       │ crcb(0x00, ...)       │       │ + HOLD_BASE  │       │ after     │
  │ field         │       │ crcb(0x59, ...)       │       │   (= 2)      │       │ 2–9       │
  │               │       │ crcb(0x4D, ...)       │       │              │       │ frames    │
  └───────────────┘       └───────────────────────┘       └───────────────┘       └───────────┘
```

**Figure 5.11** — Grid-hold restart delay computation using CRC as a hash function.

Properties:
- **Deterministic** — no RNG or timer needed
- **Unique per charger ID × grid event** — different chargers and different events restart on different frames
- **Auditable** — the delay can be verified from the meter stream alone

> **Verified spread:** Testing 10,000 sequential charger IDs shows exactly 1,250 chargers per delay bucket (2–9), confirming uniform distribution. A rebound simulation of 1,000 chargers through a grid dip demonstrates a **7.94× peak-load reduction** compared to simultaneous restart.

---

## 5.11 Hardware Constraints and Design Decisions

| Constraint | Value | Firmware Impact |
|---|---|---|
| Clock frequency | 20 MHz | ~5 MIPS peak, ~1.25 MIPS effective at ~4 CPI |
| CPI (cycles/instruction) | ALU/MUL/CRC: 4, Branch: 3, Store: 4, Load: 6 | Average ~4 CPI; loads are the bottleneck |
| UART byte time | 1,740 cycles (~400 instructions) | All per-byte processing must complete within this budget |
| DMEM capacity | 32 bytes (8 words) | All state in registers; no stack, no heap, no buffers |
| IMEM capacity | 1,024 words | Firmware uses 265 words (26% of capacity) |
| Interrupts / timer | None | Polling-only architecture; time measured in frame count |
| Division / FP | None | Integer-only arithmetic; units avoid division |
| Emulator reply limit | 8 bytes per command | One session record per session; CRC chain avoids sequence numbers |

### Calling Convention (No Stack)

Without a stack pointer, the firmware uses a **manual register-save convention**. Each function documents which registers it clobbers. Return addresses are saved in designated registers:

| Function | Saves `ra` in | Reason |
|---|---|---|
| `apply_pins` | `s11` | Calls `set_state` and `enter_fault` |
| `enter_fault` | `t4` | Calls `set_state` and `send_record` |
| `send_record` | `t3` | Calls `uart_tx_byte` |
| `poll_uart` | `t6` | Calls `on_frame` |

---

## 5.12 Verification and Testing

### End-to-End Data Flow

```
  ┌─────────────┐                                              ┌─────────────┐
  │             │  -d, -i (GPIO)                               │             │
  │   ./emu     │ ─────────────────────────►  ┌─────────────┐  │   ./emu     │
  │  (FPGA      │  -t   (UART meter frames)   │             │  │  (check     │
  │  Emulator)  │ ─────────────────────────►  │  RVBL-2     │  │  results)   │
  │             │                              │  Core +     │  │             │
  │             │  -o   (GPIO check)           │  Firmware   │  │             │
  │             │ ◄─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   │             │  │             │
  │             │  -r   (UART session record)  │             │  │             │
  │             │ ◄─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─   └─────────────┘  │             │
  └─────────────┘                                              └─────────────┘

  Firmware processing pipeline per main_loop iteration:

  ┌────────────┐    ┌───────────┐    ┌───────────┐    ┌──────────────┐
  │ apply_pins │───►│ poll_uart │───►│ on_frame  │───►│  mul V × I   │
  │ CP decode  │    │ byte      │    │ CRC check │    │  energy      │
  │ + FSM      │    │ assembly  │    │ + rules   │    │  accumulate  │
  └────────────┘    └───────────┘    └───────────┘    └──────────────┘
```

**Figure 5.12** — End-to-end data flow from emulator through firmware processing.

### Example Emulator Scenario (S2 — Normal Charge Session)

```bash
./emu -d 0xF0 -i 0x02 -o 0x30 \
  -t8 <V,I,F,CRC> -i 0x00 -o 0x00 -r8 <ENERGY,STATUS,FRAMES,CRC>
```

12 emulator scenarios (S1–S11, S1X) cover: normal session, grid hold, overcurrent, E-stop, CRC corruption, chain break, invalid pilot, replayed frame, stale inputs at boot, and back-to-back byte timing.

### Testing Methodology

| Layer | Method | Coverage |
|---|---|---|
| Golden model | Bit-exact Python model (`golden.py`) | CRC, energy, restart delay, session records — single source of truth |
| Golden model tests | pytest (`test_golden.py`) | 36 test cases for all model functions |
| Scenario DSL | `scenarios.py` generates Verilog + `./emu` commands | 12 scenarios covering all FSM paths and fault modes |
| RTL simulation | `tb_app.v` with `emu_*` tasks | 15 scenarios × 3 top-level designs = 45 simulation runs |
| CRC benchmark | `tb_crc_bench.v` (FIRMWARE 6) | Cycle-accurate measurement of hardware vs software CRC |
| Rebound simulation | `rebound_sim.py` | 1,000 chargers through grid dip; proves 7.94× load reduction |

### Two-Level FSM Observability

The firmware stores its application state in register `tp` (x4), which is wired to the processor's `x4_dbg_o` debug output. This creates a **two-level FSM** visible in a single waveform: the hardware multicycle FSM (FETCH, DECODE, EXECUTE, etc.) runs underneath the application FSM (IDLE, CONNECTED, CHARGING, etc.), and both are observable simultaneously — continuing the Phase 2 edge of comprehensive state-machine design.
