"""Export the RTL's own ./emu output for the frontend's emulator panel.

    python chip-inventor/testbench/app/export_emu_preview.py [--run]

For every application scenario (S1-S11, S1X) this pairs each ./emu option
with the line tb_app.v printed for it when the scenario ran on the RTL, and
tags it with the playback step it belongs to. Output:
chip-inventor/frontend/src/data/emuPreview.json.

--run first runs run_tests.py on hdl.v (no VCD). Without it, the existing
logs in chip-inventor/sim/app/hdl_<name>/run.log are used.

Refuses to export a log that does not match its scenario: every option must
have exactly one [ok] line carrying the same value, so a log left over from
an older firmware or protocol cannot reach the page.
"""
import argparse
import json
import re
import subprocess
import sys
from datetime import date
from pathlib import Path

HERE = Path(__file__).resolve().parent
CHIP = HERE.parents[1]
sys.path.insert(0, str(HERE))

import scenarios as sc  # noqa: E402
from golden import Charger  # noqa: E402

TOP = 'hdl.v'
OUT = CHIP / 'frontend/src/data/emuPreview.json'

# The line tb_app.v (and emu.c) prints for each option.
LINE = {
    'd': re.compile(r'^\[ok\] Written 0x([0-9A-Fa-f]+) to DIRECTION$'),
    'i': re.compile(r'^\[ok\] Written 0x([0-9A-Fa-f]+) to INPUT PINS$'),
    'o': re.compile(r'^\[ok\] Read 0x([0-9A-Fa-f]+) from OUTPUT PINS$'),
    't': re.compile(r'^\[ok\] Written 0x([0-9A-Fa-f]+) to UART RX$'),
    'r': re.compile(r'^\[ok\] Read 0x([0-9A-Fa-f]+) from UART TX$'),
}


def build_marked():
    """Rebuild the application scenarios, recording where each playback step
    starts in the op list. One step per -i, per frame() and per record(),
    matching buildPlayback() in the frontend; -o belongs to the step before."""
    def mark(kind, fn):
        def wrapped(self, *args, **kwargs):
            self.__dict__.setdefault('marks', []).append((kind, len(self.ops)))
            return fn(self, *args, **kwargs)
        return wrapped

    saved = sc.Scenario.i, sc.Scenario.frame, sc.Scenario.record
    sc.Scenario.i = mark('pins', saved[0])
    sc.Scenario.frame = mark('frame', saved[1])
    sc.Scenario.record = mark('record', saved[2])
    try:
        return sc._app()
    finally:
        sc.Scenario.i, sc.Scenario.frame, sc.Scenario.record = saved


def option_text(op):
    kind = op[0]
    if kind in ('d', 'i', 'o'):
        return f'-{kind} 0x{op[1]:02X}'
    return f'-{kind}{op[1]} 0x{op[2]:0{op[1] * 2}X}'


def export_one(s):
    log = CHIP / 'sim/app' / f'hdl_{s.name}' / 'run.log'
    if not log.exists():
        raise SystemExit(f'{s.name}: no log at {log}; run with --run')
    text = log.read_text(encoding='utf-8')
    if 'SCENARIO RESULT: PASS' not in text:
        raise SystemExit(f'{s.name}: log does not report PASS')
    lines = [ln.strip() for ln in text.splitlines() if ln.startswith(('[ok]', '[error]', '[tb]'))]
    if not lines or lines[0] != '[ok] RISC-V started!':
        raise SystemExit(f'{s.name}: log does not start with the reset line')
    lines = lines[1:]
    if len(lines) != len(s.ops):
        raise SystemExit(f'{s.name}: {len(s.ops)} options but {len(lines)} log lines (stale log?)')

    starts = [start for _, start in s.marks]
    ops = []
    for k, (op, line) in enumerate(zip(s.ops, lines)):
        kind = op[0]
        m = LINE[kind].match(line)
        value = op[1] if kind in ('d', 'i', 'o') else op[2]
        if not m or int(m.group(1), 16) != value:
            raise SystemExit(f'{s.name}: option {option_text(op)} got log line {line!r} (stale log?)')
        step = sum(1 for st in starts if st <= k) - 1     # -1 = before the first step
        ops.append({'kind': kind, 'n': op[1] if kind in ('t', 'r') else None,
                    'value': value, 'text': option_text(op), 'step': step, 'line': line})

    setup = None
    if s.preset_in:
        boot = Charger()
        boot.set_inputs(s.preset_in)
        setup = f'./emu -d 0xF0 -i 0x{s.preset_in:02X} -o 0x{boot.out:02X}'

    return {
        'title': s.title,
        'command': s.to_emu(),
        'setup': setup,
        'stream': s.stream,
        'steps': [kind for kind, _ in s.marks],
        'reset': '[ok] RISC-V started!',
        'ops': ops,
        'result': 'PASS',
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--run', action='store_true', help='run the RTL scenarios on hdl.v first')
    args = parser.parse_args()

    apps = build_marked()
    if args.run:
        cmd = [sys.executable, str(HERE / 'run_tests.py'), '--top', TOP, '--no-vcd']
        for name in apps:
            cmd += ['--scenario', name]
        if subprocess.run(cmd).returncode:
            raise SystemExit('RTL run failed; nothing exported')

    out = {
        'source': f'RTL simulation of chip-inventor/{TOP} under testbench/app/tb_app.v',
        'generated': date.today().isoformat(),
        'scenarios': {name: export_one(s) for name, s in apps.items()},
    }
    OUT.write_text(json.dumps(out, indent=1) + '\n', encoding='utf-8')
    print(f'wrote {len(out["scenarios"])} scenarios to {OUT}')


if __name__ == '__main__':
    main()
