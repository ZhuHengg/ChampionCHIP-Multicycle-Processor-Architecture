"""Tests for the grid-aware EV charger golden model (spec SS7.4-7.6)."""
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from golden import (CHARGING, CONNECTED, FAULT, F_CP_ERROR, F_CRC_LOST,
                    F_ESTOP, F_GRID_HOLD, F_OVERCURRENT, GRID_HOLD, IDLE,
                    Charger, Meter, corrupt, crc16, record_bytes, restart_delay)


def test_crc16_check_value():
    assert crc16(b"123456789") == 0x29B1


def test_crc16_matches_legacy_chain():
    assert crc16(bytes.fromhex("1234567890ABCDEF")) == 0x1E82


def test_meter_frame_layout():
    f = Meter().frame(2300, 160, 5000)
    assert f[:6] == bytes.fromhex("FC08A0008813")
    assert f[6:] == crc16(f[:6], 0xFFFF).to_bytes(2, 'little')


def test_meter_chain_uses_previous_crc_field():
    m = Meter()
    f1 = m.frame(2300, 160, 5000)
    f2 = m.frame(2300, 160, 4990)
    first_crc = int.from_bytes(f1[6:], 'little')
    assert f2[6:] == crc16(f2[:6], first_crc).to_bytes(2, 'little')


def test_restart_delay_range():
    for seed in range(0x10000):
        assert 2 <= restart_delay(seed) <= 9


def test_restart_delay_spread_sequential_ids():
    buckets = [0] * 8
    for cid in range(10000):
        buckets[restart_delay(0x1D0F, cid) - 2] += 1
    assert buckets == [1250] * 8


def test_restart_delay_spread_events():
    random.seed(1)
    buckets = [0] * 8
    for _ in range(10000):
        buckets[restart_delay(random.randrange(0x10000)) - 2] += 1
    assert all(1100 <= b <= 1400 for b in buckets), buckets


def test_normal_session():
    c, m = Charger(), Meter()
    for pins, exp in ((0, 0x00), (1, 0x20), (2, 0x30)):
        c.set_inputs(pins)
        assert c.out == exp
    c.rx_frame(m.frame(2300, 160, 5000))
    c.rx_frame(m.frame(2300, 160, 5000))
    for pins, exp in ((1, 0x20), (0, 0x00)):
        c.set_inputs(pins)
        assert c.out == exp
    assert c.tx == list(record_bytes(736000, 0x00, 2))


def test_cp_c_from_idle_settles_to_charging():
    c = Charger()
    c.set_inputs(2)
    assert c.state == CHARGING


def test_boot_with_stale_inputs():
    c = Charger()
    c.set_inputs(0x02)
    assert c.out == 0x30


def test_ventilation_refused_and_stops_charging():
    c = Charger()
    c.set_inputs(1)
    c.set_inputs(3)
    assert c.state == CONNECTED
    c.set_inputs(2)
    assert c.state == CHARGING
    c.set_inputs(3)
    assert c.state == CONNECTED


def test_cp_error_and_invalid_codes_fault():
    for cp in (4, 5, 6, 7):
        c = Charger()
        c.set_inputs(1)
        c.set_inputs(cp)
        assert c.state == FAULT, cp
        assert c.flags & F_CP_ERROR, cp
        assert len(c.tx) == 8, cp


def test_estop_latch():
    c, m = Charger(), Meter()
    c.set_inputs(1)
    c.set_inputs(2)
    c.rx_frame(m.frame(2300, 160, 5000))
    c.set_inputs(0x0A)
    assert c.state == FAULT and c.flags & F_ESTOP
    assert len(c.tx) == 8
    c.set_inputs(0x02)
    assert c.state == FAULT
    c.set_inputs(0x08)
    assert c.state == FAULT
    c.set_inputs(0x00)
    assert c.state == IDLE
    assert len(c.tx) == 8


def test_corrupted_frame_resyncs():
    c, m = Charger(), Meter()
    c.set_inputs(1)
    c.set_inputs(2)
    c.rx_frame(m.frame(2300, 160, 5000))
    c.rx_frame(corrupt(m.frame(2300, 160, 5000)))
    c.rx_frame(m.frame(2300, 160, 5000))
    assert c.frames == 2
    assert c.state == CHARGING


