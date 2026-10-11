"""Run the Stage 3 scenarios through the organiser's top.sv + our riscv.sv.

    python chip-inventor/aws/run_aws_tests.py [--clk 250|50|all]
        [--axi-delay-ms 50] [--time-scale 100] [--scenario NAME]... [-j N] [--vcd]

By default, every scenario runs on aws/tb/tb_aws.sv, which drives the real top.sv over
AXI-Lite like RVBL-Emulator's emu.c, including the 50 ms sleep
before each AXI access (scaled with the firmware's millisecond timer, see
tb_aws.sv). H* scenarios use FIRMWARE 4 (the organiser's test firmware), S*
use FIRMWARE 5 (our application). The images are the committed outputs of
gen_riscv_sv.py; regenerate them first if rtl/ changed.

--init-direction 0xF0 models an application-specific host initialization fix;
it does not modify the real emulator. --trace-rx records startup state/pins and
each received UART byte in run.log.

Build output goes to chip-inventor/sim/aws/[<tag>_]<clk>_<scenario>/ (ignored).
Exits non-zero if any scenario does not behave as expected.
"""
import argparse
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
CHIP = HERE.parent
sys.path.insert(0, str(CHIP / 'testbench/app'))

from scenarios import SCENARIOS  # noqa: E402
from run_tests import judge  # noqa: E402  (same PASS/expected-FAIL rules as Stage 3)

STUBS = HERE / 'sim/stubs'
IMAGES = {  # (firmware, core MHz) -> riscv.sv image
    (5, 250): HERE / 'riscv.sv',
    (5, 50): HERE / 'variants/riscv_fw5_50mhz.sv',
    (4, 250): HERE / 'variants/riscv_fw4_250mhz.sv',
    (4, 50): HERE / 'variants/riscv_fw4_50mhz.sv',
}


def run_one(args, mhz, name):
    s = SCENARIOS[name]
    image = IMAGES.get((s.firmware, mhz))
    if image is None:
        return mhz, name, False, f'no image for FIRMWARE {s.firmware}', ''
    tag = f'{args.tag}_' if args.tag else ''
    work = CHIP / 'sim/aws' / f'{tag}{mhz}mhz_{name}'
    work.mkdir(parents=True, exist_ok=True)
    (work / 'scenario.vh').write_text(s.to_vh(), encoding='utf-8')
    defines = [f'-DCORE_DIV={250 // mhz}', f'-DPRESET_IN={s.preset_in}',
               f'-DAXI_DELAY_MS={args.axi_delay_ms}', f'-DTIME_SCALE={args.time_scale}',
               f'-DINIT_DIRECTION={args.init_direction}']
    if args.trace_rx:
        defines.append('-DTRACE_RX')
    if args.vcd:
        defines.append('-DVCD')
    vvp = work / 'aws.vvp'
    build = subprocess.run(
        [args.iverilog, '-g2012', '-s', 'tb_aws', '-I', str(work), '-I', str(STUBS),
         *defines, '-o', str(vvp),
         str(STUBS / 'BUFGCE_DIV.v'), str(STUBS / 'sh_ddr.sv'),
         str(HERE / 'top.sv'), str(image), str(HERE / 'tb/tb_aws.sv')],
        cwd=work, capture_output=True, text=True)
    if build.returncode:
        return mhz, name, False, 'compile error', build.stderr
    run = subprocess.run([args.vvp, str(vvp)], cwd=work, capture_output=True, text=True)
    out = run.stdout + run.stderr
    (work / 'run.log').write_text(out, encoding='utf-8')
    ok, why = judge(s, out)
    return mhz, name, ok, why, out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--iverilog', default='iverilog')
    ap.add_argument('--vvp', default='vvp')
    ap.add_argument('--clk', choices=['250', '50', 'all'], default='250')
    ap.add_argument('--axi-delay-ms', type=int, default=50,
                    help='emu.c DELAY_AXI in real ms (default 50, as shipped)')
    ap.add_argument('--time-scale', type=int, default=100)
    ap.add_argument('--scenario', action='append', dest='names')
    ap.add_argument('-j', '--jobs', type=int, default=4)
    ap.add_argument('--vcd', action='store_true')
    ap.add_argument('--trace-rx', action='store_true', help='trace UART bytes and startup GPIO/state changes')
    ap.add_argument('--init-direction', type=lambda value: int(value, 0), default=1,
                    help='host direction before reset release (default 0x01: stock emu; 0xF0: application fix)')
    ap.add_argument('--tag', default='', help='prefix for the sim/aws work directories')
    args = ap.parse_args()
    if not 0 <= args.init_direction <= 255:
        ap.error('--init-direction must be a byte (0..255)')

    names = args.names or list(SCENARIOS)
    for n in names:
        if n not in SCENARIOS:
            ap.error(f'unknown scenario {n!r}; have {", ".join(SCENARIOS)}')
    clocks = [250, 50] if args.clk == 'all' else [int(args.clk)]
    jobs = [(mhz, n) for mhz in clocks for n in names]

    print(f'pacing {args.axi_delay_ms} ms per AXI access, time scale 1/{args.time_scale}')
    results = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for mhz, name, ok, why, out in pool.map(lambda j: run_one(args, *j), jobs):
            print(f'{"PASS" if ok else "FAIL"} {mhz}MHz {name}: {why} ({SCENARIOS[name].title})')
            if not ok:
                tail = [l for l in out.strip().splitlines() if l.strip()][-10:]
                print('  ' + '\n  '.join(tail))
            results.append(ok)
    print(f'\n{sum(results)}/{len(results)} runs as expected')
    return 0 if all(results) else 1


if __name__ == '__main__':
    sys.exit(main())
