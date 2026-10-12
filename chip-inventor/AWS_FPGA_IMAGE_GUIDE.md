# AWS FPGA build, saved image, and hardware test guide

Updated: 12 October 2026

## Current status

Local simulation validation is complete. User-provided AWS console output
confirmed the image became **available** and was then **loaded** into slot 0
with status **ok**. Final timing review and application hardware tests remain
unfinished.

| Item | Recorded result |
|---|---|
| Local AWS simulation | 30/30 runs behaved as expected at both clock speeds |
| Image creation output | IDs returned; see below |
| Last image state | `available` |
| FPGA slot 0 | Correct AGFI reported `loaded`, status `ok` |
| Timing visible in screenshot | Intermediate WNS = -1.624 ns; TNS = -73.429 ns |
| Final timing report | Not yet checked |
| Host emulator rebuild | Not confirmed; `mv emu.new emu` failed because `emu.new` did not exist |
| Application hardware tests | Not yet run/confirmed |

The simulation used corrected host initialization (`0xF0`), a 400 ms UART
partial-frame timeout, and a 4000 ms meter watchdog. The remote host source
was inspected and its startup call used `0x01`. Instructions to correct and
rebuild it were provided, but successful installation is not yet confirmed.

## Save these image IDs

The build returned this output, labelled `20261012-115035`:

```json
{
  "FpgaImageId": "afi-0aaea91ea96d17262",
  "FpgaImageGlobalId": "agfi-044217b7d9c9655d9"
}
```

- **AFI (`afi-...`):** use this regional ID to query and manage the image.
- **AGFI (`agfi-...`):** use this global ID to load the image onto an FPGA.

Receiving IDs means the image-creation request produced identifiers. It does
not by itself prove the image is available, timing passed, or the application
works on hardware. Keep the source revision, clock variant, and full build log
with these IDs. The exact uploaded source revision/variant has not been
independently verified here.

## What the build screen means

The FPGA build turns Verilog into a physical configuration for the FPGA.
Synthesis builds and simplifies the logic; implementation places and routes
the circuit and checks timing. Image creation then prepares it for AWS loading.

| Screen or log item | Meaning |
|---|---|
| VM Online | The cloud build computer is running; this does not mean the application is running on an FPGA |
| Finished RTL Optimization Phase 1 | An initial logic-optimization phase completed |
| Netlist sorting complete | Circuit components and connections were organized for further processing |
| Analyzing Unisim elements | The tools are processing FPGA primitive instances; the number is not an error count |
| Preparing netlist for logic optimization | Another optimization phase is being prepared |
| CPU / elapsed / memory | Build-computer resource statistics, not the processor clock speed or FPGA memory usage |
| Nodes with overlaps | Routing-progress information; it is not by itself a failed-build message |
| VM Offline | The page reports the VM offline; this alone does not establish whether the build succeeded or failed |

If the display stops updating, save the log and inspect its final lines. Look
for a completion message, `ERROR`, a failure/termination message, and image IDs.
Do not infer success or failure from an intermediate message or the VM indicator
alone. Leave a running build's VM active until its outcome is established.

## Check whether this image is ready

Run these commands in the **AWS Linux console**, not Windows PowerShell.
The region used for this build's status check was `us-east-1`.

```bash
aws ec2 describe-fpga-images \
  --fpga-image-ids afi-0aaea91ea96d17262 \
  --region us-east-1 \
  --query 'FpgaImages[0].State'
```

| State | What to do |
|---|---|
| `pending` | AWS is still processing the image. Wait a few minutes and check again. Do not restart synthesis just because it is pending. |
| `available` | The image is ready to load; this does not replace timing review or hardware testing. |
| `failed` | Save the complete state output, including its message, and investigate the reason. |

To repeat the command in the console, press the up-arrow key, then Enter.
Processing time varies; receiving IDs is not the end of image preparation.

## Check the final timing report

At 250 MHz, a processor clock cycle lasts 4 ns. At 50 MHz, it lasts 20 ns.
Simulation alone does not establish whether physical FPGA paths meet these
deadlines.

- **WNS:** worst negative slack. A negative value indicates a setup-timing
  violation in the reported analysis.
