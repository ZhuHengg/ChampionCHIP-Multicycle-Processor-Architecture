"""RTL watchdog regressions on both flattened tops, using the real application ROM.

The timer unit test checks the production 20 MHz millisecond divider. SoC cases
accelerate only that divider by 100x, retaining the firmware's configured deadline.
Frame/report expectations do not use the Charger model.
"""
import argparse
from pathlib import Path
import subprocess
from golden import Meter, corrupt, record_bytes, encode_frame, METER_TIMEOUT_MS
from run_tests import imem_instance

ROOT = Path(__file__).resolve().parents[2]


def send(frame, raw=False):
    frame = frame if raw else encode_frame(frame)
    return '\n'.join(f"send_byte(8'h{b:02x});" for b in frame) + '\nrepeat (1500) @(negedge clk);'


def check(expression, label):
    return f'if (!({expression})) $fatal(1, "{label}");'


def record(energy, status, frames):
    data = record_bytes(energy, status, frames)
    return '\n'.join(f"emu_r({n}, 32'h{int.from_bytes(data[i:i+n], 'little'):08x});"
                     for i, n in [(0, 4), (4, 2), (6, 2)])


def cases():
    start = "emu_begin; emu_d(8'hf0); emu_i(8'h02); emu_o(8'h20, 1);"
    m = Meter()
    first = m.frame(2300, 160, 5000)
    second = m.frame(2300, 160, 5000)
    charging = start + '\n' + send(first) + "\nemu_o(8'h30, 2);"
    boundary = f'''wait (dut.meter_timer_inst.age_ms == {METER_TIMEOUT_MS - 1});
if (pins_o !== 8'h30 || rx_count != 0) $fatal(1, "early timeout");
wait (dut.meter_timer_inst.age_ms == {METER_TIMEOUT_MS});
repeat (2000) @(negedge clk);
emu_o(8'h80, 5);
'''
    out = {
        'silence_deadline': (200000, charging + '\n' + boundary + record(368000, 5, 1)),
        'no_initial_frame': (200000, start + f'''
repeat ({(METER_TIMEOUT_MS + 5) * 200}) @(negedge clk);
emu_o(8'h80, 5);
''' + record(0, 5, 0)),
        'partial_frame': (200000, charging + '\n' + send(encode_frame(second)[:7], raw=True) + '\n' + boundary + record(368000, 5, 1)),
        'corrupt_frame': (200000, charging + '\n' + send(corrupt(second)) + '\n' + boundary + record(368000, 5, 1)),
    }
    refresh = charging + '\nwait (dut.meter_timer_inst.age_ms == 350);\n' + send(second)
    refresh += '\n' + check('dut.meter_timer_inst.age_ms < 20', 'valid frame did not refresh timer')
    refresh += "\nrepeat (60000) @(negedge clk); emu_o(8'h30, 2);\n"
    refresh += boundary + record(736000, 5, 2)
    refresh += f'\nrepeat ({(METER_TIMEOUT_MS + 5) * 200}) @(negedge clk);\n' + send(m.frame(2300, 160, 5000))
    refresh += "\nemu_o(8'h80, 5); emu_i(8'h08); emu_o(8'h80, 5); emu_i(0); emu_o(0, 0);"
    refresh += "\nemu_i(2); emu_o(8'h20, 1);"
    out['refresh_and_latch'] = (200000, refresh)

    m = Meter(); first = m.frame(2300, 160, 5000); low = m.frame(2300, 160, 4900)
    out['hold_silence'] = (200000, start+'\n'+send(first)+'\n'+send(low)+f'''
emu_o(8'h60, 3);
wait (dut.meter_timer_inst.age_ms == {METER_TIMEOUT_MS});
repeat (2000) @(negedge clk); emu_o(8'h80, 5);
'''+record(368000, 0x85, 1))
    out['idle_and_reset'] = (200000, f'''emu_begin; emu_d(8'hf0);
repeat ({(METER_TIMEOUT_MS + 5) * 200}) @(negedge clk); emu_o(0, 0);
if (rx_count != 0) $fatal(1, "idle must not report");
emu_i(2); emu_o(8'h20, 1);
''' + send(first) + '''
emu_o(8'h30, 2);
@(negedge clk); rst = 1;
repeat (3) @(negedge clk);
if (pins_o[4] !== 0) $fatal(1, "reset must open contactor");
rst = 0;
repeat (1500) @(negedge clk); emu_o(8'h20, 1);
''')
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iverilog', default='iverilog')
    parser.add_argument('--vvp', default='vvp')
    args = parser.parse_args()
    unit = ROOT/'sim/app/watchdog_timer_unit'
    unit.mkdir(parents=True, exist_ok=True)
    exe = unit/'timer.vvp'
    subprocess.run([args.iverilog, '-g2012', '-s', 'testbench', '-o', str(exe),
                    str(ROOT/'rtl/meter_timer.v'), str(ROOT/'rtl/address_decoder.v'),
                    str(ROOT/'testbench/app/tb_meter_timer.v')], check=True)
    result = subprocess.run([args.vvp, str(exe)], check=True, capture_output=True, text=True)
    assert 'PASS meter timer' in result.stdout, result.stdout
    (unit/'run.log').write_text(result.stdout, encoding='utf-8')
    print(result.stdout.strip(), flush=True)
    total = 0
    for rel in ('hdl.v', 'rtl/top.v'):
        for name, (hz, body) in cases().items():
            work = ROOT/'sim/app'/('watchdog_'+rel.replace('/', '_')+'_'+name)
            work.mkdir(parents=True, exist_ok=True)
            (work/'scenario.vh').write_text(body+'\nemu_end;\n', encoding='utf-8')
            exe = work/'test.vvp'
            command = [args.iverilog, '-g2012', '-s', 'testbench', '-I', str(work),
                       '-DNO_VCD', '-DEMU_GAP=1000', '-DTB_TIMEOUT_NS=2000000000',
                       f'-DWATCHDOG_TIMER_HZ={hz}', f'-DIMEM_INST={imem_instance(ROOT/rel)}',
                       '-o', str(exe), str(ROOT/rel), str(ROOT/'testbench/app/tb_app.v')]
            subprocess.run(command, check=True, capture_output=True)
            result = subprocess.run([args.vvp, str(exe)], capture_output=True, text=True, timeout=180)
            log = result.stdout+result.stderr
            (work/'run.log').write_text(log, encoding='utf-8')
            if result.returncode or 'SCENARIO RESULT: PASS' not in log or '[error]' in log or '[tb] FAIL' in log:
                raise RuntimeError(f'{rel} {name}:\n{log}')
            print(f'PASS {rel} {name}', flush=True)
            total += 1
    print(f'{total}/{total} watchdog RTL runs passed')


if __name__ == '__main__':
    main()
