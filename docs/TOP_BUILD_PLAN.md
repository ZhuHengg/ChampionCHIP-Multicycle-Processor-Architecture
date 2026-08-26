# `top.v` build plan — control unit slice 7

Companion to `DATAPATH_BUILD_PLAN.md` and `MEMORY_BUILD_PLAN.md`. Written
2026-08-25, before any `top.v` RTL exists.

## 1. Spec review (CLAUDE.md step 1)

Governing sources:

| Source | What it fixes |
|---|---|
| Guide Figure 1 | High-level block diagram — CU, CPU states, RegFile/ALU/CRC/MULT/LSU, address decoder, IMEM, DMEM. No port names |
| Guide Figure 2, §3.3.3 | LSU interface port names |
| Guide Figure 3, §4.4 | Address decoder port names and routing rules |
| Guide Table 13 | Memory map — IMEM `0x00400000`, DMEM `0x10010000` |
| `HANDOFF_control_unit_ALL_STAGES.md` §9 | Per-state control signal table |
| `rtl/pkg/rvbl2_defines.vh` | Every mux encoding |

**The guide does not specify `top.v`'s internal structure at all.** Figure 1
is a block diagram with no registers drawn and no port labels. Everything
below is our design, constrained only by what the eleven existing modules
already expect.

## 2. What `top.v` must create

None of these exist in any module today. They are `top.v`'s real work — the
wiring is the easy half.

| Element | Width | Loaded when | Notes |
|---|---|---|---|
| `pc` | 32 | `pc_write_o` | Reset to `` `PC_RESET_ADDR `` (`0x00400000`) |
| `old_pc` | 32 | `ir_write_o` (FETCH only) | **See trap 1** |
| `ir` | 32 | `ir_write_o` | Feeds `opcode_i`/`funct3_i`/`funct7_i`/`funct12_i` and both regfile read addresses |
| `alu_out` | 32 | every cycle | **See trap 2** |
| `mux_alu_a` | 32 | comb | `alu_src_a_o`: RS1 / `old_pc` |
| `mux_alu_b` | 32 | comb | `alu_src_b_o`: RS2 / imm / 4 |
| `mux_result` | 32 | comb | `result_src_o`: 5 ways |
| `mux_pc_next` | 32 | comb | `pc_src_o`: PC+4 / target / JALR target |
| `mux_mem_addr` | 32 | comb | **See trap 4** — no CU signal selects this yet |

**[CORRECTED 2026-08-26, slice 7g — both claims below were wrong; see traps
8 and 9.]**

~~An MDR (memory data register) is not required: `dmem.v`'s `data_o` is
already registered...~~ — wrong. `address_decoder.data_o` re-routes based
on the *current* address, and by `WRITE_BACK` that address is `pc`, not the
load's effective address — the decoder is reading IMEM by then regardless
of which device actually served the load. A `mem_result` register
(capturing `lsu.core_data_i` while `result_src_o == RESULT_SRC_MEM`) is
required. See trap 8.

~~MUL and CRC results also need no register. Both read `rs1_data`/
`rs2_data` directly... so their combinational outputs are still valid in
`WRITE_BACK`.~~ — the operand half of this is correct, but the op-select
half isn't: `mult_op_o`/`crc_op_o` are driven only in `EXECUTE_ALU` and
revert to their `4'h0` defaults in `WRITE_BACK` (the state `mux_result`
actually samples). `mult_result_r`/`crc_result_r` registers, gated on
`mult_en_o`/`crc_en_o`, are required. See trap 9 — this one shipped broken
in commit `44d9aa2` before being fixed in `3efdead`.

---

## 3. Integration traps

Nine places where the obvious wiring produces a core that simulates without
error and executes the wrong thing. Traps 1-5 were found by reading the
control unit's per-state outputs against what the consuming module needs,
not by running anything, before any `top.v` RTL existed. Traps 6-9 were
found during integration (slices 7d/7e/7f) and are corrected here
2026-08-26 (slice 7g) — this section originally listed only 1-5; the other
four existed only in `rtl/top.v`'s own header until now.

### Trap 1 — branch targets need `old_pc`, not `pc`

FETCH asserts `pc_write_o = 1` with `pc_src_o = ` `` `PC_SRC_PLUS4 ``, so at
the end of FETCH the PC has **already advanced to PC+4**. EXECUTE then
computes the branch target with `alu_src_a_o = ` `` `ALU_SRC_A_PC ``.

