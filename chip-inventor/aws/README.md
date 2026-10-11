# Stage 4: AWS FPGA build

Runs the Stage 3 SoC (RV32I + Zmmul + Xicrc multicycle core, GPIO, UART,
EV-charger firmware) on the AWS FPGA through ChipInventor's **AWS FPGA** area.

Organiser sources: `docs/AWS Guide.pdf` and
[CCX_Malaysia_Edition_Stage_4](https://github.com/championchip-experience-community/CCX_Malaysia_Edition_Stage_4)
(`top.sv` copied verbatim from commit `b748304`).

## What gets uploaded

Vivado only sees the files in the AWS project. Nothing else from this repo
(`hdl.v`, `rtl/*.v`, `simulate.v`) is uploaded.

| File in AWS project | Source here | Notes |
|---|---|---|
| `cl_ports.vh` | provided by AWS | never edit |
| `top.sv` | [`top.sv`](top.sv) | organiser's file, **unchanged** |
| `riscv.sv` | [`riscv.sv`](riscv.sv) | generated; the whole processor in one file |

`riscv.sv` is **generated** from `rtl/top.v`, the file all Stage 3
testbenches ran against. The processor logic is identical; the only changes
are:

1. Our SoC module `top` is renamed `rvbl2_soc`, because the AWS wrapper is also
   `top`. Every other module gets an `rvbl2_` prefix.
2. The imem `FIRMWARE` default is set to the selected program. The repo default
   0 is the Stage 2 ROM.
3. `w_PC_Output` is added in the SoC, so top.sv's PC readback
   (`riscvtop.e_PROCESSOR.w_PC_Output`) works without editing top.sv.
4. The appended adapters are:
   - `RISCV`: ports `i_Clk`, `i_nRst`, `i_Rx_Serial`, `o_Tx_Serial`, `io_Pins`, matching the reference processor.
   - `Transmitter` / `Receiver`: thin wrappers around our `uart_tx` / `uart_rx`.

```
python chip-inventor/aws/gen_riscv_sv.py      # regenerate every image after any rtl/ change
```

Never hand-edit a generated `.sv`.

### Images

| Image | Firmware | Core clock | Use |
|---|---|---|---|
| `riscv.sv` | 5: EV charger app | 250 MHz | **primary**, first synthesis |
| `variants/riscv_fw5_50mhz.sv` | 5 | 50 MHz | if 250 MHz misses timing (WNS < 0) |
| `variants/riscv_fw4_250mhz.sv` | 4: organiser test firmware | 250 MHz | platform bring-up with the organiser's own `./emu` example |
| `variants/riscv_fw4_50mhz.sv` | 4 | 50 MHz | bring-up at the fallback clock |

To use a variant, paste its contents into the AWS project file named `riscv.sv`.

The 50 MHz images divide `clk_main_a0` by 5 with a `BUFGCE_DIV` clock
buffer, and our UART counts 434 clocks per bit. 5 x 434 = 2170, top.sv's
`p_CLKS_PER_BIT`, so both ends keep exactly the same baud rate. `top.sv`
does not change.

## Build and run (AWS Guide slides 2-14)

1. **AWS FPGA** (left bar) -> create `riscv.sv` and `top.sv` and paste the contents ->
   menu -> **Save Project** -> wait for "Project saved and synced successfully".
2. **Start Synthesis**. The VM starts; watch the Synthesis Logs panel. The guide's
   own run took about 40 min.
3. In the log:
   - **Copy** the JSON block with `FpgaImageId` (`afi-...`) and `FpgaImageGlobalId` (`agfi-...`).
   - **Check timing.** Search for `WNS` / `Timing` / `timing violation`. If WNS is negative, the
     250 MHz image cannot be trusted; switch to `variants/riscv_fw5_50mhz.sv`.
   - Save the full log for the report.
4. **Start FPGA** -> **Open Console**, then:
   ```bash
   aws ec2 describe-fpga-images --fpga-image-ids afi-XXXX --region us-east-1   # until "available" (about 15 min)
   sudo fpga-clear-local-image -S 0
   sudo fpga-load-local-image -S 0 -I agfi-XXXX
   ./axil_rw write 0 0x00 0 && sleep 1 && ./axil_rw write 0 0x00 1 && sleep 1
   ```
5. Run the application scenarios (copy `../emulator/run_scenarios.sh` and
   `../emulator/emu_commands.txt` next to `./emu`):
   ```bash
   bash run_scenarios.sh            # pass = >=1 [ok] and no [error] per line
   ```
   For the FIRMWARE 4 bring-up image, run the organiser's example instead:
   `./emu -d 0xF0 -i 0x02 -t1 0x30 -r1 0x30 -o 0x20`.
6. **Terminate VM** when done.

## Pre-upload verification

```
python chip-inventor/aws/run_aws_tests.py --clk all     # every scenario, both clocks
```

[`tb/tb_aws.sv`](tb/tb_aws.sv) simulates **the organiser's top.sv unchanged**
plus a generated image. It drives the OCL AXI-Lite port call for call like
`RVBL-Emulator/src/emu.c`:
- **Reset:** `fpga_init` writes direction then reset 1, 0, 1.
- **IN register:** read-modify-write.
- **TX:** write, then poll bit 8 until done.
- **RX:** the 64-bit window with a static pointer.
- **Errors:** the first `[error]` stops the run.
- **Timing:** the 50 ms sleep before every access.

Simulation time is compressed 100x for both the host delay and the firmware's
millisecond timer, so timeouts keep their real ratio to host pacing. UART bit
timing is not scaled.

AWS HDK files are replaced by simulation stubs in [`sim/stubs/`](sim/stubs).
**Never upload the stubs.**

## Assumptions and open items

- **Vivado was not run locally.** The first AWS synthesis is the first real Vivado
  elaboration. Risks:
  - the internal tristate on `io_Pins` (the organiser's reference uses the same pattern);
  - the cross-module PC reference (also from the reference design);
  - `BUFGCE_DIV` driven from `clk_main_a0` (50 MHz images only).
- **Timing at 250 MHz is unverified.** The 32x32 multiplier is single-cycle
  combinational (by design), and is the expected critical path. Read WNS from the log.
- **OUT bits whose direction is input** read as `z` from top.sv in simulation. The
  testbench reads them as 0, as on the FPGA. The organiser's example
  (`-i 0x02 ... -o 0x20`) shows the same behaviour.
- **Power-on:** `riscv_nreset` resets to 1, so the core runs from FPGA power-on
  state until the first reset. Always reset (step 4, or any `./emu` call) before
  trusting outputs.
