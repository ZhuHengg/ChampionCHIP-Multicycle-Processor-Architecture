"""Build application artifacts and synchronize ROMs without requiring make.

python firmware/scripts/build.py --tool-prefix /path/to/riscv-none-elf-
The prefix may also be riscv32-unknown-elf- or riscv64-unknown-elf- on PATH.
"""
import argparse
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tool-prefix', default='riscv-none-elf-')
    args = parser.parse_args()
    firmware = Path(__file__).resolve().parents[1]
    root = firmware.parent
    build = firmware / 'build'
    build.mkdir(exist_ok=True)

    def run(tool, *argv):
        return subprocess.run([args.tool_prefix + tool, *map(str, argv)],
                              check=True, capture_output=True).stdout

    run('as', '-march=rv32i_zmmul', '-mabi=ilp32', firmware/'src/main.s',
        '-o', build/'main.o')
    run('ld', '-m', 'elf32lriscv', '-T', firmware/'bsp/custom.ld',
        build/'main.o', '-o', build/'firmware.elf')
    run('objcopy', '-O', 'binary', build/'firmware.elf', build/'firmware.bin')
    (build/'firmware.dmp').write_bytes(run('objdump', '-D', build/'firmware.elf'))
    binary = (build/'firmware.bin').read_bytes()
    assert len(binary) % 4 == 0 and len(binary) <= 4096, 'application exceeds ROM'
    lines = [f"32'h{0x400000+i:08X}: r_Instruction = 32'h{int.from_bytes(binary[i:i+4], 'little'):08X};"
             for i in range(0, len(binary), 4)]
    (build/'firmware.txt').write_text('\n'.join(lines)+'\n', encoding='utf-8')
    subprocess.run([sys.executable, str(root/'testbench/gen_imem.py')], check=True)
    print(f'Built {len(binary)//4} application instruction words; synchronized both tops.')


if __name__ == '__main__':
    main()
