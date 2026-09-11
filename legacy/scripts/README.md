# scripts/

No RV32I assembler is available in this project's environment
(`riscv64-unknown-elf-as`, `riscv32-unknown-elf-as`, `riscv-none-elf-as` —
all checked repeatedly, absent from PATH across slices 7c through 7g).
Every firmware `.hex` file under `firmware/` was hand-assembled with the
tools in this directory. They are committed here — not left in a session
scratchpad — because the `.hex` files can't otherwise be regenerated or
audited by anyone else working on the repo.

## Files

- **`rvbl2_asm.py`** — two-pass assembler. Supports labels, forward/backward
  branches (`beq`/`bne`/.../`bgeu`), `jal`/`jalr`, all RV32I R/I/S/B/U/J
  encodings, Zmmul (`mul`/`mulh`/`mulhsu`/`mulhu`) and Xicrc
  (`crcb`/`crch`/`crcw`), plus pseudo-ops `li` (constant load, handles the
  lui+addi bit-11 sign-extension adjustment automatically), `la` (load a
  label's absolute address), `call`/`ret` (standard `ra`=x1 convention),
  and `word` (embed a raw literal data word in IMEM, guide §4.2). Every
  opcode/funct3/funct7 literal is cross-checked against
  `rtl/pkg/rvbl2_defines.vh`, `rtl/control_unit.v`'s ALU decode table, and
  `rtl/datapath/branch_comparator.v` — see the file's own header for the
  exact citations. Nothing is invented from memory.

  Usage as a library:
  ```python
  from rvbl2_asm import Asm
  a = Asm(base_addr=0x00400000)
  a.li(1, 6); a.li(2, 7)
  a.r('mul', 3, 1, 2)
  a.ecall()
  words = a.assemble()      # [(addr, word, text, comment), ...]
  a.write_hex('out.hex')
  ```
  Run directly (`python rvbl2_asm.py`) for a small smoke-test program
  printed to stdout — not a firmware generator itself.

- **`rvbl2_decode.py`** — independent decoder, a deliberately separate
  bitfield-extraction code path from the assembler's encoder (an assembler
  that decodes its own output by re-running its own encoder backwards
  would validate its own arithmetic, not catch a shared mistake). Resolves
  branch/jal immediates to absolute target addresses so a caller can check
  the target lands on the intended label, not just that the mnemonic text
  looks right.

  CLI: `python rvbl2_decode.py firmware/validation.hex [base_addr_hex]`
  prints every decoded instruction with its resolved branch/jump targets.

- **`rvbl2_sim.py`** — small reference functional simulator (fetch-decode-
  execute over an assembled word list). A design-time verification tool,
  not part of the RTL or the Verilog testbenches' pass/fail authority: it
  lets a self-checking firmware program (like `validation.hex`) be proven
  correct — and its exact predicted cycle count derived from the handoff
  doc's per-instruction-type table — *before* ever touching `iverilog`.
  Its semantics are re-derived from the same RTL sources `rvbl2_asm.py`
  cites (plus `rtl/datapath/lsu.v`'s load-extension/store-positioning
  logic and `rtl/datapath/mult.v`/`crc.v`'s arithmetic), not copied from
  the RTL — cross-check both independently rather than trusting either
  exclusively.

- **`gen_validation_fw.py`** — builds `firmware/validation.hex` (slice 7g's
  end-to-end self-checking validation program) using `rvbl2_asm.py`,
  round-trip-verifies it with `rvbl2_decode.py`, functionally verifies it
  with `rvbl2_sim.py` (asserting it reaches `PASS_CODE`, not a `FAIL_ID`),
  and prints the exact predicted cycle count and the full check registry
  for transcription into `tb/system/tb_top_system.v`.

  Run: `python gen_validation_fw.py` — regenerates
  `firmware/validation.hex` in place and prints a full report to stdout.

- **`crc_reference.py`** — pre-existing (slice 7f), a from-scratch CRC-16/
  CCITT-FALSE reference implementation used to cross-check
  `firmware/crc_test.S`'s three chains against `rtl/datapath/crc.v`'s
  golden vectors. Unrelated to the assembler/decoder/simulator above;
  kept as-is.

## Regenerating a firmware file

Every `.hex` file in `firmware/` other than `crc_test.S` (organiser-
supplied, hand-transcribed rather than script-generated) traces back to a
generator script built on `rvbl2_asm.py`. `gen_validation_fw.py` is the
only one currently kept in this directory as a standalone, re-runnable
generator; earlier slices' firmware (`fetch_test.hex`, `alu_test.hex`,
`branch_test.hex`, `mem_test.hex`, `muldiv_test.hex`) was produced by
similar but not-yet-consolidated scripts from those sessions' scratchpads.
If one of those needs to be regenerated or audited, rebuild its generator
from `rvbl2_asm.py`/`rvbl2_decode.py` following the same pattern as
`gen_validation_fw.py`.

## Requirements

Python 3 standard library only — no third-party packages.
