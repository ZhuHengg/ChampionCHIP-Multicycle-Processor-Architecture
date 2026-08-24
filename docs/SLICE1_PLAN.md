# Slice 1 Implementation Plan — control_unit.v (R-type ALU path)

Read `.claude/CLAUDE.md` and `docs/HANDOFF_control_unit.md` first. This plan
assumes both. Follow CLAUDE.md's 9-step workflow — steps 1-3 are already
done below, start at step 4 (RTL coding).

## Scope — what slice 1 covers

FETCH → DECODE → EXECUTE_ALU → WRITE_BACK → FETCH, **R-type ALU only**
(opcode `0110011`, funct7 else-branch). 4 cycles per instruction.

**Explicitly out of scope** (later slices, do not add):
- I-type ALU — blocked on `imm_sel_o` encoding (handoff §8, still open)
- Load/store, MEM_ADDR, MEM_ACCESS — blocked on `op_size_o` (§8, open)
- Branch, JAL, JALR — needs `branch_taken_i` from branch comparator
- MUL, CRC — blocked on `mult_op`/`crc_op` port width (§8, open)
- LUI, AUIPC, ECALL/EBREAK/FENCE

Do not add ports for out-of-scope signals. They arrive with their slice.

## Decisions already locked (do not re-litigate, do not ask again)

1. **Reset is SYNCHRONOUS.** `always @(posedge clk_i)` with `if (rst_i)`
   inside. Not `always @(posedge clk_i or posedge rst_i)`.
2. **R-type only** for this slice.
3. **All invented output signals carry `_o`** — handoff §3 naming paragraph.
   `branch_taken` is `branch_taken_i` (input), not in this slice anyway.
4. **State encoding is `localparam` inside control_unit.v**, NOT in
   `rtl/pkg/rvbl2_defines.vh`. It never crosses a module boundary.
5. **4-bit state register** — 9+ states eventually, 3 bits is too few.

## Step 2 — Interface (implement exactly this)

```verilog
module control_unit (
    input  wire        clk_i,
    input  wire        rst_i,
    // From IR — decode fields
    input  wire [6:0]  opcode_i,      // IR[6:0]
    input  wire [2:0]  funct3_i,      // IR[14:12]
    input  wire [6:0]  funct7_i,      // IR[31:25]
    // Datapath control — invented signals (handoff §3)
    output reg         pc_write_o,
    output reg  [1:0]  pc_src_o,
    output reg         ir_write_o,
    output reg         reg_write_o,
    output reg  [2:0]  result_src_o,
    output reg         alu_src_a_o,
    output reg  [1:0]  alu_src_b_o,
    output reg  [3:0]  alu_op_o,
    // Memory interface — guide-fixed names, must match exactly
    output reg         we_o,
    output reg         oe_o
);
```

Note `alu_op_o` — the handoff glossary lists it bare as `alu_op` under the
guide-fixed table, but it is a control-unit *output*, so it takes `_o` under
the §3 convention. **Flag this to the user when done** — the handoff §3
guide-fixed table still says `alu_op`, and that row may want updating for
consistency, or may deliberately stay bare because a teammate's module
declares it as `alu_op`. Do not silently change the doc; ask.

## Step 3 — State table (implement exactly these values)

| State | Next state | pc_write_o | pc_src_o | ir_write_o | reg_write_o | result_src_o | alu_src_a_o | alu_src_b_o | alu_op_o | we_o | oe_o |
|---|---|---|---|---|---|---|---|---|---|---|---|
| RESET | FETCH | 0 | `PC_SRC_PLUS4` | 0 | 0 | `RESULT_SRC_ALU` | `ALU_SRC_A_RS1` | `ALU_SRC_B_RS2` | `ALU_PASS_B` | 0 | 0 |
| FETCH | DECODE | 1 | `PC_SRC_PLUS4` | 1 | 0 | `RESULT_SRC_ALU` | `ALU_SRC_A_RS1` | `ALU_SRC_B_RS2` | `ALU_PASS_B` | 0 | 1 |
| DECODE | EXECUTE_ALU | 0 | `PC_SRC_PLUS4` | 0 | 0 | `RESULT_SRC_ALU` | `ALU_SRC_A_RS1` | `ALU_SRC_B_RS2` | `ALU_PASS_B` | 0 | 0 |
| EXECUTE_ALU | WRITE_BACK | 0 | `PC_SRC_PLUS4` | 0 | 0 | `RESULT_SRC_ALU` | `ALU_SRC_A_RS1` | `ALU_SRC_B_RS2` | *decoded* | 0 | 0 |
| WRITE_BACK | FETCH | 0 | `PC_SRC_PLUS4` | 0 | 1 | `RESULT_SRC_ALU` | `ALU_SRC_A_RS1` | `ALU_SRC_B_RS2` | `ALU_PASS_B` | 0 | 0 |