def test_dropped_frame_costs_one_frame():
    c, m = Charger(), Meter()
    c.set_inputs(1)
    c.set_inputs(2)
    c.rx_frame(m.frame(2300, 160, 5000))
    m.frame(2300, 160, 5000)                  # generated, never delivered
    c.rx_frame(m.frame(2300, 160, 5000))      # rejected: chain skipped
    assert c.frames == 1
    c.rx_frame(m.frame(2300, 160, 5000))      # accepted again
    assert c.frames == 2
    assert c.state == CHARGING


def test_two_bad_frames_fault():
    c, m = Charger(), Meter()
    c.set_inputs(1)
    c.set_inputs(2)
    c.rx_frame(corrupt(m.frame(2300, 160, 5000)))
    c.rx_frame(corrupt(m.frame(2300, 160, 5000)))
    assert c.state == FAULT
    assert c.flags & F_CRC_LOST


def test_replayed_frame_faults():
    c, m = Charger(), Meter()
    c.set_inputs(1)
    c.set_inputs(2)
    f1 = m.frame(2300, 160, 5000)
    f2 = m.frame(2300, 160, 5000)
    c.rx_frame(f1)
    c.rx_frame(f2)
    c.rx_frame(f1)                            # replay -> rejected
    c.rx_frame(m.frame(2300, 160, 5000))      # chain broken -> rejected
    assert c.state == FAULT
    assert c.flags & F_CRC_LOST


def test_fault_sends_no_second_record():
    c, m = Charger(), Meter()
    c.set_inputs(1)
    c.set_inputs(2)
    c.rx_frame(corrupt(m.frame(2300, 160, 5000)))
    c.rx_frame(corrupt(m.frame(2300, 160, 5000)))
    assert c.state == FAULT and len(c.tx) == 8
    for _ in range(4):
        c.rx_frame(corrupt(m.frame(2300, 160, 5000)))
    assert len(c.tx) == 8


def test_overcurrent_boundary():
    c, m = Charger(), Meter()
    c.set_inputs(1)
    c.set_inputs(2)
    c.rx_frame(m.frame(2070, 320, 4950))      # exactly on every limit -> billed
    assert c.energy == 662400
    assert c.state == CHARGING
    c.rx_frame(m.frame(2300, 321, 5000))      # I > I_MAX
    assert c.state == FAULT
    assert c.flags & F_OVERCURRENT


def test_grid_hold_restart_exact_frame():
    c, m = Charger(), Meter()
    c.set_inputs(1)
    c.set_inputs(2)
    c.rx_frame(m.frame(2300, 160, 5000))
    billed = c.energy

    trigger = m.frame(2300, 160, 4920)        # F < F_LOW -> GRID_HOLD
    c.rx_frame(trigger)
    assert c.state == GRID_HOLD
    assert c.flags & F_GRID_HOLD
    assert c.delay == restart_delay(int.from_bytes(trigger[6:], 'little'))

    c.rx_frame(m.frame(2300, 160, 4940))      # still unhealthy -> hold resets
    assert c.hold == 0
    assert c.state == GRID_HOLD

    delay = c.delay
    for n in range(1, delay + 1):
        c.rx_frame(m.frame(2070, 160, 4950))
        expected = CHARGING if n == delay else GRID_HOLD
        assert c.state == expected, (n, delay)
    assert c.energy == billed                 # no hold frame is billed


def test_frames_saturate_at_255():
    c, m = Charger(), Meter()
    c.set_inputs(1)
    c.set_inputs(2)
    for _ in range(300):
        c.rx_frame(m.frame(2300, 160, 5000))
    assert c.frames == 255


def test_energy_wraps_mod_2_32():
    # The plan's literal (65535, 65535, 5000) trips over-current (I > I_MAX =
    # 320) and faults before billing, so wrap is driven with the largest
    # billable frame instead: V = 65535, I = I_MAX.
    c, m = Charger(), Meter()
    c.set_inputs(1)
    c.set_inputs(2)
    total = 0
    while total <= 2 ** 32:
        c.rx_frame(m.frame(65535, 320, 5000))
        total += 65535 * 320
    assert c.state == CHARGING
    assert c.energy == total % 2 ** 32
    assert c.energy < total                   # proves it actually wrapped
