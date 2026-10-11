"""Golden model of the grid-aware EV charging-station controller.

Single source of truth for the application: it defines the frame and record
formats, computes every CRC, and produces the expected value of every ./emu
-o / -r check. The firmware in chip-inventor/firmware/src/main.s must agree
with this model bit for bit.

"""
import struct
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "emulator"))
from meter_protocol import encode_frame, frame_body, transmit_options, MARKER, ESCAPE

# Constants (spec SS7.6). Placeholders, not real grid-code values.
F_LOW = 4950            # 49.50 Hz
V_SAG = 2070            # 207.0 V
I_MAX = 320             # 32.0 A, over-current when I > I_MAX
HOLD_BASE = 2           # minimum healthy frames before restart
CHARGER_ID = 0x4D590001  # "MY" + 0001, hashed as bytes 01 00 59 4D

# Application states; the firmware mirrors these in tp (x4).
IDLE, CONNECTED, CHARGING, GRID_HOLD, FAULT = range(5)
METER_TIMEOUT = 5       # latched fault; distinct low-three-bit report state
# AWS demonstration defaults; keep firmware and frontend constants synchronized.
METER_TIMEOUT_MS = 4000
RX_TIMEOUT_MS = 400

# DATAOUT per state (spec SS7.3/7.6).
OUT = {IDLE: 0x00, CONNECTED: 0x20, CHARGING: 0x30, GRID_HOLD: 0x60, FAULT: 0x80}
OUT[METER_TIMEOUT] = 0x80

# STATUS cause flags (spec SS7.6).
F_ESTOP = 0x08
F_CP_ERROR = 0x10
F_OVERCURRENT = 0x20
F_CRC_LOST = 0x40
F_GRID_HOLD = 0x80

SAFETY = 0x08           # DATAIN bit 3


def crc16(data, seed=0xFFFF):
    """CRC-16 as rtl/crc.eq26.v computes it: poly 0x1021, MSB-first, no
    reflection, xorout 0. Byte at a time == a chain of `crcb`."""
    crc = seed
    for byte in data:
        for i in range(7, -1, -1):
            msb = (crc >> 15) & 1
            crc = (crc << 1) & 0xFFFF
            if msb ^ ((byte >> i) & 1):
                crc ^= 0x1021
    return crc


def restart_delay(trigger_crc, charger_id=CHARGER_ID):
    """Healthy frames to wait before leaving GRID_HOLD (spec SS7.6).

    Hashing the charger ID with the triggering frame's CRC as seed de-syncs
    the fleet: same grid event, different restart frame per charger.
    """
    return HOLD_BASE + (crc16(charger_id.to_bytes(4, 'little'), trigger_crc) & 7)


def record_bytes(energy, status, frames):
    """The 8-byte session record (spec SS7.5)."""
    body = struct.pack('<IBB', energy & 0xFFFFFFFF, status & 0xFF, frames & 0xFF)
    return body + crc16(body).to_bytes(2, 'little')


class Meter:
    """Produces unescaped protocol-v2 bodies; encode_frame produces wire bytes."""
    def __init__(self, sequence=0):
        self.sequence = sequence

    def frame(self, v, i, f):
        body = frame_body(self.sequence, v, i, f)
        self.sequence = (self.sequence + 1) & 255
        return body


def corrupt(frame):
    """Corrupt voltage, retaining the CRC and sequence for rejection tests."""
    return frame[:1] + bytes([frame[1] ^ 1]) + frame[2:]


