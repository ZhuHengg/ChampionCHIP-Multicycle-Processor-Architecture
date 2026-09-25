# GPIO and UART Integration Status

**Prepared for:** Zhu Heng  
**Project:** ChampionCHIP Multicycle Processor  
**Target platform:** Chip Inventor

## Current Status

The `gpio.v` and `uart.v` modules have been added. The remaining work for integrating these peripherals into the Chip Inventor design is not yet complete.

| Module | Functionality |
| --- | --- |
| `gpio.v` | Provides eight bidirectional GPIO pins with data output, data input, and direction control registers. Each pin can be configured independently as an input or output. |
| `uart.v` | Provides a serial transmit/receive interface with transmit data, receive data, and control/status registers. The module depends on `uart_tx.v` and `uart_rx.v`. |

Both modules use a 32-bit processor-side data interface with byte write enables and registered read data.

## Remaining Work in Chip Inventor

1. Add the GPIO and UART blocks to the processor design, including the UART transmitter and receiver dependencies.
2. Connect the clock, reset, address, write data, byte write enables, and read/write control signals.
3. Complete the peripheral address decoding and connect the GPIO and UART read data to the processor's read-data selection logic.
4. Expose and assign the eight GPIO pins and the UART receive/transmit pins. Ensure that GPIO direction control is connected to the appropriate bidirectional I/O implementation.
5. Confirm that the UART clock and baud-rate parameters match the intended system configuration.
6. Verify the integrated design through simulation, including GPIO input/output operation and UART transmission/reception.
7. Run synthesis for the updated Chip Inventor design and review the resulting reports.

## Completion Criteria

The peripheral integration will be considered complete when the processor can access the GPIO and UART registers correctly, the external pins operate as intended, and the updated design passes integration simulation and synthesis checks.

The addition of the module files alone does not establish completion of the Chip Inventor integration or validation of the updated design.
