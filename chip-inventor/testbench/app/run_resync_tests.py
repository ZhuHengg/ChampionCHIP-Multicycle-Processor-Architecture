"""Run byte-level UART fault injection against both application RTL designs.

No golden Charger model generates expectations. UART runs at production speed.
Only inter-byte timeout cases accelerate the timer divider by 100x.
"""
import argparse
from pathlib import Path
import subprocess
from golden import Meter, encode_frame, corrupt, record_bytes, RX_TIMEOUT_MS
from run_tests import imem_instance

ROOT = Path(__file__).resolve().parents[2]


def send_wire(data):
    return '\n'.join(f"send_byte(8'h{byte:02x});" for byte in data) + '\nrepeat (1500) @(negedge clk);\n'


def report(energy, flags, frames):
    data = record_bytes(energy, flags, frames)
    return '\n'.join(f"emu_r({n}, 32'h{int.from_bytes(data[i:i+n], 'little'):08x});"
                     for i, n in [(0, 4), (4, 2), (6, 2)])


START = "emu_begin; emu_d(8'hf0); emu_i(2); emu_o(8'h20, 1);\n"


def finish(energy, flags, count):
    return "emu_o(8'h30, 2); emu_i(0); emu_o(0, 0);\n" + report(energy, flags, count)


def cases():
    m = Meter()
    frames = [m.frame(2300, 160, 5000) for _ in range(4)]
    encoded = [encode_frame(f) for f in frames]
    base = START + send_wire(encoded[0]) + "emu_o(8'h30, 2);\n"
    out = {}
    for i in range(1, 10):
        damaged = encoded[1][:i] + encoded[1][i+1:]
        out[f'dropped_body_byte_{i}'] = (False, base + send_wire(damaged) +
            send_wire(encoded[2]) + finish(736000, 0x40, 2))
    out['inserted_byte'] = (False, base + send_wire(encoded[1][:-1]+b'\x55\x7e') +
                           send_wire(encoded[2]) + finish(736000, 0x40, 2))
    out['shared_marker'] = (False, base + send_wire(encoded[1][:-1]+encoded[2]) + finish(1104000, 0, 3))
    out['noise'] = (False, START + send_wire(b'\x00\xff\x55\x7d') +
                    send_wire(b'\x7e\x7e'+encoded[0]) + finish(368000, 0, 1))
    for name, suffix in [('invalid_escape', b'\x7d\x00'), ('dangling_escape', b'\x7d\x7e')]:
        out[name] = (False, base + send_wire(encoded[1][:4]+suffix) +
                     send_wire(encoded[2]) + finish(736000, 0x40, 2))
    # Partial timeout: deadline minus one / deadline; late tails cannot complete a frame.
    partial = base + send_wire(encoded[1][:5]) + f'''
wait (dut.meter_timer_inst.rx_age_ms == {RX_TIMEOUT_MS - 1});
if (pins_o !== 8'h30) $fatal(1, "partial timeout changed output early");
wait (dut.meter_timer_inst.rx_age_ms == {RX_TIMEOUT_MS});
repeat (1500) @(negedge clk);
'''
    partial += send_wire(encoded[1][5:-1]) + send_wire(encoded[2]) + finish(736000, 0x40, 2)
    out['partial_timeout'] = (True, partial)
    # Completing after the timeout deadline without a new marker must NOT bill the old frame.
    out['late_tail'] = (True, base + send_wire(encoded[1][:-1]) + f'''
wait (dut.meter_timer_inst.rx_age_ms == {RX_TIMEOUT_MS});
repeat (1500) @(negedge clk);
''' + send_wire(encoded[1][-1:]) + send_wire(encoded[2]) + finish(736000, 0x40, 2))
    m = Meter(0x7D)
    escaped = START
    for _ in range(2):
        escaped += send_wire(encode_frame(m.frame(0x7D7E, 0x7E, 5000)))
    out['escaped_data_and_sequence'] = (False, escaped + finish(2*0x7D7E*0x7E, 0, 2))
    m = Meter(254)
    wrap = START
    for _ in range(3):
        wrap += send_wire(encode_frame(m.frame(2300, 160, 5000)))
    out['sequence_wrap'] = (False, wrap + finish(1104000, 0, 3))
    out['duplicate_recovery'] = (False, base + send_wire(encoded[0])+send_wire(encoded[1])+finish(736000, 0, 2))
    # Two replay errors latch FAULT; valid framed data must never clear it.
    fault = base + send_wire(encoded[0])+send_wire(encoded[0])+"emu_o(8'h80, 4);\n"
    fault += report(368000, 0x44, 1) + '\n' + send_wire(encoded[1])+"emu_o(8'h80, 4);\n"
    out['fault_stays_latched'] = (False, fault)
    for v in range(2070, 65536):
        frame = Meter().frame(v, 100, 5000)
        if 0x7E in frame[-2:] or 0x7D in frame[-2:]:
            out['escaped_crc'] = (False, START + send_wire(encode_frame(frame)) + finish(v*100, 0, 1))
            break
    # Consume the first session's report, then check a second session without
    # sending a second report (the emulator's receive window is eight bytes).
    again = base + send_wire(encoded[1][:5]) + "emu_i(0); emu_o(0, 0);\n"
    again += report(368000, 0, 1) + "\nemu_i(2); emu_o(8'h20, 1);\n"
    again += send_wire(encoded[1][5:]) + "emu_o(8'h20, 1);\n"
    again += send_wire(encoded[0]) + "emu_o(8'h30, 2);\n"
    out['new_session_reset'] = (False, again)
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--iverilog', default='iverilog')
    p.add_argument('--vvp', default='vvp')
    p.add_argument('--case', action='append', dest='names')
    p.add_argument('--top', action='append', dest='tops')
    a = p.parse_args()
    total = 0
    for rel in a.tops or ['hdl.v', 'rtl/top.v']:
        for name, (accelerate, body) in cases().items():
            if a.names and name not in a.names:
                continue
            work = ROOT/'sim/app'/('resync_'+rel.replace('/', '_')+'_'+name)
            work.mkdir(parents=True, exist_ok=True)
            (work/'scenario.vh').write_text(body+'\nemu_end;\n', encoding='utf-8')
            exe = work/'test.vvp'
            command = [a.iverilog, '-g2012', '-s', 'testbench', '-I', str(work),
                       '-DNO_VCD', '-DEMU_GAP=1500', '-DTB_TIMEOUT_NS=2000000000',
                       f'-DIMEM_INST={imem_instance(ROOT/rel)}', '-o', str(exe),
                       str(ROOT/rel), str(ROOT/'testbench/app/tb_app.v')]
            if accelerate:
                command.insert(1, '-DWATCHDOG_TIMER_HZ=200000')
            subprocess.run(command, check=True, capture_output=True)
            result = subprocess.run([a.vvp, str(exe)], capture_output=True, text=True, timeout=180)
            log = result.stdout+result.stderr
            (work/'run.log').write_text(log, encoding='utf-8')
            if result.returncode or 'SCENARIO RESULT: PASS' not in log or '[error]' in log or '[tb] FAIL' in log:
                raise RuntimeError(f'{rel} {name}:\n{log}')
            print(f'PASS {rel} {name}', flush=True)
            total += 1
    assert total, 'no tests selected'
    print(f'{total}/{total} UART resynchronization RTL runs passed')


if __name__ == '__main__':
    main()