Wire that to the live `pc` and every branch target becomes
`branch_addr + 4 + imm` — off by exactly one instruction. RISC-V defines it
as `branch_addr + imm`.

**Fix:** a second register, `old_pc`, latched from `pc` in the same cycle the
IR is latched (`ir_write_o`). `` `ALU_SRC_A_PC `` selects `old_pc`.

Affects BEQ/BNE/BLT/BGE/BLTU/BGEU, JAL, and AUIPC — 9 of the 47.

**Not** affected: `` `RESULT_SRC_PC4 `` (the JAL/JALR link value) is defined
as `jump_addr + 4`, which is precisely the already-incremented `pc`. So the
two PC taps are genuinely different signals, not a naming choice:

| Consumer | Taps |
|---|---|
| `` `ALU_SRC_A_PC `` | `old_pc` |
| `` `RESULT_SRC_PC4 `` | `pc` |

### Trap 2 — `RESULT_SRC_ALU` must tap the register, `PC_SRC_TARGET` must tap live

`WRITE_BACK` sets `reg_write_o = 1` and leaves `alu_op_o` at its default
`` `ALU_PASS_B ``, `alu_src_a_o` at RS1, `alu_src_b_o` at RS2. The ALU's
*live* output during `WRITE_BACK` is therefore `rs2_data` — not the result
computed back in `EXECUTE_ALU`.

So `` `RESULT_SRC_ALU `` must select the **`alu_out` register**, latched at
the end of every cycle.

But branches and jumps assert `pc_write_o` **inside `EXECUTE_ALU`**, the same
cycle the ALU computes the target. `alu_out` does not hold it until the end
of that cycle. So `` `PC_SRC_TARGET `` and `` `PC_SRC_JALR `` must select the
**live ALU output**.

Two taps off the same ALU, and swapping them is silent:

| Consumer | Taps | Why |
|---|---|---|
| `` `RESULT_SRC_ALU `` | `alu_out` register | Consumed a cycle after it is computed |
| `` `PC_SRC_TARGET ``, `` `PC_SRC_JALR `` | live `alu_result` | Consumed in the same cycle |

### Trap 3 — `op_size_o` is not driven when the LSU needs it

This one is a control unit gap, not a wiring choice.

`lsu.v` extends load data as a function of `op_size_o`. The CU's per-state
output logic drives `op_size_o = op_size_lookup` in `MEM_ADDR`,
`MEM_ACCESS_ADDR` and `MEM_ACCESS_STORE` — but **not** in `MEM_ACCESS_DATA`
(which sets only `result_src_o`) and **not** in `WRITE_BACK` (which sets only
`reg_write_o` and `result_src_o`). In both of those states `op_size_o` falls
back to its default, `` `OP_SIZE_WORD ``.

Those are exactly the two states in which the loaded word is extended and
written back. Result: **every `lb`/`lh`/`lbu`/`lhu` behaves like `lw`** —
5 of the 47 instructions, and the byte/half loads are the ones the guide's
own Table 12 worked example exercises.

`lw` still works, which is what makes this dangerous: a smoke test that only
loads words passes.

**Fix (control unit, not `top.v`):** drive `op_size_o = op_size_lookup` in
`MEM_ACCESS_DATA`, and in `WRITE_BACK` when the load path was taken
(`prev_state == MEM_ACCESS_DATA`). `ir` is unchanged across those states, so
`op_size_lookup` is still valid — no new register or input needed.

Needs its own directed test per load variant before `top.v` is wired, using
the guide's Table 12 vectors (`0xF1/F2/F3/F4` at `0x10010000`) as golden
reference per CLAUDE.md step 6.

### Trap 4 — nothing selects the memory address

The address bus feeding `address_decoder.address_i` comes from two places:
`pc` during FETCH, and `alu_out` during `MEM_ACCESS_ADDR` /
`MEM_ACCESS_DATA` / `MEM_ACCESS_STORE`.

The classic multicycle datapath calls this select line `IorD`. **The control
unit has no such output** — it is absent from the handoff's §3 signal
glossary and from every row of the §9 per-state table. `control_unit.v`
deviation note 2 records that `address_o` was deliberately left out of the
CU's ports, but the *select* for it was never assigned an owner.

Two ways to resolve it, see §6 decision D1.

**A separate bus per memory is not an escape hatch.** The tempting
alternative — wire `pc` straight to IMEM and `alu_out` straight to DMEM,
Harvard-style, no mux — is ruled out by the guide's own worked example
(§4.2): IMEM holds constants that programs read with ordinary loads.

