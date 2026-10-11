"""Behavioral boundary tests for meter freshness and latched timeout reports."""
import pytest
from golden import (Charger, Meter, corrupt, crc16, CONNECTED, CHARGING,
                    GRID_HOLD, IDLE, METER_TIMEOUT, METER_TIMEOUT_MS, encode_frame)


def charging():
    c, m = Charger(), Meter()
    c.set_inputs(2)
    c.rx_frame(m.frame(2300, 160, 5000))
    return c, m


def test_no_data_at_startup_times_out_with_contactor_open():
    c = Charger()
    c.set_inputs(2)
    assert c.state == CONNECTED and c.out == 0x20
    c.advance_ms(METER_TIMEOUT_MS - 1)
    assert c.state == CONNECTED
    c.advance_ms(1)
    assert c.state == METER_TIMEOUT and c.out == 0x80
    assert bytes(c.tx[:6]) == bytes([0, 0, 0, 0, 5, 0])
    assert int.from_bytes(bytes(c.tx[6:]), 'little') == crc16(c.tx[:6])


def test_silence_after_charging_latches_once():
    c, m = charging()
    c.advance_ms(METER_TIMEOUT_MS - 1)
    assert c.state == CHARGING
    c.advance_ms(1)
    assert c.state == METER_TIMEOUT and not c.out & 0x10
    report = c.tx[:]
    c.advance_ms(2**32)
    c.rx_frame(m.frame(2300, 160, 5000))
    c.rx_frame(corrupt(m.frame(2300, 160, 5000)))
    c.rx_frame(corrupt(m.frame(2300, 160, 5000)))
    c.set_inputs(2)
    assert c.state == METER_TIMEOUT and c.tx == report
    c.set_inputs(8)
    assert c.state == METER_TIMEOUT
    c.set_inputs(0)
    assert c.state == IDLE
    c.set_inputs(2)
    assert c.state == CONNECTED
    c.rx_frame(m.frame(2300, 160, 5000))
    assert c.state == CHARGING


def test_valid_frames_refresh_deadline():
    c, m = charging()
    for _ in range(5):
        c.advance_ms(METER_TIMEOUT_MS - 1)
        c.rx_frame(m.frame(2300, 160, 5000))
        assert c.state == CHARGING and c.age_ms == 0
    assert not c.tx


@pytest.mark.parametrize('kind', ['corrupt', 'partial'])
def test_invalid_or_partial_frame_does_not_refresh(kind):
    c, m = charging()
    c.advance_ms(METER_TIMEOUT_MS - 10)
    frame = m.frame(2300, 160, 5000)
    if kind == 'corrupt':
        c.rx_frame(corrupt(frame))
    else:
        for byte in encode_frame(frame)[:7]:
            c.rx_byte(byte)
    assert c.age_ms == METER_TIMEOUT_MS - 10
    c.advance_ms(10)
    assert c.state == METER_TIMEOUT


def test_idle_silence_never_reports():
    c = Charger()
    c.advance_ms(2**33)
    assert c.state == IDLE and not c.tx
    c.set_inputs(2)
    assert c.age_ms == 0 and c.state == CONNECTED


def test_grid_hold_silence_faults():
    c, m = charging()
    c.rx_frame(m.frame(2300, 160, 4900))
    assert c.state == GRID_HOLD
    c.advance_ms(METER_TIMEOUT_MS)
    assert c.state == METER_TIMEOUT and c.tx[4] == 0x85


@pytest.mark.parametrize('sample', [(2300, 160, 4900), (2000, 160, 5000), (2300, 321, 5000)])
def test_unhealthy_initial_measurement_never_closes_contactor(sample):
    c = Charger()
    c.set_inputs(2)
    c.rx_frame(Meter().frame(*sample))
    assert not c.out & 0x10


def test_freshness_required_again_after_unplug():
    c, m = charging()
    c.set_inputs(0)
    c.set_inputs(2)
    assert c.state == CONNECTED and not c.healthy
