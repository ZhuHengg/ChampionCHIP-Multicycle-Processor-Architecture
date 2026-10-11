"""Fault injection for protocol v2, independent of the scenario DSL."""
import pytest
from golden import (Charger, Meter, encode_frame, crc16, corrupt, CHARGING,
                    FAULT, METER_TIMEOUT, F_CRC_LOST, transmit_options, RX_TIMEOUT_MS, METER_TIMEOUT_MS)


def wire(c, data):
    for byte in data:
        c.rx_byte(byte)


def setup():
    c, m = Charger(), Meter()
    c.set_inputs(2)
    c.rx_frame(m.frame(2300, 160, 5000))
    return c, m


@pytest.mark.parametrize('index', range(1, 10))
def test_each_dropped_body_byte_recovers_at_next_frame(index):
    c, m = setup()
    data = encode_frame(m.frame(2300, 160, 5000))
    wire(c, data[:index] + data[index+1:])
    assert c.frames == 1 and c.bad == 1
    c.rx_frame(m.frame(2300, 160, 5000))
    assert c.state == CHARGING and c.frames == 2 and c.bad == 0
    assert c.flags & F_CRC_LOST


@pytest.mark.parametrize('extra', [0, 0xFF, 0x55])
def test_inserted_byte_does_not_bill_a_valid_prefix(extra):
    c, m = setup()
    data = encode_frame(m.frame(2300, 160, 5000))
    wire(c, data[:-1] + bytes([extra, 0x7E]))
    assert c.frames == 1 and c.bad == 1
    c.rx_frame(m.frame(2300, 160, 5000))
    assert c.frames == 2 and c.state == CHARGING


def test_noise_and_empty_markers_are_harmless():
    c = Charger()
    wire(c, bytes([0, 0xFF, 0x7D, 0x55, 0x7E, 0x7E, 0x7E]))
    assert c.bad == 0 and not c.tx and not c.frames


def test_marker_and_escape_payload_sequence_and_crc():
    c = Charger(); c.set_inputs(2)
    m = Meter(sequence=0x7D)
    for _ in range(2):
        frame = m.frame(0x7D7E, 0x7E, 5000)
        encoded = encode_frame(frame)
        assert b'\x7d\x5e' in encoded and b'\x7d\x5d' in encoded
        assert 0x7E not in encoded[1:-1]
        wire(c, encoded)
    assert c.frames == 2 and c.state == CHARGING
    # Search a valid measurement whose CRC itself needs escaping.
    for v in range(2070, 65536):
        f = Meter().frame(v, 100, 5000)
        if 0x7E in f[-2:] or 0x7D in f[-2:]:
            other = Charger(); other.set_inputs(2); wire(other, encode_frame(f))
            assert other.frames == 1
            break
    else:
        pytest.fail('no escaped CRC test vector')


@pytest.mark.parametrize('tail', [b'\x7d\x00', b'\x7d\x7e'])
def test_malformed_escape_recovers(tail):
    c, m = setup()
    dropped = m.frame(2300, 160, 5000)
    wire(c, encode_frame(dropped)[:4] + tail)
    assert c.bad == 1
    c.rx_frame(m.frame(2300, 160, 5000))
    assert c.frames == 2 and c.state == CHARGING


def test_partial_timeout_boundary_and_tail_ignored():
    c, m = setup()
    data = encode_frame(m.frame(2300, 160, 5000))
    wire(c, data[:5])
    c.advance_ms(RX_TIMEOUT_MS - 1)
    assert c._active and c.bad == 0
    c.advance_ms(1)
    assert not c._active and c.bad == 1 and c.age_ms == RX_TIMEOUT_MS
    c.advance_ms(RX_TIMEOUT_MS)
    assert c.bad == 1             # counted once, not once per polling loop
    wire(c, data[5:-1])           # late body bytes cannot complete stale frame
    c.rx_frame(m.frame(2300, 160, 5000))
    assert c.frames == 2 and c.bad == 0


def test_received_bytes_refresh_only_partial_timer():
    c, m = setup()
    data = encode_frame(m.frame(2300, 160, 5000))
    for b in data[:-1]:
        c.advance_ms(40)
        c.rx_byte(b)
    assert c.age_ms == 400 and c.frames == 1
    c.rx_byte(data[-1])
    assert c.age_ms == 0 and c.frames == 2