> "the IMEM will be accessed again, but not to read an instruction, but
> rather a constant value, which according to Table 14 is the value 10."

A load's effective address must therefore be able to reach IMEM, so both
sources must reach both devices through the decoder. One bus, one mux.

### Trap 5 — loads from IMEM return zero

Found 2026-08-25 while writing up trap 4; same root area, separate defect.

`imem.v` gates its output on `oe_i`:

```verilog
assign data_o = oe_i ? mem[index] : 32'b0;
```

The CU asserts `oe_o` in `MEM_ACCESS_ADDR` but **not** in `MEM_ACCESS_DATA`,
which is the state where `result_src_o = ` `` `RESULT_SRC_MEM `` and the value
is actually consumed. Walk a load whose target address is in IMEM:

| Cycle | State | `oe_o` | `imem.data_o` | decoder `data_o` |
|---|---|---|---|---|
| 4 | `MEM_ACCESS_ADDR` | 1 | the constant | the constant — but nothing consumes it yet |
| 5 | `MEM_ACCESS_DATA` | **0** | **`32'b0`** | **`32'b0`** ❌ |

DMEM loads are unaffected: `dmem.v`'s `data_o` is a real register and holds
its value with `oe_i` low. IMEM is combinational, so it has nothing to hold
with — dropping `oe_i` drops the data.

**Fix:** assert `oe_o` in `MEM_ACCESS_DATA` as well. IMEM then presents the
constant in the same cycle it is consumed. DMEM simply re-reads the same
address and latches the same value, which is harmless. One line, and it
depends on `adr_src_o` still selecting `alu_out` in that state (D1).

An MDR register is *not* an alternative fix here: latching at the end of
`MEM_ACCESS_ADDR` would capture IMEM correctly but DMEM a cycle too early,
since DMEM's registered read has not landed yet.

### Trap 6 — `RESULT_SRC_PC4` must be `old_pc + 4`, not `pc`

**Symptom:** JAL/JALR's link register (`rd`) ends up holding the *jump
target*, not the return address — `x1` (or whatever `rd` is) comes back
wrong by however far the jump moved, not by a fixed +4.

**Root cause:** `` `RESULT_SRC_PC4 `` is defined as "this instruction's
address + 4," which for an *ordinary* instruction is exactly the
already-incremented `pc` (FETCH's `pc_write_o=1`/`PC_SRC_PLUS4` has already
advanced it). But JAL and JALR redirect `pc` to the jump target **inside
`EXECUTE_ALU`** (`pc_write_o=1`, `PC_SRC_TARGET`/`PC_SRC_JALR`) — the very
same instruction whose link value `RESULT_SRC_PC4` is trying to compute. By
`WRITE_BACK`, `pc` holds the target, not `old_pc + 4`.

**Fix:** `mux_result`'s `` `RESULT_SRC_PC4 `` arm reads `old_pc + 4`
directly, not `pc`. `old_pc` is stable across an instruction's full cycle
count (`ir_write_o` only fires in FETCH), so it's unaffected by whatever
`pc` gets redirected to later in the same instruction.

### Trap 7 — `alu_out` must freeze while the memory path owns the address

**Symptom:** loads and stores intermittently address the wrong word — the
effective address computed in `MEM_ADDR` gets silently overwritten one
cycle later.

**Root cause:** `alu_out`'s original spec ("loads every cycle," §2 above)
was correct only through slice 7d, when nothing needed `alu_out` to survive
past the cycle it was computed. Once the memory path exists, `MEM_ACCESS_ADDR`
leaves `alu_src_a_o`/`alu_src_b_o`/`alu_op_o` at their RS1/RS2/PASS_B
defaults (that state drives only `oe_o`/`op_size_o`/`adr_src_o`) — so the
*live* ALU output during `MEM_ACCESS_ADDR` is `rs2_data`, which for an
I-type load is immediate bits, not a real register value. An
unconditionally-loading `alu_out` clobbers `MEM_ADDR`'s correctly-computed
effective address with this garbage one cycle later.

