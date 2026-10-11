# Stage 3 application firmware — grid-aware EV charging-station controller

This directory is our copy of the organiser's **RVBL-Firmware-Builder**, with
our Stage 3 application as `src/main.s`.

The layout deliberately matches the organiser's repo, so `src/main.s` can be
dropped into their `RVBL-Firmware-Builder/src/` and built there unchanged.

## Provenance of the vendored files

Copied **verbatim** (byte-for-byte, original `Confidencial - Propriedade do CPA
Wernher von Braun` headers intact) from
`external/CCX_Malaysia_Edition_Stage_3/RVBL-Firmware-Builder/`:

| File | Role |
|---|---|
| `Makefile` | assemble → link → `.bin` → `.txt` ROM image → `.dmp` listing |
| `bsp/custom.ld` | `ENTRY(_start)`, FLASH at `0x00400000`, SRAM at `0x10010000` |
| `scripts/bin2rom.py` | `.bin` → `32'hADDR: r_Instruction = 32'hWORD;` lines |

**Do not edit these three files.** They are the organiser's tooling; keeping
them unmodified is what proves our firmware builds with their flow.

Ours:

| File | Role |
|---|---|
| `src/main.s` | the application (the only `.s` file in `src/` — the Makefile globs `src/*.s`) |
| `README.md` | this file |

## Build

`make` needs the RISC-V toolchain and `python3`, which on this host resolve
only inside an **MSYS2 UCRT64** shell:

```bash
# in an MSYS2 UCRT64 shell
cd chip-inventor/firmware
make
```

Toolchain installed with:

```bash
pacman -S mingw-w64-ucrt-x86_64-riscv64-unknown-elf-gcc \
          mingw-w64-ucrt-x86_64-riscv64-unknown-elf-binutils \
          mingw-w64-ucrt-x86_64-python
```

The Makefile prefers `riscv32-unknown-elf-*` and falls back to
`riscv64-unknown-elf-*`; we have the latter, built with
`-march=rv32i_zmmul -mabi=ilp32`, so the output is 32-bit either way.

### One environment gotcha

MSYS2's shell starts with `TMP`, `TEMP` and `TMPDIR` **unset**. The native
`gcc.exe` driver then falls back to `C:\WINDOWS\` for its temporary files and
the link step fails with:

```
Cannot create temporary file in C:\WINDOWS\: Permission denied
```

Export a writable Windows-style path before `make` (this is a host environment
fix, not a Makefile change):

```bash
export TMP='C:\Users\<you>\AppData\Local\Temp'
export TEMP="$TMP" TMPDIR="$TMP"
```

## Outputs

`make` writes to `build/`:

| File | Committed? | Purpose |
|---|---|---|
| `firmware.txt` | yes | ROM image; `testbench/firmware.py` loads it as `FIRMWARE 5` |
| `firmware.bin` | yes | raw image, Stage 3 deliverable |
| `firmware.dmp` | yes | disassembly — the audit trail for the Xicrc `.insn` encodings |
| `firmware.elf` | yes | linked image |
| `main.o` | no | gitignored intermediate |

After rebuilding, load the new image into the RTL with:

```bash
python chip-inventor/testbench/gen_imem.py
```

which regenerates `rtl/imem.v` and syncs `hdl.v`, `rtl/top.v`.
Re-uploading `rtl/imem.v` to the ChipInventor canvas is a manual step.

## Xicrc instructions

The stock assembler does not know `crcb`/`crch`/`crcw`, so `src/main.s` defines
them as macros over `.insn r 0x33, <funct3>, 0x40, rd, rs1, rs2` — opcode
`0110011`, funct7 `1000000`, funct3 `000`/`001`/`010`, taken from the handoff
opcode table (`docs/HANDOFF_control_unit.md`). Operands: **rs1 = data,
rs2 = seed/running CRC**, result in `rd`.

Verified two ways: `build/firmware.dmp` shows `crcb s0, s1, s0` assembling to
`0x80848433`, the same word the repo's own assembler
(`legacy/scripts/rvbl2_asm.py`) emits for that instruction.

## Toolchain validation

Before writing any application code, the toolchain was checked against the
organiser's own output: building their
`RVBL-GPIO-UART-Test-Firmware/src/main.s` with this builder reproduces their
committed `firmware.txt` exactly (21 lines, `diff` clean).

## Meter-data watchdog update (7 October 2026)

The original 500 ms / 100 ms defaults were revised on 11 October to 4000 ms /
400 ms for the AWS host-paced demonstration. The values below describe the
current build; see `../new change.md` for the timing tradeoff and evidence.

The firmware now waits for a healthy initial meter frame and faults after 4000 ms
without a complete CRC-valid frame during a session. It requires the new MMIO
timer at `0xF2000000`. Timeout uses report state code 5 and opens the contactor
before sending the report. See [improvement made.md](../improvement%20made.md).

An additional portable build helper is available; it also synchronizes both ROMs:

```sh
python firmware/scripts/build.py --tool-prefix /path/to/riscv-none-elf-
```

Run it from the project root. This helper invokes GNU assembler/linker/binutils
and does not require make or MSYS2. It leaves the organiser's tools unchanged.

## UART protocol v2

FIRMWARE 5 now expects escaped marker-delimited meter frames with sequence numbers
and independent per-frame CRC. The additional timer register at `0xF2000004`
measures the 400 ms partial-frame timeout. Build and upload the updated RTL and
firmware together; update the meter sender using `emulator/meter_protocol.py`.
See `emulator/README.md` for the exact wire format and migration details.
