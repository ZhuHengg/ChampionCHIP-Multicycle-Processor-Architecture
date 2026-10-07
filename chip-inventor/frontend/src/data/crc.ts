// Ported 1:1 from chip-inventor/testbench/app/golden.py: crc16().
//
// CRC-16 as rtl/crc.eq26.v computes it: poly 0x1021, MSB-first, no
// reflection, xorout 0. Byte at a time == a chain of `crcb`.

export function crc16(data: Uint8Array | number[], seed = 0xFFFF): number {
  let crc = seed & 0xFFFF;
  for (const byte of data) {
    for (let i = 7; i >= 0; i--) {
      const msb = (crc >> 15) & 1;
      crc = (crc << 1) & 0xFFFF;
      if (msb ^ ((byte >> i) & 1)) {
        crc ^= 0x1021;
      }
    }
  }
  return crc & 0xFFFF;
}