- **TNS:** total negative slack, summarizing setup-timing violations.
- Zero or positive WNS is a passing result for that setup check, not proof that
  every timing/build check passed. Review the final timing report and constraints.

The screenshot showed **Intermediate Timing Summary: WNS = −1.624 ns**.
That was an intermediate routing result, not a final timing verdict. Find the
final implementation timing summary before deciding whether the build is usable.

If the final 250 MHz design fails timing, rebuild with
`aws/variants/riscv_fw5_50mhz.sv` copied into the AWS project's file named
`riscv.sv`. Keep the organiser's `top.sv`. A different build produces a new
image and new IDs; the IDs above continue to refer to the earlier build.

## Next time: reuse the saved image

**You normally do not need to rerun synthesis for the same design.**
An available image can be loaded again while it still exists, you have load
permission, and the FPGA instance/platform is compatible.

1. Start a compatible FPGA instance through the platform and open its console.
2. Ensure the image is `available` and review its saved final timing result.
3. When ready to replace the design in slot 0, load the saved image:

```bash
sudo fpga-load-local-image -S 0 -I agfi-044217b7d9c9655d9
```

4. Check the loaded image and slot status:

```bash
sudo fpga-describe-local-image -S 0
```

Confirm that the reported image matches the intended AGFI and the slot reports
it loaded. The SDK management tools must be installed/configured on the instance.

If a clean clear-and-load sequence is needed, the documented commands are:

```bash
sudo fpga-clear-local-image -S 0
sudo fpga-load-local-image -S 0 -I agfi-044217b7d9c9655d9
sudo fpga-describe-local-image -S 0
```

Clearing or reloading interrupts the current FPGA design and resets its state.
Do this when ready to start a fresh test. Reloading the image does not restore
an earlier charging session or its runtime data.

Restarting or replacing the VM does not, by itself, require new synthesis.
However, the platform's image-retention policy and account permissions still
apply. Keep separate copies of host scripts, source, and logs rather than
assuming files on a terminated VM will remain available.

## When synthesis must be rerun

Build a new image when the hardware configuration changes, for example:

- Changing processor/peripheral RTL.
- Changing this project's firmware embedded in instruction ROM.
- Switching from the 250 MHz processor image to the 50 MHz variant.
- Fixing implementation/timing problems that require a changed design.

Changing only the host emulator or a test script does not itself change the
FPGA image. Rebuild the host program when its source changes.

For a new ChipInventor build, use `aws/top.sv` and the selected generated image
as `riscv.sv`; `cl_ports.vh` is supplied by the platform. Save the project and
start synthesis. Never upload the simulation stubs in `aws/sim/stubs/`.

## Prepare the real host emulator

The stock emulator initializes direction to `0x01` before processor reset is
released. For the charger application, change the initial direction in
`fpga_init` to **`0xF0`**, then rebuild the host emulator.

The later command-line option `-d 0xF0` alone is too late: initialization has
already run. In our simulation, `0x01` left a pilot input undriven and caused a
false connection followed by an empty report. Starting with `0xF0` removed it.

### Remote source and rebuild progress

The source is on the ChipInventor VM at:

```text
/home/ubuntu/aws-fpga/sdk/userspace/emu.c
```

The supplied source output confirmed this call at line 157 inside `fpga_init`,
before `fpga_reset(pci)`:

```c
err = fpga_write_direction(pci, 0x01);
```

Change only that startup call to `0xF0`. Do not replace every `0x01` in the file.
The following commands are for the AWS Linux console:

```bash
cd /home/ubuntu/aws-fpga/sdk/userspace
cp -n emu.c emu.c.before-startup-fix
sed -i 's/fpga_write_direction(pci, 0x01)/fpga_write_direction(pci, 0xF0)/' emu.c
grep -n 'fpga_write_direction(pci,' emu.c
```

The console confirmed `include/fpga_pci.h`, `include/fpga_mgmt.h`,
`lib/libfpga_mgmt.a`, and `lib/libfpga_pci.a` exist. The proposed build command is:

```bash
gcc -Wall -O2 -I./include emu.c -L./lib -lfpga_mgmt -lfpga_pci -lpthread -o emu.new
```

