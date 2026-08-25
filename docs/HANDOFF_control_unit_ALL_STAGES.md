# Master Handoff — Control Unit, All Stages (ChampionCHIP RVBL-2)

Single self-contained document covering the control unit from spec through
`top.v` integration. Everything needed to pick up the work cold, without
re-deriving decisions already made.

**Consolidates:** `HANDOFF_control_unit.md` (spec), `CONTROL_UNIT_BUILD_PLAN.md`
(slice roadmap), `SLICE1_PLAN.md` (slice 1 detail). Those remain as the
working documents; this is the single-read overview. **Where they disagree,
this document is newer — but check `rvbl2_defines.vh` for the actual
authoritative constant values, since that's what the RTL compiles against.**

**Also read:** `.claude/CLAUDE.md` — the 9-step per-module workflow is
mandatory and this document assumes it.

---

# PART I — PROJECT CONTEXT

Multicycle RISC-V core (RV32I + Zmmul + Xicrc), built from the single-cycle
ChampionCHIP training core, extended per the Stage 2 Block Guide
(`ChipInventor RVBL-2`, `docs/Championchip-stage-2-guide.pdf`).

**Deliverables depending on this doc:** report §3.2 (Control Unit), report §2
(ISA coverage table), and `rtl/control_unit.v` itself.

**ChipInventor is figure-generation only** — not the RTL/verification
environment. All RTL, simulation, and physical design happen outside it.

**Ownership (per README):** FSM pair owns `rtl/control_unit.v`, `rtl/top.v`,
`tb/control_unit/`. Memory pair owns `rtl/memory/`, `tb/memory/`. Datapath
(`rtl/datapath/` — ALU, mult, CRC, branch comparator, immediate extender) is
shared across all four. `rtl/pkg/rvbl2_defines.vh` is shared — everyone
reads, nobody edits without team agreement.

---

# PART II — THE SPEC

## 1. FSM state diagram

```
RESET → FETCH → DECODE ─┬─→ EXECUTE (case on opcode/funct7/funct3) ─┐
                        │                                           │
                        └─→ MEM_ADDR → MEM_ACCESS (load/store)       │
                                                                     │
      ┌── branch / store: loop directly back to FETCH ───────────────┤
      │                                                              │
      └── everything else: → WRITE BACK → FETCH ←────────────────────┘
```

Three design decisions baked into this shape:

- **Branch and jump are NOT separate states** — cases inside EXECUTE,
  selected by opcode, same as ALU/MUL/CRC. No shared-hardware conflict
  justifies splitting them, and splitting would cost every branch/jump an
  extra cycle for nothing.
- **Loads take 2 sub-cycles in MEM_ACCESS** (`MEM_ACCESS_ADDR` then
  `MEM_ACCESS_DATA`); **stores take 1.** Forced by DMEM being a synchronous
  registered-output SRAM (guide §4.3) — read data isn't valid until the cycle
  *after* the address is presented; writes commit on the edge itself.
- **Branches and stores skip WRITE BACK**, looping straight to FETCH — they
  produce no register result.

## 2. Cycle counts (verify against this every slice)

| Instruction type | Cycles | Path |
|---|---|---|
| R-type / I-type ALU, MUL, CRC, LUI, AUIPC | 4 | fetch, decode, execute, write back |
| Branch | 3 | fetch, decode, execute → fetch |
| JAL / JALR | 4 | fetch, decode, execute, write back |
| Store | 4 | fetch, decode, mem_addr, mem_access → fetch |
| Load | 6 | fetch, decode, mem_addr, mem_access_addr, mem_access_data, write back |
| ECALL / EBREAK / FENCE | 3 | fetch, decode, execute → fetch |

**Cycle count = number of states traversed**, consistently across every row.
Store is 4, not 5: it visits FETCH, DECODE, MEM_ADDR, MEM_ACCESS_STORE and
then loops straight back to FETCH, skipping WRITE BACK because a store
produces no register result. (Earlier revisions of this table and of
`HANDOFF_control_unit.md` §2 said 5 — that was an arithmetic slip, derived
by subtracting one from load's 6 without also accounting for store dropping
WRITE BACK. The four state names listed for store have always been correct.)

## 3. Naming convention

**All control-unit outputs use `_o`, invented ones included** —
`pc_write_o`, not bare `pc_write`. This mirrors the guide's own convention
(`we_o` on the core's side becomes `we_i` on the receiving module's side),
applied uniformly so the port list reads consistently instead of mixing two
styles. Inputs take `_i` — hence `branch_taken_i`.

**State encoding stays `localparam` inside `control_unit.v`**, never in the
shared `defines.vh` — it doesn't cross a module boundary (no other module
reads `state`, only the outputs derived from it), so there's no cross-file
mismatch risk to guard against by sharing it.

## 4. Signal glossary

### Guide-fixed — names must match exactly

The core drives these as its own outputs; they arrive at the address decoder
as `_i` ports (same wires, named from the receiving side). Downstream the
decoder produces `dmem_we_o` for DMEM specifically (IMEM has no write path) —
that renaming happens inside the decoder, not something the control unit
drives.

