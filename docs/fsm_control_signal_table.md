# FSM Control Signal Table — Scaffold

Fill in each cell per state (and per opcode group where a state's behavior
branches, e.g. EXECUTE). Leave `-` for "don't care" / signal not driven that
cycle. This table is the direct source for section 3.2 (Control Unit) of the
report, and the contract between Teammate A (control unit) and Teammates B/C
(ALU, MUL, CRC, LSU, register file).

## Signal glossary

Two categories below. Keep them visually distinct — they have different
authority. Signals in the first table are **fixed by the block guide**;
Teammate A's control unit must emit exactly these names/widths, because
Teammates B and C's modules (LSU, address decoder, ALU/MULT/CRC muxes) are
built to receive them. Signals in the second table are **not in the guide**
— they're internal FSM/datapath control signals our team is inventing
because a multicycle design needs them; the guide only specifies the fixed
module interfaces, not our internal control scheme. Names/widths here are a
proposal, not a spec — confirm with Teammate A before Teammate B/C code
against them.

### From the block guide (fixed — must match exactly)

Figure 3 confirms the naming convention: the core drives `address_o`,
`we_o`, `oe_o`, `bw_o` out of *itself*. Those same wires arrive at the
address decoder as its own input ports, named `address_i`, `we_i`, `oe_i`,
`bw_i` (same wires, named from the receiving module's perspective — this is
what our control unit must emit, since the control unit lives inside the
core). Downstream of the decoder, DMEM's write enable is a distinct signal
named `dmem_we_o`, since only DMEM can be written — IMEM never receives a
write-enable at all.

| Signal | Width (2^width = bit) | Source in guide | Meaning |
|---|---|---|---|
| `we_o` | 1 | Fig. 3, §4.4 | **Core's own output.** Write enable, driven by the control unit; becomes the decoder's `we_i`. Decoder routes it onward as `dmem_we_o` (DMEM only — never reaches IMEM) |
| `oe_o` | 1 | Fig. 3, §4.4 | **Core's own output.** Read enable, driven by the control unit; becomes the decoder's `oe_i`. Decoder routes an `oe_o` to both DMEM and IMEM |
| `bw_o` | 4 | Fig. 3, §4.4 | **Core's own output.** Byte write mask, driven by the control unit; becomes the decoder's `bw_i`. Decoder routes it onward as `bw_o` to DMEM only |
| `address_o` | 32 (30 to devices) | Fig. 3, §4.4 | **Core's own output.** Driven by the control unit/ALU; becomes the decoder's `address_i`. Decoder routes `address_o` to both DMEM and IMEM, bottom 2 bits dropped |
| `op_size_o` | 3 | Fig. 2, §3.3.3 | Core→LSU: access size + sign (word/half/byte, signed/unsigned) |
| `core_data_o` | 32 | Fig. 2 | Core→LSU: data to write (store) |
| `core_data_i` | 32 | Fig. 2 | LSU→core: data read back (load), already sign/zero-extended |
| `alu_op` | 4 | Table 9, §3.1.1 | ALU select, values 4'h0–4'hA |
| `mult_op` | 2 | Table 10, §3.1.2 | MUL unit select, values 4'h0–4'h3 |
| `crc_op` | 2 | Table 11, §3.1.3 | CRC unit select, values 4'h0–4'h2 |

### Invented by us (internal FSM control — not in the guide)

| Signal | Width | Meaning |
|---|---|---|
| `pc_write` | 1 | Enable PC register to latch a new value this cycle |
| `pc_src` | 2 | Select PC input: `00`=PC+4, `01`=branch/jump target, `10`=jalr target |
| `ir_write` | 1 | Enable IR to latch instruction from IMEM |
| `reg_write` | 1 | Enable register file write in this cycle |
| `result_src` | 3 | Select value written to `rd`: `000`=ALU out, `001`=MUL out, `010`=CRC out, `011`=DMEM data (`core_data_i`), `100`=PC+4 (jal/jalr) |
| `alu_src_a` | 1 | ALU input A: `0`=rs1, `1`=PC |
| `alu_src_b` | 2 | ALU input B: `00`=rs2, `01`=immediate, `10`=constant 4 |
| `imm_sel` | 3 | Immediate format: I / S / B / U / J |
| `mult_en` | 1 | Enable multiplier, latch A/B into MUL unit this cycle |
| `crc_en` | 1 | Enable CRC unit this cycle |
| `branch_taken` | 1 | Output from branch comparator, consumed by `pc_src` logic (not driven by control unit — informs next state) |

**Resolved (was an open question):** confirmed against Figure 3 — the core
drives `address_o`/`we_o`/`oe_o`/`bw_o`, which arrive at the decoder as its
input ports `address_i`/`we_i`/`oe_i`/`bw_i` (same wires, opposite-end
naming). Our control unit should emit the `_o` names. Note DMEM's
write-enable is specifically `dmem_we_o` downstream of the decoder, since
IMEM has no write path at all.

## Per-state table

