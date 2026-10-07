// Small helpers standing in for Python's `struct` module, used by the
// ports of golden.py / scenarios.py. All multi-byte fields are
// little-endian, matching struct.pack('<...', ...) in the Python source.

export function u32ToBytesLE(value: number): Uint8Array {
  const out = new Uint8Array(4);
  out[0] = value & 0xFF;
  out[1] = (value >>> 8) & 0xFF;
  out[2] = (value >>> 16) & 0xFF;
  out[3] = (value >>> 24) & 0xFF;
  return out;
}

export function u16ToBytesLE(value: number): Uint8Array {
  const out = new Uint8Array(2);
  out[0] = value & 0xFF;
  out[1] = (value >>> 8) & 0xFF;
  return out;
}

export function bytesToU32LE(bytes: Uint8Array | number[], offset = 0): number {
  return (
    (bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24)) >>>
    0
  );
}

export function bytesToU16LE(bytes: Uint8Array | number[], offset = 0): number {
  return (bytes[offset] | (bytes[offset + 1] << 8)) & 0xFFFF;
}

export function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const total = parts.reduce((sum, p) => sum + p.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}
