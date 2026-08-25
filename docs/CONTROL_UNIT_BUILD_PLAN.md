# Control Unit Build Plan — Slices 1 through 7

Incremental build plan for `rtl/control_unit.v`, from the R-type-only slice
through full ISA coverage and `top.v` integration.

**Read first:** `.claude/CLAUDE.md` (workflow rules) and
`docs/HANDOFF_control_unit.md` (the spec — FSM, per-state table, opcode map,
op-code values). This document does not restate them; it sequences the work
and records what each slice needs before it can start.

**Per-slice discipline** — every slice follows CLAUDE.md's 9-step workflow:
spec review → interface → state/truth table → RTL → self-review → test plan
→ simulate → document deviations → note synthesis concerns. Do not skip to
RTL because a slice "seems simple." Do not start a slice whose blockers are
unresolved — ask instead.

**Definition of done for every slice:** testbench written, simulation run,
output pasted into the status report, deviations commented inline in the RTL
citing the handoff section. "Should work" is not a status — either it passed
its testbench or it hasn't been tested. Say which.

---

## Locked decisions (apply to every slice — do not re-litigate)

1. **Reset is synchronous.** `always @(posedge clk_i)` with `if (rst_i)`
   inside. Never `or posedge rst_i`.
2. **All control-unit output signals carry `_o`**, invented ones included
   (handoff §3 naming paragraph). Inputs carry `_i` — `branch_taken_i`.
3. **State encoding is `localparam` inside `control_unit.v`**, never in
   `rtl/pkg/rvbl2_defines.vh` — it doesn't cross a module boundary.
4. **4-bit state register.** Nine-plus states eventually; 3 bits is too few.
5. **Three always blocks, one purpose each:** state register (sequential,
   `<=`), next-state logic (combinational, `=`), output logic
   (combinational, `=`, every output defaulted before any `case`).
6. **Every constant comes from `rvbl2_defines.vh`** via a named macro. No
   raw opcode/op-code literals in the RTL.
7. **MUL is combinational, single-cycle.** No `MUL_WAIT` state unless the
   OpenLane area report forces a revisit (handoff §7.1).
8. **funct7 category selection is an `else`, not an equality check.**
   `0000001`→MUL, `1000000`→CRC, everything else→ALU. Writing
   `if (funct7 == 7'b0000000)` to mean "is ALU" silently breaks SUB and SRA
   (handoff §5, and the warning block in `rvbl2_defines.vh`).

---

## Slice status

| Slice | Scope | Status | Blockers |
|---|---|---|---|
| 1 | R-type ALU path | **Done, passing** | — |
| 2 | Load / store | Unblocked | — (`op_size_o`, `bw_o` decided, handoff §7 items 9, 11) |
| 3 | Branch / jump | Unblocked (stub `branch_taken_i` in testbench) | — (`imm_sel_o` decided, handoff §7 item 10) |
| 4 | MUL / CRC | Unblocked | — (port width decided 4-bit, handoff §7 item 7) |
| 5 | LUI / AUIPC / system no-ops | Unblocked | — |
| 6 | I-type ALU | Unblocked | — |
| 7 | `top.v` integration | Not started | Slices 2-6, datapath + memory modules must land |

**Update:** the five open questions that originally gated slices 2-6
(`op_size_o` encoding, `imm_sel_o` encoding, `mult_op`/`crc_op` width,
`bw_o` ownership, `alu_op` naming) were all decided and written into
`docs/HANDOFF_control_unit.md` §7 (items 6-11) and `rtl/pkg/rvbl2_defines.vh`
before any teammate started their module — no alignment cost yet, since
there's nothing built against the old ambiguity. **These are now decisions,
not proposals** — every macro a slice needs already exists in
`rvbl2_defines.vh`. If ALU/MULT/CRC/LSU owners have a real objection once
they start, it's still cheap to revisit; just don't silently diverge from
what's documented.

---

## Slice 1 — R-type ALU path ✅ DONE

**Scope:** FETCH → DECODE → EXECUTE_ALU → WRITE_BACK → FETCH, opcode
`0110011` via the funct7 else-branch. 4 cycles.

**Implemented:** 5 states, sync reset, 10-way `alu_op_o` decode on
(funct3, funct7[5]), 10 outputs.

**Tested and passing:** all 10 R-type ALU instructions (ADD, SUB, SLL, SLT,
SLTU, XOR, SRL, SRA, OR, AND), each verified for correct `alu_op_o` and a
4-cycle count matching handoff §2. `ALL TESTS PASSED`.

