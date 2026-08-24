# Datapath Build Plan — five modules

Build plan for `rtl/datapath/`: `alu.v`, `mult.v`, `crc.v`,
`branch_comparator.v`, `imm_extend.v`.

**Read first:** `.claude/CLAUDE.md` (the 9-step workflow is mandatory) and
`docs/HANDOFF_control_unit_ALL_STAGES.md` (signal encodings — the control
unit already drives every select line these modules consume).

**Every constant comes from `rtl/pkg/rvbl2_defines.vh`.** The control unit
is built against those exact values. Re-deriving them from the guide tables
independently is how two modules end up disagreeing about what `4'h2` means.

---

## What these modules are

All five are **combinational** — values in, value out, no clock, no state.
Each takes a select line from the control unit and does one transform.

That's what makes them independent: none of them depends on any other, and
none depends on the memory modules. Five people could build five of these in
parallel without talking.

**They are not the ISA.** The ISA says `sub rd, rs1, rs2` computes
rs1 − rs2. These modules are one particular hardware that satisfies that —
`alu_op = 4'h2` meaning SUB is this chip's private wiring convention (guide
Table 9), not something RISC-V specifies.

---

## Ownership — assign before starting

`rtl/datapath/` is shared across all four people under the current split.
**Shared means nobody owns any given module**, which is how you get two
`alu.v` implementations and no `crc.v`. Put a name on each of the five
before anyone writes code.

| Module | Owner | Status |
|---|---|---|
| `branch_comparator.v` | | Not started |
| `imm_extend.v` | | Not started |
| `alu.v` | | Not started |
| `mult.v` | | Not started |
| `crc.v` | | **Blocked** — see below |

---

## Build order

Suggested, not mandatory — they're independent, so parallel is fine.

1. **`branch_comparator.v`** — smallest, and it closes a loop: the control
   unit's `branch_taken_i` is currently driven by a testbench stub.
2. **`imm_extend.v`** — small, fully specified, `imm_sel_o` already decided.
3. **`alu.v`** — the most-used module in the design. Table 9 specifies it
   completely.
4. **`mult.v`** — straightforward, but the biggest area risk in the project.
5. **`crc.v`** — blocked on a spec gap. Raise the question now so an answer
   exists by the time the other four are done.

---

## `branch_comparator.v`

**Guide §3.1.6.** Compares rs1 and rs2, outputs whether the branch is taken.

| Port | Dir | Width | Notes |
|---|---|---|---|
| `rs1_i` | in | 32 | |
| `rs2_i` | in | 32 | |
| `funct3_i` | in | 3 | Selects the comparison |
| `branch_taken_o` | out | 1 | Arrives at the CU as `branch_taken_i` |

**Comparisons** (funct3 from the RISC-V spec — verify, don't trust this
table alone):

| funct3 | Instruction | Condition | Signed? |
|---|---|---|---|
| `000` | BEQ | rs1 == rs2 | n/a |
| `001` | BNE | rs1 != rs2 | n/a |
| `100` | BLT | rs1 < rs2 | signed |
| `101` | BGE | rs1 >= rs2 | signed |
| `110` | BLTU | rs1 < rs2 | unsigned |
| `111` | BGEU | rs1 >= rs2 | unsigned |

Note funct3 `010` and `011` are unused — needs a `default` arm.

**The trap: signed vs unsigned comparison.** In Verilog, `<` on a plain
`wire [31:0]` is unsigned. BLT and BGE need signed comparison — use
`$signed(rs1_i) < $signed(rs2_i)`. Getting this wrong makes `blt` work for
positive numbers and silently fail for negatives, which most casual tests
won't catch.

**Tests:** each of the 6 instructions, both taken and not-taken. Include
negative operands specifically for BLT/BGE, and a case where signed and
unsigned disagree — e.g. rs1 = `0xFFFFFFFF`, rs2 = `0x00000001`. Signed
that's −1 < 1 (taken for BLT); unsigned it's 4294967295 > 1 (not taken for
BLTU). Same bits, opposite answers. That one test catches the whole class of
bug.

---

## `imm_extend.v`

**Guide §3.1.5.** Extracts the immediate from the instruction and
sign-extends it to 32 bits.

