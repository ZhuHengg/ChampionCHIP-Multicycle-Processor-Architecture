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
| Store | 5 | fetch, decode, mem_addr, mem_access → fetch |
| Load | 6 | fetch, decode, mem_addr, mem_access_addr, mem_access_data, write back |

## 3. Signal glossary

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
| `alu_op` | 4 | Table 9 | ALU select, `4'h0`–`4'hA` (11 values, needs 4 bits) |
| `mult_op` | 2* | Table 10 | MUL select, values 0–3 (4 values, fits 2 bits) (*guide writes the values as `4'hN` literals but never states the port width — confirm with Teammate B before finalizing) |
| `crc_op` | 2* | Table 11 | CRC select, values 0–2 (3 values, fits 2 bits) (*same caveat) |

### Invented internally — not in the guide, proposal only until confirmed with the team

| Signal | Width | Meaning |
|---|---|---|
| `pc_write` | 1 | Enable PC to latch new value this cycle |
| `pc_src` | 2 | `00`=PC+4, `01`=branch/jump target, `10`=jalr target |
| `ir_write` | 1 | Enable IR to latch from IMEM (asserted only in FETCH) |
| `reg_write` | 1 | Enable register file write |
| `result_src` | 3 | `000`=ALU, `001`=MUL, `010`=CRC, `011`=DMEM data, `100`=PC+4 |
| `alu_src_a` | 1 | `0`=rs1, `1`=PC |
| `alu_src_b` | 2 | `00`=rs2, `01`=immediate, `10`=constant 4 |
| `imm_sel` | 3 | Immediate format: I/S/B/U/J |
| `mult_en` | 1 | Trigger multiplier this cycle |
| `crc_en` | 1 | Trigger CRC unit this cycle |
| `branch_taken` | 1 | Comparator output → feeds `pc_src` decision (not driven by control unit) |

## 4. Per-state control signal table

`mult_op`/`crc_op` aren't separate columns here since they're not part of
the original signal set drawn out per state — see §6 for their values
(direct funct3 passthrough, asserted alongside `mult_en`/`crc_en` in the
rows below).

| State | pc_write | pc_src | ir_write | reg_write | result_src | alu_src_a | alu_src_b | alu_op | imm_sel | mult_en | crc_en | we_o | oe_o | bw_o | op_size_o |
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

\* `pc_write` for branch is conditional on `branch_taken` from the comparator.

## 5. Decode's opcode → next-state map

`0110011` is shared by three categories — decode must also check `funct7`.

| Opcode | funct7 (if 0110011) | Category | Next state |
|---|---|---|---|
| `0110011` | `0000000` (default) | R-type ALU | EXECUTE — ALU |
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

**Verify these literal bit patterns against the RISC-V spec before coding** —
a wrong opcode here silently misroutes an entire instruction class.

## 6. ALU / MUL / CRC operation codes (from guide Tables 9–11, copy exactly)

`alu_op` needs 4 bits (11 distinct values, `4'h0`–`4'hA`). `mult_op` and
`crc_op` only need 2 bits (4 and 3 distinct values respectively) — the
guide's `4'hN` notation is just how it writes hex literals for these
tables, not a statement of port width. **Port width for `mult_op`/`crc_op`
is still open** — confirm with Teammate B whether the module expects a
tight 2-bit port or a 4-bit port matching `alu_op`'s width for interface
consistency (either works functionally; it's a wiring-convention choice,
not a spec question).

**`alu_op`:** `4'h0`=PASS_B, `4'h1`=ADD, `4'h2`=SUB, `4'h3`=AND, `4'h4`=OR,
`4'h5`=XOR, `4'h6`=SLL, `4'h7`=SRL, `4'h8`=MRS(arith. shift/SRA), `4'h9`=SLT,
`4'hA`=SLTU. **Needs real decode logic** — these codes do not match
RV32I's standard funct3 encoding (e.g. ADD and SUB both use funct3=`000`,
distinguished only by funct7 bit 5), so `alu_op` must come from a
case/lookup on (funct3, funct7[5]), not a passthrough.

**`mult_op`:** `4'h0`=MUL, `4'h1`=MULH, `4'h2`=MULHSU, `4'h3`=MULHU.
**Direct passthrough of funct3** — Table 7's funct3 values for mul (`000`)
/ mulh (`001`) / mulhsu (`010`) / mulhu (`011`) equal the MULT code
numerically. Wire `mult_op = {1'b0, funct3}` — no lookup table needed.

**`crc_op`:** `4'h0`=CRCB, `4'h1`=CRCH, `4'h2`=CRCW. **Direct passthrough
of funct3** — same pattern as MUL: Table 8's funct3 values for crcb
(`000`) / crch (`001`) / crcw (`010`) equal the CRC code numerically.
Wire `crc_op = {1'b0, funct3}` — no lookup table needed.

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

6. **`mult_op`/`crc_op` are both a direct passthrough of `funct3`** — no
   lookup table needed, unlike `alu_op` which requires real decode logic
   since its codes don't match RV32I's standard funct3 numbering. Port
   *width* for `mult_op`/`crc_op` (2-bit tight fit vs 4-bit to match
   `alu_op`) is still open — see §8.

## 8. Still open — pick up here

- [ ] `mult_op`/`crc_op` port width — 2 bits (tight fit) or 4 bits (match
      `alu_op`)? Values themselves are settled (direct funct3 passthrough,
      §6) — only the port declaration width is open. Coordinate with
      Teammate B.
- [ ] `op_size_o` exact 3-bit encoding (size + sign) — coordinate with
      whoever owns the LSU
- [ ] `imm_sel` exact encoding, opcode → format mapping (confirmed not in
      guide at all — this is fully our own invention, no spec to check
      against, just internal consistency)
- [ ] x0 write protection (register file should silently discard writes to
      x0) — not FSM-blocking, add as a guard once main path works
- [ ] Illegal-opcode handling policy — undecided, not required for first
      working version
- [ ] ECALL behavior — revisit once validation firmware is available (see
      §7 item 4)

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
   `reg_write` etc. match §4's table row-by-row for a single instruction
   (e.g. `add x5, x6, x7`).
3. Only once that passes, add MEM_ADDR/MEM_ACCESS/branch/jump paths.

This catches control-unit timing bugs early, before they're tangled up
with ALU/LSU/regfile integration issues.