**Known open items carried forward:**
- ~~`alu_op` vs `alu_op_o` naming~~ — **closed 2026-08-25.** The guide never
  names this port; Table 9 fixes the encoding only, so there was no
  guide-fixed name to conflict with. CU drives `alu_op_o`, `alu.v` receives
  `alu_op_i`, both built and passing. Handoff §3 corrected.
- Illegal-opcode default is `ALU_ADD` placeholder; policy undecided.
- `opcode_i` is declared but unused — DECODE unconditionally targets
  EXECUTE_ALU. Slice 2 is where it starts being read.

---

## Slice 2 — Load / store

**Blockers: none — unblocked.** `op_size_o` encoding and `bw_o` ownership
were decided in handoff §7 (items 9, 11) before the LSU owner started; use
`` `OP_SIZE_* `` macros from `rvbl2_defines.vh`. Flag it to the LSU owner
once they start, in case they have a reason to want it different — cheap to
change now, not after their module is built against it.

**New states:** `MEM_ADDR`, `MEM_ACCESS_ADDR`, `MEM_ACCESS_DATA`,
`MEM_ACCESS_STORE`.

**Path (handoff §2):**
- Load: FETCH → DECODE → MEM_ADDR → MEM_ACCESS_ADDR → MEM_ACCESS_DATA →
  WRITE_BACK → FETCH. **6 cycles.**
- Store: FETCH → DECODE → MEM_ADDR → MEM_ACCESS_STORE → FETCH. **4 cycles**,
  no write back (nothing to write to a register).

The two-cycle load is forced by DMEM being a synchronous registered-output
SRAM (guide §4.3) — read data isn't valid until the cycle *after* the
address is presented. Stores commit on the edge itself, so one cycle.

**New ports:** `bw_o` (4), `op_size_o` (3). Both guide-fixed names — must
match exactly.

**DECODE gains real work:** this is where `opcode_i` starts being read.
`OPCODE_LOAD` → MEM_ADDR, `OPCODE_STORE` → MEM_ADDR, `OPCODE_RTYPE` →
EXECUTE_ALU. MEM_ADDR then branches on opcode to pick the load or store
sub-path.

**Per-state values:** handoff §4, rows MEM_ADDR / MEM_ACCESS_ADDR /
MEM_ACCESS_DATA / MEM_ACCESS (store). Note `alu_op = ADD` in MEM_ADDR
(effective address = rs1 + offset), `alu_src_b_o = ALU_SRC_B_IMM`,
`result_src_o = RESULT_SRC_MEM` in MEM_ACCESS_DATA.

**`bw_o` is a byte mask, not a binary selector** — one bit per byte
(handoff §3). Its value depends on both access size and `address[1:0]`:
guide §3.3.2's worked example writes byte 3 of a word with `bw_o = 4'b0100`.
The control unit may or may not own this computation — **confirm with the
LSU owner** whether `bw_o` is driven by the control unit or generated inside
the LSU from `op_size_o` and the address. Handoff §4's table implies the
control unit drives it ("per size/addr[1:0]"), but that's worth verifying
rather than assuming.

**Test vectors — use the guide's own worked example, not invented ones.**
Table 12 gives DMEM contents `0xF1/F2/F3/F4` at `0x10010000` and works out
all five load results explicitly (guide §3.3.1):
- `lbu` @ `0x10010000` → `0x000000F1`
- `lb`  @ `0x10010000` → `0xFFFFFFF1`
- `lhu` @ `0x10010000` → `0x0000F2F1`
- `lh`  @ `0x10010000` → `0xFFFFF2F1`
- `lw`  @ `0x10010000` → `0xF4F3F2F1`
- `lb`  @ `0x10010002` → `0x000000F3` (byte repositioning case)

At the control-unit level these verify `op_size_o` and cycle counts, not the
actual extension (that's the LSU's job) — but they're the golden reference
when the two modules meet at `top.v`.

Also assert: load = 6 cycles, store = 4 cycles, `we_o`/`oe_o` asserted in
exactly the right states and nowhere else. `we_o` must be 0 in every state
except MEM_ACCESS_STORE — a stray write enable corrupts memory silently.

---

## Slice 3 — Branch / jump

**Blockers: `imm_sel_o` resolved** (handoff §7 item 10 — use `` `IMM_SEL_B ``/
`` `IMM_SEL_J ``). Still need `branch_taken_i` driven by something — the real
`branch_comparator.v` if it exists yet, otherwise a testbench stub. That's a
testing dependency, not a spec question, so it doesn't block writing the RTL.

**No new states** — branch and jump are cases *inside* EXECUTE, selected by
opcode (handoff §7.3). Splitting them into their own states would cost every
branch an extra cycle for no benefit.