class Charger:
    """The controller. State lives in attributes that map 1:1 onto the
    firmware's registers."""

    def __init__(self):
        self.state = IDLE
        self.energy = 0
        self.frames = 0
        self.flags = 0
        self.bad = 0            # consecutive bad frames
        self.hold = 0           # healthy frames seen in GRID_HOLD
        self.delay = 0          # healthy frames required
        self.last_sequence = None
        self.pins = 0
        self.tx = []
        self._buf = bytearray()
        self._active = False
        self._escape = False
        self.rx_age_ms = 0
        self.age_ms = 0
        self.healthy = False

    def advance_ms(self, elapsed):
        """Advance hardware time explicitly; silence and partial frames count."""
        if elapsed < 0:
            raise ValueError('elapsed time must be non-negative')
        # A large model time step must preserve which deadline expires first.
        partial_due = RX_TIMEOUT_MS - self.rx_age_ms if self._active else float('inf')
        meter_due = (METER_TIMEOUT_MS - self.age_ms
                     if self.state in (CONNECTED, CHARGING, GRID_HOLD) else float('inf'))
        self.age_ms = min(0xFFFFFFFF, self.age_ms + elapsed)
        self.rx_age_ms = min(0xFFFFFFFF, self.rx_age_ms + elapsed)
        if partial_due < meter_due:
            self._check_partial_timeout()
            self.check_timeout()
        else:
            self.check_timeout()
            self._check_partial_timeout()

    def check_timeout(self):
        if self.state in (CONNECTED, CHARGING, GRID_HOLD) and self.age_ms >= METER_TIMEOUT_MS:
            self.healthy = False
            self.state = METER_TIMEOUT
            self._record(METER_TIMEOUT)

    @property
    def out(self):
        return OUT[self.state]

    def _record(self, new_state):
        self.tx.extend(record_bytes(self.energy, new_state | self.flags, self.frames))

    def _enter_fault(self, flag):
        self.flags |= flag
        self._record(FAULT)
        self.state = FAULT

    def set_inputs(self, value):
        """Apply pilot/safety rules until stable; charging needs healthy data."""
        self.pins = value & 0xFF
        while True:
            before = self.state
            self._step_pins()
            if self.state == before:
                self.check_timeout()
                return

    def _step_pins(self):
        cp = self.pins & 0x07
        safety = bool(self.pins & SAFETY)

        if self.state in (FAULT, METER_TIMEOUT):
            # Latched: only a clear safety pin and CP = A release it, no record.
            if not safety and cp == 0:
                self.state = IDLE
            return

        if safety:
            self._enter_fault(F_ESTOP)
            return
        if cp >= 4:
            self._enter_fault(F_CP_ERROR)
            return

        if self.state == IDLE:
            if cp in (1, 2, 3):
                self.energy = self.frames = self.flags = 0
                self.age_ms = 0
                self.healthy = False
                self.last_sequence = None
                self._buf.clear()
                self._active = self._escape = False
                self.state = CONNECTED
        elif self.state == CONNECTED:
            if cp == 2 and self.healthy and self.age_ms < METER_TIMEOUT_MS:
                self.state = CHARGING
            elif cp == 0:
                self._record(IDLE)
                self.state = IDLE
        elif self.state in (CHARGING, GRID_HOLD):
            # CP = D (3) refused: no ventilation support, so charging stops.
            if cp in (1, 3):
                self.state = CONNECTED
            elif cp == 0:
                self._record(IDLE)
                self.state = IDLE

    def _bad_frame(self):
        self.bad = min(2, self.bad + 1)
        if self.bad >= 2 and self.state not in (FAULT, METER_TIMEOUT):
            self._enter_fault(F_CRC_LOST)

    def _check_partial_timeout(self):
        if self._active and self.rx_age_ms >= RX_TIMEOUT_MS:
            partial = bool(self._buf) or self._escape
            self._active = self._escape = False
            self._buf.clear()
            if partial:
                self._bad_frame()

    def rx_byte(self, b):
        """Consume a raw wire byte, recovering at the next unescaped marker."""
        self._check_partial_timeout()
        b &= 255
        if b == MARKER:
            if self._active and (self._buf or self._escape):
                if not self._escape and len(self._buf) == 9:
                    self._on_frame(bytes(self._buf))
                else:
                    self._bad_frame()
            self._buf.clear()
            self._active, self._escape = True, False
            self.rx_age_ms = 0
            return
        if not self._active:
            return
        self.rx_age_ms = 0
        if self._escape:
            if b not in (MARKER ^ 0x20, ESCAPE ^ 0x20):
                self._active = self._escape = False
                self._buf.clear()
                self._bad_frame()
                return
            b ^= 0x20
            self._escape = False
        elif b == ESCAPE:
            self._escape = True
            return
        if len(self._buf) >= 9:
            self._active = False
            self._buf.clear()
            self._bad_frame()
            return
        self._buf.append(b)

    def rx_frame(self, frame):
        for b in encode_frame(frame):
            self.rx_byte(b)

    def _on_frame(self, frame):
        self.check_timeout()
        field = int.from_bytes(frame[-2:], 'little')
        if crc16(frame[:7]) != field:
            self._bad_frame()
            return
        seq = frame[0]
        if self.last_sequence is not None:
            delta = (seq - self.last_sequence) & 255
            if delta == 0 or delta >= 128:
                self._bad_frame()
                return
            if delta != 1:
                self.flags |= F_CRC_LOST
        self.last_sequence = seq

        self.bad = 0                           # rule 3: reset in every state
        v, i, f = struct.unpack('<HHH', frame[1:7])
        self.age_ms = 0
        self.healthy = i <= I_MAX and f >= F_LOW and v >= V_SAG

        if self.state == CONNECTED and (self.pins & 0x0F) == 2:
            # Evaluate the initial frame before permitting the contactor.
            if i > I_MAX:
                self._enter_fault(F_OVERCURRENT)
                return
            if not self.healthy:
                self.flags |= F_GRID_HOLD
                self.delay = restart_delay(field)
                self.hold = 0
                self.state = GRID_HOLD
                return
            self.state = CHARGING

        if self.state == CHARGING:
            if i > I_MAX:
                self._enter_fault(F_OVERCURRENT)
            elif f < F_LOW or v < V_SAG:
                self.flags |= F_GRID_HOLD
                self.delay = restart_delay(field)
                self.hold = 0
                self.state = GRID_HOLD
            else:
                self.energy = (self.energy + v * i) & 0xFFFFFFFF
                self.frames = min(self.frames + 1, 255)
        elif self.state == GRID_HOLD:
            # Over-current is ignored here: the contactor is already open.
            if f >= F_LOW and v >= V_SAG:
                self.hold += 1
                if self.hold >= self.delay:
                    self.state = CHARGING      # this frame is not billed
            else:
                self.hold = 0