**Deviation from handoff §4 — document this inline in the RTL with a
comment.** Handoff §4 shows `-` (don't care) in many cells. This table
fills them with concrete defaults instead, because CLAUDE.md requires every
output assigned a default before any `case` to avoid inferred latches during
OpenLane synthesis. Behavior is identical — those signals are ignored by the
datapath in those states.

DECODE next-state is unconditionally EXECUTE_ALU **in this slice only**,
since R-type is the only opcode handled. Structure the next-state logic so
adding the other opcode branches later is a matter of adding `case` arms,
not restructuring. A `default` arm should exist even now.

## Step 4 — RTL structure (three always blocks, one per purpose)

```
always @(posedge clk_i)      // state register, SYNC reset, uses <=
always @(*)                  // next-state logic, uses =
always @(*)                  // output logic, uses =, all defaults first
```

Never mix `<=` and `=` in one block. Never combine state and output logic.

`` `include "pkg/rvbl2_defines.vh" `` is already at the top of the existing
stub file — keep it. Use the named macros (`` `ALU_ADD ``, `` `PC_SRC_PLUS4 ``,
etc.), never raw literals. The defines file already has every constant this
slice needs.

## alu_op decode (EXECUTE_ALU state only)

From handoff §6. Only funct3 `000` and `101` consult `funct7_i[5]`:

| funct3 | funct7[5] | alu_op_o macro |
|---|---|---|
| `000` | 0 | `` `ALU_ADD `` |
| `000` | 1 | `` `ALU_SUB `` |
| `001` | x | `` `ALU_SLL `` |
| `010` | x | `` `ALU_SLT `` |
| `011` | x | `` `ALU_SLTU `` |
| `100` | x | `` `ALU_XOR `` |
| `101` | 0 | `` `ALU_SRL `` |
| `101` | 1 | `` `ALU_MRS `` (SRA) |
| `110` | x | `` `ALU_OR `` |
| `111` | x | `` `ALU_AND `` |

Needs a `default` arm. Illegal-opcode policy is undecided (handoff §8) — for
now default to `` `ALU_ADD `` and leave an inline comment saying the policy is
open, do not invent a trap/exception path.

**Do not** write `if (funct7_i == 7'b0000000)` to detect "is ALU" — see the
ELSE warning in `rvbl2_defines.vh` and handoff §5. Not directly relevant in
this slice (R-type is the only path) but structure it as an `else` branch
from the start so slices 4-5 slot in cleanly.

## Step 5 — Self-review before simulating

Check each explicitly:
- Every `always @(*)` block assigns every output before any `case`
- Every `case` has a `default`
- No signal driven from two blocks
- Bit-width literals consistent (defines.vh uses `4'hN` style)
- Sync reset, not async

## Step 6 — Testbench: `tb/control_unit/tb_control_unit.v`

Directed test, instruction `add x5, x6, x7`:
- opcode_i = `7'b0110011`, funct3_i = `3'b000`, funct7_i = `7'b0000000`

Assert, cycle by cycle, that state and all 10 outputs match the step-3 table
row for that state. Then let it loop back to FETCH and confirm the cycle
count is 4 (handoff §2 cycle table: R-type = 4 cycles).

Second directed test, `sub x5, x6, x7` (funct3 `000`, funct7 `0100000`) —
this is the one that catches the funct7[5] bug. Assert `alu_op_o` ==
`` `ALU_SUB `` in EXECUTE_ALU, not `` `ALU_ADD ``.

Third, `sra` (funct3 `101`, funct7 `0100000`) → `` `ALU_MRS ``, and `srl`
(funct3 `101`, funct7 `0000000`) → `` `ALU_SRL ``. Same trap, other funct3.

Optionally cover the remaining 6 R-type ops — cheap, and it completes the
10/10 coverage claim for the report.

Testbench MUST call:
```verilog
$dumpfile("sim/tb_control_unit.vcd");
$dumpvars(0, tb_control_unit);
```

## Step 7 — Simulate

```bash
iverilog -o sim/tb_control_unit.vvp -I rtl rtl/control_unit.v tb/control_unit/tb_control_unit.v
vvp sim/tb_control_unit.vvp
```

Verify against the step-3 table row by row. Do not eyeball a waveform and
declare success. Report actual pass/fail output.

## Step 8/9 — Report format

Report status as: what's implemented, what's tested and passing, what's still
open or assumed. Never say "should work" — either it passed the testbench or
it hasn't been tested, say which.

Flag for the user at the end:
1. The `alu_op` vs `alu_op_o` naming question (see Step 2 note)
2. Illegal-opcode default choice (defaulted to ADD, policy still open)
3. Any wide combinational logic worth revisiting at OpenLane time
