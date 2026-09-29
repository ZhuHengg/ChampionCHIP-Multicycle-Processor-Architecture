"""Run from any directory: python run_tests.py [--iverilog PATH] [--vvp PATH].

Builds into ignored chip-inventor/sim/organiser. For every top
(hdl.v = the ChipInventor canvas top, rtl/top.v): the official
Stage 3 GPIO/UART test firmware (FIRMWARE 4, loaded verbatim from
external/CCX_Malaysia_Edition_Stage_3/RVBL-GPIO-UART-Test-Firmware),
checked against that folder's own minimum test: P3-0 = 0xA -> P7-4 = 0xA,
and UART RX 0x30 -> TX 0x30. The design files are used exactly as checked
in - no ROM swapping.
"""
import argparse
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
CHIP = HERE.parent


def imem_instance(top_file):
    """Instance name of imem in the top module (differs per canvas export)."""
    text = top_file.read_text(encoding='utf-8')
    return re.search(r'^\s*imem\b\s*(?:#\(.*?\)\s*)?(\w+)\s*\(', text, re.M | re.S).group(1)


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument('--iverilog', default='iverilog')
    parser.add_argument('--vvp', default='vvp')
    args = parser.parse_args()
    scratch = CHIP / 'sim/organiser'
    scratch.mkdir(parents=True, exist_ok=True)

    def run(name, sources, defines=()):
        out = scratch / (name + '.vvp')
        subprocess.run([args.iverilog, '-g2012', '-s', 'testbench', *defines, '-o', str(out),
                        *map(str, sources)], check=True, cwd=scratch)
        result = subprocess.run([args.vvp, str(out)], check=True, cwd=scratch,
                                capture_output=True, text=True)
        print(name + ':\n' + result.stdout)
        if 'PASS: GPIO and UART firmware test completed successfully' not in result.stdout:
            raise RuntimeError(name + ' failed')
        if 'FAIL' in result.stdout:
            raise RuntimeError(name + ' failed')

    tops = ['hdl.v', 'rtl/top.v']
    for rel in [t for t in tops if (CHIP / t).exists()]:
        top = CHIP / rel
        tag = rel.replace('/', '_').replace('.v', '')
        run(tag + '_organiser', [top, HERE/'testbench.v'],
            ['-DIMEM_INST=' + imem_instance(top)])


if __name__ == '__main__':
    main()
