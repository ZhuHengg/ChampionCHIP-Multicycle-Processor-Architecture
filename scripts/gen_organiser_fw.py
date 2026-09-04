#!/usr/bin/env python3
"""gen_organiser_fw.py -- converts the organiser-supplied golden firmware
(external/CCX_Malaysia_Edition_Firmware_Stage_2/firmware.txt, a
`32'hADDR: r_Instruction = 32'hWORD;` case-block listing) into
firmware/organiser_validation.hex: a plain sequential-word .hex file in
the same format rtl/memory/imem.v's $readmemh expects (one 8-hex-digit
word per line, base address 0x00400000, no gaps).

This is the organiser's own Stage 2 validation program, kept separate
from firmware/validation.hex (our self-authored, self-checking slice-7g
program built by gen_validation_fw.py). Run this script to regenerate:

    python scripts/gen_organiser_fw.py

Per the organiser's README.md: firmware starts at PC=0x00400000, and at
end of execution x4 == 0x00000000 means PASS, x4 == 0xFFFFFFFF means FAIL.
"""

import re
import os

SRC = os.path.join(os.path.dirname(__file__), '..', 'external',
                    'CCX_Malaysia_Edition_Firmware_Stage_2', 'firmware.txt')
OUT = os.path.join(os.path.dirname(__file__), '..', 'firmware',
                    'organiser_validation.hex')
BASE_ADDR = 0x00400000

LINE_RE = re.compile(r"32'h([0-9A-Fa-f]+):\s*r_Instruction = 32'h([0-9A-Fa-f]+);")


def main():
    entries = []
    with open(SRC) as f:
        for line in f:
            m = LINE_RE.search(line)
            if m:
                entries.append((int(m.group(1), 16), int(m.group(2), 16)))

    if not entries:
        raise SystemExit(f"no instruction entries parsed from {SRC}")

    entries.sort(key=lambda e: e[0])

    for (a0, _), (a1, _) in zip(entries, entries[1:]):
        if a1 - a0 != 4:
            raise SystemExit(f"address gap: 0x{a0:08x} -> 0x{a1:08x} "
                              f"(expected +4) -- fill logic not implemented")

    if entries[0][0] != BASE_ADDR:
        raise SystemExit(f"firmware does not start at 0x{BASE_ADDR:08x} "
                          f"(starts at 0x{entries[0][0]:08x})")

    with open(OUT, 'w') as f:
        for _, word in entries:
            f.write(f"{word:08x}\n")

    print(f"wrote {OUT}: {len(entries)} words, "
          f"0x{entries[0][0]:08x}..0x{entries[-1][0]:08x}")


if __name__ == '__main__':
    main()
