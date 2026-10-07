// Ported 1:1 from chip-inventor/testbench/app/golden.py: Meter class and
// corrupt().

import { crc16 } from './crc';
import { concatBytes, u16ToBytesLE } from './binutil';

/**
 * The station energy meter. Advances its CRC chain on every frame it
 * produces, whether or not the charger accepts it (spec SS7.4).
 */
export class Meter {
  chain = 0xFFFF;

  frame(v: number, i: number, f: number): Uint8Array {
    const payload = concatBytes(u16ToBytesLE(v), u16ToBytesLE(i), u16ToBytesLE(f));
    const crc = crc16(payload, this.chain);
    this.chain = crc;
    return concatBytes(payload, u16ToBytesLE(crc));
  }
}

/** Flip bit 0 of byte 0, leaving the CRC field intact. */
export function corrupt(frame: Uint8Array): Uint8Array {
  const out = new Uint8Array(frame);
  out[0] = out[0] ^ 1;
  return out;
}
