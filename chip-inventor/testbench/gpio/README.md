# Stage 3 GPIO

Implemented in `chip-inventor/rtl/gpio.v` and embedded in both flattened
entry points, `chip-inventor/hdl.v` and `chip-inventor/rtl/top.v`.
Compile one entry point at a time: each already contains all its modules.
The older `legacy/` and separate `v2-chip-inventor-synth/` tracks are unchanged.

Stage 3 Part 1 sections 1.1-1.3 specify eight bidirectional pins. The tri-state
pad sits outside the block: GPIO exposes `pins_i`, `pins_o` (DATAOUT) and
`pins_oe_o` (DATADIR), because ChipInventor's Inout Pin drops its C/D inputs. Each DATADIR bit independently selects input (0) or output (1).
Input mode releases the output driver and samples the pin into DATAIN.
Output mode drives DATAOUT and stops updating that pin's DATAIN bit.

| Byte address | Register | Access |
|---|---|---|
| `0xF0000000` | DATAOUT[7:0] | Read/write |
| `0xF0000004` | DATAIN[7:0] | Read-only |
| `0xF0000008` | DATADIR[7:0] | Read/write |

Use aligned `lw` and `sw`. Upper 24 register bits read zero; writes to them
have no effect. The decoder ignores address bits [1:0] for register selection
and selects only these three words, preventing aliases into UART or memory.

Example: pins 0-3 outputs, pins 4-7 inputs; outputs 0 and 2 high:

```asm
lui  x1, 0xF0000
addi x2, x0, 15
sw   x2, 8(x1)       # DATADIR = 00001111
addi x2, x0, 5
sw   x2, 0(x1)       # DATAOUT = 00000101
lw   x3, 4(x1)       # DATAIN; mask with 0xF0 to inspect inputs
```

## Integration and timing

The GPIO interface uses `clk_i`/`rst_i`, 32-bit byte address `addr_i` (bits [3:2] select the register),
`we_i`/`oe_i`, four-bit byte mask `bw_i`, 32-bit `data_i`/`data_o`, and
eight-bit `pins_i`/`pins_o`/`pins_oe_o`. Writes commit on the rising clock edge.
Reads register the selected value on the rising edge when `oe_i` is high;
the result holds otherwise, matching DMEM's registered read interface.
DATAIN samples separately, so reads return the previously sampled pin value.

The address decoder adds `gpio_data_i`, `gpio_we_o`, and `gpio_oe_o`.
Top connects the original byte address [3:2], the control unit's byte mask,
and the LSU's store data to GPIO, then returns GPIO data through the decoder
and the existing LSU load path. No new instructions or control-unit states
are required.

The alternate `rtl/top.v` previously tied both the ALU address register and
load-result register enables high. Its original Stage 2 regression failed
at PC `0x004003F8`, x4=`0xFFFFFFFF`. Their enables now use the existing
`not_adr_src_o` and `result_src_is_mem_o` outputs, as `hdl.v` already did.
Both entry points now pass Stage 2 at PC `0x004003EC`, x4=0.

## Verification

With Icarus Verilog on PATH:

```sh
python chip-inventor/testbench/gpio/run_tests.py
```

Alternatively supply `--iverilog <path-to-iverilog>` and `--vvp <path-to-vvp>`.
The runner produces ignored scratch sources, binaries, and waveforms under
`chip-inventor/sim/gpio/`. It never overwrites the checked-in firmware ROM.

Five simulations pass:

- GPIO plus address decoder: reset, each pin high/low/released, mixed
  directions, input sampling, output isolation, read-only DATAIN, byte masks,
  reserved bits/addresses, registered read timing and memory decode regression.
- Official Stage 3 organiser GPIO/UART firmware with `hdl.v`.
- CPU GPIO program with `hdl.v`: stores directions/output, loads all three
  registers, checks external input bits and verifies physical output levels.
- The same organiser and GPIO CPU simulations with `rtl/top.v`.

## Assumptions and remaining hardware work

Where the guide is silent, this implementation uses the project's synchronous
active-high reset, resets all registers to zero (all pins inputs), holds
DATAIN bits while in output mode, and ignores writes without byte lane zero.
These choices are explicit rather than claimed as additional guide rules.

This models the guide's direct clocked input sampling; asynchronous board
inputs still need a synchronizer policy, and buttons may need debouncing.
Tri-state connections must map to physical bidirectional pads for fabrication
(or FPGA I/O buffers). Direction gating does not prevent contention if an
external device also drives an output-mode pin. Existing GDS/netlists and
ChipInventor diagrams predate GPIO; no new physical layout has been generated.
