def crc16_ccitt_false_bits(data, nbits, seed):
    """Feed nbits of data (MSB-first) through CRC-16/CCITT-FALSE."""
    crc = seed & 0xFFFF
    for i in range(nbits - 1, -1, -1):
        bit = (data >> i) & 1
        msb = (crc >> 15) & 1
        crc = ((crc << 1) & 0xFFFF)
        if msb ^ bit:
            crc ^= 0x1021
    return crc

# crcb: 8 bits from rs1, rs2 = seed
crc = 0xFFFF
for b in [0x12,0x34,0x56,0x78,0x90,0xAB,0xCD,0xEF]:
    crc = crc16_ccitt_false_bits(b, 8, crc)
print(f"crcb chain (8 x 8-bit):  0x{crc:04X}")

# crch: 16 bits
crc = 0xFFFF
for h in [0x1234,0x5678,0x90AB,0xCDEF]:
    crc = crc16_ccitt_false_bits(h, 16, crc)
print(f"crch chain (4 x 16-bit): 0x{crc:04X}")

# crcw: 32 bits
crc = 0xFFFF
for w in [0x12345678,0x90ABCDEF]:
    crc = crc16_ccitt_false_bits(w, 32, crc)
print(f"crcw chain (2 x 32-bit): 0x{crc:04X}")

print()
print("firmware expects:        0x1E82")