def test_duplicate_does_not_refresh_watchdog():
    c = Charger(); c.set_inputs(2)
    f = Meter().frame(2300, 160, 5000)
    c.rx_frame(f); c.advance_ms(METER_TIMEOUT_MS - 10); c.rx_frame(f)
    assert c.age_ms == METER_TIMEOUT_MS - 10 and c.frames == 1
    c.advance_ms(10)
    assert c.state == METER_TIMEOUT


def test_sequence_wrap_and_reordered_frame():
    c = Charger(); c.set_inputs(2); m = Meter(254)
    old = m.frame(2300, 160, 5000)
    c.rx_frame(old)
    c.rx_frame(m.frame(2300, 160, 5000))
    c.rx_frame(m.frame(2300, 160, 5000))
    assert c.frames == 3 and c.flags == 0 and c.last_sequence == 0
    c.rx_frame(old)
    assert c.frames == 3 and c.bad == 1 and c.last_sequence == 0
    c.rx_frame(m.frame(2300, 160, 5000))
    assert c.frames == 4 and c.bad == 0


def test_sequence_is_crc_protected():
    c, m = setup()
    f = m.frame(2300, 160, 5000)
    c.rx_frame(bytes([f[0] ^ 1]) + f[1:])
    assert c.frames == 1 and c.bad == 1


def test_latched_fault_survives_parser_recovery():
    c, m = setup()
    for _ in range(2):
        c.rx_frame(corrupt(m.frame(2300, 160, 5000)))
    assert c.state == FAULT and len(c.tx) == 8
    record = c.tx[:]
    c.rx_frame(m.frame(2300, 160, 5000))
    assert c.bad == 0 and c.state == FAULT and c.out == 0x80 and c.tx == record


def test_single_shared_delimiter_and_missing_final_delimiter():
    c, m = setup()
    f1, f2 = [encode_frame(m.frame(2300, 160, 5000)) for _ in range(2)]
    wire(c, f1[:-1] + f2)
    assert c.frames == 3 and c.bad == 0


def test_sender_known_wire_vector():
    # Fixed expected bytes also cross-check the independent sender CRC routine.
    body = Meter().frame(2300, 160, 5000)
    assert encode_frame(body) == bytes.fromhex('7e 00 fc 08 a0 00 88 13 a9 33 7e')
    assert crc16(body[:7]) == 0x33A9


@pytest.mark.parametrize('delta, accepted', [(127, True), (128, False)])
def test_sequence_forward_window(delta, accepted):
    c, _ = setup()
    c.rx_frame(Meter(delta).frame(2300, 160, 5000))
    assert c.frames == (2 if accepted else 1)


def test_new_session_discards_partial_data_and_allows_sender_restart():
    c, m = setup()
    partial = encode_frame(m.frame(2300, 160, 5000))
    wire(c, partial[:5])
    c.set_inputs(0)
    c.set_inputs(2)
    wire(c, partial[5:])
    assert c.frames == 0 and c.out == 0x20
    c.rx_frame(Meter().frame(2300, 160, 5000))
    assert c.frames == 1 and c.state == CHARGING


def test_partial_error_deadline_precedes_watchdog_during_long_silence():
    c, m = setup()
    c.rx_frame(corrupt(m.frame(2300, 160, 5000)))
    wire(c, encode_frame(m.frame(2300, 160, 5000))[:5])
    c.advance_ms(METER_TIMEOUT_MS)
    assert c.state == FAULT and c.tx[4] == 0x44


def test_emulator_word_padding_and_50ms_host_pacing():
    c = Charger(); c.set_inputs(2); m = Meter()
    bodies = [m.frame(2300, 160, 5000) for _ in range(3)]
    bodies[1] = corrupt(bodies[1])
    for body in bodies:
        for size, value in transmit_options(encode_frame(body)):
            for byte in value.to_bytes(size, 'little'):
                c.advance_ms(50)  # TX register write
                c.rx_byte(byte)
                c.advance_ms(50)  # TX-done poll, per byte (not per word)
        c.advance_ms(50)      # output-check access between frames
    assert c.state == CHARGING and c.frames == 2 and c.bad == 0
    assert c.flags & F_CRC_LOST
