"""Run the EV charger scenarios against the RTL through the ./emu model.

    python chip-inventor/testbench/app/run_tests.py
        [--iverilog PATH] [--vvp PATH] [--top REL]... [--scenario NAME]...

Defaults to every top (hdl.v = ChipInventor canvas export,
rtl/top.v) x every scenario in scenarios.SCENARIOS. Builds into the ignored
chip-inventor/sim/app/<toptag>_<scenario>/. Exits non-zero on any failure.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CHIP = HERE.parents[1]
sys.path.insert(0, str(HERE))

from scenarios import SCENARIOS  # noqa: E402

TOPS = ('hdl.v', 'rtl/top.v')


def imem_instance(top_file):
    """Instance name of imem in the top module (differs per canvas export)."""
    text = top_file.read_text(encoding='utf-8')
    return re.search(r'^\s*imem\b\s*(?:#\(.*?\)\s*)?(\w+)\s*\(', text, re.M | re.S).group(1)


def judge(scenario, out):
    """PASS/FAIL per the plan: an expect_fail scenario must fail with exactly
    one [error] and no harness-level [tb] FAIL."""
    errors = out.count('[error]')
    tb_fail = '[tb] FAIL' in out
    if scenario.expect_fail:
        if 'SCENARIO RESULT: FAIL' not in out:
            return False, 'expected a FAIL result'
        if errors != 1:
            return False, f'expected exactly one [error], saw {errors}'
        if tb_fail:
            return False, 'harness-level [tb] FAIL'
        return True, 'expected-FAIL'
    if 'SCENARIO RESULT: PASS' not in out:
        return False, 'no PASS result'
    if errors or tb_fail:
        return False, f'{errors} [error] line(s)' + (', [tb] FAIL' if tb_fail else '')
    return True, 'PASS'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iverilog', default='iverilog')
    parser.add_argument('--vvp', default='vvp')
    parser.add_argument('--top', action='append', dest='tops')
    parser.add_argument('--scenario', action='append', dest='names')
    args = parser.parse_args()

    tops = args.tops or [t for t in TOPS if (CHIP / t).exists()]
    names = args.names or list(SCENARIOS)
    for name in names:
        if name not in SCENARIOS:
            parser.error(f'unknown scenario {name!r}; have {", ".join(SCENARIOS)}')

    results = []
    for rel in tops:
        top = CHIP / rel
        tag = rel.replace('/', '_').replace('.v', '')
        for name in names:
            s = SCENARIOS[name]
            work = CHIP / 'sim/app' / f'{tag}_{name}'
            work.mkdir(parents=True, exist_ok=True)
            (work / 'scenario.vh').write_text(s.to_vh(), encoding='utf-8')

            defines = [f'-DIMEM_INST={imem_instance(top)}',
                       f'-DFIRMWARE_SEL={s.firmware}',
                       f'-DPRESET_IN={s.preset_in}']
            if s.stream:
                # No gap before a -t and none between its bytes: the meter
                # streams frames back to back.
                defines += ['-DEMU_T_GAP=0', '-DEMU_BYTE_GAP=0']

            vvp = work / 'app.vvp'
            build = subprocess.run(
                [args.iverilog, '-g2012', '-s', 'testbench', '-I', str(work),
                 *defines, '-o', str(vvp), str(top), str(HERE / 'tb_app.v')],
                cwd=work, capture_output=True, text=True)
            if build.returncode:
                print(f'FAIL {tag} {name}: compile error')
                print(build.stderr.strip())
                results.append((tag, name, False))
                continue

            run = subprocess.run([args.vvp, str(vvp)], cwd=work,
                                 capture_output=True, text=True)
            out = run.stdout + run.stderr
            (work / 'run.log').write_text(out, encoding='utf-8')
            ok, why = judge(s, out)
            print(f'{"PASS" if ok else "FAIL"} {tag} {name}: {why} '
                  f'({s.title})')
            if not ok:
                print('  ' + '\n  '.join(out.strip().splitlines()[-12:]))
            results.append((tag, name, ok))

    passed = sum(1 for *_, ok in results if ok)
    print(f'\n{passed}/{len(results)} runs as expected')
    return 0 if passed == len(results) else 1


if __name__ == '__main__':
    sys.exit(main())