| Signal | Width | Source | Meaning |
|---|---|---|---|
| `we_o` | 1 | Fig. 3, §4.4 | Write enable |
| `oe_o` | 1 | Fig. 3, §4.4 | Read enable |
| `bw_o` | 4 | Fig. 3, §4.4 | Byte write mask — one bit per byte, **not** a binary-coded selector |
| `address_o` | 32 | Fig. 3, §4.4 | Address bus; bottom 2 bits dropped before reaching devices |
| `op_size_o` | 3 | Fig. 2, §3.3.3 | Core→LSU: access size + sign |
| `core_data_o` | 32 | Fig. 2 | Core→LSU: store data |
| `core_data_i` | 32 | Fig. 2 | LSU→core: load data, already sign/zero-extended |
| `core_address_o` | 32 | Fig. 2 | Core→LSU: access address |
| `mem_data_o` | 32 | Fig. 2 | Memory→LSU: raw word read back |
| `mem_data_i` | 32 | Fig. 2 | LSU→memory: store data, byte-positioned |
| `mem_address_i` | 32 | Fig. 2 | LSU→memory: address |
| `byte_write_i` | 4 | Fig. 2 | LSU→memory: byte write mask — the guide's own name for what §4.4 calls `bw_o` on the core side |

**Verified against the PDF, 2026-08-25.** This is the complete set of port
names the guide actually states. `we_o`/`oe_o`/`bw_o`/`address_o` appear in
the §4.4 body text and in Figure 3; the LSU names are the labels drawn
inside Figure 2. Nothing else in the guide names a port.

### Op-select ports — encodings guide-fixed, names ours

Tables 9/10/11 are **value tables**: an encoding column and an operation
column, no port-name column. The strings `alu_op`, `mult_op`, and `crc_op`
appear nowhere in the guide (full-text search of the PDF, 2026-08-25).
Encodings must match exactly; the names are a team decision.

| Signal | Width | Encoding source | Meaning |
|---|---|---|---|
| `alu_op_o` | 4 | Table 9 | ALU select, `4'h0`–`4'hA` (11 values → 4 bits) |
| `mult_op_o` | 4 | Table 10 | MUL select, values 0–3 |
| `crc_op_o` | 4 | Table 11 | CRC select, values 0–2 |

✅ **Resolved 2026-08-25.** These were originally declared bare
(`mult_op`/`crc_op`), the only two control-unit outputs missing the `_o`
suffix. Renamed to `mult_op_o`/`crc_op_o` before `top.v` was written, while
`control_unit.v` was still the only file referencing them. `mult.v` and
`crc.v` receive them as `mult_op_i`/`crc_op_i` and were untouched.

### Invented internally — not in the guide

| Signal | Width | Meaning |
|---|---|---|
| `pc_write_o` | 1 | Enable PC to latch new value this cycle |
| `pc_src_o` | 2 | `00`=PC+4, `01`=branch/jump target, `10`=jalr target |
| `ir_write_o` | 1 | Enable IR to latch from IMEM (asserted only in FETCH) |
| `reg_write_o` | 1 | Enable register file write |
| `result_src_o` | 3 | `000`=ALU, `001`=MUL, `010`=CRC, `011`=DMEM data, `100`=PC+4 |
| `alu_src_a_o` | 1 | `0`=rs1, `1`=PC |
| `alu_src_b_o` | 2 | `00`=rs2, `01`=immediate, `10`=constant 4 |
| `imm_sel_o` | 3 | Immediate format select — see §5 |
| `mult_en_o` | 1 | Trigger multiplier this cycle |
| `crc_en_o` | 1 | Trigger CRC unit this cycle |
| `branch_taken_i` | 1 | Comparator output → feeds `pc_src_o` decision. **Input**, not an output |

## 5. Settled encodings

All macros live in `rtl/pkg/rvbl2_defines.vh`. **Use the macros, never raw
literals.**

### `imm_sel_o` — immediate format select

| Value | Format | Used by | Macro |
|---|---|---|---|
| `3'b000` | I | I-type ALU, JALR, loads | `` `IMM_SEL_I `` |
| `3'b001` | S | Stores | `` `IMM_SEL_S `` |
| `3'b010` | B | Branches | `` `IMM_SEL_B `` |
| `3'b011` | U | LUI, AUIPC | `` `IMM_SEL_U `` |
| `3'b100` | J | JAL | `` `IMM_SEL_J `` |

### `op_size_o` — `[2:1]`=size, `[0]`=sign

Sign bit is don't-care for stores (stores never extend).

| Value | Size | Sign | Instruction | Macro |
|---|---|---|---|---|
| `3'b000` | byte | signed | lb / sb | `` `OP_SIZE_BYTE_S `` |
| `3'b001` | byte | unsigned | lbu | `` `OP_SIZE_BYTE_U `` |
| `3'b010` | half | signed | lh / sh | `` `OP_SIZE_HALF_S `` |
| `3'b011` | half | unsigned | lhu | `` `OP_SIZE_HALF_U `` |
| `3'b100` | word | — | lw / sw | `` `OP_SIZE_WORD `` |

### `bw_o` — byte write mask, driven by the control unit

Computed from `op_size_o` and `addr_lsb_i[1:0]`.

**Note the input port.** The effective address is `rs1 + imm`, computed by
the ALU — the control unit never drives `address_o` (see the per-state table
in §9, where no state drives it). So the CU takes the low 2 address bits back
as a dedicated 2-bit input, `addr_lsb_i`, sourced from the ALU result
register. It exists solely to compute `bw_o`; the CU does not own or drive
`address_o` itself. Added in slice 2.

- word → `4'b1111` (address bits irrelevant)
- half → `4'b0011` if `address[1]=0`, else `4'b1100`
- byte → `4'b0001` shifted left by `address[1:0]` — e.g. `address[1:0]=10`
  → `4'b0100`, matching guide §3.3.2's worked example of writing byte 3

