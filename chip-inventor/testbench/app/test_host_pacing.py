"""Replay existing application expectations with per-access host delays.

The earlier pacing test treated a -t4 word as one access. The emulator actually
writes and polls EACH byte. RTL/AWS tests remain the integration authority.
"""
import pytest
from golden import Charger
from scenarios import SCENARIOS


@pytest.mark.parametrize('delay_ms', [50, 60])
@pytest.mark.parametrize('name', [n for n, s in SCENARIOS.items() if s.firmware == 5])
def test_application_at_stock_pacing_and_twenty_percent_margin(name, delay_ms):
    scenario = SCENARIOS[name]
    charger = Charger()
    charger.set_inputs(scenario.preset_in)
    read_pointer = 0
    for op in scenario.ops:
        kind = op[0]
        if kind == 't':
            for byte in op[2].to_bytes(op[1], 'little'):
                charger.advance_ms(delay_ms)  # TX register write
                charger.rx_byte(byte)
                charger.advance_ms(delay_ms)  # TX done poll
        else:
            charger.advance_ms(delay_ms * (2 if kind in ('d', 'i', 'r') else 1))
            if kind == 'i':
                charger.set_inputs(op[1])
            elif kind == 'o':
                assert charger.out == op[1]
                assert charger.state == op[2]
            elif kind == 'r':
                data = charger.tx[read_pointer:read_pointer + op[1]]
                assert len(data) == op[1]
                assert int.from_bytes(bytes(data), 'little') == op[2]
                read_pointer += op[1]
    assert len(charger.tx) == read_pointer