Columns follow the same split: guide-fixed signals (`we_o`, `oe_o`, `bw_o`,
`op_size_o`) on the right, our invented internal signals on the left.

| State | pc_write | pc_src | ir_write | reg_write | result_src | alu_src_a | alu_src_b | alu_op | imm_sel | mult_en | crc_en | we_o | oe_o | bw_o | op_size_o | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **RESET** | 0 | - | 0 | 0 | - | - | - | - | - | 0 | 0 | 0 | 0 | - | - | PC ← 0x00400000 |
| **FETCH** | 1 | 00 | 1 | 0 | - | - | - | - | - | 0 | 0 | 0 | 1 | - | - | oe_o reads IMEM |
| **DECODE** | 0 | - | 0 | 0 | - | - | - | - | per opcode | 0 | 0 | 0 | 0 | - | - | Async RF read only, no writes |
| **EXECUTE — R-type/I-type ALU** | 0 | - | 0 | 0 | 000 | 0 | 00 / 01 | per funct3/7 | I (if imm) | 0 | 0 | 0 | 0 | - | - | |
| **EXECUTE — MUL (Zmmul)** | 0 | - | 0 | 0 | 001 | 0 | 00 | - | - | 1 | 0 | 0 | 0 | - | - | May need MUL_WAIT if iterative |
| **EXECUTE — CRC (Xicrc)** | 0 | - | 0 | 0 | 010 | 0 | 00 | - | - | 0 | 1 | 0 | 0 | - | - | |
| **EXECUTE — Branch** | 0/1 | 01 | 0 | 0 | - | 1 | 01 | ADD (target) | B | 0 | 0 | 0 | 0 | - | - | pc_write depends on branch_taken |
| **EXECUTE — Jump (JAL)** | 1 | 01 | 0 | 0 | 100 | 1 | 01 | ADD (target) | J | 0 | 0 | 0 | 0 | - | - | reg_write happens at WB, not here |
| **EXECUTE — Jump (JALR)** | 1 | 10 | 0 | 0 | 100 | 0 | 01 | ADD (target) | I | 0 | 0 | 0 | 0 | - | - | |
| **EXECUTE — LUI** | 0 | - | 0 | 0 | 000 | - | 01 | PASS_B | U | 0 | 0 | 0 | 0 | - | - | |
| **EXECUTE — AUIPC** | 0 | - | 0 | 0 | 000 | 1 | 01 | ADD | U | 0 | 0 | 0 | 0 | - | - | |
| **MEM_ADDR** | 0 | - | 0 | 0 | - | 0 | 01 | ADD | I / S | 0 | 0 | 0 | 0 | - | - | Computes effective address for load/store |
| **MEM_ACCESS — Load (addr out)** | 0 | - | 0 | 0 | - | - | - | - | - | 0 | 0 | 0 | 1 | - | per instr. | TBD: may split into 2 cycles — see open issue |
| **MEM_ACCESS — Load (data in)** | 0 | - | 0 | 0 | 011 | - | - | - | - | 0 | 0 | 0 | 0 | - | - | Latch core_data_i into buffer |
| **MEM_ACCESS — Store** | 0 | - | 0 | 0 | - | - | - | - | - | 1 | 0 | 1 | 0 | per size/addr[1:0] | per instr. | |
| **WRITE BACK** | 0 | - | 0 | 1 | (from EXECUTE/MEM state) | - | - | - | - | 0 | 0 | 0 | 0 | - | - | |

## Resolved — Issue 2: DMEM load timing (1 vs 2 sub-cycles)

**Decision: loads need 2 sub-cycles in MEM_ACCESS, stores need only 1.**

DMEM is a synchronous SRAM we build ourselves. The safe, standard
implementation is registered-output: the memory array captures the address
on a clock edge, and the data output updates *from* that edge — so valid
read data isn't available until the *next* cycle, not combinationally
within the same one. A write, by contrast, commits *on* the edge itself
(address/data/`we_o` just need to be stable going into it) — no waiting.

This means the per-state table's two load rows are real, distinct cycles,
not a loose description of one cycle:

- **MEM_ACCESS_ADDR** (load only): address presented, `oe_o = 1`, DMEM
  begins its internal capture.
- **MEM_ACCESS_DATA** (load only): DMEM's registered output is now valid;
  latch `core_data_i` into a buffer register (sign/zero extension per
  `op_size_o` happens here, inside the LSU).
- **MEM_ACCESS** (store only, single cycle): address, `core_data_o`,
  `we_o`, and `bw_o` all presented together; write commits on this cycle's
  clock edge; loop straight back to FETCH, no write back needed.

Confirms `lw` at 6 cycles (fetch, decode, mem_addr, mem_access_addr,
mem_access_data, write back) and `sw` at 5 (fetch, decode, mem_addr,
mem_access, back to fetch — no write back).

## Resolved — Issue 3: Decode's opcode → next-state map

**Important wrinkle:** `Zmmul` (MUL) and `Xicrc` (CRC) instructions share
the *same opcode* (`0110011`) as base R-type ALU instructions (Tables 7–8
in the guide). Decode cannot route on opcode alone for this case — it must
also inspect `funct7` to tell the three apart.