Keeping this in the control unit leaves the LSU a purely combinational
passthrough, and puts all "which bytes" logic in one place — the control unit
already owns `op_size_o` selection.

## 6. Opcode → next-state map

| Opcode | funct7 (if `0110011`) | Category | Next state | Macro |
|---|---|---|---|---|
| `0110011` | **else** (not `0000001`, not `1000000`) | R-type ALU | EXECUTE — ALU | `` `OPCODE_RTYPE `` |
| `0110011` | `0000001` | Zmmul | EXECUTE — MUL | `` `FUNCT7_MUL `` |
| `0110011` | `1000000` | Xicrc | EXECUTE — CRC | `` `FUNCT7_CRC `` |
| `0010011` | — | I-type ALU | EXECUTE — ALU | `` `OPCODE_ITYPE `` |
| `0000011` | — | Load | MEM_ADDR | `` `OPCODE_LOAD `` |
| `0100011` | — | Store | MEM_ADDR | `` `OPCODE_STORE `` |
| `1100011` | — | Branch | EXECUTE — Branch | `` `OPCODE_BRANCH `` |
| `1101111` | — | JAL | EXECUTE — JAL | `` `OPCODE_JAL `` |
| `1100111` | — | JALR | EXECUTE — JALR | `` `OPCODE_JALR `` |
| `0110111` | — | LUI | EXECUTE — LUI | `` `OPCODE_LUI `` |
| `0010111` | — | AUIPC | EXECUTE — AUIPC | `` `OPCODE_AUIPC `` |
| `1110011` | — | ECALL / EBREAK | EXECUTE — no-op | `` `OPCODE_SYSTEM `` |
| `0001111` | — | FENCE | EXECUTE — no-op | `` `OPCODE_FENCE `` |

### ⚠ The funct7 else-trap — read this before writing decode

**Category selection is an `else`, not a three-way equality check.** SUB and
SRA use `funct7 = 0100000` — a fourth value the table above never lists as a
category. Correct logic:

```verilog
if      (funct7_i == `FUNCT7_MUL) ...  // Zmmul
else if (funct7_i == `FUNCT7_CRC) ...  // Xicrc
else                              ...  // R-type ALU (0000000 AND 0100000)
```

Writing `if (funct7 == 7'b0000000)` to mean "this is ALU" silently breaks SUB
and SRA — they match nothing and fall through to whatever the default is.
There is deliberately **no `FUNCT7_ALU` constant** in `defines.vh` to
discourage exactly that mistake.

`funct7[5]` gets used again *inside* the ALU branch, but for a different
purpose — picking ADD vs SUB and SRL vs SRA within `alu_op_o`, not selecting
the ALU category itself. Two different jobs, same bit.

## 7. `alu_op_o` decode table

`alu_op_o` **needs real decode logic** — the guide's codes do not match
RV32I's funct3 numbering, so this is a lookup on (funct3, funct7[5]), never a
passthrough. Only funct3 `000` and `101` consult funct7[5]:

| Instruction | funct3 | funct7 | funct7[5] | alu_op_o | Macro |
|---|---|---|---|---|---|
| ADD | `000` | `0000000` | 0 | `4'h1` | `` `ALU_ADD `` |
| SUB | `000` | `0100000` | 1 | `4'h2` | `` `ALU_SUB `` |
| SLL | `001` | `0000000` | 0 | `4'h6` | `` `ALU_SLL `` |
| SLT | `010` | `0000000` | 0 | `4'h9` | `` `ALU_SLT `` |
| SLTU | `011` | `0000000` | 0 | `4'hA` | `` `ALU_SLTU `` |
| XOR | `100` | `0000000` | 0 | `4'h5` | `` `ALU_XOR `` |
| SRL | `101` | `0000000` | 0 | `4'h7` | `` `ALU_SRL `` |
| SRA | `101` | `0100000` | 1 | `4'h8` | `` `ALU_MRS `` |
| OR | `110` | `0000000` | 0 | `4'h4` | `` `ALU_OR `` |
| AND | `111` | `0000000` | 0 | `4'h3` | `` `ALU_AND `` |

Ten rows, matching the guide's "Arithmetic and Logic (Register): 10 expected."
`` `ALU_PASS_B `` (`4'h0`) has no R-type instruction — it's used by LUI only.

## 8. `mult_op_o` / `crc_op_o` — direct funct3 passthrough

**The opposite of `alu_op_o`.** The guide's numbering makes these identical
to funct3 by construction, so no lookup table is needed:

```verilog
mult_op_o = {2'b00, funct3_i};   // 4-bit port, zero-extended
crc_op_o  = {2'b00, funct3_i};
```

| mult_op_o | Instruction | funct3 | | crc_op_o | Instruction | funct3 |
|---|---|---|---|---|---|---|
| `4'h0` | mul | `000` | | `4'h0` | crcb | `000` |
| `4'h1` | mulh | `001` | | `4'h1` | crch | `001` |
| `4'h2` | mulhsu | `010` | | `4'h2` | crcw | `010` |
| `4'h3` | mulhu | `011` | | | | |

**This asymmetry with `alu_op_o` is deliberate and documented** — don't
"fix" it into consistency by building a lookup table MUL/CRC don't need.

## 9. Per-state control signal table

| State | pc_write_o | pc_src_o | ir_write_o | reg_write_o | result_src_o | alu_src_a_o | alu_src_b_o | alu_op_o | imm_sel_o | mult_en_o | crc_en_o | we_o | oe_o | bw_o | op_size_o |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| RESET | 0 | - | 0 | 0 | - | - | - | - | - | 0 | 0 | 0 | 0 | - | - |
| FETCH | 1 | 00 | 1 | 0 | - | - | - | - | - | 0 | 0 | 0 | 1 | - | - |
| DECODE | 0 | - | 0 | 0 | - | - | - | - | per opcode | 0 | 0 | 0 | 0 | - | - |
| EXECUTE — ALU (R/I-type) | 0 | - | 0 | 0 | 000 | 0 | 00/01 | per funct3/7 | I | 0 | 0 | 0 | 0 | - | - |
| EXECUTE — MUL | 0 | - | 0 | 0 | 001 | 0 | 00 | - | - | 1 | 0 | 0 | 0 | - | - |
| EXECUTE — CRC | 0 | - | 0 | 0 | 010 | 0 | 00 | - | - | 0 | 1 | 0 | 0 | - | - |
| EXECUTE — Branch | 0/1\* | 01 | 0 | 0 | - | 1 | 01 | ADD | B | 0 | 0 | 0 | 0 | - | - |
| EXECUTE — JAL | 1 | 01 | 0 | 0 | 100 | 1 | 01 | ADD | J | 0 | 0 | 0 | 0 | - | - |
| EXECUTE — JALR | 1 | 10 | 0 | 0 | 100 | 0 | 01 | ADD | I | 0 | 0 | 0 | 0 | - | - |
| EXECUTE — LUI | 0 | - | 0 | 0 | 000 | - | 01 | PASS_B | U | 0 | 0 | 0 | 0 | - | - |
| EXECUTE — AUIPC | 0 | - | 0 | 0 | 000 | 1 | 01 | ADD | U | 0 | 0 | 0 | 0 | - | - |
| EXECUTE — ECALL/EBREAK/FENCE | 0 | - | 0 | 0 | - | - | - | - | - | 0 | 0 | 0 | 0 | - | - |
| MEM_ADDR | 0 | - | 0 | 0 | - | 0 | 01 | ADD | I/S | 0 | 0 | 0 | 0 | - | - |
| MEM_ACCESS_ADDR (load) | 0 | - | 0 | 0 | - | - | - | - | - | 0 | 0 | 0 | 1 | - | per instr |
| MEM_ACCESS_DATA (load) | 0 | - | 0 | 0 | 011 | - | - | - | - | 0 | 0 | 0 | 0 | - | - |
| MEM_ACCESS (store) | 0 | - | 0 | 0 | - | - | - | - | - | 0 | 0 | 1 | 0 | per size/addr[1:0] | per instr |
| WRITE BACK | 0 | - | 0 | 1 | (carried from prior state) | - | - | - | - | 0 | 0 | 0 | 0 | - | - |

\* `pc_write_o` for branch is conditional on `branch_taken_i`. This is the
**only** output that depends on a datapath input rather than state alone.

**Implementation deviation, applies to every slice:** this table shows `-`
for don't-care. The RTL fills those with concrete defaults instead, because
CLAUDE.md requires every output assigned before any `case` to avoid inferred
latches during OpenLane synthesis. Behavior is identical — the datapath
ignores those signals in those states. Document this inline in the RTL.

---

# PART III — THE BUILD SEQUENCE

## Locked decisions — apply to every slice

1. **Reset is synchronous.** `always @(posedge clk_i)` with `if (rst_i)`
   inside. Never `or posedge rst_i`.
2. **All outputs `_o`, all inputs `_i`** (§3).
3. **State encoding is `localparam`** inside `control_unit.v` (§3).
4. **4-bit state register.** Nine-plus states eventually.
5. **Three always blocks, one purpose each:** state register (sequential,
   `<=`), next-state (combinational, `=`), output logic (combinational, `=`,
   every output defaulted before any `case`). Never mix `<=` and `=` in one
   block; never combine state and output logic.
6. **Every constant from `rvbl2_defines.vh`** via a named macro.
7. **MUL is combinational, single-cycle.** No `MUL_WAIT` state unless the
   OpenLane area report forces a revisit.
8. **funct7 category selection is an `else`** (§6 trap).

## Definition of done — every slice

Testbench written, simulation actually run, output reported verbatim,
deviations commented inline in the RTL citing the handoff section.
**"Should work" is not a status** — either it passed its testbench or it
hasn't been tested. Say which.

**Re-run the full testbench after every slice, not just the new tests.** Each
slice adds branches to shared decode logic. Slice 4 in particular can break
slice 1's SUB/SRA if the funct7 dispatch was written as an equality chain.

## Slice status

| Slice | Scope | Status | Blockers |
|---|---|---|---|
| 1 | R-type ALU path | **Done, passing** | — |
| 2 | Load / store | **Done, passing** (19/19 incl. slice 1 regression) | — |
| 3 | Branch / jump | Unblocked (needs `branch_taken_i` stub for testing) | — |
| 4 | MUL / CRC | Unblocked | — |
| 5 | LUI / AUIPC / system no-ops | Unblocked | — |
| 6 | I-type ALU | Unblocked | — |
| 7 | `top.v` integration | Not started | Slices 2-6 + datapath/memory modules |

---

## Slice 1 — R-type ALU path ✅ DONE

**Scope:** FETCH → DECODE → EXECUTE_ALU → WRITE_BACK → FETCH, opcode
`0110011` via the funct7 else-branch. 4 cycles.

**Implemented:** 5 states, sync reset, 10-way `alu_op_o` decode on
(funct3, funct7[5]), 10 output ports.

**Tested and passing:** all 10 R-type ALU instructions (ADD, SUB, SLL, SLT,
SLTU, XOR, SRL, SRA, OR, AND), each verified for correct `alu_op_o` and a
4-cycle count. Simulation output: `ALL TESTS PASSED`.

**Carried forward:**
- Illegal-opcode default is `` `ALU_ADD `` placeholder. **Policy now decided**
  (silent no-op, decision #13) — fold the change into the next edit of
  `control_unit.v`; it changes nothing observable for the 47 defined
  instructions.
- `opcode_i` declared but unused — DECODE unconditionally targets
  EXECUTE_ALU. Resolved in slice 2, where it started being read.

---

## Slice 2 — Load / store

**New states:** `MEM_ADDR`, `MEM_ACCESS_ADDR`, `MEM_ACCESS_DATA`,
`MEM_ACCESS_STORE`.

**Paths:**
- Load: FETCH → DECODE → MEM_ADDR → MEM_ACCESS_ADDR → MEM_ACCESS_DATA →
  WRITE_BACK → FETCH. **6 cycles.**
- Store: FETCH → DECODE → MEM_ADDR → MEM_ACCESS_STORE → FETCH. **4 cycles**,
  no write back.

**New ports:** `bw_o` (4), `op_size_o` (3), `address_o` (32),
`core_data_o` (32), `core_data_i` (32) — all guide-fixed names.

**DECODE gains real work** — this is where `opcode_i` starts being read.
`OPCODE_LOAD`/`OPCODE_STORE` → MEM_ADDR; `OPCODE_RTYPE` → EXECUTE_ALU.
MEM_ADDR then branches on opcode to pick the load or store sub-path.

**Key values:** `alu_op_o = ADD` in MEM_ADDR (effective address = rs1 +
offset), `alu_src_b_o = ALU_SRC_B_IMM`, `imm_sel_o = IMM_SEL_I` for loads /
`IMM_SEL_S` for stores, `result_src_o = RESULT_SRC_MEM` in MEM_ACCESS_DATA.

**Test vectors — use the guide's own worked example (Table 12), not invented
ones.** DMEM holds `0xF1/F2/F3/F4` at `0x10010000`; guide §3.3.1 works out
all five load results:

| Instruction | Address | Expected result |
|---|---|---|
| `lbu` | `0x10010000` | `0x000000F1` |
| `lb` | `0x10010000` | `0xFFFFFFF1` |
| `lhu` | `0x10010000` | `0x0000F2F1` |
| `lh` | `0x10010000` | `0xFFFFF2F1` |
| `lw` | `0x10010000` | `0xF4F3F2F1` |
| `lb` | `0x10010002` | `0x000000F3` (byte repositioning) |

At control-unit level these verify `op_size_o` and cycle counts, not the
extension itself (that's the LSU's job) — but they're the golden reference
when the two modules meet at `top.v`.

**Also assert:** load = 6 cycles, store = 4 cycles, and **`we_o` is 0 in
every state except MEM_ACCESS_STORE.** A stray write enable corrupts memory
silently — this is the highest-consequence assertion in the slice.

---

## Slice 3 — Branch / jump

**No new states** — cases inside EXECUTE, selected by opcode.

**New EXECUTE cases:** `OPCODE_BRANCH`, `OPCODE_JAL`, `OPCODE_JALR`.

**New port:** `branch_taken_i` (1, **input** from the comparator). Needs the
real `branch_comparator.v` or a testbench stub — a testing dependency, not a
spec gap, so RTL can be written now.

**Cycle counts:** branch = 3 (no write back), JAL/JALR = 4.

**The conditional-PC-write case:** for branch, `pc_write_o` follows
`branch_taken_i` rather than being a constant. Only place in the design where
an output isn't a pure function of state.

**Per-instruction values:**

| | pc_src_o | alu_src_a_o | result_src_o | imm_sel_o |
|---|---|---|---|---|
| Branch | `PC_SRC_TARGET` | `ALU_SRC_A_PC` | - | `IMM_SEL_B` |
| JAL | `PC_SRC_TARGET` | `ALU_SRC_A_PC` | `RESULT_SRC_PC4` | `IMM_SEL_J` |
| JALR | `PC_SRC_JALR` | `ALU_SRC_A_RS1` | `RESULT_SRC_PC4` | `IMM_SEL_I` |

JALR differs on `alu_src_a_o` because its target is `rs1 + imm`, not
`PC + imm`. `RESULT_SRC_PC4` for the jumps because the link register gets
PC+4 while the ALU is busy computing the target.

**Do not decode branch funct3 in the control unit** — funct3 selects which
comparison, but that's the comparator's job. The control unit only routes
`branch_taken_i`.

**Tests:** all 6 branch instructions with `branch_taken_i` forced both 0 and
1 — assert `pc_write_o` follows it and `pc_src_o` is right in both cases.
JAL/JALR: 4 cycles, `result_src_o == RESULT_SRC_PC4`, correct `pc_src_o`.
Assert `reg_write_o` stays 0 for branches throughout.

---

## Slice 4 — MUL / CRC

**No new states.** MUL is combinational and single-cycle, so EXECUTE handles
it in one cycle like ALU. 4 cycles total.

**New EXECUTE cases:** both under `OPCODE_RTYPE`, disambiguated by funct7 —
`FUNCT7_MUL` → MUL, `FUNCT7_CRC` → CRC, **else → ALU**. This is where slice
1's else-structure pays off.

**New ports:** `mult_op_o` (4), `crc_op_o` (4), `mult_en_o` (1), `crc_en_o` (1).

**Wiring:** `mult_op_o = {2'b00, funct3_i}`, `crc_op_o = {2'b00, funct3_i}` —
passthrough, no lookup table (§8).

**`result_src_o`:** `RESULT_SRC_MUL` for MUL, `RESULT_SRC_CRC` for CRC.

**Tests:** 4 MUL (mul, mulh, mulhsu, mulhu — funct3 000/001/010/011) and 3
CRC (crcb, crch, crcw — funct3 000/001/010). Assert `mult_op_o`/`crc_op_o` equals
funct3, correct enable, correct `result_src_o`, 4 cycles.

**⚠ Regression risk — test explicitly.** After adding the MUL/CRC funct7
branches, re-run the slice 1 R-type tests. SUB (`funct7=0100000`) and SRA
must still decode correctly. If the funct7 dispatch became an equality chain
rather than an else-fallthrough, **this is exactly where it breaks.**

**Synthesis note:** the 64-bit combinational multiplier is the single largest
area risk in the design. Flag it during OpenLane area review; the fallback is
an iterative shift-add version, which *would* reintroduce a `MUL_WAIT` state
with a done handshake. Don't pre-optimize for that now.

---

## Slice 5 — LUI / AUIPC / system no-ops

**No new states.** All EXECUTE cases.

**New EXECUTE cases:** `OPCODE_LUI`, `OPCODE_AUIPC`, `OPCODE_SYSTEM`,
`OPCODE_FENCE`.

- **LUI:** `alu_op_o = ALU_PASS_B`, `alu_src_b_o = ALU_SRC_B_IMM`,
  `imm_sel_o = IMM_SEL_U`. The only use of `PASS_B`.
- **AUIPC:** `alu_op_o = ALU_ADD`, `alu_src_a_o = ALU_SRC_A_PC`,
  `alu_src_b_o = ALU_SRC_B_IMM`, `imm_sel_o = IMM_SEL_U`.
- **ECALL/EBREAK/FENCE:** no-op — advance to FETCH, write nothing, assert
  nothing. 3 cycles.

**⚠ ECALL caveat — a real trap.** A bare no-op satisfies the report's 47/47
coverage table, but some RISC-V validation suites use ECALL as an explicit
"test complete / halt" signal the testbench watches for. If the official
firmware does that, a no-op ECALL **silently breaks firmware validation**
(report §6) while still looking correct in the coverage table — passing one
scored category while failing another, with nothing pointing at the cause.

**✅ DONE 2026-08-25 — `halt_o` implemented.** Sticky status flag, set on
the posedge that retires an ECALL, cleared only by reset.

- **Requires a new CU input**, `funct12_i` = IR[31:20]. `funct7_i`
  (IR[31:25]) cannot do this job: ECALL and EBREAK share opcode `1110011`,
  funct3 `000`, *and* funct7 `0000000`. They differ only in IR[20].
  `` `FUNCT12_ECALL `` = `12'h000`, `` `FUNCT12_EBREAK `` = `12'h001`,
  cross-referenced against the RISC-V spec's Environment Call chapter.
- **Execution semantics unchanged.** ECALL, EBREAK and FENCE all remain
  3-cycle no-ops with the PC advancing. `halt_o` is a status output that
  nothing inside the core reads, so all 48 prior tests are unaffected by
  construction — and are still passing.
- **Set on retire, not on decode** (EXECUTE_ALU, not DECODE), so the flag
  cannot assert for an instruction that never executed.
- **Sticky, not a pulse.** A one-cycle pulse is missable by a testbench
  sampling on the wrong edge.
- **Tested:** reset clears it; EBREAK and FENCE leave it at 0; ECALL sets
  it; a later ADD does not clear it; reset clears it again. A continuous
  guard block also fails the run if `halt_o` ever asserts before an ECALL
  has retired. Four mutants (drop the funct12 check, match EBREAK instead,
  set during DECODE, make it non-sticky) were each confirmed to fail the
  testbench.
- **Still open:** whether the firmware needs the core to actually *stop*
  (PC frozen) rather than just flag. One line from here — gate
  `pc_write_o` on `!halt_o`. See decision 15.

**Tests:** LUI/AUIPC assert correct `alu_op_o`/`alu_src_*_o`, 4 cycles,
`reg_write_o` in WRITE_BACK. System no-ops assert 3 cycles and
`reg_write_o`/`we_o` never asserted.

---

## Slice 6 — I-type ALU

**No new states.** Extends EXECUTE_ALU to accept `OPCODE_ITYPE` alongside
`OPCODE_RTYPE`.

**The one difference:** `alu_src_b_o = ALU_SRC_B_IMM` instead of
`ALU_SRC_B_RS2`, and `imm_sel_o = IMM_SEL_I`. The `alu_op_o` decode table is
reused as-is, keyed on funct3 alone.

**⚠ Why funct7 mostly doesn't apply — with one exception.** I-type has no
funct7 field; those bits are part of the 12-bit immediate. So no ADD/SUB
ambiguity (there is no SUBI). **But SRAI vs SRLI is still distinguished by
instruction bit 30** — the same bit position funct7[5] occupies, now living
inside the immediate. **Confirm against the RISC-V spec before coding.**
Getting this wrong makes `srai` silently execute as `srli`.

**Instruction count: 9**, not 10 (ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI,
SRLI, SRAI) — precisely because SUBI doesn't exist.

**Tests:** all 9, with SRAI/SRLI as the specific trap case. Re-run R-type
tests as regression — the shared decode path now serves two opcodes.

---

## Slice 7 — `top.v` integration

**Blocked on:** slices 2-6 complete, plus datapath modules (ALU, mult, CRC,
branch comparator, immediate extender) and memory modules (regfile, LSU,
address decoder, IMEM, DMEM) landing from their owners.

**Work:**
1. Replace every testbench stub input with the real module output.
2. Verify port widths match on both sides of every connection — especially
   `mult_op_o`/`crc_op_o` (4-bit here) and `op_size_o`.
3. Wire `branch_taken_i` from the real comparator.
4. Run the full-core testbench in `tb/system/`.
5. Run the official validation firmware once released.

**Integration risks — where two modules can each be correct and still not
work together:**
- **Port name mismatches on invented signals.** Nothing outside our team
  catches these. `alu_op_o` in particular — if `alu.v` declared it bare as
  `alu_op`, this is a compile error here.
- **`bw_o` ownership.** Control unit drives it (§5). If the LSU owner also
  built byte-mask logic, one of the two is dead code — or worse, they
  disagree.
- **Off-by-one-cycle on the DMEM read.** The control unit expects data valid
  in MEM_ACCESS_DATA. Verify DMEM actually registers its output rather than
  reading combinationally — the whole 2-cycle load design rests on this.
- **`x0` write protection.** The regfile should silently discard writes to
  x0 (guide §3.1.4: x0 is hardwired zero). The control unit asserts
  `reg_write_o` regardless; the guard belongs in the regfile. Confirm the
  regfile owner implemented it.

---

# PART IV — DECISION LOG

## Resolved (don't re-litigate)

| # | Decision | Rationale |
|---|---|---|
| 1 | MUL is combinational, single-cycle | Timing slack is ample at target clock; area is the risk, not timing. Revisit only if OpenLane shows MUL dominating |
| 2 | DMEM load = 2 sub-cycles, store = 1 | Forced by synchronous registered-output SRAM (guide §4.3) |
| 3 | Branch/jump merged into EXECUTE | No shared-hardware conflict justifies splitting; splitting costs a cycle per branch |
| 4 | ECALL/EBREAK/FENCE as no-ops | Needed for 47/47 coverage. EBREAK and FENCE are *finished* this way — no debugger, no caches, nothing for either to do in this core. ECALL additionally raises `halt_o`; see decision 15 |
| 5 | `we_o`/`oe_o`/`bw_o`/`address_o` naming | Confirmed against Figure 3 — core drives `_o`, decoder receives `_i` |
| 6 | `mult_op_o`/`crc_op_o` are funct3 passthrough | Guide's own numbering makes them identical — no lookup table needed |
| 7 | `mult_op_o`/`crc_op_o` are 4 bits | Matches `alu_op_o`; wiring consistency. Values need only 2 bits, extra 2 always zero |
| 8 | Port named `alu_op_o`, not `alu_op` | Uniform `_o` convention across all CU outputs. **Corrected 2026-08-25:** originally recorded as deviating from a guide-fixed name — it doesn't. The guide never names this port; Table 9 fixes the encoding only |
| 9 | `op_size_o` = `[2:1]` size, `[0]` sign | See §5 |
| 10 | `imm_sel_o` encoding + opcode map | See §5 |
| 11 | `bw_o` driven by control unit, via `addr_lsb_i` input | Keeps LSU a pure passthrough; CU already owns `op_size_o`. Requires a 2-bit `addr_lsb_i` input from the ALU result — the CU doesn't compute the address. **Close call:** the LSU already has the address locally, so it could own `bw_o` with no new port. Raise with the LSU owner |
| 12 | Reset is synchronous | Guide is silent; sync chosen for OpenLane flow |
| 13 | Illegal opcode → **silent no-op** | Unknown opcode advances to FETCH writing nothing. The guide never mentions illegal-instruction trapping, the ISA coverage table has no row for it, and the validation firmware won't deliberately execute bad opcodes. Replaces the earlier `ALU_ADD` fallthrough placeholder, which quietly *executed* garbage as an ADD. Report wording: "unimplemented opcodes are treated as no-ops; illegal-instruction trapping is out of scope for this ISA subset." **Cosmetic for the 47 defined instructions** — changes nothing observable, so fold it into the next edit of `control_unit.v` rather than making it a task |
| 14 | `mem_address_i`/`byte_write_i` not implemented on the LSU | Guide Figure 2 draws both as LSU outputs to memory. Ours has neither: the address goes core → address decoder directly, and `bw_o` is driven by the control unit (decision 11). `lsu.v` still reads `core_address_o[1:0]` internally for byte positioning. **Functionally equivalent, structurally a deviation from Figure 2** — state it explicitly in the report rather than letting a reviewer find it |
| 15 | ECALL raises a **sticky status flag**, it does not stop the core | The guide never mentions ECALL, halting, or traps at all (full-text search of the PDF, 2026-08-25), so there is no spec to comply with. Two readings existed: (a) flag completion and keep running, (b) freeze the PC. **(a) chosen** because it is strictly weaker — it adds an observable signal without changing any executed behavior, so it cannot break firmware that uses ECALL mid-program for something other than termination. (b) can be layered on later by gating `pc_write_o` on `!halt_o`; starting at (b) and discovering the firmware wanted (a) is not recoverable as cheaply |
| 16 | `mult_op`/`crc_op` renamed to `mult_op_o`/`crc_op_o` | They were the only two CU outputs without the `_o` suffix. Done 2026-08-25, before `top.v` existed and while `control_unit.v` was the sole file referencing them — one file plus its testbench, versus two files and a written report later. Receiving ports (`mult_op_i`/`crc_op_i` on `mult.v`/`crc.v`) were already correct and did not change |

**Items 6-12 were set unilaterally**, before the ALU/MULT/CRC/LSU owners
started their modules — no teammate to conflict with yet, and every value is
either forced by the guide's numbering (6) or an internal wiring convention
with no external spec to violate (7-12). **Flag each to its module's owner
when they start.** Cheap to change before their module is built against it;
not cheap after.

| Decision | Confirm with |
|---|---|
| `op_size_o` encoding, `bw_o` ownership | LSU owner |
| `mult_op_o`/`crc_op_o` width | MULT/CRC owner |
| `alu_op_o` port name | ALU owner |
| `imm_sel_o` encoding | Team (our own invention) |

## Still genuinely open

**One item.** The other two that used to sit here have been reclassified —
see below.

| # | Question | Blocks | Why it can't be settled here |
|---|---|---|---|
| 1 | Does the validation firmware use ECALL as a "test complete / halt" signal? | Slice 5 correctness | Depends on firmware behavior; firmware not yet released |

### ECALL — what to do while it's blocked

The *decision* is blocked, but the *preparation* isn't. Two things worth
doing before the firmware lands:

**1. Structure for a one-line fix.** Give the control unit a `halt_o` output
(or an internal `halted` flag) wired to the ECALL case, held at 0 for now.
If the firmware turns out to use ECALL as a halt signal, setting it becomes
a one-liner instead of a restructure under deadline pressure.

**2. Check whether it's actually unknowable.** Don't assume it is. The
ChampionCHIP platform may already document the firmware's conventions, and
standard RISC-V test suites (`riscv-tests`) use a well-known pattern: write
a result code to a fixed address, then ECALL, with the testbench watching
for it. If the validation firmware follows that convention, the required
behavior is predictable *before* release. Worth ten minutes on the platform
docs.

**Why this one matters more than it looks:** a bare no-op ECALL satisfies
the report's 47/47 coverage table *and* silently fails firmware validation
(report §6) if the suite depends on it. Passing one scored category while
failing another, with no error message pointing at the cause.

## Reclassified — no longer open questions

| Former item | New status |
|---|---|
| Illegal-opcode policy | **Decided** — silent no-op, decision #13 above |
| x0 write protection | **Not a decision, not the control unit's** — it's a task on the memory pair's list. Guide §3.1.4 is explicit ("x0 is hardwired at zero and cannot be modified") and the implementation is one line in the regfile: `if (reg_write_i && rd_addr_i != 5'd0)`. The CU correctly asserts `reg_write_o` regardless; the guard belongs downstream. Confirm the regfile owner has it — see slice 7 integration risks |

---

# PART V — REFERENCE

## Build / simulate

```bash
iverilog -o sim/tb_control_unit.vvp -I rtl rtl/control_unit.v tb/control_unit/tb_control_unit.v
vvp sim/tb_control_unit.vvp
gtkwave sim/tb_control_unit.vcd
```

**`-I rtl`, not `-I rtl/pkg`** — the RTL includes `"pkg/rvbl2_defines.vh"`,
so the search root is `rtl/`. Earlier revisions of these docs said
`-I rtl/pkg`, which fails with `Include file pkg/rvbl2_defines.vh not found`.

Every testbench needs `$dumpfile("sim/<name>.vcd")` and `$dumpvars(0, ...)`.

## ISA coverage target — 47 total (guide §2)

| Category | Expected | Slice | Status |
|---|---|---|---|
| Arithmetic and Logic (Register) | 10 | 1 | ✅ |
| Arithmetic and Logic (Immediate) | 9 | 6 | |
| Load | 5 | 2 | |
| Store | 3 | 2 | |
| Branch | 6 | 3 | |
| Jump | 2 | 3 | |
| Upper Immediate | 2 | 5 | |
| System / Synchronization | 3 | 5 | |
| Multiplication | 4 | 4 | |
| CRC | 3 | 4 | |
| **Total** | **47** | | **47/47 decoded** |

All 47 decode in `control_unit.v` (slices 1-6, 48/48 tests passing). Decode
coverage is not the same as end-to-end execution — that needs `top.v` and
the system testbench before the report's coverage table can be claimed.

## Memory map (guide Table 13)

| Base | Device | Macro |
|---|---|---|
| `0x00400000` | IMEM (4 MB ROM) | `` `IMEM_BASE ``, `` `PC_RESET_ADDR `` |
| `0x10010000` | DMEM (8 kB SRAM) | `` `DMEM_BASE `` |

## Related documents

| Path | Contents |
|---|---|
| `.claude/CLAUDE.md` | 9-step workflow, RTL coding standards, hard rules |
| `docs/HANDOFF_control_unit.md` | Original spec doc — FSM, signals, decode tables |
| `docs/CONTROL_UNIT_BUILD_PLAN.md` | Slice roadmap with per-slice detail |
| `docs/SLICE1_PLAN.md` | Slice 1 implementation plan (completed) |
| `docs/fsm_control_signal_table.md` | Original scaffold with issue-resolution history |
| `docs/Championchip-stage-2-guide.pdf` | The competition block guide — source of truth for guide-fixed signals |
| `rtl/pkg/rvbl2_defines.vh` | **All constants — what the RTL actually compiles against** |
