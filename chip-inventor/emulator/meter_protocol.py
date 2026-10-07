"""Meter protocol v2 sender helper (integer measurement units unchanged).

python emulator/meter_protocol.py --sequence 0 --voltage 2300 --current 160 --frequency 5000
Use --format emu for transmit options to append to an emulator command.
Send the returned bytes on an already-open meter UART; this helper does not reset
the processor or manage a serial port. Increment sequence modulo 256 per frame.
"""
import argparse
import struct

MARKER, ESCAPE = 0x7E, 0x7D


def crc16(data, seed=0xFFFF):
    for byte in data:
        seed ^= byte << 8
        for _ in range(8):
            seed = ((seed << 1) ^ (0x1021 if seed & 0x8000 else 0)) & 0xFFFF
    return seed


def frame_body(sequence, voltage, current, frequency):
    body = struct.pack('<BHHH', sequence, voltage, current, frequency)
    return body + crc16(body).to_bytes(2, 'little')


def encode_frame(body):
    if len(body) != 9:
        raise ValueError('protocol v2 requires a nine-byte unescaped body')
    out = bytearray([MARKER])
    for byte in body:
        if byte in (MARKER, ESCAPE):
            out.extend((ESCAPE, byte ^ 0x20))
        else:
            out.append(byte)
    out.append(MARKER)
    return bytes(out)


def transmit_options(wire):
    # Each emulator write incurs a host delay. Empty trailing markers safely
    # pad a complete frame to full words, avoiding a separate -t2 and -t1.
    if not wire or wire[-1] != MARKER:
        raise ValueError('emulator packing requires a complete framed packet')
    wire = bytes(wire) + bytes([MARKER]) * (-len(wire) % 4)
    return [(4, int.from_bytes(wire[i:i+4], 'little')) for i in range(0, len(wire), 4)]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sequence', type=int, required=True)
    p.add_argument('--voltage', type=int, required=True, help='0.1 V units')
    p.add_argument('--current', type=int, required=True, help='0.1 A units')
    p.add_argument('--frequency', type=int, required=True, help='0.01 Hz units')
    p.add_argument('--format', choices=('hex', 'emu'), default='hex')
    a = p.parse_args()
    try:
        wire = encode_frame(frame_body(a.sequence, a.voltage, a.current, a.frequency))
    except struct.error as exc:
        p.error(str(exc))
    print(wire.hex(' ') if a.format == 'hex' else ' '.join(
        f'-t{n} 0x{value:0{n*2}X}' for n, value in transmit_options(wire)))


if __name__ == '__main__':
    main()
