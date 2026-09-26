# GPIO and UART Official Test Firmware

This firmware is provided to validate the GPIO and UART peripherals integrated into the RV32I processor. It performs a GPIO echo and a UART echo, allowing both peripherals to be tested in a local simulation.

Each project must generate the machine instructions, load them into its instruction memory, and create a testbench that demonstrates the expected responses in the simulation log and waveform.

## Validation flow

1. Place the instructions in `firmware.txt` in the processor instruction memory (IMEM), as illustrated below:

   ```verilog
   always @(*) begin
       case (i_Address)
           32'h00400000: r_Instruction = 32'hF0000437;
           32'h00400004: r_Instruction = 32'hF10004B7;
           // Remaining generated instructions

           default: r_Instruction = 32'h00000000;
       endcase
   end
   ```

2. Create a testbench for the processor with GPIO and UART stimulus.
3. Run the simulation and verify the GPIO and UART responses.

## Peripheral interface

The firmware accesses the peripherals through memory-mapped registers.

### GPIO

| Address | Register | Purpose |
|---:|---|---|
| `0xF0000000` | `DATAOUT` | GPIO output value |
| `0xF0000004` | `DATAIN` | GPIO input value |
| `0xF0000008` | `DATADIR` | GPIO direction: `0` input, `1` output |

### UART

| Address | Register | Purpose |
|---:|---|---|
| `0xF1000000` | `TXDATA` | Byte to be transmitted |
| `0xF1000004` | `RXDATA` | Received byte |
| `0xF1000008` | `CONTROL` | UART control and status |

The firmware uses bit 0 of `CONTROL` to start a transmission, bit 1 to detect a received byte, and bit 2 to check whether the transmitter is ready.

## Firmware behavior

The firmware continuously executes the following sequence:

```text
Read P3-P0 and copy the value to P7-P4
                    |
                    v
Wait for one byte through UART RX
                    |
                    v
Send the same byte through UART TX
                    |
                    +----------------------> repeat
```

### GPIO configuration

The four upper pins are configured as outputs. The four lower pins remain as inputs.

```asm
lw  t0, GPIO_DATADIR(s0)
ori t0, t0, 0xF0
sw  t0, GPIO_DATADIR(s0)
```

```text
P7 P6 P5 P4  P3 P2 P1 P0
 1  1  1  1   0  0  0  0
   outputs        inputs
```

### GPIO echo

The value read from `P3-P0` is shifted to `P7-P4` and written to `DATAOUT`.

```asm
_loop:
    lw   t0, GPIO_DATAIN(s0)
    slli t0, t0, 4
    sw   t0, GPIO_DATAOUT(s0)
```

For example:

```text
P3-P0 = 0xA  ->  P7-P4 = 0xA
DATAIN = 0x0A  ->  DATAOUT = 0xA0
```

### UART reception

The firmware waits until `RXDONE` is set and then reads the received byte from `RXDATA`.

```asm
_check_rxdone:
    lw   t0, UART_CONTROL(s1)
    andi t0, t0, UART_CONTROL_RXDONE
    beq  t0, zero, _check_rxdone

    sw zero, UART_CONTROL(s1)
    lw t1, UART_RXDATA(s1)
```

### UART transmission

The firmware waits until `TXDONE` is set, writes the received byte to `TXDATA`, and starts the transmission.

```asm
_check_txdone:
    lw   t0, UART_CONTROL(s1)
    andi t0, t0, UART_CONTROL_TXDONE
    beq  t0, zero, _check_txdone

    sw  t1, UART_TXDATA(s1)
    lw  t1, UART_CONTROL(s1)
    ori t1, t1, UART_CONTROL_TRANSMIT
    sw  t1, UART_CONTROL(s1)

    j _loop
```

## Testbench requirements

The testbench must apply known GPIO and UART inputs and compare them with the corresponding outputs. The testbench implementation is part of each project and is not supplied with this firmware.

At minimum, the simulation must demonstrate:

| Test | Stimulus | Expected response |
|---|---|---|
| GPIO | Apply `0xA` to `P3-P0` | Observe `0xA` on `P7-P4` (`DATAOUT = 0xA0`) |
| UART | Send `0x30` through UART RX | Receive `0x30` through UART TX |

The first GPIO stimulus must be present before the firmware performs its GPIO read. After writing the GPIO output, the firmware waits for a UART byte. A new GPIO value is processed only after the UART echo completes and the loop restarts.

The testbench should include a timeout and report a clear failure if an expected response is not produced.

## Expected evidence

The simulation log must clearly show that both comparisons passed. For example:

```text
[PASS] GPIO: P3-P0 = 0xA, P7-P4 = 0xA
[PASS] UART: RX = 0x30, TX = 0x30
[PASS] GPIO and UART firmware test completed successfully
```

The waveform must show the same behavior:

- the value applied to `P3-P0` and the corresponding value produced on `P7-P4`;
- the byte sent to UART RX and the same byte returned through UART TX;
- clock and reset during the test.

Signal names may vary between projects, but the input and output behavior must remain equivalent.
