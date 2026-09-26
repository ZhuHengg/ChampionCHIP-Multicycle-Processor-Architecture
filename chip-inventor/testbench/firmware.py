"""Test firmware for the FIRMWARE-selectable imem (see canvas_blocks/gen_imem.py).

Each program returns an Asm; gen_imem.py assembles them into imem's ROMs:
  FIRMWARE 1 = gpio_program   (tb_gpio_system.v)
  FIRMWARE 2 = uart_program   (tb_uart_system.v)
  FIRMWARE 3 = system_program (tb_system.v)
FIRMWARE 0 is the official Stage 2 firmware and is not generated here.
Pass/fail convention for all three: x4 = 0x55 when the program completes.
"""
from pathlib import Path
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


PROGRAMS = {1: ('GPIO system test', gpio_program),
            2: ('UART echo test', uart_program),
            3: ('full system test', system_program)}
