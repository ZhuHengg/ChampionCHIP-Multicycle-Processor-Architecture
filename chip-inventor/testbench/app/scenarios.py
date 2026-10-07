"""Scenario DSL: one scenario == one ./emu command == one Verilog test.

Each Scenario records a list of emulator options. It renders two ways:
  to_emu() -> the real "./emu ..." command line (exported to
              chip-inventor/emulator/emu_commands.txt for the FPGA stage)
  to_vh()  -> emu_* task calls included by tb_app.v

Scenarios with firmware == 5 are backed by golden.Charger, so the expected
value of every -o and -r comes from the model, never from hand arithmetic.

Spec: docs/STAGE3_STRATEGY.md SS3 (emulator), SS7.8 (scenario set).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from golden import Charger, Meter, corrupt, restart_delay, encode_frame, transmit_options  # noqa: F401

HERE = Path(__file__).resolve().parent
CHIP = HERE.parents[1]

APP_FIRMWARE = 5          # PROGRAMS[5] in testbench/firmware.py
ORGANISER_FIRMWARE = 4


class Scenario:
    def __init__(self, name, title, firmware=APP_FIRMWARE, stream=False,
                 expect_fail=False, preset_in=0):
        self.name = name
        self.title = title
        self.firmware = firmware
        self.stream = stream
        self.expect_fail = expect_fail
        self.preset_in = preset_in
        self.ops = []                      # (kind, *args)
        if firmware == APP_FIRMWARE:
            # emu.c resets per command but the GPIO input value persists, so
            # the firmware can boot with pins already asserted.
            self.model = Charger()
            self.model.set_inputs(preset_in)
        else:
            self.model = None

    # ---- options -------------------------------------------------------
    def d(self, value):
        self.ops.append(('d', value))
        return self

    def i(self, value):
        if self.model is not None:
            self.model.set_inputs(value)
        self.ops.append(('i', value))
        return self

    def o(self, value=None, state=None):
        """Expected GPIO output. Taken from the model when value is None."""
        if value is None:
            if self.model is None:
                raise ValueError(f'{self.name}: o() needs a value without a model')
            value = self.model.out
            if state is None:
                state = self.model.state
        self.ops.append(('o', value, 0xFF if state is None else state))
        return self

    def t(self, n, value):
        self.ops.append(('t', n, value))
        return self

    def r(self, n, value):
        self.ops.append(('r', n, value))
        return self

    # ---- composites ----------------------------------------------------
    def frame(self, body):
        """Transmit an escaped protocol-v2 frame in supported emulator chunks."""
        for n, value in transmit_options(encode_frame(body)):
            self.t(n, value)
        if self.model is not None:
            self.model.rx_frame(body)
        return self

    def record(self):
        """Read the session record: -r4 ENERGY, -r2 (FRAMES<<8|STATUS), -r2 CRC."""
        tx = bytes(self.model.tx)
        if len(tx) != 8:
            raise AssertionError(f'{self.name}: model transmitted {len(tx)} bytes, '
                                 'expected exactly 8 (one record per command)')
        self.r(4, int.from_bytes(tx[0:4], 'little'))
        self.r(2, int.from_bytes(tx[4:6], 'little'))
        self.r(2, int.from_bytes(tx[6:8], 'little'))
        return self

    # ---- rendering -----------------------------------------------------
    def to_emu(self):
        parts = ['./emu']
        for op in self.ops:
            kind = op[0]
            if kind in ('d', 'i'):
                parts.append(f'-{kind} 0x{op[1]:02X}')
            elif kind == 'o':
                parts.append(f'-o 0x{op[1]:02X}')
            else:                          # t / r
                n, value = op[1], op[2]
                parts.append(f'-{kind}{n} 0x{value:0{n * 2}X}')
        return ' '.join(parts)

    def to_vh(self):
        lines = [f'// {self.name}: {self.title}',
                 f'// {self.to_emu()}',
                 'emu_begin;']
        for op in self.ops:
            kind = op[0]
            if kind in ('d', 'i'):
                lines.append(f'emu_{kind}(8\'h{op[1]:02X});')
            elif kind == 'o':
                lines.append(f'emu_o(8\'h{op[1]:02X}, 8\'h{op[2]:02X});')
            else:
                lines.append(f'emu_{kind}({op[1]}, 32\'h{op[2]:08X});')
        lines.append('emu_end;')
        return '\n'.join(lines) + '\n'

    def read_bytes(self):
        """Total bytes the -r options consume (emu.c allows at most 8)."""
        return sum(op[1] for op in self.ops if op[0] == 'r')


# --------------------------------------------------------------------------
# Harness scenarios: FIRMWARE 4, the organiser's own firmware, no model.
# They validate the testbench itself before it judges our application.
# --------------------------------------------------------------------------
def _harness():
    out = {}

    # The organiser firmware copies P3-0 to P7-4 once per loop, then blocks on
    # UART. So the GPIO check has to come *after* a UART echo has let the loop
    # go round again.
    h0 = Scenario('H0', 'organiser echo via emu model', firmware=ORGANISER_FIRMWARE)
    h0.d(0xF0).i(0x0A).t(1, 0x30).r(1, 0x30).o(0xA0, state=0xFF)
    out['H0'] = h0

    # Same, but expecting the wrong output: proves the harness reports exactly
    # one [error] and skips every later option (emu.c's goto main_end).
    h1 = Scenario('H1', 'harness catches a mismatch', firmware=ORGANISER_FIRMWARE,
                  expect_fail=True)
    h1.d(0xF0).i(0x0A).t(1, 0x30).o(0xB0, state=0xFF).r(1, 0x30)
    out['H1'] = h1

    # RVBL-Emulator/README.md's own example, verbatim. It only passes because
    # the emulator's IN register still holds 0x02 from a previous run: the
    # organiser firmware reads GPIO once and then blocks on UART, so it cannot
    # see an -i that arrives after boot. preset_in models that persistence.
    h2 = Scenario('H2', 'organiser README example, verbatim (needs IN=0x02 at boot)',
                  firmware=ORGANISER_FIRMWARE, preset_in=0x02)
    h2.d(0xF0).i(0x02).o(0x20, state=0xFF).t(1, 0x30).r(1, 0x30)
    out['H2'] = h2

    return out


def _app():
    """S1-S11 + S1X: the application scenario set of spec SS7.8.

    Every scenario starts with -d 0xF0 (our DATADIR) and ends by reading the
    one 8-byte session record.
    """
    out = {}

    def new(name, title, **kw):
        s = Scenario(name, title, **kw)
        s.d(0xF0)
        out[name] = s
        return s

    def N(m):
        return m.frame(2300, 160, 5000)        # healthy nominal frame

    # ---- S1: normal session ------------------------------------------------
    s, m = new('S1', 'normal session: plug in, charge two frames, unplug'), Meter()
    s.i(0).o().i(1).o().i(2).o()
    s.frame(N(m)).o()
    s.frame(N(m)).o()
    s.i(1).o().i(0).o().record()

    # ---- S1X: same, streamed ----------------------------------------------
    # 16 bytes back to back with no gap: the first frame's end-of-frame
    # processing must finish inside one byte time (1740 cycles).
    s, m = new('S1X', 'stress: S1 with back-to-back UART bytes', stream=True), Meter()
    s.i(0).o().i(1).o().i(2).o()
    s.frame(N(m))
    s.frame(N(m))
    s.o()
    s.i(1).o().i(0).o().record()

    # ---- S2: grid under-frequency -> hold -> CRC-timed restart ------------
    s, m = new('S2', 'grid under-frequency: hold, then CRC-timed restart'), Meter()
    s.i(1).o().i(2).o()
    s.frame(N(m)).o()
    trigger = m.frame(2300, 160, 4920)         # F < F_LOW -> GRID_HOLD
    delay = restart_delay(int.from_bytes(trigger[-2:], 'little'))
    s.frame(trigger).o()
    s.frame(m.frame(2300, 160, 4940)).o()      # still unhealthy: count resets
    for _ in range(delay):                     # healthy frames; the last one
        s.frame(m.frame(2070, 160, 4950)).o()  # restarts charging
    s.frame(N(m)).o()
    s.i(1).o().i(0).o().record()

    # ---- S3: corrupted frame and dropped frame ---------------------------
    s, m = new('S3', 'corrupted and missing frames: next valid frame recovers'), Meter()
    s.i(1).o().i(2).o()
    s.frame(N(m)).o()
    s.frame(corrupt(N(m))).o()                 # rejected
    s.frame(N(m)).o()                          # valid independent CRC recovers
    N(m)                                       # generated but never delivered
    s.frame(N(m)).o()                          # accepted: forward sequence gap is flagged
    s.frame(N(m)).o()                          # accepted again
    s.i(0).o().record()

    # ---- S4: meter link lost ---------------------------------------------
    s, m = new('S4', 'meter link lost: two bad frames in a row latch FAULT'), Meter()
    s.i(1).o().i(2).o()
    s.frame(N(m)).o()
    s.frame(corrupt(N(m))).o()
    s.frame(corrupt(N(m))).o()                 # -> 0x80, CRC-lost flag
    s.i(0).o().record()

    # ---- S5: emergency stop while charging, latched -----------------------
    s, m = new('S5', 'E-stop while charging latches FAULT until released and unplugged'), Meter()
    s.i(1).o().i(2).o()
    s.frame(N(m)).o()
    s.i(0x0A).o()                              # CP C + SAFETY_TRIP -> FAULT
    s.i(0x02).o()                              # still faulted
    s.i(0x08).o()                              # still faulted
    s.i(0x00).o()                              # released and unplugged -> IDLE
    s.record()

    # ---- S6: straight to C, unplug under load ----------------------------
    s, m = new('S6', 'plug straight into CP C, then unplug while charging'), Meter()
    s.i(2).o()                                 # CONNECTED until first healthy frame
    s.frame(N(m)).o()
    s.i(0).o().record()

    # ---- S7: boundaries and over-current ---------------------------------
    s, m = new('S7', 'frame exactly on every limit is billed; I_MAX+1 faults'), Meter()
    s.i(1).o().i(2).o()
    s.frame(m.frame(2070, 320, 4950)).o()      # V_SAG, I_MAX, F_LOW exactly
    s.frame(m.frame(2300, 321, 5000)).o()      # I > I_MAX -> FAULT
    s.i(0).o().record()

    # ---- S8: ventilation required, then CP error -------------------------
    s = new('S8', 'ventilation (CP D) refused; CP E latches FAULT')
    s.i(1).o().i(3).o()                        # D refused, stays CONNECTED
    s.i(2).o()                                 # C waits for healthy meter data
    s.i(3).o()                                 # D -> back to CONNECTED
    s.i(4).o()                                 # E -> FAULT, CP-error flag
    s.i(0).o().record()

    # ---- S9: invalid pilot code ------------------------------------------
    s = new('S9', 'invalid pilot code 7 latches FAULT with the CP-error flag')
    s.i(1).o().i(7).o().i(0).o().record()

    # ---- S10: replayed frame ---------------------------------------------
    s, m = new('S10', 'two replayed frames rejected -> FAULT'), Meter()
    s.i(1).o().i(2).o()
    f1 = N(m)
    f2 = N(m)
    s.frame(f1).o()
    s.frame(f2).o()
    s.frame(f1).o()                            # replay -> rejected
    s.frame(f1).o()                            # second replay -> FAULT
    s.i(0).o().record()

    # ---- S11: stale input pins at power-up -------------------------------
    # emu.c keeps IN across its reset, so the firmware can boot with CP = C
    # already asserted; the contactor must remain open until healthy data.
    s, m = new('S11', 'stale pins at boot: CP C waits for healthy meter data',
               preset_in=0x02), Meter()
    s.o()                                      # 0x20 without any -i
    s.frame(N(m)).o()
    s.i(0).o().record()

    return out


SCENARIOS = {}
SCENARIOS.update(_harness())
SCENARIOS.update(_app())


def write_emu_commands(path=None):
    """Export every application scenario as a real ./emu command line."""
    path = Path(path) if path else CHIP / 'emulator' / 'emu_commands.txt'
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = ['# ./emu command lines for the grid-aware EV charger application.',
             '# Generated by chip-inventor/testbench/app/scenarios.py -- do not edit.',
             '# Expected values come from the Python golden model (golden.py).',
             '']
    for s in SCENARIOS.values():
        if s.firmware != APP_FIRMWARE:
            continue
        if s.preset_in:
            # emu.c keeps IN across its reset, so the only way to boot with
            # pins asserted is to leave them there with a previous command.
            # The run before this one may have ended on any IN value.
            boot = Charger()
            boot.set_inputs(s.preset_in)
            lines.append(f'# {s.name} setup: leave IN = 0x{s.preset_in:02X} '
                         f'for the reset at the start of {s.name}')
            lines.append(f'./emu -d 0xF0 -i 0x{s.preset_in:02X} -o 0x{boot.out:02X}')
            lines.append('')
        lines.append(f'# {s.name}: {s.title}')
        lines.append(s.to_emu())
        lines.append('')
    path.write_text('\n'.join(lines), encoding='utf-8')
    return path


if __name__ == '__main__':
    p = write_emu_commands()
    n = sum(1 for s in SCENARIOS.values() if s.firmware == APP_FIRMWARE)
    print(f'wrote {n} command lines to {p}')
