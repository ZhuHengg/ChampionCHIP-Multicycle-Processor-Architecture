"""Run from any directory: python run_tests.py [--iverilog PATH] [--vvp PATH].

Builds into ignored chip-inventor/sim/system. Then, for every top
(hdl.v = the ChipInventor canvas top, hdl_ref.v, rtl/top.v): the Stage 2 firmware check, and the full system test (UART + GPIO + MUL + CRC).
The system test selects FIRMWARE 3 in imem via defparam, so the design
files are used exactly as checked in - no ROM swapping.
"""
import argparse
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
CHIP = HERE.parents[1]


def imem_instance(top_file):
    """Instance name of imem in the top module (differs per canvas export)."""
    text = top_file.read_text(encoding='utf-8')
    return re.search(r'^\s*imem\b\s*(?:#\(.*?\)\s*)?(\w+)\s*\(', text, re.M | re.S).group(1)


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--iverilog', default='iverilog')
    parser.add_argument('--vvp', default='vvp')
    args = parser.parse_args()
    scratch = CHIP / 'sim/system'
    scratch.mkdir(parents=True, exist_ok=True)

    def run(name, sources, defines=()):
        out = scratch / (name + '.vvp')
        subprocess.run([args.iverilog, '-g2012', '-s', 'testbench', *defines, '-o', str(out),
                        *map(str, sources)], check=True, cwd=scratch)
        result = subprocess.run([args.vvp, str(out)], check=True, cwd=scratch,
                                capture_output=True, text=True)
        print(name + ':\n' + result.stdout)
        if 'ALL TESTS PASSED' not in result.stdout or 'FAIL' in result.stdout:
            raise RuntimeError(name + ' failed')


    tops = ['hdl.v', 'hdl_ref.v', 'rtl/top.v']
    for rel in [t for t in tops if (CHIP / t).exists()]:
        top = CHIP / rel
        tag = rel.replace('/', '_').replace('.v', '')
        run(tag + '_stage2', [top, CHIP/'testbench/testbench.v'])
        run(tag + '_system_system', [top, HERE/'tb_system.v'],
            ['-DIMEM_INST=' + imem_instance(top)])


if __name__ == '__main__':
    main()
