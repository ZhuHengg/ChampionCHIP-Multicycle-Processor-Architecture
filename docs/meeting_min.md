## Overview
Matheus outlined the roadmap and deliverables for the firmware/application stages of the competition and AWS FPGA integration; Pedro provided a practical walkthrough of the FPGA–software interface, emulator usage, and register-level I/O testing procedures. The team emphasized creating an application definition, developing firmware and a testbench, and preparing an AXI/HR5 (H5) adaptation so the top 10 teams can later complete full AWS FPGA deployments.

## Key decisions and deliverables
- Teams must define a concrete application context (examples suggested: drone control, financial/stock market processing, game) and list inputs, processing, and outputs.
- Each team must develop:
  - Firmware that implements the application logic running on the RISC-V (HiFive) processor.
  - A testbench/framework to simulate inputs and validate outputs locally before moving to the AWS FPGA emulator or real hardware.
  - An “emulator adaptation” (C code) that configures parameters and sends test data from a console terminal to the processor on the AWS FPGA — a required intermediate step prior to the final top-10 AWS FPGA submissions.
- The organizers (Matheus/Pedro) will provide:
  - A sample firmware and test samples (Matheus mentioned 10 samples) on GitHub.
  - An assembler, binary, and Makefile similar to what was used in Stage 2 to convert assembly into binaries for deployment.

## Application definition requirements (from Matheus)
- Specify the system context and processor responsibilities (what inputs the processor receives, what computations it performs, and what outputs it produces).
- Provide examples of inputs and outputs:
  - Drone example: Input — velocity/pitch; Processing — derive acceleration; Output — deceleration value or a flag signaling over-limit acceleration, or motor control commands.
  - Stock market example: Input — price ticks; Processing — compute mid-price/decision metric; Output — buy/sell decision or indicator.
- Aim for a balance between creativity and feasibility: choose an idea that is realistic to implement within the available time and resources.
- Teams should plan a presentation describing the application on competition day.

## Firmware & testbench expectations (from Matheus)
- Firmware must:
  - Run on the HiFive RISC-V core provided in the SoC.
  - Read inputs (e.g., UART, GPIO), perform required processing, and write outputs back (via UART/GPIO/AXI as appropriate).
- Testbench must:
  - Simulate inputs and validate outputs against expected results (the “echo”-style test is a recommended simple starting point).
  - Be developed by each team to verify their firmware behavior locally before AWS FPGA deployment.
- The provided firmware/test bench is only a starting point to help verify correctness — teams are responsible for their own testbench and firmware robustness.

## Emulator and AWS FPGA adaptation (from Matheus & Pedro)
- “Adapter”/C code: Teams must implement a small C-layer (referred to as the “emulator adaptation” or “adaptation C”) that sets parameters and sends data from a terminal/console to the processor running on the AWS FPGA.
- Purpose: to demonstrate how teams will change values and send test vectors to the HiFive core when running on the AWS FPGA/emulator; this is a required intermediate submission for all teams now, with the top 10 continuing to full AWS FPGA usage later.
- Pedro and Matheus will provide examples and documentation (including GitHub resources) on how to run the emulator and use the provided samples.

## FPGA architecture & interface details (from Pedro)
- Top-level elements inside the FPGA SoC:
  - HiFive (RISC-V) core
  - GPIO, UART, memories, firmware
  - An AXI-to-HiFive (AXI→H5) converter/wrapper that translates AXI transactions into signals/registers the HiFive core can use
- Software–hardware interface uses memory-mapped registers:
  - The emulator exposes registers that control directions and values of up to 8 GPIO pins via a 16-bit register: upper 8 bits define direction (1 = output, 0 = input), lower 8 bits define value.
  - Separate emulator registers are provided for writing inputs, reading outputs, TX write, and RX read.
  - RX FIFO is a 64-entry circular FIFO; Pedro recommended reading up to 8 elements for simplicity.
  - Reset behavior in emulator: toggling a reset bit (write 0 then 1) drives the SoC into normal or reset states as required.
- Typical I/O flow:
  - From shell: write data to emulator registers → emulator wrapper converts to AXI/HiFive IO → HiFive firmware reads registers and processes → firmware writes results back → emulator reads outputs and returns to user tools.

## Emulator and tooling options (from Pedro)
- Two main access tools were described:
  - A low-level AXI read/write tool (xa x i l-like) that writes directly to slots/address/value — precise control but requires encoding direction + value bits when manipulating GPIO.
  - A higher-level emulator GUI/tool that abstracts some details and makes batch testing and send/receive operations easier and quicker for iterative debugging.
- Suggested workflow:
  - Use the high-level emulator tool for quick, repeated functional tests and batching.
  - Use the lower-level register access tool when debugging tricky issues or verifying register states precisely.
- Best practice: when writing an input via emulator, remove/assert it appropriately after use so it does not remain asserted and interfere with subsequent tests.

## Test methodology & examples (from Pedro)
- Example test patterns:
  - Echo test: firmware reads inputs and writes them back unchanged to outputs. Testbench/emulator MUST verify input==output.
  - Basic GPIO toggles: set P0 high via emulator, expect the firmware to detect and set P1 high; read back confirmation.
  - UART flow: write to TX register, check data appears through RX reading.
- Important notes:
  - The emulator register format for GPIO requires explicitly setting direction bits (upper 8 bits) and value bits (lower 8 bits) if using the low-level tool. The emulator GUI can abstract these details.
  - The RX is a circular FIFO; track read position appropriately.
  - Reset operations should be carefully toggled (write 0 then 1) to return system to a known state.

## Immediate action items (who / what)
- All teams:
  - Choose and document an application definition (inputs, processing, outputs) that is feasible to implement.
  - Develop firmware for the HiFive core implementing that application.
  - Build a local testbench that simulates inputs and validates outputs (start with an Echo test to confirm basic I/O).
  - Implement the emulator adaptation C code to send test data and configure parameters for console-driven testing on AWS FPGA.
  - Use provided GitHub resources, assembler, Makefile, and the sample test vectors (Matheus mentioned ~10 samples) as references.
- Organizers (Matheus/Pedro):
  - Provide sample firmware, test samples, assembler/binary/Makefile on GitHub.
  - Share step-by-step tutorials and demos for emulator use and register access (Pedro to continue lecture/materials).

## Risks / open questions
- Teams must balance creativity and feasibility — overly ambitious application ideas may not finish in time.
- Clarification needed on exact format and number of test samples to be provided on GitHub (Matheus mentioned 10 samples; confirm availability and format).
- Ensure all teams understand the register bit-encoding for GPIO direction/value when using low-level tools; documentation and examples should be posted.
- Confirm whether any additional constraints or fixed peripherals must be used (e.g., strictly which UART/AXI slots or memory map offsets) — organizers to provide concrete memory map and address offsets in GitHub materials.

## Next steps and timeline reminders
- Immediate: teams prepare application definition, firmware, testbench, and emulator adaptation (C) using provided samples and Makefile.
- Organizers to post GitHub resources, binaries, and tutorials referenced in the call.
- Top 10 teams (after judging) will proceed to full AWS FPGA deployment and deeper integration using the emulator and final AWS flow.