| Opcode (binary) | funct7 (if 0110011) | Category | Next state |
|---|---|---|---|
| `0110011` | `0000000` (and other non-special codes) | R-type ALU | EXECUTE — ALU |
| `0110011` | `0000001` | Zmmul (MUL) | EXECUTE — MUL |
| `0110011` | `1000000` | Xicrc (CRC) | EXECUTE — CRC |
| `0010011` | — | I-type ALU | EXECUTE — ALU |
| `0000011` | — | Load | MEM_ADDR |
| `0100011` | — | Store | MEM_ADDR |
| `1100011` | — | Branch | EXECUTE — Branch |
| `1101111` | — | JAL | EXECUTE — Jump (JAL) |
| `1100111` | — | JALR | EXECUTE — Jump (JALR) |
| `0110111` | — | LUI | EXECUTE — LUI |
| `0010111` | — | AUIPC | EXECUTE — AUIPC |
| `1110011` | — | ECALL / EBREAK | TBD (Issue 4 — not yet designed) |
| `0001111` | — | FENCE | TBD (Issue 4 — not yet designed) |

Note: exact opcode bit patterns above should be double-checked against the
RISC-V spec [1] cited in the guide before this goes into RTL — these are
the standard RV32I encodings but worth a direct verification pass, since a
wrong opcode literal here silently misroutes an entire instruction class.

## ALU / MUL / CRC operation codes (from Tables 9, 10, 11 of the block guide)

These are fixed by the guide — copy exactly, do not re-derive.

**`alu_op` (Table 9, §3.1.1):**

| Code | Operation | Instructions that use it |
|---|---|---|
| `4'h0` | PASS_B | LUI |
| `4'h1` | ADD | ADD, ADDI, load/store address calc, AUIPC, branch/jump target calc |
| `4'h2` | SUB | SUB, branch comparisons (BEQ/BNE use subtract-and-check-zero internally, or route through the dedicated comparator per §3.1.6 — confirm with Teammate B which path is used) |
| `4'h3` | AND | AND, ANDI |
| `4'h4` | OR | OR, ORI |
| `4'h5` | XOR | XOR, XORI |
| `4'h6` | SLL | SLL, SLLI |
| `4'h7` | SRL | SRL, SRLI |
| `4'h8` | MRS (arithmetic shift) | SRA, SRAI |
| `4'h9` | SLT | SLT, SLTI |
| `4'hA` | SLTU | SLTU, SLTIU |

**`mult_op` (Table 10, §3.1.2):**

| Code | Operation | Instruction |
|---|---|---|
| `4'h0` | MUL | mul |
| `4'h1` | MULH | mulh |
| `4'h2` | MULHSU | mulhsu |
| `4'h3` | MULHU | mulhu |

**`crc_op` (Table 11, §3.1.3):**

| Code | Operation | Instruction |
|---|---|---|
| `4'h0` | CRCB | crcb |
| `4'h1` | CRCH | crch |
| `4'h2` | CRCW | crcw |

Note the guide's tables label these as 4-bit values (`4'h0`–`4'hA` /
`4'h0`–`4'h3` / `4'h0`–`4'h2`) even though MUL only needs 2 bits and CRC
only needs 2 bits to enumerate their options — worth deciding whether to
keep `mult_op`/`crc_op` at 4 bits to match the guide's literal encoding, or
narrow them to 2 bits internally and let Teammate B's module decode
whichever width is agreed. Flag this with Teammate B before finalizing port
widths.

## Resolved — Issue 1: MUL implementation choice

**Decision: combinational (single-cycle) 64-bit multiplier.**

At the clock speeds this project realistically targets (tens of MHz — not
pushing Sky130 anywhere near its speed limit), a combinational 32×32→64-bit
multiplier has ample timing slack even on a 130nm process. The real risk
from this choice isn't timing closure, it's die area — Sky130 gates are
large, so a full combinational multiplier is a non-trivial chunk of the
report's area/density numbers (§5). Going combinational first prioritizes a
working, verifiable core; if OpenLane's area report later shows MUL
dominating total area, revisit with an iterative shift-add version (which
would reintroduce a `MUL_WAIT` state with a `done` handshake — not needed
under this decision).

**Consequence for the FSM:** no new state required. EXECUTE — MUL stays a
single cycle, `mult_en=1` triggers the full computation combinationally
that same cycle, result is ready for WRITE BACK on the next edge, matching
the per-state table already in this doc.

## Still to fill in

- `op_size` encoding (probably 3 bits: size[1:0] + sign) — define alongside LSU interface with Teammate C
- `imm_sel` exact encoding and which opcodes map to which immediate format
- Whether MEM_ACCESS for loads is genuinely 1 or 2 sub-states (depends on DMEM timing decision — flagged as open issue)
- ECALL / EBREAK / FENCE — likely a no-op path through EXECUTE, not yet added as a row