| Port | Dir | Width | Notes |
|---|---|---|---|
| `instr_i` | in | 32 | Full instruction word |
| `imm_sel_i` | in | 3 | From the CU's `imm_sel_o` |
| `imm_o` | out | 32 | Sign-extended |

**Select values** — already decided, macros in `rvbl2_defines.vh`:

| Value | Macro | Format | Used by |
|---|---|---|---|
| `3'b000` | `` `IMM_SEL_I `` | I | I-type ALU, JALR, loads |
| `3'b001` | `` `IMM_SEL_S `` | S | Stores |
| `3'b010` | `` `IMM_SEL_B `` | B | Branches |
| `3'b011` | `` `IMM_SEL_U `` | U | LUI, AUIPC |
| `3'b100` | `` `IMM_SEL_J `` | J | JAL |

**Bit extraction — get this from the RISC-V spec, not from memory.** The
five formats scatter immediate bits differently across the instruction, and
B and J are the awkward ones (bits deliberately shuffled so that hardware
can share wiring). Specifically:

- **I:** `instr[31:20]`, sign-extended. Straightforward.
- **S:** `{instr[31:25], instr[11:7]}`, sign-extended. Split in two.
- **B:** `{instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}` —
  note the implicit trailing zero (branch targets are 2-byte aligned) and
  that bit 7 and bit 31 swap roles relative to S.
- **U:** `{instr[31:12], 12'b0}` — the immediate occupies the *upper* bits;
  no sign extension needed, the low 12 are zero.
- **J:** `{instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}` —
  the most scrambled. Implicit trailing zero again.

**All sign extension uses `instr[31]`** as the sign bit (except U, which
needs none). **Verify every one of these against the spec before coding** —
a single misplaced bit here produces branch targets that are wrong by a
power of two, which looks like a working processor that occasionally jumps
somewhere absurd.

**Tests:** one per format minimum, with a negative immediate for each of
I/S/B/J to exercise sign extension. For B and J, specifically assert the
low bit is always 0.

---

## `alu.v`

**Guide §3.1.1, Table 9.** The most-used module in the design — every ALU
instruction, plus address calculation for loads/stores, plus branch and jump
target calculation.

| Port | Dir | Width | Notes |
|---|---|---|---|
| `a_i` | in | 32 | Operand A (rs1 or PC) |
| `b_i` | in | 32 | Operand B (rs2, immediate, or constant 4) |
| `alu_op_i` | in | 4 | From the CU's `alu_op_o` |
| `result_o` | out | 32 | |

**Port naming:** the CU declares its output as `alu_op_o`; this module
receives it as `alu_op_i`. Same wire, opposite-end naming — the convention
the guide uses for `we_o`/`we_i` (handoff §3).

**Operations** — use the `` `ALU_* `` macros, values from Table 9:

| Macro | Value | Operation |
|---|---|---|
| `` `ALU_PASS_B `` | `4'h0` | `Q = B` (used by LUI) |
| `` `ALU_ADD `` | `4'h1` | `Q = A + B` |
| `` `ALU_SUB `` | `4'h2` | `Q = A - B` |
| `` `ALU_AND `` | `4'h3` | `Q = A & B` |
| `` `ALU_OR `` | `4'h4` | `Q = A \| B` |
| `` `ALU_XOR `` | `4'h5` | `Q = A ^ B` |
| `` `ALU_SLL `` | `4'h6` | `Q = A << B[4:0]` |
| `` `ALU_SRL `` | `4'h7` | `Q = A >> B[4:0]` (logical) |
| `` `ALU_MRS `` | `4'h8` | `Q = A >>> B[4:0]` (arithmetic) |
| `` `ALU_SLT `` | `4'h9` | `Q = (A < B) ? 1 : 0`, signed |
| `` `ALU_SLTU `` | `4'hA` | `Q = (A < B) ? 1 : 0`, unsigned |

**Three traps in this table:**

1. **Shift amount is `B[4:0]`, not all of B.** The guide says so explicitly.
   Using the full 32 bits gives undefined behavior for large shifts.
2. **`ALU_MRS` is arithmetic shift right** despite the odd name — the guide
   calls it MRS but describes `A >>> B[4:0]`. In Verilog, `>>>` only does
   sign extension if the operand is signed: `$signed(a_i) >>> b_i[4:0]`.
   Plain `a_i >>> b_i[4:0]` on an unsigned wire behaves like `>>`, silently
   turning SRA into SRL.
3. **SLT vs SLTU** — same signed/unsigned trap as the branch comparator.
   `$signed()` for SLT, plain for SLTU.

**Needs a `default` arm** — `alu_op` has 11 defined values out of 16
possible. Per handoff decision #13 the illegal-opcode policy is silent
no-op, so a sensible default is `result_o = 32'b0` or pass-through; note
which you chose in a comment.

**Tests:** all 11 operations. For the shifts, include a shift amount > 31 to
prove `B[4:0]` masking works. For SRA, a negative operand. For SLT/SLTU, the
`0xFFFFFFFF` vs `0x00000001` case that distinguishes them.

---

## `mult.v`

**Guide §3.1.2, Table 10.** 32×32 → 64-bit multiply, with a mux selecting
which half of the result to return.

| Port | Dir | Width | Notes |
|---|---|---|---|
| `a_i` | in | 32 | rs1 |
| `b_i` | in | 32 | rs2 |
| `mult_op_i` | in | 4 | From the CU's `mult_op` |
| `result_o` | out | 32 | |

**Combinational, single cycle** — handoff decision #1. No `MUL_WAIT` state,
no done handshake. The control unit's EXECUTE state expects the result the
same cycle.

**Operations:**

| Macro | Value | Operation |
|---|---|---|
| `` `MULT_MUL `` | `4'h0` | `(rs1 signed × rs2 signed)[31:0]` |
| `` `MULT_MULH `` | `4'h1` | `(rs1 signed × rs2 signed)[63:32]` |
| `` `MULT_MULHSU `` | `4'h2` | `(rs1 signed × rs2 unsigned)[63:32]` |
| `` `MULT_MULHU `` | `4'h3` | `(rs1 unsigned × rs2 unsigned)[63:32]` |

**The trap: three different signedness combinations.** MULHSU is the one
people get wrong — rs1 signed, rs2 *unsigned*, mixed. In Verilog you need
the multiply itself to happen at 64-bit width with correct sign extension on
each operand independently:

```verilog
// signed × signed
wire signed [63:0] p_ss = $signed(a_i) * $signed(b_i);
// signed × unsigned — extend a_i signed, b_i zero-extended, to 64 bits first
wire signed [63:0] p_su = $signed({{32{a_i[31]}}, a_i}) * $signed({32'b0, b_i});
// unsigned × unsigned
wire        [63:0] p_uu = a_i * b_i;
```

Getting the extension wrong produces results that are correct for small
positive operands and wrong everywhere else — passes a lazy test, fails
firmware.

**Note MUL (`4'h0`) returns the low 32 bits**, where signedness doesn't
actually matter — the low half is identical for signed and unsigned
multiply. Only the upper-half variants care.

**⚠ Synthesis note — the biggest area risk in the project.** A full
combinational 64-bit multiplier is a large block on Sky130. Flag it
specifically in the OpenLane area report (report §5). If it dominates, the
fallback is an iterative shift-add version — but that would reintroduce a
`MUL_WAIT` state with a done handshake in the control unit, i.e. it changes
the FSM, not just this module. **Don't pre-optimize.** Build it
combinational, measure, then decide.

**Tests:** all 4 operations. Include negative × negative, negative ×
positive, and the MULHSU mixed case specifically. `0xFFFFFFFF × 0xFFFFFFFF`
is a good stress case — signed that's (−1)×(−1)=1, unsigned it's a very
large number, and the two give completely different upper halves.

---

## `crc.v` — ⚠ BLOCKED

**Guide §3.1.3, Table 11.** Computes a 16-bit CRC over parts of rs1/rs2.

| Port | Dir | Width | Notes |
|---|---|---|---|
| `a_i` | in | 32 | rs1 |
| `b_i` | in | 32 | rs2 |
| `crc_op_i` | in | 4 | From the CU's `crc_op` |
| `result_o` | out | 32 | Result in `[15:0]`, upper bits zero |

| Macro | Value | Operation |
|---|---|---|
| `` `CRC_CRCB `` | `4'h0` | `rd = CRC8(rs1, rs2)[15:0]` |
| `` `CRC_CRCH `` | `4'h1` | `rd = CRC16(rs1, rs2)[15:0]` |
| `` `CRC_CRCW `` | `4'h2` | `rd = CRC32(rs1, rs2)[15:0]` |

### What's missing from the spec

The guide gives the table above and says "processing the CRC-16 natively"
and "without latency." It **never states**:

- **The polynomial.** CRC-16 alone has many in common use — CCITT
  (`0x1021`), IBM/ANSI (`0x8005`), and others. Different polynomial,
  completely different output.
- **The initial value.** `0x0000` and `0xFFFF` are both common.
- **Bit ordering / reflection.** Whether input bytes and output are
  bit-reversed. Same polynomial, reflected vs not, different results.
- **Final XOR.** Some variants XOR the output with `0xFFFF`.
- **What CRC8/CRC16/CRC32 mean here.** Table 8 says crcb/crch/crcw process
  8/16/32 bits of input — so the names appear to describe *input width*,
  not three different CRC algorithms, with all three producing a 16-bit
  result. Worth confirming: "CRC32" producing a 16-bit output is unusual
  phrasing and could equally mean the CRC-32 algorithm truncated.
- **How rs1 and rs2 combine.** `CRC8(rs1, rs2)` takes two operands — likely
  rs1 is the running CRC state and rs2 the new data (that's the standard
  pattern for an incremental CRC instruction), but the guide doesn't say.

These are not details that can be reasoned out. They're arbitrary
parameters, and the validation firmware will have exactly one right answer.

### What to do

**Ask on the ChampionCHIP platform now** — before the other four modules are
done, so the answer arrives without blocking. Specifically ask for: the
polynomial, initial value, reflection convention, final XOR, and the
rs1/rs2 operand roles.

**Do not guess and build.** This is the same class of gap as `op_size_o`
was for the control unit, except worse: `op_size_o` was an internal
convention we could pick freely because only our own modules consume it. The
CRC output is checked against firmware we don't control — a wrong guess
produces a module that works perfectly, self-consistently, and fails
validation.

**If an answer doesn't arrive:** build the module with the polynomial and
init value as parameters (`parameter POLY = 16'h1021;`), so swapping them is
a one-line change rather than a rewrite. Then pick the most common
convention (CRC-16/CCITT, init `0xFFFF`) as a placeholder and document the
assumption prominently in the report.

---

## Testing

Each module gets a testbench in `tb/datapath/`, named `tb_<module>.v`.

```bash
iverilog -o sim/tb_alu.vvp -I rtl rtl/datapath/alu.v tb/datapath/tb_alu.v
vvp sim/tb_alu.vvp
gtkwave sim/tb_alu.vcd
```

Note `-I rtl`, not `-I rtl/pkg` — the include path is `"pkg/rvbl2_defines.vh"`,
so the search root is `rtl/`.

Every testbench needs `$dumpfile("sim/<name>.vcd")` and `$dumpvars(0, ...)`.

**Definition of done, per module:** every operation in its table exercised by
a directed test, the signedness traps specifically covered, simulation
actually run, output reported verbatim. "Should work" is not a status.

---

## What these modules unblock

Once all five exist plus the memory modules, `top.v` (control unit slice 7)
becomes possible. The control unit is finished through slice 6 and waiting.

**Integration risks to keep in mind while building** — cheaper to avoid than
to debug later:

- **Port naming.** The CU drives `alu_op_o`; this module receives
  `alu_op_i`. Same wire. Mismatches here are compile errors at `top.v`, not
  subtle bugs — but they're avoidable by following the convention now.
- **Width agreement.** `mult_op`/`crc_op` are 4 bits (handoff decision #7),
  even though the values only need 2. Declare the ports 4 bits wide.
- **`bw_o` is NOT the datapath's job.** The control unit computes it
  (decision #11). If someone builds byte-mask logic into the LSU or ALU too,
  one of them is dead code.
