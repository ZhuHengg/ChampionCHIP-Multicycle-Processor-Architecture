"""Test firmware for the FIRMWARE-selectable imem (see testbench/gen_imem.py).

Each program returns an Asm-like object with .assemble(); gen_imem.py
assembles them into imem's ROMs:
  FIRMWARE 1 = gpio_program       (tb_gpio_system.v)
  FIRMWARE 2 = uart_program       (tb_uart_system.v)
  FIRMWARE 3 = system_program     (tb_system.v)
  FIRMWARE 4 = organiser_program  (tb_organiser.v) -- verbatim official
               Stage 3 GPIO/UART test firmware, see
               external/CCX_Malaysia_Edition_Stage_3/RVBL-GPIO-UART-Test-Firmware
FIRMWARE 0 is the official Stage 2 firmware and is not generated here.
Pass/fail convention for FIRMWARE 1-3: x4 = 0x55 when the program completes.
FIRMWARE 4 is the organiser's own program verbatim and has no such marker;
its testbench checks GPIO/UART behavior directly per the organiser's README.
"""
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'legacy/scripts'))
from rvbl2_asm import Asm


def gpio_program():
    """P3..P0 outputs, P7..P4 inputs; checks DATADIR/DATAOUT readback and DATAIN."""
    a = Asm()
    a.lui(1, 0xf0000)             # GPIO base address
    a.li(2, 15)
    a.store('sw', 2, 8, 1)        # Four inputs, four outputs
    a.load('lw', 3, 8, 1)
    a.branch('bne', 3, 2, 'fail')
    a.li(2, 5)
    a.store('sw', 2, 0, 1)        # Drive output pins 0 and 2 high
    a.load('lw', 3, 0, 1)
    a.branch('bne', 3, 2, 'fail')
    a.load('lw', 3, 4, 1)         # Read externally driven high nibble
    a.i('andi', 3, 3, 0xf0)
    a.li(2, 0xa0)
    a.branch('bne', 3, 2, 'fail')
    a.li(4, 0x55)
    a.label('pass')
    a.jal(0, 'pass')
    a.label('fail')
    a.li(4, 0xff)
    a.label('failed')
    a.jal(0, 'failed')
    return a


def uart_program():
    """Echo one byte: wait RXDONE, read RXDATA, send it back, wait TXDONE."""
    a = Asm()
    a.lui(1, 0xf1000)
    a.label('rxwait')
    a.load('lw', 3, 8, 1)
    a.i('andi', 3, 3, 2)
    a.branch('beq', 3, 0, 'rxwait')
    a.store('sw', 0, 8, 1)
    a.load('lw', 2, 4, 1)
    a.label('txwait')
    a.load('lw', 3, 8, 1)
    a.i('andi', 3, 3, 4)
    a.branch('beq', 3, 0, 'txwait')
    a.store('sw', 2, 0, 1)
    a.li(3, 1)
    a.store('sw', 3, 8, 1)
    a.label('donewait')
    a.load('lw', 3, 8, 1)
    a.i('andi', 3, 3, 4)
    a.branch('beq', 3, 0, 'donewait')
    a.li(4, 0x55)
    a.label('pass')
    a.jal(0, 'pass')
    return a


GPIO, UART = 8, 9                 # s0 = GPIO base, s1 = UART base
CRC, COUNT, BYTE, SW, REPLY, T = 10, 11, 12, 13, 14, 5


def _wait_bit(a, mask, label):
    """Spin until UART CONTROL & mask != 0."""
    a.label(label)
    a.load('lw', T, 8, UART)
    a.i('andi', T, T, mask)
    a.branch('beq', T, 0, label)


def _send(a, reg, n):
    """Wait TXDONE, write TXDATA, pulse TRANSMIT."""
    _wait_bit(a, 4, f'txwait{n}')
    a.store('sw', reg, 0, UART)
    a.li(T, 1)
    a.store('sw', T, 8, UART)


def system_program():
    """Per received byte b with switches s on P7..P4: LEDs = b[3:0],
    reply (b*s)&0xFF, crc = CRCB(b, crc). After 4 bytes send crc lo, hi."""
    a = Asm()
    a.lui(GPIO, 0xf0000, 'GPIO base 0xF0000000')
    a.lui(UART, 0xf1000, 'UART base 0xF1000000')
    a.li(T, 0x0f)
    a.store('sw', T, 8, GPIO, 'DATADIR: P3..P0 out (LEDs), P7..P4 in (switches)')
    a.li(CRC, 0xffff, 'CRC-16/CCITT seed')
    a.li(COUNT, 4)
    a.label('loop')
    _wait_bit(a, 2, 'rxwait')
    a.store('sw', 0, 8, UART, 'clear RXDONE')
    a.load('lw', BYTE, 4, UART, 'b = RXDATA')
    a.crc('crcb', CRC, BYTE, CRC, 'crc = CRCB(b, crc)')
    a.store('sw', BYTE, 0, GPIO, 'LEDs = b[3:0]')
    a.load('lw', SW, 4, GPIO, 'DATAIN')
    a.i('srli', SW, SW, 4)
    a.i('andi', SW, SW, 0x0f, 's = switches')
    a.mul('mul', REPLY, BYTE, SW, 'reply = b * s')
    a.i('andi', REPLY, REPLY, 0xff)
    _send(a, REPLY, 0)
    a.addi(COUNT, COUNT, -1)
    a.branch('bne', COUNT, 0, 'loop')
    a.i('andi', REPLY, CRC, 0xff)
    _send(a, REPLY, 1)
    a.i('srli', REPLY, CRC, 8)
    _send(a, REPLY, 2)
    _wait_bit(a, 4, 'txdone')
    a.li(4, 0x55, 'x4 = pass marker')
    a.label('pass')
    a.jal(0, 'pass')
    return a