**New EXECUTE cases:** `OPCODE_BRANCH` (`1100011`), `OPCODE_JAL`
(`1101111`), `OPCODE_JALR` (`1100111`).

**Cycle counts:** branch = 3 (no write back — a branch produces no register
result), JAL/JALR = 4 (write back the return address).

**New port:** `branch_taken_i` (1, **input** — from the comparator).

**The conditional-PC-write case:** for branch, `pc_write_o` is
`branch_taken_i`-dependent, not a constant. This is the only state where an
output depends on a datapath input rather than state alone — handoff §4's
`0/1*` footnote. Everywhere else, outputs are a pure function of state.

**`pc_src_o` values:** branch → `PC_SRC_TARGET` (`01`), JAL →
`PC_SRC_TARGET`, JALR → `PC_SRC_JALR` (`10`). JALR differs because its
target is `rs1 + imm` rather than `PC + imm`, so `alu_src_a_o` is
`ALU_SRC_A_RS1` for JALR but `ALU_SRC_A_PC` for JAL and branch.

**`result_src_o = RESULT_SRC_PC4`** for JAL/JALR — the link register gets
PC+4, not the ALU result (the ALU is busy computing the jump target).

**Tests:** all 6 branch instructions (BEQ, BNE, BLT, BGE, BLTU, BGEU) with
`branch_taken_i` forced both 0 and 1 — assert `pc_write_o` follows it and
`pc_src_o` is correct in both cases. Then JAL and JALR: assert 4 cycles,
`result_src_o == RESULT_SRC_PC4`, correct `pc_src_o`. Assert `reg_write_o`
stays 0 for branches through the whole sequence.

**Note:** the guide's coverage table expects 6 branch + 2 jump = 8
instructions. funct3 selects which comparison, but that's the comparator's
business — the control unit just routes `branch_taken_i`. Do not decode
branch funct3 in the control unit.

---

## Slice 4 — MUL / CRC

**Blockers: none — unblocked.** Port width decided 4 bits, matching
`alu_op_o` (handoff §7 item 7). Flag it to whoever builds `mult.v`/`crc.v`
once they start, in case they'd rather have the tight 2-bit port.

**No new states.** MUL is combinational and single-cycle (handoff §7.1), so
EXECUTE handles it in one cycle like ALU. 4 cycles total, same as R-type.

**New EXECUTE cases:** both live under `OPCODE_RTYPE`, disambiguated by
funct7 — `FUNCT7_MUL` (`0000001`) → MUL, `FUNCT7_CRC` (`1000000`) → CRC,
else → ALU. **This is where slice 1's else-structure pays off** — the ALU
branch must remain the fallthrough, or SUB and SRA break.

**New ports:** `mult_op`, `crc_op` (width TBD), `mult_en_o`, `crc_en_o`.

**`mult_op` and `crc_op` are a direct passthrough of funct3** (handoff §6) —
`mult_op = {1'b0, funct3_i}` (or `= funct3_i[1:0]` if the port lands at 2
bits). Do **not** build a lookup table; the guide's numbering makes them
identical by construction. This is the opposite of `alu_op`, which needs
real decode. That asymmetry is deliberate and documented — don't "fix" it
into consistency.

**`result_src_o`:** `RESULT_SRC_MUL` (`001`) for MUL, `RESULT_SRC_CRC`
(`010`) for CRC.

**Tests:** 4 MUL instructions (mul, mulh, mulhsu, mulhu — funct3 000/001/
010/011) and 3 CRC (crcb, crch, crcw — funct3 000/001/010). Assert
`mult_op`/`crc_op` equals funct3, correct enable asserted, correct
`result_src_o`, 4-cycle count.

**Regression risk — test this explicitly:** after adding the MUL/CRC funct7
branches, re-run the slice 1 R-type tests. SUB (`funct7=0100000`) and SRA
must still decode correctly. If the funct7 dispatch was written as an
equality chain rather than an else-fallthrough, this is where it breaks.

**Synthesis note:** the 64-bit combinational multiplier is the single
largest area risk in the design (handoff §7.1). Flag it in the OpenLane
area report review; if it dominates, the fallback is an iterative shift-add
version, which *would* reintroduce a `MUL_WAIT` state with a done handshake.
Don't pre-optimize for that now.

---

## Slice 5 — LUI / AUIPC / system no-ops

