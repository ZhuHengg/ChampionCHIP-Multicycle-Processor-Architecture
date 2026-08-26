# Handoff — Multicycle RISC-V Control Unit (ChampionCHIP RVBL-2)

Status as of handoff: FSM topology + control signal table designed and
resolved. Ready to start RTL. This doc is self-contained — everything
needed to pick up work in the IDE without re-deriving decisions already
made.

---

## 1. Project context

- Target: multicycle RISC-V core (RV32I + Zmmul + Xicrc), built from the
  single-cycle ChampionCHIP training core, extended per the Stage 2 Block
  Guide (`ChipInventor RVBL-2`).
- Deliverables that depend on this doc: report §3.2 (Control Unit),
  §2 (ISA coverage table), and the actual RTL (`control_unit.v`).
- ChipInventor is used **only** to produce block-diagram figures for the
  report — it is not the RTL/verification environment. All RTL, sim, and
  physical design happens outside it (see §6, Tooling).

## 2. FSM state diagram (final)

```
RESET → FETCH → DECODE ─┬─→ EXECUTE (case on opcode/funct7/funct3) ─┐
                          │                                          │
                          └─→ MEM_ADDR → MEM_ACCESS (load/store)    │
                                                                      │
        ┌── branch / store: loop directly back to FETCH ─────────────┤
        │                                                            │
        └── everything else: → WRITE BACK → FETCH ←───────────────────┘
```

Key design decisions baked into this shape:

- **Branch and jump are NOT separate states** — they're cases inside
  EXECUTE, selected by opcode, same as ALU/MUL/CRC. Rationale: no shared
  hardware conflict to resolve by splitting, and splitting would cost every
  branch/jump an extra cycle for no benefit.
- **Loads take 2 sub-cycles in MEM_ACCESS** (`MEM_ACCESS_ADDR` then
  `MEM_ACCESS_DATA`); **stores take 1**. This is forced by DMEM being a
  synchronous, registered-output SRAM (§3.3 of the guide) — read data isn't
  valid until the cycle *after* the address is presented; writes commit on
  the edge itself.
- **Branches and stores skip WRITE BACK** and loop straight to FETCH — they
  produce no register result.

### Cycle counts (confirmed)

| Instruction type | Cycles | Path |
|---|---|---|
| R-type/I-type ALU, MUL, CRC, LUI, AUIPC | 4 | fetch, decode, execute, write back |
| Branch | 3 | fetch, decode, execute → fetch |
| JAL / JALR | 4 | fetch, decode, execute, write back |
| Store | 4 | fetch, decode, mem_addr, mem_access → fetch |
| Load | 6 | fetch, decode, mem_addr, mem_access_addr, mem_access_data, write back |

**Corrected:** store is 4 cycles, not 5. Cycle count equals states traversed
in every row; store visits FETCH, DECODE, MEM_ADDR, MEM_ACCESS_STORE and
loops back to FETCH, skipping WRITE BACK. The earlier "5" was an arithmetic
slip (load's 6 minus one, without accounting for store also dropping WRITE
BACK). The state names listed here were always right.

## 3. Signal glossary

**Naming convention:** all control-unit output signals use `_o`, including
invented ones — not just the guide-fixed set. `pc_write_o`, not bare
`pc_write`. This matches the guide's own convention (`we_o` on the core's
side becomes `we_i` on the receiving module's side) applied uniformly, so
the whole port list reads consistently rather than mixing two naming
styles. State encoding stays as `localparam` inside `control_unit.v`, not
in the shared `defines.vh` — it never crosses a module boundary (no other
module reads `state` directly, only the output signals derived from it), so
there's no cross-file mismatch risk to guard against by sharing it.

### Fixed by the block guide — must match exactly (these are the ports other teammates' modules expect)