class LiteralRom:
    """Wraps a fixed (addr, word) list with the .assemble() interface
    gen_imem.py expects, so a verbatim ROM can sit alongside Asm programs
    without going through the assembler."""
    def __init__(self, words, comment):
        self._words = words
        self._comment = comment

    def assemble(self):
        return [(addr, word, self._comment, '') for addr, word in self._words]


_ORGANISER_TXT = (Path(__file__).resolve().parents[2] / 'external' /
    'CCX_Malaysia_Edition_Stage_3' / 'RVBL-GPIO-UART-Test-Firmware' / 'src' /
    'firmware.txt')

_APP_TXT = Path(__file__).resolve().parents[1] / 'firmware' / 'build' / 'firmware.txt'


def _load_firmware_txt(path, comment, expected_words=None):
    """Parse a Firmware-Builder firmware.txt into an (addr, word) LiteralRom."""
    text = Path(path).read_text(encoding='utf-8')
    pairs = re.findall(r"32'h([0-9A-Fa-f]{8}):\s*r_Instruction\s*=\s*32'h([0-9A-Fa-f]{8})", text)
    if expected_words is not None:
        assert len(pairs) == expected_words, \
            f'expected {expected_words} words in {path}, got {len(pairs)}'
    assert pairs, f'no instruction words found in {path}'
    return LiteralRom([(int(a, 16), int(w, 16)) for a, w in pairs], comment)


def organiser_program():
    """Verbatim official Stage 3 GPIO/UART test firmware (21 words), loaded
    byte-for-byte from the organiser's firmware.txt -- not reassembled, so
    this is exactly what they shipped. See that folder's README for the
    RV32I source (P7-4 output/P3-0 input; GPIO echo P3-0->P7-4; UART RX
    byte echoed back on TX)."""
    return _load_firmware_txt(_ORGANISER_TXT,
                              'organiser GPIO/UART test firmware (verbatim)',
                              expected_words=21)


def app_program():
    """Stage 3 application: grid-aware EV charging-station controller, built
    from chip-inventor/firmware/src/main.s by the organiser's Firmware-Builder
    (see that folder's README). Rebuild with `make`, then rerun gen_imem.py."""
    return _load_firmware_txt(_APP_TXT, 'grid-aware EV charger application')


# Registers for crc_bench_program
_B = 5          # t0 — scratch / byte value
_CRC_HW = 6    # t1 — hardware CRC result
_CRC_SW = 7    # t2 — software CRC result
_POLY = 10     # a0 — polynomial 0x1021
_CNT = 11      # a1 — bit counter
_BIT = 12      # a2 — extracted bit


def crc_bench_program():
    """CRC-16 speed bench: hardware crcb vs software shift-xor loop on the
    6-byte payload of a standard meter frame (2300 V, 160 I, 5000 F).
    x4 transitions: 0->1 (hw start), 1->2 (hw done / sw start), 2->3 (sw done),
    then x4 = (crc_hw << 16) | crc_sw and park."""
    a = Asm()
    payload = [0xFC, 0x08, 0xA0, 0x00, 0x88, 0x13]

    # --- hardware CRC via crcb ---
    a.li(4, 1, 'x4 = 1: hw CRC start')
    a.li(_CRC_HW, 0xFFFF, 'seed')
    for b in payload:
        a.li(_B, b)
        a.crc('crcb', _CRC_HW, _B, _CRC_HW)

    # --- software CRC (MSB-first, poly 0x1021, 8 bits per byte) ---
    a.li(4, 2, 'x4 = 2: sw CRC start')
    a.li(_CRC_SW, 0xFFFF, 'seed')
    a.li(_POLY, 0x1021)
    for idx, b in enumerate(payload):
        lbl = f'sw_bit{idx}'
        skip = f'sw_skip{idx}'
        a.li(_B, b)
        a.i('slli', _B, _B, 8)
        a.r('xor', _CRC_SW, _CRC_SW, _B)
        a.li(_CNT, 8)
        a.label(lbl)
        a.i('slli', _CRC_SW, _CRC_SW, 1)
        a.i('srli', _BIT, _CRC_SW, 16)
        a.i('andi', _BIT, _BIT, 1)
        a.branch('beq', _BIT, 0, skip)
        a.r('xor', _CRC_SW, _CRC_SW, _POLY)
        a.label(skip)
        a.addi(_CNT, _CNT, -1)
        a.branch('bne', _CNT, 0, lbl)
    a.li(_B, 0xFFFF)
    a.r('and', _CRC_SW, _CRC_SW, _B)

    # --- done: x4 = 3, then x4 = (hw << 16) | sw ---
    a.li(4, 3, 'x4 = 3: both done')
    a.i('slli', _B, _CRC_HW, 16)
    a.r('or', 4, _B, _CRC_SW)
    a.label('park')
    a.jal(0, 'park')
    return a


PROGRAMS = {1: ('GPIO system test', gpio_program),
            2: ('UART echo test', uart_program),
            3: ('full system test', system_program),
            4: ('organiser official GPIO/UART firmware', organiser_program),
            5: ('grid-aware EV charger application', app_program),
            6: ('crcb vs software CRC-16 cycle bench', crc_bench_program)}