**Blockers: none — unblocked.** `imm_sel_o` decided (handoff §7 item 10) —
use `` `IMM_SEL_U `` for LUI/AUIPC.

**No new states.** All are EXECUTE cases.

**New EXECUTE cases:** `OPCODE_LUI` (`0110111`), `OPCODE_AUIPC` (`0010111`),
`OPCODE_SYSTEM` (`1110011`, ECALL/EBREAK), `OPCODE_FENCE` (`0001111`).

- **LUI:** `alu_op_o = ALU_PASS_B`, `alu_src_b_o = ALU_SRC_B_IMM`. The ALU
  passes the immediate straight through. This is the only use of `PASS_B`.
- **AUIPC:** `alu_op_o = ALU_ADD`, `alu_src_a_o = ALU_SRC_A_PC`,
  `alu_src_b_o = ALU_SRC_B_IMM`. PC + immediate.
- **ECALL/EBREAK/FENCE:** no-op — advance to FETCH, write nothing, assert
  nothing. 3 cycles (no write back).

**⚠ ECALL caveat (handoff §7.4) — this one has a real trap.** Implementing
ECALL as a bare no-op satisfies the report's 47/47 coverage table, but some
RISC-V validation suites use ECALL as an explicit "test complete / halt"
signal that the testbench watches for. If the official firmware does that, a
no-op ECALL silently breaks firmware validation (report §6) while still
looking correct in the coverage table. **Revisit once the official
validation firmware is released on the ChampionCHIP platform.** Until then,
no-op is the right placeholder — but leave the inline comment saying so.

**Tests:** LUI and AUIPC assert correct `alu_op_o`/`alu_src_*_o` and 4-cycle
count with `reg_write_o` asserted in WRITE_BACK. System no-ops assert 3
cycles and `reg_write_o`/`we_o` never asserted.

---

## Slice 6 — I-type ALU

**Blockers: none — unblocked.** `imm_sel_o` decided (handoff §7 item 10) —
use `` `IMM_SEL_I ``.

**No new states.** Extends the existing EXECUTE_ALU case to accept
`OPCODE_ITYPE` (`0010011`) alongside `OPCODE_RTYPE`.

**The one difference from R-type:** `alu_src_b_o = ALU_SRC_B_IMM` instead of
`ALU_SRC_B_RS2`. The `alu_op_o` decode table is otherwise reused as-is,
keyed on funct3 alone.

**Why funct7 mostly doesn't apply:** I-type instructions have no funct7
field — those bits are part of the 12-bit immediate. So there's no ADD/SUB
ambiguity (there is no SUBI). **But SRAI vs SRLI is still distinguished by
instruction bit 30** — the same bit position funct7[5] occupies, now living
inside the immediate. **Confirm this against the RISC-V spec before coding**
(handoff §6 flags it as needing verification). Getting this wrong makes
`srai` silently execute as `srli`.

**Instruction count:** 9 per the guide's coverage table (ADDI, SLTI, SLTIU,
XORI, ORI, ANDI, SLLI, SRLI, SRAI) — note there are 9, not 10, precisely
because SUBI doesn't exist.

**Tests:** all 9, with SRAI/SRLI as the specific trap case. Re-run R-type
tests as regression — the shared decode path is now serving two opcodes.

---

## Slice 7 — `top.v` integration

**Blocked on:** slices 2-6 complete, plus datapath modules (ALU, mult, CRC,
branch comparator, immediate extender) and memory modules (regfile, LSU,
address decoder, IMEM, DMEM) landing from their owners.

**Work:**
1. Replace every testbench stub input with the real module output.
2. ~~Resolve the `alu_op` vs `alu_op_o` naming question~~ — settled:
   `alu_op_o` on the CU, `alu_op_i` on the ALU, same wire.
3. Verify port widths match on both sides of every connection, especially
   `mult_op_o`→`mult_op_i` / `crc_op_o`→`crc_op_i` (4 bits both ends) and
   `op_size_o`.
4. Wire `branch_taken_i` from the real comparator.
5. Run the full-core testbench in `tb/system/`.
6. Run the official validation firmware (`firmware/`) once released.

**Integration risks to check first** — these are the places where two
modules can each be individually correct and still not work together:
- Port name mismatches on invented signals (nothing outside our team fixes
  these for us).
- `bw_o` ownership — control unit vs LSU (raised in slice 2).
- Off-by-one-cycle on the DMEM read: control unit expects data valid in
  MEM_ACCESS_DATA; verify the DMEM implementation actually registers its
  output rather than reading combinationally.
- `x0` write protection (handoff §8) — the regfile should silently discard
  writes to x0. Control unit asserts `reg_write_o` regardless; the guard
  belongs in the regfile (guide §3.1.4: x0 is hardwired zero). Confirm the
  regfile owner implemented it.

---

## Questions resolved without waiting for teammates

