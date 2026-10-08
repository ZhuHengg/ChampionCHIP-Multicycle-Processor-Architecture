// Ported 1:1 from chip-inventor/testbench/app/golden.py: Meter class and
// corrupt() (protocol v2, see improvement made.md "resilient UART frame
// recovery"). Meter.frame() returns the unescaped 9-byte body (sequence,
// V, I, F, CRC-16); encodeFrame() in meterProtocol.ts wraps it on the wire.

import { frameBody } from './meterProtocol';

/** Produces unescaped protocol-v2 bodies; encodeFrame produces wire bytes. */
export class Meter {
  sequence: number;

  constructor(sequence = 0) {
    this.sequence = sequence;
  }

  frame(v: number, i: number, f: number): Uint8Array {
    const body = frameBody(this.sequence, v, i, f);
    this.sequence = (this.sequence + 1) & 0xFF;
    return body;
  }
}

/** Corrupt voltage, retaining the CRC and sequence for rejection tests. */
export function corrupt(frame: Uint8Array): Uint8Array {
  const out = new Uint8Array(frame);
  out[1] = out[1] ^ 1;
  return out;
}
