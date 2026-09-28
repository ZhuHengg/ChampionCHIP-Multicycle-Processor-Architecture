"""Build and run the crcb vs software CRC-16 cycle bench on rtl/top.v."""
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CHIP = HERE.parents[2]


def imem_instance(top_file):
    text = top_file.read_text(encoding='utf-8')
    return re.search(r'^\s*imem\b\s*(?:#\(.*?\)\s*)?(\w+)\s*\(', text, re.M | re.S).group(1)


def main():
    top = CHIP / 'rtl' / 'top.v'
    scratch = CHIP / 'sim' / 'crc_bench'
    scratch.mkdir(parents=True, exist_ok=True)

    inst = imem_instance(top)
    out = scratch / 'crc_bench.vvp'

    subprocess.run([
        'iverilog', '-g2012', '-s', 'testbench',
        f'-DIMEM_INST={inst}',
        '-o', str(out),
        str(top), str(HERE / 'tb_crc_bench.v'),
    ], check=True, cwd=scratch)

    result = subprocess.run(['vvp', str(out)], check=True, cwd=scratch,
                            capture_output=True, text=True)
    print(result.stdout)

    if 'ALL TESTS PASSED' in result.stdout and 'FAIL' not in result.stdout:
        print('PASS')
        return 0
    else:
        print('FAIL')
        return 1


if __name__ == '__main__':
    sys.exit(main())