**This build has not yet been confirmed successful.** The last installation
attempt reported `mv: cannot stat 'emu.new': No such file or directory`.
Run the compile command and inspect any errors. Only after successful compilation
and verifying `emu.new` exists, install it:

```bash
ls -l emu.new
cp -n emu emu.before-startup-fix
mv emu.new emu
```

This host-only change needs no FPGA synthesis or image reload.

### Reopen the file through ChipInventor

Open ChipInventor's AWS FPGA page and its FPGA Console once the VM is online.
If connected to the same VM with the source still present:

```bash
cd /home/ubuntu/aws-fpga/sdk/userspace
nano emu.c
```

In nano, Ctrl+O then Enter saves; Ctrl+X exits. To read without editing,
use `less emu.c` and press Q to exit.

ChipInventor file retention after VM termination has not been verified.
Save a separate copy of the remote source and logs before terminating it.
The saved FPGA image does not include this host C program.

**Repository backup scope:** the remote `emu.c`, its executable, and remote logs
have not been downloaded into this repository. This guide records the observed
source call and recovery instructions, not a complete backup of remote files.

## Run the application tests on the FPGA

After loading the charger image and preparing the host emulator, copy these
local files to the AWS host, beside the `emu` executable:

```text
chip-inventor/emulator/run_scenarios.sh
chip-inventor/emulator/emu_commands.txt
```

Enter that directory in the AWS console. To inspect commands without running
them:

```bash
bash run_scenarios.sh --dry-run
```

Then run the application scenarios and save the runner's output:

```bash
set -o pipefail
bash run_scenarios.sh 2>&1 | tee hardware-test.log
```

The runner prints PASS/FAIL per application scenario and a final total. It uses
the emulator's `[ok]` and `[error]` messages, because the documented emulator
exit-code behavior is unreliable. Passing scenarios are summarized; failing
ones include their output. This hardware runner is not identical to the local
simulation harness and does not independently perform every internal RTL check.

Save any detailed emulator output needed for the report as well. Confirm real
host pacing remains within the configured 400 ms byte-gap and 4000 ms
accepted-frame deadlines.

The optional organiser firmware-4 bring-up image uses a simpler GPIO/UART test:

```bash
./emu -d 0xF0 -i 0x02 -t1 0x30 -r1 0x30 -o 0x20
```

Use that command with the organiser test-firmware image, not the charger image.
Its purpose is to verify platform communication before running the charger.

## Local simulation is a separate test

The following command runs the virtual AWS setup on your computer. It does not
load an FPGA or run tests on AWS hardware. From `ChampionCHIP-latest`:

```powershell
$env:Path = "C:\Users\SHIYI\.cache\championchip-tools\iverilog\bin;$env:Path"
python chip-inventor/aws/run_aws_tests.py --clk all --init-direction 0xF0
```

The full local suite already completed with 30/30 expected results. H1 is a
deliberate negative harness test: detecting its intentionally incorrect expected
output counts as a pass. See
[validation evidence](testbench/app/evidence/stage4_timing_validation.log) and
[new change.md](new%20change.md).

## Evidence to keep

- Exact source commit/revision, selected clock variant, and uploaded files.
- Full synthesis/implementation log and final timing report.
- Image-creation JSON and final image-state output.
- Output confirming which AGFI was loaded into slot 0.
- Host-emulator initialization change and build details.
- Hardware test logs and any failure details.

Once work is finished and evidence is saved, terminate the VM according to the
platform workflow. A saved image can normally be reused later; VM lifetime and
image availability are separate concerns.

## References

- [Local AWS build instructions](aws/README.md)
- [Current Stage 4 handoff](HANDOFF_STAGE4_AWS_FPGA.md)
- [AWS FPGA image guide](https://github.com/aws/aws-fpga/blob/f2/hdk/docs/Amazon_FPGA_Images_Afis_Guide.md)
- [AWS FPGA management tools](https://github.com/aws/aws-fpga/blob/f2/sdk/userspace/fpga_mgmt_tools/README.md)
- [AWS DescribeFpgaImages API](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_DescribeFpgaImages.html)