**Fix:** `alu_out` loads every cycle **except** while `adr_src_o` selects
`` `ADR_SRC_ALU `` (i.e. not during `MEM_ACCESS_ADDR`/`MEM_ACCESS_DATA`/
`MEM_ACCESS_STORE`) — freezing the effective address for the memory path's
own three cycles, then resuming normal every-cycle loading everywhere else.

### Trap 8 — a `mem_result` register is required after all

**Symptom:** loaded values read back as `0` (or as whatever IMEM happens to
hold at the current PC) by the time `WRITE_BACK` commits them to the
register file.

**Root cause:** §2's original claim — "an MDR is not required, `dmem.v`'s
`data_o` already holds the value" — is **wrong**, and is corrected here
rather than left standing. That reasoning only covers DMEM. By `WRITE_BACK`,
`adr_src_o` has reverted to `` `ADR_SRC_PC `` (its default), so
`mux_mem_addr` is `pc` — always inside IMEM's address range — and
`address_decoder.data_o` **re-routes to the IMEM branch based on the
current address**, regardless of which device the load actually read from.
A plain DMEM `lw` breaks too: by `WRITE_BACK`, the decoder is reading back
`imem_data_o`, which is itself `0` because `oe_o` is not asserted on IMEM in
`WRITE_BACK` and `imem.v` is combinational.

**Fix:** `mem_result` captures `lsu.core_data_i` (the LSU's already-fully-
computed extended load result) whenever `result_src_o == RESULT_SRC_MEM` —
true in both `MEM_ACCESS_DATA` (when the capture is correct) and the
following `WRITE_BACK` (a harmless re-capture of the same by-then-stale
value, since the regfile write already sampled the register from the prior
edge). `mux_result`'s `` `RESULT_SRC_MEM `` arm reads this register, not the
live `lsu.core_data_i` wire.

### Trap 9 — `mult_op_o`/`crc_op_o` are only driven in `EXECUTE_ALU`

