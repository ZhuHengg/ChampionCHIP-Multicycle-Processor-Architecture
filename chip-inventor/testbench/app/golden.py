"""Golden model of the grid-aware EV charging-station controller.

Single source of truth for the application: it defines the frame and record
formats, computes every CRC, and produces the expected value of every ./emu
-o / -r check. The firmware in chip-inventor/firmware/src/main.s must agree
with this model bit for bit.

Spec: docs/STAGE3_STRATEGY.md SS7.4 (meter frame), SS7.5 (session record),
SS7.6 (FSM, frame rules, constants).
"""
import struct

# Constants (spec SS7.6). Placeholders, not real grid-code values.
F_LOW = 4950            # 49.50 Hz
V_SAG = 2070            # 207.0 V
I_MAX = 320             # 32.0 A, over-current when I > I_MAX
HOLD_BASE = 2           # minimum healthy frames before restart
CHARGER_ID = 0x4D590001  # "MY" + 0001, hashed as bytes 01 00 59 4D

# Application states; the firmware mirrors these in tp (x4).
IDLE, CONNECTED, CHARGING, GRID_HOLD, FAULT = range(5)

# DATAOUT per state (spec SS7.3/7.6).
OUT = {IDLE: 0x00, CONNECTED: 0x20, CHARGING: 0x30, GRID_HOLD: 0x60, FAULT: 0x80}

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
    """The station energy meter. Advances its CRC chain on every frame it
    produces, whether or not the charger accepts it (spec SS7.4)."""

    def __init__(self):
        self.chain = 0xFFFF

    def frame(self, v, i, f):
        payload = struct.pack('<HHH', v, i, f)
        crc = crc16(payload, self.chain)
        self.chain = crc
        return payload + crc.to_bytes(2, 'little')


def corrupt(frame):
    """Flip bit 0 of byte 0, leaving the CRC field intact."""
    return bytes([frame[0] ^ 1]) + frame[1:]


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
        self.seed = 0xFFFF      # CRC chain seed
        self.pins = 0
        self.tx = []
        self._buf = bytearray()

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
        """Apply the pilot/safety rules until the state is stable, so CP = C
        straight from IDLE walks IDLE -> CONNECTED -> CHARGING (spec SS7.6)."""
        self.pins = value & 0xFF
        while True:
            before = self.state
            self._step_pins()
            if self.state == before:
                return

    def _step_pins(self):
        cp = self.pins & 0x07
        safety = bool(self.pins & SAFETY)

        if self.state == FAULT:
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
                self.state = CONNECTED
        elif self.state == CONNECTED:
            if cp == 2:
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

    def rx_byte(self, b):
        """Bytes are framed by count from reset -- no resync byte, the
        emulator always sends whole frames (spec SS7.6)."""
        self._buf.append(b & 0xFF)
        if len(self._buf) == 8:
            frame, self._buf = bytes(self._buf), bytearray()
            self._on_frame(frame)

    def rx_frame(self, frame):
        for b in frame:
            self.rx_byte(b)

    def _on_frame(self, frame):
        field = int.from_bytes(frame[6:], 'little')
        valid = crc16(frame[:6], self.seed) == field
        self.seed = field                      # rule 1: always advance

        if self.state == FAULT:
            return

        if not valid:                          # rule 2
            self.bad += 1
            if self.bad >= 2:
                self._enter_fault(F_CRC_LOST)
            return

        self.bad = 0                           # rule 3
        v, i, f = struct.unpack('<HHH', frame[:6])

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
