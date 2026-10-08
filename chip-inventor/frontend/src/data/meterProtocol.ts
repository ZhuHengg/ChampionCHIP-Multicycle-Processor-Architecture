// Ported 1:1 from chip-inventor/emulator/meter_protocol.py.
//
// Protocol v2: a 9-byte unescaped body (sequence, V, I, F, CRC-16) framed
// between MARKER bytes, with MARKER/ESCAPE bytes inside the body escaped.

import { crc16 } from './crc';
import { concatBytes } from './binutil';

export const MARKER = 0x7E;
export const ESCAPE = 0x7D;

/** The 9-byte unescaped protocol-v2 body: sequence, V, I, F, CRC-16. */
export function frameBody(sequence: number, voltage: number, current: number, frequency: number): Uint8Array {
  const body = new Uint8Array(7);
  body[0] = sequence & 0xFF;
  body[1] = voltage & 0xFF;
  body[2] = (voltage >>> 8) & 0xFF;
  body[3] = current & 0xFF;
  body[4] = (current >>> 8) & 0xFF;
  body[5] = frequency & 0xFF;
  body[6] = (frequency >>> 8) & 0xFF;
  const crc = crc16(body);
  return concatBytes(body, new Uint8Array([crc & 0xFF, (crc >>> 8) & 0xFF]));
}

/** Escape MARKER/ESCAPE bytes inside `body` and wrap with MARKER delimiters. */
export function encodeFrame(body: Uint8Array): Uint8Array {
  if (body.length !== 9) {
    throw new Error('protocol v2 requires a nine-byte unescaped body');
  }
  const out: number[] = [MARKER];
  for (const byte of body) {
    if (byte === MARKER || byte === ESCAPE) {
      out.push(ESCAPE, byte ^ 0x20);
    } else {
      out.push(byte);
    }
  }
  out.push(MARKER);
  return new Uint8Array(out);
}