**Symptom:** `mulh`/`mulhsu`/`mulhu` silently return `mul`'s answer, and
`crch`/`crcw` silently return `crcb`'s answer. `mul` and `crcb` themselves
pass regardless, since they happen to be op-select `4'h0` — the same value
these signals default to everywhere else. **This one shipped broken:**
commit `44d9aa2` left a mutation-testing artifact
(`` `RESULT_SRC_MUL: mux_result = mult_result; `` — the live tap, not the
register) uncommitted-reverted in the tree; it was caught and fixed in
`3efdead`.

**Root cause:** §2's claim that "MUL and CRC results also need no register"
is **wrong about the op-select, even though it's right about the operands**
— corrected here rather than left standing. `rs1_data`/`rs2_data` genuinely
are stable for an instruction's whole multi-cycle execution. But
`mult_op_o`/`crc_op_o` are driven only inside `EXECUTE_ALU`'s MUL/CRC cases;
every other state — including `WRITE_BACK`, the state `mux_result` actually
samples — falls back to the control unit's `4'h0` defaults. A live tap of
`mult.result_o`/`crc.result_o` from `mux_result` therefore reads the
low-half-MUL/CRCB answer regardless of which op the instruction actually
requested.

**Fix:** `mult_result_r`/`crc_result_r` registers capture the live
`mult`/`crc` output while `mult_en_o`/`crc_en_o` are asserted — exactly
`EXECUTE_ALU`, the one state where the op-select is still correctly driven
— then hold through `WRITE_BACK`. `mux_result`'s `` `RESULT_SRC_MUL ``/
`` `RESULT_SRC_CRC `` arms read these registers, not the live outputs. Same
pattern as traps 2 and 8.

---

## 4. Wiring table

Signal names are `top.v`-internal unless stated. Guide-fixed names marked ★.

### Control unit

| CU port | Source / destination |
|---|---|
| `opcode_i` | `ir[6:0]` |
| `funct3_i` | `ir[14:12]` |
| `funct7_i` | `ir[31:25]` |
| `funct12_i` | `ir[31:20]` |
| `addr_lsb_i` | `alu_out[1:0]` — **register, not live ALU**. `bw_o` is only consumed in `MEM_ACCESS_STORE`, where the live ALU is computing `PASS_B(rs2)`, not the address |
| `branch_taken_i` | `branch_comparator.branch_taken_o` |
| `halt_o` | `top.v` output, to the system testbench |

### Register file

| Port | Wire |
|---|---|
| `rs1_addr_i` | `ir[19:15]` |
| `rs2_addr_i` | `ir[24:20]` |
| `rd_addr_i` | `ir[11:7]` |
| `write_data_i` | `mux_result` |
| `reg_write_i` | `reg_write_o` |

### Datapath

| Module | Inputs |
|---|---|
| `alu` | `a_i = mux_alu_a`, `b_i = mux_alu_b`, `alu_op_i = alu_op_o` |
| `mult` | `a_i = rs1_data`, `b_i = rs2_data`, `mult_op_i = mult_op_o` |
| `crc` | `a_i = rs1_data` (data), `b_i = rs2_data` (seed), `crc_op_i = crc_op_o` |
| `branch_comparator` | `rs1_i = rs1_data`, `rs2_i = rs2_data`, `funct3_i = ir[14:12]` |
| `imm_extend` | `instr_i = ir`, `imm_sel_i = imm_sel_o` |

⚠ `crc.v` takes **rs1 = data, rs2 = seed** — reversed from the usual
incremental-CRC convention, confirmed by the organisers. Do not "fix" this
at the wiring level.

### Memory path

```
mux_mem_addr ─★address_o→ address_decoder.address_i
                            ├─ address_o[29:0] ─→ imem.addr_i  (zero-extend to 32)
                            ├─ address_o[29:0] ─→ dmem.addr_i  (zero-extend to 32)
                            ├─ imem_oe_o ───────→ imem.oe_i
                            ├─ dmem_oe_o ───────→ dmem.oe_i
                            ├─ dmem_we_o ───────→ dmem.we_i
                            ├─ bw_o ────────────→ dmem.bw_i
                            └─ data_o ──────────→ lsu.mem_data_o  and  ir input
lsu.mem_data_i ──────────────────────────────────→ dmem.data_i   (bypasses decoder)
```

Two things to get right here:

- **Width.** `address_decoder.address_o` is `[29:0]` (bottom 2 bits already
  dropped); `imem.addr_i` / `dmem.addr_i` are `[31:0]` word addresses.
  Zero-extend — do not shift again.
- **Store data bypasses the decoder.** Guide Figure 3 draws no data path
  through the decoder, and `address_decoder.v`'s header already flags this.
  `lsu.mem_data_i` wires straight to `dmem.data_i`.

### LSU

Names are from the core's perspective (guide Figure 2), so the LSU's
*inputs* carry `_o` names. This reads backwards and is correct.

| LSU port | Direction | Wire |
|---|---|---|
| `core_data_o` ★ | in | `rs2_data` (store data) |
| `core_address_o` ★ | in | `alu_out` (uses `[1:0]` for byte positioning) |
| `op_size_o` ★ | in | CU `op_size_o` — **see trap 3** |
| `mem_data_o` ★ | in | `address_decoder.data_o` |
| `core_data_i` ★ | out | `mux_result` input for `` `RESULT_SRC_MEM `` |
| `mem_data_i` ★ | out | `dmem.data_i` |

Guide Figure 2 also draws `mem_address_i` and `byte_write_i` as LSU outputs.
Ours has neither — the address goes core → decoder directly and `bw_o` comes
from the CU (decision 11). Recorded as decision 14; state it in the report.

### Mux definitions

```
mux_alu_a    = alu_src_a_o ? old_pc : rs1_data          // ALU_SRC_A_PC : _RS1
mux_alu_b    = ALU_SRC_B_RS2    -> rs2_data
               ALU_SRC_B_IMM    -> imm
               ALU_SRC_B_CONST4 -> 32'd4
mux_result   = RESULT_SRC_ALU -> alu_out        (register — trap 2)
               RESULT_SRC_MUL -> mult_result
               RESULT_SRC_CRC -> crc_result
               RESULT_SRC_MEM -> lsu.core_data_i
               RESULT_SRC_PC4 -> pc             (already incremented — trap 1)
mux_pc_next  = PC_SRC_PLUS4  -> pc + 4
               PC_SRC_TARGET -> alu_result      (live — trap 2)
               PC_SRC_JALR   -> {alu_result[31:1], 1'b0}   // D2: spec says & ~1
mux_mem_addr = ADR_SRC_PC    -> pc
               ADR_SRC_ALU   -> alu_out         // D1: new CU output adr_src_o
```

Every mux needs a `default` arm (CLAUDE.md step 5) — `result_src_o` has 5
defined values in 3 bits, `pc_src_o` has 3 in 2 bits.

---

## 5. Build slices

Smallest working slice first, per CLAUDE.md workflow preference and handoff
§11. Each slice ends in a passing simulation before the next begins.

| Slice | Scope | Proves |
|---|---|---|
| **7a** | `control_unit.v`: fix traps 3 and 5, add `adr_src_o` (D1). Directed tests per load variant, per `adr_src_o` state, and an `oe_o`-in-`MEM_ACCESS_DATA` assertion | Load extension, address select and IMEM-load timing are correct before anything depends on them |
| **7b** | PC, `old_pc`, IR, IMEM, decoder. Fetch only, no execution | Instructions arrive at the IR in order, PC increments |
| **7c** | + regfile, ALU, `alu_out`, source and result muxes | R-type and I-type execute and write back |
| **7d** | + branch comparator, PC mux | Branches and jumps land on the right address (trap 1 shows up here or never) |
| **7e** | + LSU, DMEM, `mux_mem_addr` | Loads and stores, all 5 load variants against guide Table 12 |
| **7f** | + MUL, CRC | Zmmul and Xicrc results reach the register file |
| **7g** | `halt_o` out to the top-level port, full firmware run | End-to-end |

Slice 7a is first deliberately: it is a control unit change, and doing it
while `control_unit.v` is still standalone means its testbench catches
regressions in isolation rather than through `top.v`.

## 6. Decisions — settled 2026-08-25 (CLAUDE.md step 2)

**D1 — memory address select (trap 4): a new `adr_src_o` control unit
output.** Explicit, matching how every other mux in the design is driven.
The alternative — deriving it in `top.v` from `ir_write_o`, which is correct
today because FETCH is the only state asserting it — was rejected as an
implicit dependency on a coincidence between two unrelated signals. Costs one
CU port, one per-state table column, and a testbench update.

```verilog
// control_unit.v
output reg adr_src_o
FETCH:            adr_src_o = `ADR_SRC_PC;
MEM_ACCESS_ADDR:  adr_src_o = `ADR_SRC_ALU;
MEM_ACCESS_DATA:  adr_src_o = `ADR_SRC_ALU;
MEM_ACCESS_STORE: adr_src_o = `ADR_SRC_ALU;
```

New macros in `rvbl2_defines.vh`: `` `ADR_SRC_PC `` = `1'b0`,
`` `ADR_SRC_ALU `` = `1'b1`.

**D2 — JALR clears the low bit.** `PC_SRC_JALR -> {alu_result[31:1], 1'b0}`,
per the RISC-V spec's `(rs1 + imm) & ~1`. The guide is silent; the ISA spec
the guide says the core implements is not. One line, and it removes a case
the validation firmware could plausibly test deliberately.

**D3 — IMEM depth and firmware file are `top.v` parameters.**

```verilog
module top #(
    parameter IMEM_DEPTH_WORDS = 1024,
    parameter IMEM_INIT_FILE   = ""
) ( ... );
```

The system testbench will need to point at a different `.hex` per test;
hardcoding means editing RTL for every firmware case.

## 7. Test plan (CLAUDE.md step 6)

- Golden vectors from the guide's own worked examples: Table 12's byte
  example (`0xF1/F2/F3/F4` at `0x10010000`) and its five load variants;
  Table 14's IMEM firmware layout.
- One directed test per slice above, not one at the end.
- Cycle counts cross-checked against the handoff §2 table: 4 for ALU/I-type,
  **6 for loads** (FETCH, DECODE, MEM_ADDR, MEM_ACCESS_ADDR, MEM_ACCESS_DATA,
  WRITE_BACK — corrected 2026-08-26, slice 7g; this section previously said
  5, which was wrong — `HANDOFF_control_unit_ALL_STAGES.md` lines 393-397
  and `tb_top_mem`'s own passing assertion both say 6), 4 for stores, 3 for
  branches and system no-ops.
- `firmware/crc_test.S` already exists and is the natural 7f test.
- A `$monitor`-style trace of `pc` / `ir` / `state` makes slice 7b
  debuggable; wire it before it is needed.

## 8. Synthesis notes (CLAUDE.md step 9)

- `mult.v`'s 64-bit combinational multiply is the largest block and now sits
  in a path that also feeds `mux_result`. Watch its slack in the first
  OpenLane run; the fallback (iterative shift-add) changes the FSM, not just
  `mult.v`.
- `imem.v`'s `DEPTH_WORDS` default of 1024 words is a simulation
  convenience, not the guide's 4 MB. Area numbers reported from a run using
  the default must say so.
- `address_decoder.v` does two 32-bit range comparisons combinationally in
  the same path as the memory access. Cheap, but it is in the address path
  every cycle.