The core drives these as its own outputs. They arrive at the address
decoder as its input ports with `_i` suffix instead of `_o` (same wires,
named from the receiving module's side) — e.g. core's `we_o` becomes the
decoder's `we_i`. Downstream, the decoder produces `dmem_we_o` specifically
for DMEM (IMEM has no write path at all) — that renaming happens inside
the decoder, not something the control unit needs to drive directly.

| Signal | Width | Source | Meaning |
|---|---|---|---|
| `we_o` | 1 | Fig. 3, §4.4 | Write enable |
| `oe_o` | 1 | Fig. 3, §4.4 | Read enable |
| `bw_o` | 4 | Fig. 3, §4.4 | Byte write mask (one bit per byte, not a binary-coded selector) |
| `address_o` | 32 | Fig. 3, §4.4 | Address bus; bottom 2 bits dropped before reaching devices |
| `op_size_o` | 3 | Fig. 2, §3.3.3 | Core→LSU: access size + sign |
| `core_data_o` | 32 | Fig. 2 | Core→LSU: store data | 
| `core_data_i` | 32 | Fig. 2 | LSU→core: load data, already sign/zero-extended |
| `core_address_o` | 32 | Fig. 2 | Core→LSU: access address |
| `mem_data_o` | 32 | Fig. 2 | Memory→LSU: raw word read back |
| `mem_data_i` | 32 | Fig. 2 | LSU→memory: store data, byte-positioned |
| `mem_address_i` | 32 | Fig. 2 | LSU→memory: address |
| `byte_write_i` | 4 | Fig. 2 | LSU→memory: byte write mask (the guide's own name for what §4.4 calls `bw_o` on the core side) |

**Verified against the PDF, 2026-08-25.** These are the only port names the
guide actually states. `we_o`/`oe_o`/`bw_o`/`address_o` appear in the §4.4
body text and Figure 3; the LSU names above are the labels inside Figure 2.

### Op-select ports — encodings guide-fixed, names ours

Tables 9/10/11 give **values only** — an encoding column and an operation
column, no port name anywhere. The strings `alu_op`, `mult_op`, and `crc_op`
do not appear in the guide at all (checked by full-text search of the PDF,
2026-08-25). So the encodings below must match exactly; the port names are a
team decision.

| Signal | Width | Encoding source | Meaning |
|---|---|---|---|
| `alu_op_o` | 4 | Table 9 | ALU select, `4'h0`–`4'hA` (11 values, needs 4 bits). Named `alu_op_o` per the §3 `_o` convention for outputs — an internal naming choice, not a guide requirement. |
| `mult_op_o` | 4 | Table 10 | MUL select, values 0–3 (only 2 bits strictly needed). **Decided: 4 bits**, matching `alu_op_o`'s width for consistency across all three op-select ports — simpler mux-select wiring, costs 2 unused bits. |
| `crc_op_o` | 4 | Table 11 | CRC select, values 0–2 (only 2 bits strictly needed). **Decided: 4 bits**, same rationale as `mult_op_o`. |

✅ **Resolved 2026-08-25.** These were originally declared bare
(`mult_op`/`crc_op`), the only two control-unit outputs missing the `_o`
suffix. Renamed to `mult_op_o`/`crc_op_o` before `top.v` was written, while
`control_unit.v` was still the only file referencing them. `mult.v` and
`crc.v` receive them as `mult_op_i`/`crc_op_i` and were untouched.

### Invented internally — not in the guide, proposal only until confirmed with the team

| Signal | Width | Meaning |
|---|---|---|
| `pc_write_o` | 1 | Enable PC to latch new value this cycle |
| `pc_src_o` | 2 | `00`=PC+4, `01`=branch/jump target, `10`=jalr target |
| `ir_write_o` | 1 | Enable IR to latch from IMEM (asserted only in FETCH) |
| `reg_write_o` | 1 | Enable register file write |
| `result_src_o` | 3 | `000`=ALU, `001`=MUL, `010`=CRC, `011`=DMEM data, `100`=PC+4 |
| `alu_src_a_o` | 1 | `0`=rs1, `1`=PC |
| `alu_src_b_o` | 2 | `00`=rs2, `01`=immediate, `10`=constant 4 |
| `imm_sel_o` | 3 | Immediate format select. **Decided:** `000`=I, `001`=S, `010`=B, `011`=U, `100`=J (see table below) |
| `mult_en_o` | 1 | Trigger multiplier this cycle |
| `crc_en_o` | 1 | Trigger CRC unit this cycle |
| `branch_taken_i` | 1 | Comparator output → feeds `pc_src_o` decision (**input** to control unit, not an output — hence `_i`) |

**`imm_sel_o` opcode → format map (decided, self-consistent — no external
spec to check against since this is fully our own invention):**

| imm_sel_o | Format | Used by |
|---|---|---|
| `000` | I | I-type ALU, JALR, loads |
| `001` | S | Stores |
| `010` | B | Branches |
| `011` | U | LUI, AUIPC |
| `100` | J | JAL |

**`op_size_o` 3-bit encoding (decided):** `op_size_o[2:1]` = size,
`op_size_o[0]` = sign (ignored for stores, since stores never extend).

| op_size_o | Size | Sign | Instruction |
|---|---|---|---|
| `000` | byte | signed | lb / sb |
| `001` | byte | unsigned | lbu |
| `010` | half | signed | lh / sh |
| `011` | half | unsigned | lhu |
| `100` | word | — | lw / sw |

For stores, only `op_size_o[2:1]` (size) matters — bit 0 is don't-care.

**`bw_o` ownership (decided): control unit drives it**, not the LSU. Keeps
the LSU a purely combinational passthrough and keeps all "which bytes"
decision logic in one place — the control unit already owns `op_size_o`
selection, so the byte-mask math naturally lives alongside it. Computed from
`op_size_o` and `address_o[1:0]`:

- word → `4'b1111` (all bytes, address bits don't matter)
- half → `4'b0011` if `address[1]=0`, else `4'b1100`
- byte → `4'b0001` shifted left by `address[1:0]` (e.g. `address[1:0]=10` →
  `4'b0100`, matching guide §3.3.2's worked example of writing byte 3)

## 4. Per-state control signal table

`mult_op_o`/`crc_op_o` aren't separate columns here since they're not part of
the original signal set drawn out per state — see §6 for their values
(direct funct3 passthrough, asserted alongside `mult_en_o`/`crc_en_o` in
the rows below).

| State | pc_write_o | pc_src_o | ir_write_o | reg_write_o | result_src_o | alu_src_a_o | alu_src_b_o | alu_op_o | imm_sel_o | mult_en_o | crc_en_o | we_o | oe_o | bw_o | op_size_o |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| RESET | 0 | - | 0 | 0 | - | - | - | - | - | 0 | 0 | 0 | 0 | - | - |
| FETCH | 1 | 00 | 1 | 0 | - | - | - | - | - | 0 | 0 | 0 | 1 | - | - |
| DECODE | 0 | - | 0 | 0 | - | - | - | - | per opcode | 0 | 0 | 0 | 0 | - | - |
| EXECUTE — ALU (R/I-type) | 0 | - | 0 | 0 | 000 | 0 | 00/01 | per funct3/7 | I | 0 | 0 | 0 | 0 | - | - |
| EXECUTE — MUL | 0 | - | 0 | 0 | 001 | 0 | 00 | - | - | 1 | 0 | 0 | 0 | - | - |
| EXECUTE — CRC | 0 | - | 0 | 0 | 010 | 0 | 00 | - | - | 0 | 1 | 0 | 0 | - | - |
| EXECUTE — Branch | 0/1* | 01 | 0 | 0 | - | 1 | 01 | ADD | B | 0 | 0 | 0 | 0 | - | - |
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

\* `pc_write_o` for branch is conditional on `branch_taken_i` from the comparator.

## 5. Decode's opcode → next-state map

`0110011` is shared by three categories — decode must also check `funct7`.

| Opcode | funct7 (if 0110011) | Category | Next state |
|---|---|---|---|
| `0110011` | **else** (not `0000001`, not `1000000`) | R-type ALU | EXECUTE — ALU |
| `0110011` | `0000001` | Zmmul | EXECUTE — MUL |
| `0110011` | `1000000` | Xicrc | EXECUTE — CRC |
| `0010011` | — | I-type ALU | EXECUTE — ALU |
| `0000011` | — | Load | MEM_ADDR |
| `0100011` | — | Store | MEM_ADDR |
| `1100011` | — | Branch | EXECUTE — Branch |
| `1101111` | — | JAL | EXECUTE — JAL |
| `1100111` | — | JALR | EXECUTE — JALR |
| `0110111` | — | LUI | EXECUTE — LUI |
| `0010111` | — | AUIPC | EXECUTE — AUIPC |
| `1110011` | — | ECALL / EBREAK | EXECUTE — no-op (verify ECALL against real firmware, see §7) |
| `0001111` | — | FENCE | EXECUTE — no-op |

**Category selection is an `else`, not a three-way equality check.** SUB and
SRA use `funct7 = 0100000` — a fourth value this table never lists. Category
logic must be: `funct7==0000001` → MUL, `funct7==1000000` → CRC, everything
else → ALU (which includes both `0000000` and `0100000`). Coding this as
`if (funct7 == 7'b0000000)` to detect "this is ALU" silently breaks SUB/SRA
— they'd match nothing. `funct7[5]` is used again inside the ALU branch, but
for a different purpose: picking ADD vs SUB and SRL vs SRA within `alu_op`,
not selecting the ALU category itself. See `alu_op` decode table in §6.

**Verify these literal bit patterns against the RISC-V spec before coding** —
a wrong opcode here silently misroutes an entire instruction class.

## 6. ALU / MUL / CRC operation codes (from guide Tables 9–11, copy exactly)

`alu_op_o` needs 4 bits (11 distinct values, `4'h0`–`4'hA`). `mult_op_o` and
`crc_op_o` only strictly need 2 bits (4 and 3 distinct values respectively) —
the guide's `4'hN` notation is just how it writes hex literals for these
tables, not a statement of port width. **Decided: `mult_op_o`/`crc_op_o` are 4
bits**, matching `alu_op_o`'s width — one consistent width across all three
op-select ports simplifies mux-select wiring for whoever builds MULT/CRC;
the 2 unused bits cost nothing.

**`alu_op_o`:** `4'h0`=PASS_B (no R-type instruction — used for LUI), plus
the 10 R-type ALU codes below. **Needs real decode logic** — these codes do
not match RV32I's standard funct3 encoding, so `alu_op_o` must come from a
lookup on (funct3, funct7[5]), not a passthrough.

**`alu_op_o` decode table** (R-type ALU, opcode `0110011`, reached only via
the `else`-branch described in §5). Only funct3 `000` and `101` need
`funct7[5]` to disambiguate; every other funct3 maps to `alu_op_o` directly
regardless of funct7:

| Instruction | funct3 | funct7 | funct7[5] | alu_op_o | Macro |
|---|---|---|---|---|---|
| ADD | `000` | `0000000` | 0 | `4'h1` | `ALU_ADD` |
| SUB | `000` | `0100000` | 1 | `4'h2` | `ALU_SUB` |
| SLL | `001` | `0000000` | 0 | `4'h6` | `ALU_SLL` |
| SLT | `010` | `0000000` | 0 | `4'h9` | `ALU_SLT` |
| SLTU | `011` | `0000000` | 0 | `4'hA` | `ALU_SLTU` |
| XOR | `100` | `0000000` | 0 | `4'h5` | `ALU_XOR` |
| SRL | `101` | `0000000` | 0 | `4'h7` | `ALU_SRL` |
| SRA | `101` | `0100000` | 1 | `4'h8` | `ALU_MRS` |
| OR | `110` | `0000000` | 0 | `4'h4` | `ALU_OR` |
| AND | `111` | `0000000` | 0 | `4'h3` | `ALU_AND` |

10 rows, matching the guide's "Arithmetic and Logic (Register): 10 expected"
coverage count. I-type ALU (ADDI, SLTI, etc., opcode `0010011`) reuses this
same table keyed on funct3 alone — no funct7 exists in I-type encoding, so
no ADD/SUB or SRL/SRA ambiguity there (I-type has no SUBI; SRAI is
distinguished from SRLI via `imm[10]` instead, worth confirming against the
spec when that module gets built).

**`mult_op_o`:** `4'h0`=MUL, `4'h1`=MULH, `4'h2`=MULHSU, `4'h3`=MULHU.
**Direct passthrough of funct3** — Table 7's funct3 values for mul (`000`)
/ mulh (`001`) / mulhsu (`010`) / mulhu (`011`) equal the MULT code
numerically. Wire `mult_op_o = {2'b00, funct3}` (4-bit port, zero-extended) —
no lookup table needed.

**`crc_op_o`:** `4'h0`=CRCB, `4'h1`=CRCH, `4'h2`=CRCW. **Direct passthrough
of funct3** — same pattern as MUL: Table 8's funct3 values for crcb
(`000`) / crch (`001`) / crcw (`010`) equal the CRC code numerically.
Wire `crc_op_o = {2'b00, funct3}` (4-bit port, zero-extended) — no lookup
table needed.

## 7. Resolved design decisions (reference, don't re-litigate)

1. **MUL is combinational, single-cycle.** No `MUL_WAIT` state. Revisit only
   if OpenLane's area report shows the multiplier dominating chip area —
   then consider iterative shift-add.
2. **DMEM load = 2 sub-cycles, store = 1.** Forced by synchronous SRAM
   read-after-address-cycle timing (§3.3 of guide).
3. **Branch/jump merged into EXECUTE**, not split into their own state.
4. **ECALL/EBREAK/FENCE implemented as no-ops** in EXECUTE — needed to hit
   full 47/47 ISA coverage in the report table. **Caveat:** confirm ECALL's
   behavior against the actual validation firmware once released — some
   RISC-V test suites use ECALL as an explicit "test complete / halt"
   signal the testbench watches for; if so, a bare no-op would silently
   break firmware validation (report §6) even though it satisfies the
   coverage table.
5. **`we_o`/`oe_o`/`bw_o`/`address_o` naming confirmed** against Figure 3 —
   core drives `_o`, decoder receives as `_i`, same wires.

6. **`mult_op_o`/`crc_op_o` are both a direct passthrough of `funct3`** — no
   lookup table needed, unlike `alu_op_o` which requires real decode logic
   since its codes don't match RV32I's standard funct3 numbering.
7. **`mult_op_o`/`crc_op_o` are 4 bits**, matching `alu_op_o`'s width — settled
   as a wiring-consistency call, not a spec requirement (values only need 2
   bits; the extra 2 are always zero).
8. **Port is named `alu_op_o`** (not bare `alu_op`) — uniform `_o` suffix
   across every control-unit output. **Corrected 2026-08-25:** this was
   originally written up as deviating from a guide-fixed name. It doesn't.
   The guide never names this port; Table 9 fixes the encoding only. There
   was nothing to deviate from, and nothing here needs organiser sign-off.
9. **`op_size_o` 3-bit encoding decided** — `[2:1]`=size, `[0]`=sign. See
   table in §3.
10. **`imm_sel_o` encoding and opcode map decided** — see table in §3.
11. **`bw_o` is driven by the control unit**, computed from `op_size_o` and
    `address_o[1:0]` — not generated inside the LSU. See §3.

**These six items (6-11) were set unilaterally, before the ALU/MULT/CRC/LSU
owners started their modules** — no teammate to conflict with yet, and every
value is either forced by the guide's own numbering (6) or an internal
wiring convention with no external spec to get wrong (7-11). Cheap to change
if a teammate has a real reason to, before their module is built against it.
Not cheap after.

## 8. Still open — pick up here

**One genuinely open item.** See `HANDOFF_control_unit_ALL_STAGES.md`
Part IV for the full treatment.

- [x] **ECALL observability** — DONE 2026-08-25. `halt_o`, a sticky status
      flag set when an ECALL retires, plus a new `funct12_i` (IR[31:20])
      input to tell ECALL from EBREAK (funct7 cannot — they differ only in
      IR[20]). Execution semantics unchanged; the flag is what the system
      testbench waits on instead of a cycle-count timeout.
- [x] **ECALL semantics** — DONE 2026-08-26. **The core stops.**
      `control_unit.v` gates `pc_write_o` **and** `ir_write_o` on
      `!halt_o`, appended after the output `case` so it overrides every
      state. Both signals must be gated: the one-line sketch this item
      originally proposed (gate `pc_write_o` only) freezes `pc` at
      `ECALL address + 4`, but `ir_write_o` keeps firing every FETCH, so
      the core reloads `mem[ECALL+4]` and re-executes that single
      instruction forever — side effects included, so a store there would
      repeat indefinitely. Freezing `ir` as well pins it at the `ECALL`,
      a no-op that writes nothing, and the FSM spins harmlessly.
      Verified: `tb_control_unit`'s `[halted]` check holds both signals
      at 0 and `halt_o` at 1 for 12 cycles, and fails under a mutation
      that gates `pc_write_o` alone.

      This **replaces** the earlier flag-only reading. The old
      `ADD_AFTER_ECALL` test asserted the opposite ("the core did not
      stall") and was removed along with the decision it encoded.

**Resolved since this list was written:**

- ~~Illegal-opcode policy~~ — **decided: silent no-op.** The guide never
  mentions illegal-instruction trapping and the coverage table has no row
  for it. Replaces the `ALU_ADD` fallthrough placeholder.

  **IMPLEMENTED 2026-08-26** — the decision sat here unimplemented for a
  while, and the gap was real: DECODE's else-branch routed any unknown
  opcode to EXECUTE_ALU, which fell through to WRITE_BACK and asserted
  `reg_write_o`, so an illegal instruction executed as an ADD and
  clobbered `rd`. Confirmed in simulation before the fix (custom-0
  opcode `7'b0001011` with `rd=x6` overwrote `x6`). Now a new
  `opcode_legal` wire adds unknown opcodes to the same skip-WRITE_BACK
  path `BRANCH`/`SYSTEM`/`FENCE` already take: 3 cycles, no register
  write, no memory write, PC advances. Note the `ALU_ADD` default in the
  funct3 case was *not* the actual defect — `funct3_i` is 3 bits with all
  eight values covered, so that arm is unreachable. The defect was the
  next-state routing. Tested by `tb_control_unit`'s `[ILLEGAL]` check.
- ~~x0 write protection~~ — **not a control-unit item.** It's a one-line
  guard in the regfile (`if (reg_write_i && rd_addr_i != 5'd0)`), per guide
  §3.1.4. Belongs on the memory pair's task list, not this open-questions
  list. Confirm with the regfile owner at integration.

## 9. Suggested repo layout

```
project/
  rtl/
    control_unit.v
    alu.v
    mult.v
    crc.v
    branch_comparator.v
    imm_extend.v
    regfile.v
    lsu.v
    address_decoder.v
    imem.v
    dmem.v
    top.v
  tb/
    tb_control_unit.v
    tb_alu.v
    tb_top.v
  sim/              # .vvp / .vcd output, gitignore this
  config.json        # OpenLane config
```

## 10. Tooling

- **iverilog** — compile: `iverilog -o sim/tb_x.vvp rtl/x.v tb/tb_x.v`
- **run:** `vvp sim/tb_x.vvp`
- **view:** `gtkwave sim/x.vcd` (testbench needs `$dumpfile`/`$dumpvars`)
- **OpenLane** — separate step, physical design flow, produces GDSII +
  gate-level netlist + `config.json` for submission
- ChipInventor — report figures only, not part of the RTL/sim/OpenLane flow

## 11. Recommended first implementation step

Build and simulate the smallest possible slice first, before wiring the
full datapath:

1. State register + next-state logic for FETCH → DECODE → EXECUTE(ALU) →
   WRITE BACK only.
2. Testbench that steps the clock and asserts `state`, `we_o`, `alu_op`,
   `reg_write_o` etc. match §4's table row-by-row for a single instruction
   (e.g. `add x5, x6, x7`).
3. Only once that passes, add MEM_ADDR/MEM_ACCESS/branch/jump paths.

This catches control-unit timing bugs early, before they're tangled up
with ALU/LSU/regfile integration issues.
