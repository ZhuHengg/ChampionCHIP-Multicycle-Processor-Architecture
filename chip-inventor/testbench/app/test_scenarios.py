"""Tests for the scenario set: every expected value comes from the golden model."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from golden import Meter, restart_delay
from scenarios import APP_FIRMWARE, SCENARIOS


def app_scenarios():
    return {k: s for k, s in SCENARIOS.items() if s.firmware == APP_FIRMWARE}


def test_every_scenario_reads_exactly_8_bytes():
    # emu.c keeps one static byte pointer over a 64-bit window, so a command
    # may never read more than 8 bytes -- and our design sends exactly one
    # 8-byte record per session.
    for name, s in app_scenarios().items():
        assert s.read_bytes() == 8, (name, s.read_bytes())
        assert len(s.model.tx) == 8, (name, len(s.model.tx))


def test_s1_record():
    assert SCENARIOS['S1'].to_emu().endswith('-r4 0x000B3B00 -r2 0x0200 -r2 0xD05C')


def test_s2_hold_length():
    s = SCENARIOS['S2']
    emu = s.to_emu()
    m = Meter()
    m.frame(2300, 160, 5000)
    trigger = m.frame(2300, 160, 4920)
    delay = restart_delay(int.from_bytes(trigger[-2:], 'little'))
    # One -o 0x60 for the triggering frame, one for the unhealthy frame that
    # resets the count, then one per hold frame except the last (which
    # restarts charging).
    assert emu.count('-o 0x60') == delay + 1, (emu.count('-o 0x60'), delay)
    # The -o right after the last hold frame is back to CHARGING (the last two
    # -o options are the CONNECTED/IDLE unplug steps).
    ops = [o for o in s.ops if o[0] == 'o']
    assert ops[-3][1] == 0x30, ops[-3]
    assert '-r4 0x000B3B00 -r2 0x0280' in emu


def test_s3_record():
    assert '-r4 0x00167600 -r2 0x0440' in SCENARIOS['S3'].to_emu()


def test_s4_record():
    assert '-r4 0x00059D80 -r2 0x0144' in SCENARIOS['S4'].to_emu()


def test_s5_record():
    assert '-r4 0x00059D80 -r2 0x010C' in SCENARIOS['S5'].to_emu()


def test_s6_record():
    assert '-r4 0x00059D80 -r2 0x0100' in SCENARIOS['S6'].to_emu()


def test_s7_record():
    assert '-r4 0x000A1B80 -r2 0x0124' in SCENARIOS['S7'].to_emu()


def test_s8_s9_records():
    for name in ('S8', 'S9'):
        assert '-r4 0x00000000 -r2 0x0014' in SCENARIOS[name].to_emu(), name


def test_s10_record():
    assert '-r2 0x0244' in SCENARIOS['S10'].to_emu()


def test_s11_boots_with_contactor_open():
    s = SCENARIOS['S11']
    first_o = next(op for op in s.ops if op[0] == 'o')
    assert first_o[1] == 0x20
    assert s.preset_in == 0x02


def test_first_frame_emu_encoding():
    assert '-t4 0x08FC007E -t4 0x138800A0 -t4 0x7E7E33A9' in SCENARIOS['S1'].to_emu()


def test_s1x_streams():
    s = SCENARIOS['S1X']
    assert s.stream is True
    # Same record as S1: the stress variant must bill both frames.
    assert '-r4 0x000B3B00 -r2 0x0200' in s.to_emu()