Decided unilaterally and written into `docs/HANDOFF_control_unit.md` §7
(items 6-11) and `rtl/pkg/rvbl2_defines.vh`, since no teammate had started
their module yet — nothing to align against, nothing lost by deciding now.
**Flag each to its module's owner once they start**, so they can object
early if they have a real reason to want it different:

| # | Question | Decision | Confirm with |
|---|---|---|---|
| 1 | `op_size_o` 3-bit encoding | `[2:1]`=size, `[0]`=sign — see handoff §3 | LSU owner |
| 2 | `imm_sel_o` encoding + opcode→format map | `000`=I…`100`=J — see handoff §3 | Team (our own invention, no spec to violate) |
| 3 | `mult_op`/`crc_op` port width | 4 bits, matches `alu_op_o` | MULT/CRC owner |
| 3b | `mult_op`/`crc_op` port **names** | Renamed to `mult_op_o`/`crc_op_o` 2026-08-25 — they were the only CU outputs missing the `_o` suffix. Done before `top.v`, while `control_unit.v` was the only file using them. Receiving ports `mult_op_i`/`crc_op_i` unchanged | Closed |
| 4 | `bw_o` driven by control unit or LSU? | Control unit | LSU owner |
| 5 | `alu_op` vs `alu_op_o` port name | `alu_op_o` (uniform `_o` convention). **Not a guide question at all** — verified 2026-08-25 that the guide names no op-select port | Nobody — closed, `alu.v` already built to `alu_op_i` |

## Still genuinely open (no unilateral answer possible)

| # | Question | Blocks | Why it can't be decided here |
|---|---|---|---|
| 6 | Does the firmware expect the core to **stop** on ECALL, or only to flag it? | System testbench design | **Prep done 2026-08-25** — `halt_o` implemented as a sticky status flag, set when an ECALL retires (funct12 `12'h000`), cleared by reset. Execution semantics unchanged: ECALL is still a 3-cycle no-op and the PC still advances. The testbench can now `wait (halt_o)` instead of timing out. Remaining unknown: whether the firmware needs the PC actually frozen. That is a one-line change from here — gate `pc_write_o` on `!halt_o` |

## Reclassified — were on this list, no longer questions

| Former item | New status |
|---|---|
| Illegal-opcode policy | **Decided: silent no-op.** Guide never mentions illegal-instruction trapping; coverage table has no row for it. Replaces the `ALU_ADD` fallthrough. Cosmetic for the 47 defined instructions — fold into the next edit of `control_unit.v` |
| x0 write protection | **Not a decision and not the control unit's.** One-line guard in the regfile per guide §3.1.4. Memory pair's task list; confirm at integration |

---

## Build / simulate

```bash
iverilog -o sim/tb_control_unit.vvp -I rtl rtl/control_unit.v tb/control_unit/tb_control_unit.v
vvp sim/tb_control_unit.vvp
gtkwave sim/tb_control_unit.vcd
```

Every testbench needs `$dumpfile("sim/<name>.vcd")` and `$dumpvars(0, ...)`.

**Run the full testbench after every slice, not just the new tests.** Each
slice adds branches to shared decode logic; slice 4 in particular can break
slice 1's SUB/SRA if the funct7 dispatch is written as an equality chain.
The regression is cheap and catches exactly the class of bug that's hardest
to find later.

---

## Cycle count reference (handoff §2 — verify against this every slice)

| Instruction type | Cycles | Path |
|---|---|---|
| R-type / I-type ALU, MUL, CRC, LUI, AUIPC | 4 | fetch, decode, execute, write back |
| Branch | 3 | fetch, decode, execute → fetch |
| JAL / JALR | 4 | fetch, decode, execute, write back |
| Store | 4 | fetch, decode, mem_addr, mem_access → fetch |
| Load | 6 | fetch, decode, mem_addr, mem_access_addr, mem_access_data, write back |
| ECALL / EBREAK / FENCE | 3 | fetch, decode, execute → fetch |

---

## ISA coverage target (guide §2 — 47 total)

| Category | Expected | Slice that delivers it |
|---|---|---|
| Arithmetic and Logic (Register) | 10 | 1 ✅ |
| Arithmetic and Logic (Immediate) | 9 | 6 |
| Load | 5 | 2 |
| Store | 3 | 2 |
| Branch | 6 | 3 |
| Jump | 2 | 3 |
| Upper Immediate | 2 | 5 |
| System / Synchronization | 3 | 5 |
| Multiplication | 4 | 4 |
| CRC | 3 | 4 |
| **Total** | **47** | |

10/47 covered as of slice 1.
