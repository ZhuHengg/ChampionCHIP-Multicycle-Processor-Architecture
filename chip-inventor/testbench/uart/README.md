# Stage 3 UART

Stage 3 Part 1 section 2 is implemented in `rtl/uart.v`, `rtl/uart_tx.v`,
and `rtl/uart_rx.v`, and embedded in both `hdl.v` and `rtl/top.v`.
Compile either flattened entry point alone, or the individual modules for unit
simulation; do not compile flattened files together with their component modules.

UART uses 115200 baud, eight data bits LSB first, no parity, one start bit and
one stop bit. TX idles high. Independent TX/RX shift registers support full duplex.
RX uses a two-flop synchronizer and one midpoint sample per bit, no oversampling.

| Byte address | Register | Access |
|---|---|---|
| 0xF1000000 | TXDATA[7:0] | RW |
| 0xF1000004 | RXDATA[7:0] | R |
| 0xF1000008 | CONTROL: TXDONE[2], RXDONE[1], TRANSMIT[0] | R / RW / W |

Use aligned lw/sw. Low two address bits are ignored by the decoder; only the
three register words are selected. Reserved bits read zero. Byte lane zero must
be enabled for writes. Reads are registered on oe_i and hold otherwise, matching
GPIO and the existing CPU load sequence. The control unit is unchanged.

TRANSMIT is a one-cycle command; reads return zero for this bit. TXDONE clears
when a command is accepted and sets after a complete stop bit. RXDONE is sticky
until software writes zero to bit 1; reading RXDATA does not clear it. Writing
CONTROL cannot change TXDONE. Software should preserve RXDONE when starting TX
if unread receive data must remain flagged.

Top exposes rx_i, tx_o and CLK_HZ (default 20000000, matching config.json's
50 ns clock period). Set CLK_HZ to the actual input clock frequency before hardware
use. The divider rounds CLK_HZ/115200 to the nearest integer (174 at 20 MHz).
Supported settings require at least four clock cycles per bit. Tie unused RX high.

Implementation choices where the guide is silent: synchronous active-high reset,
TXDONE resets to 1, other registers reset to zero, starts while busy are ignored,
new data replaces unread RXDATA (no queue or overrun flag), invalid start/stop
bits are discarded, and receive completion wins over simultaneous software writes
to RXDONE. Reset aborts in-progress transfers. These shift registers are not
multi-entry FIFOs. No hardware flow control or interrupts are added.

Run with Icarus Verilog on PATH:

```sh
python chip-inventor/testbench/uart/run_tests.py
python chip-inventor/testbench/gpio/run_tests.py
```

Both runners accept --iverilog and --vvp executable paths. UART tests cover
register access, byte masks, read-only RXDATA, reserved address decoding, LSB-first
TX timing, busy commands, TXDATA changes during transmission, full duplex,
RXDONE clearing, receive overwrite, and reset. A CPU lw/sw echo test and the
original Stage 2 firmware run against both flattened entry points. Scratch ROMs
and simulation outputs stay under ignored sim/uart; the shipped ROM is unchanged.
Simulation uses a shorter divider to keep tests quick. FPGA pin assignments,
ChipInventor diagrams, synthesis and physical layout artifacts are not regenerated.
