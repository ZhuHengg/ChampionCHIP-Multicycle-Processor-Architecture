# Memory Build Plan — five modules

Build plan for `rtl/memory/`: `regfile.v`, `lsu.v`, `address_decoder.v`,
`imem.v`, `dmem.v`.

**Read first:** `.claude/CLAUDE.md` (the 9-step workflow is mandatory) and
`docs/HANDOFF_control_unit_ALL_STAGES.md` (signal encodings — the control
unit already drives every signal these modules consume).

**Every constant comes from `rtl/pkg/rvbl2_defines.vh`.** The control unit
and all four datapath modules are already built against those values.

---

## What these modules are

Unlike the datapath (pure combinational transforms), these are **stateful**
or **routing** blocks:

- `regfile.v` — holds 32 registers, clocked write
- `dmem.v` — holds 8 kB, clocked read *and* write
- `imem.v` — holds the program, clocked read
- `lsu.v` — combinational, but sits on the data path between core and memory
- `address_decoder.v` — combinational routing, no storage

Two of them (`dmem`, `imem`) are the only modules in the project whose
*timing* the control unit's FSM design depends on. Get that wrong and the
FSM is wrong — see the DMEM section.

---

## Ownership and order

All five are owned by the memory pair. None is blocked.

| # | Module | Depends on | Notes |
|---|---|---|---|
| 1 | `regfile.v` | — | Smallest, fully specified |
| 2 | `imem.v` | — | Simple ROM |
| 3 | `dmem.v` | — | ⚠ Timing-critical |
| 4 | `address_decoder.v` | — | Pure routing |
| 5 | `lsu.v` | — | Most logic; Table 12 gives golden vectors |

They're independent — parallel is fine. Order above is easiest-first.

---

## Sizing decision — parameterize, small defaults

The guide specifies IMEM at 4 MB and DMEM at 8 kB. A literal 4 MB ROM is
1,048,576 words, which makes simulation slow and OpenLane area meaningless.

**Both memories take a `DEPTH_WORDS` parameter with a small default.**
Real sizes get set at `top.v` / OpenLane time if needed.

```verilog
module imem #(parameter DEPTH_WORDS = 1024) (...);   // 4 kB default
module dmem #(parameter DEPTH_WORDS = 2048) (...);   // 8 kB — the real size
```

DMEM's 8 kB is already small, so its default is the true value. Only IMEM
gets shrunk for practicality. **Document this in the report** — an evaluator
comparing your area numbers against a 4 MB spec should see why.

Address the array with the *low* bits of the word address, so a small array
still responds to the guide's real addresses:

```verilog
wire [$clog2(DEPTH_WORDS)-1:0] index = addr_i[$clog2(DEPTH_WORDS)-1:0];
```

---

## `regfile.v`

**Guide §3.1.4.** 32 general-purpose 32-bit registers. Asynchronous read of
rs1/rs2, synchronous write of rd.

| Port | Dir | Width | Notes |
|---|---|---|---|
| `clk_i` | in | 1 | |
| `rst_i` | in | 1 | Synchronous, matching the CU |
| `rs1_addr_i` | in | 5 | From `IR[19:15]` |
| `rs2_addr_i` | in | 5 | From `IR[24:20]` |
| `rd_addr_i` | in | 5 | From `IR[11:7]` |
| `write_data_i` | in | 32 | Result to write back |
| `reg_write_i` | in | 1 | From the CU's `reg_write_o` |
| `rs1_data_o` | out | 32 | Async |
| `rs2_data_o` | out | 32 | Async |

**Reads are asynchronous** — the guide says "simultaneous asynchronous
reading of the rs1 and rs2 operands." Combinational, no clock:

```verilog
assign rs1_data_o = regs[rs1_addr_i];
```

**Writes are synchronous**, on the clock edge, in WRITE_BACK.

### ⚠ x0 write protection — this module's job

x0 is hardwired to zero and cannot be modified (guide §3.1.4). **The control
unit asserts `reg_write_o` regardless of which register `rd` names** — it has
no idea whether the destination is x0. The guard lives here:

```verilog
if (reg_write_i && rd_addr_i != 5'd0)
    regs[rd_addr_i] <= write_data_i;
```

Nothing upstream catches a write to x0. Skip this and `addi x0, x0, 5`
silently corrupts the zero register, which then breaks every instruction
that reads x0 as a source of zero — a diffuse, hard-to-trace failure.

Reads of x0 must also return zero even before anything is written. Either
initialize `regs[0] = 0` at reset, or special-case the read.

**Tests:** write to x1-x31 and read back. Write to x0 and confirm it reads
zero. Read x0 before any write. Simultaneous read of two different registers.
Read-during-write of the same register (async read should see the *old*
value, since the write lands on the edge).

---

## `imem.v`

**Guide §4.2.** Instruction ROM at `` `IMEM_BASE `` (`0x00400000`). Read-only —
it has no write port at all.

| Port | Dir | Width | Notes |
|---|---|---|---|
| `clk_i` | in | 1 | |
| `addr_i` | in | 30 or 32 | Word address (bottom 2 bits already dropped by the decoder) |
| `oe_i` | in | 1 | Read enable |
| `data_o` | out | 32 | Instruction word |

**Loading a program:** use `$readmemh` from a hex file in `firmware/`:

```verilog
initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
```

Make the filename a parameter so testbenches can point at different programs.

**IMEM also holds constants**, not just instructions — guide §4.2 gives the
example of `lw` reading a data word out of IMEM at `0x00400100`. So IMEM must
respond to ordinary load addresses in its range, not only to fetches.

**Timing:** the guide doesn't explicitly state whether IMEM is registered-
output like DMEM. The FSM's FETCH state asserts `oe_o` and latches into IR in
the *same* cycle, which means **IMEM must read combinationally** (or at
least be valid within the cycle). Build it async-read:

```verilog
assign data_o = mem[index];
```

**Flag this if it turns out wrong at integration** — if IMEM must be
registered like DMEM, FETCH needs a second cycle and every instruction gets
one cycle longer. That would change the FSM, not just this module.

**Tests:** load a known hex file, read several addresses, confirm the right
words come back. Confirm reads outside the loaded range don't produce X's in
a way that breaks simulation.

---

## `dmem.v` — ⚠ TIMING-CRITICAL

**Guide §4.3.** 8 kB data SRAM at `` `DMEM_BASE `` (`0x10010000`).

| Port | Dir | Width | Notes |
|---|---|---|---|
| `clk_i` | in | 1 | |
| `addr_i` | in | 30 or 32 | Word address |
| `we_i` | in | 1 | From the decoder's `dmem_we_o` |
| `oe_i` | in | 1 | Read enable |
| `bw_i` | in | 4 | Byte write mask, one bit per byte |
| `data_i` | in | 32 | Write data |
| `data_o` | out | 32 | Read data — **registered** |

### The critical detail

**DMEM must be registered-output (synchronous read).** Address is captured on
a clock edge; data is valid on the *next* edge — not combinationally within
the same cycle.

```verilog
always @(posedge clk_i)
    if (oe_i) data_o <= mem[index];    // registered, NOT assign
```

**This is what the entire 2-cycle load design rests on.** The FSM has
separate `MEM_ACCESS_ADDR` and `MEM_ACCESS_DATA` states precisely because the
data isn't ready in the address cycle (handoff decision #2, guide §4.3:
"the operation will only be completed after a clock cycle").

If you build this combinational (`assign data_o = mem[index];`), simulation
of `top.v` will appear to work — the data arrives *early*, the FSM reads it a
cycle later, everything looks fine. Then in synthesis, the real SRAM behaves
synchronously and the timing is wrong. **A bug that passes simulation and
fails silicon is the worst kind.** Build it registered from the start.

### Byte-write support

Guide §4.3: the memory stores 4-byte words but must allow independent writes
to each byte, driven by `bw_i`:

```verilog
if (we_i) begin
    if (bw_i[0]) mem[index][ 7: 0] <= data_i[ 7: 0];
    if (bw_i[1]) mem[index][15: 8] <= data_i[15: 8];
    if (bw_i[2]) mem[index][23:16] <= data_i[23:16];
    if (bw_i[3]) mem[index][31:24] <= data_i[31:24];
end
```

`bw_i` is a **mask**, one bit per byte — not a binary-coded selector. The
control unit computes it (handoff decision #11); this module just applies it.

**Tests:** write a full word, read it back (two cycles — assert the data is
*not* valid in the first). Write single bytes with each `bw_i` pattern and
confirm the other three bytes are untouched. Use the guide's Table 12 layout
(`0xF1/F2/F3/F4` at `0x10010000`) so the LSU tests can build on the same
data. Specifically assert the registered-read behaviour: present an address,
check `data_o` is still the *previous* value that cycle, then check it
updates on the next edge.

---

## `address_decoder.v`

**Guide §4.4, Figure 3.** Routes core memory requests to IMEM or DMEM based
on address, and muxes the read data back.

| Port | Dir | Width | Notes |
|---|---|---|---|
| `address_i` | in | 32 | From core's `address_o` |
| `we_i` | in | 1 | From core's `we_o` |
| `oe_i` | in | 1 | From core's `oe_o` |
| `bw_i` | in | 4 | From core's `bw_o` |
| `core_data_i` | in | 32 | Store data heading out |
| `dmem_data_i` | in | 32 | Read data from DMEM |
| `imem_data_i` | in | 32 | Read data from IMEM |
| `address_o` | out | 30 | **Bottom 2 bits dropped** |
| `dmem_we_o` | out | 1 | DMEM only |
| `dmem_oe_o` | out | 1 | |
| `imem_oe_o` | out | 1 | |
| `bw_o` | out | 4 | DMEM only |
| `data_o` | out | 32 | Muxed read data back to core |

**Naming convention:** the core drives `we_o`; this module receives it as
`we_i`. Same wire, named from each end (handoff §3). Downstream it becomes
`dmem_we_o` — **IMEM never receives a write enable at all** (guide §4.4:
"EXCEPT IMEM memory, which cannot be written").

**Address decoding** from guide Table 13:

| Range | Device |
|---|---|
| `0x00400000` + 4 MB | IMEM |
| `0x10010000` + 8 kB | DMEM |

**Bottom 2 bits are dropped** before reaching devices — both memories are
word-addressed (guide §4.4: "ignoring the bottom two bits, alignment at 4
bytes"). The LSU and the CU's `bw_o` logic use those bits; the memories
never see them.

**Read-data mux:** select which device's `data_o` goes back to the core based
on the address. Note DMEM's output is registered, so the mux select must
still be correct in the cycle the data comes back — decoding from the address
combinationally is fine as long as the address is held stable, which the FSM
does.

**Unmapped addresses:** the guide doesn't say what happens. Return zero and
assert nothing; add a comment noting the guide is silent. Don't invent a bus
error mechanism.

**Tests:** an address in each range routes to the right device. `we_i` reaches
`dmem_we_o` but never IMEM. `bw_o` reaches DMEM only. Bottom 2 bits are
dropped from `address_o`. The read mux returns the right device's data.

---

## `lsu.v`

**Guide §3.3.** Sits between the core and memory. Handles alignment and
sign/zero extension on loads. The most logic of the five.

| Port | Dir | Width | Notes |
|---|---|---|---|
| `core_data_o` | in | 32 | Store data from the core (rs2) |
| `core_address_o` | in | 32 | Effective address (needs bits [1:0]) |
| `op_size_o` | in | 3 | From the CU |
| `mem_data_o` | in | 32 | Word read back from memory |
| `core_data_i` | out | 32 | Load result, extended — back to the core |
| `mem_data_i` | out | 32 | Store data, positioned — out to memory |

**Port naming is confusing here and worth care.** Guide Figure 2 names these
from the *core's* perspective, so `core_data_o` is an **input** to the LSU
(it's the core's output). Match Figure 2's names exactly — other modules are
built against them — but comment the direction clearly.

### Loads — extension and repositioning

`op_size_o` encoding (already decided, macros in `rvbl2_defines.vh`):

| Value | Macro | Size | Sign |
|---|---|---|---|
| `3'b000` | `` `OP_SIZE_BYTE_S `` | byte | signed (lb) |
| `3'b001` | `` `OP_SIZE_BYTE_U `` | byte | unsigned (lbu) |
| `3'b010` | `` `OP_SIZE_HALF_S `` | half | signed (lh) |
| `3'b011` | `` `OP_SIZE_HALF_U `` | half | unsigned (lhu) |
| `3'b100` | `` `OP_SIZE_WORD `` | word | — (lw) |

**Byte selection uses `address[1:0]`.** Memory returns a whole word; the LSU
picks the right part and moves it to the bottom of the register. Guide
§3.3.1's example: reading `0x10010002` from a word containing `0xF4F3F2F1`
must yield `0x000000F3` — byte 2 selected *and repositioned* to bits [7:0].

**Sign extension** replicates the selected field's top bit for lb/lh; zero
for lbu/lhu.

### ⚠ Golden test vectors — use these, don't invent

Guide Table 12 + §3.3.1 work out every load variant explicitly. DMEM holds
`0xF1, 0xF2, 0xF3, 0xF4` at bytes `0x10010000`–`0x10010003`, i.e. the word
`0xF4F3F2F1`:

| Instruction | Address | Expected result |
|---|---|---|
| `lbu` | `0x10010000` | `0x000000F1` |
| `lb` | `0x10010000` | `0xFFFFFFF1` |
| `lhu` | `0x10010000` | `0x0000F2F1` |
| `lh` | `0x10010000` | `0xFFFFF2F1` |
| `lw` | `0x10010000` | `0xF4F3F2F1` |
| `lbu` | `0x10010002` | `0x000000F3` |
| `lb` | `0x10010002` | `0xFFFFFFF3` ← **see below** |

### ⚠ RESOLVED — the `0x10010002` case

**Earlier revisions of this plan listed `lb @ 0x10010002 → 0x000000F3`,
copied uncritically from the guide's prose. That was wrong.** The correct
value for `lb` is `0xFFFFFFF3`; `0x000000F3` is the `lbu` result.

Guide §3.3.1's closing paragraph says: *"when reading the 0x10010002 address,
only the 0xF3 byte of the word read (in the case 0xF4F3F2F1) will be placed
in the register (which should then have the value 0x000000F3). The LSU should
then reposition the byte correctly."*

That paragraph is about **byte repositioning**, not sign extension — it never
names an instruction, and its point is that byte 2 must be moved down to bits
[7:0]. Three things settle it:

1. **The guide's own general rule contradicts the literal reading.** Same
   section: *"The lh and lb instructions fill the rest of the register bits
   with the signal bit (MSB) value of the read value."* `0xF3` is `11110011`
   — bit 7 is set — so `lb` must give `0xFFFFFFF3`. An explicit stated rule
   outranks an unlabeled example.
2. **Sign extension already had its own worked examples earlier** in the same
   section (`lb @ +0 → 0xFFFFFFF1`). This paragraph introduces a different
   concept.
3. **RISC-V settles it independently.** `lb` sign-extends, unconditionally.
   A core returning `0x000000F3` would fail compliance and the validation
   firmware. The guide cites the RISC-V spec as its authority (§1.2 [1]) and
   doesn't override it in prose.

Implemented per the general rule. `lbu` at the same address is unambiguous
(`0x000000F3`) and is the better regression test — it passes under either
reading.

### Stores — positioning

For stores, the LSU positions the data into the right byte lane of the word.
Guide §3.3.2's example: writing `0x12` to `0x10010002` produces
`0x00120000` on the data bus, with `bw_o = 4'b0100` selecting byte 2.

**The LSU does not generate `bw_o`** — the control unit does (decision #11).
The LSU only positions the data. If you find yourself writing byte-mask
logic here, stop: it already exists in `control_unit.v`.

No extension needed on stores — every byte of a word is independently
addressable, so there's nothing to extend.

**Tests:** all six load vectors above. Stores of byte/half/word at each
alignment, confirming correct positioning. Cross-check the store example
against guide §3.3.2.

---

## Testing

One testbench per module in `tb/memory/`, named `tb_<module>.v`.

```bash
iverilog -o sim/tb_regfile.vvp -I rtl rtl/memory/regfile.v tb/memory/tb_regfile.v
vvp sim/tb_regfile.vvp
```

Note `-I rtl`, not `-I rtl/pkg`. Every testbench needs
`$dumpfile("sim/<name>.vcd")` and `$dumpvars(0, ...)`.

**Definition of done, per module:** every behaviour in its section above
exercised by a directed test, simulation actually run, output reported
verbatim. "Should work" is not a status.

**For `dmem.v` specifically**, the testbench must prove the *timing*, not just
the values: assert that read data is NOT valid in the address cycle and IS
valid the next. A test that only checks values would pass on a combinational
implementation too, which defeats the point.

---

## Integration notes

Once these five plus `crc.v` exist, `top.v` (control unit slice 7) becomes
possible.

**Risks specific to these modules:**

- **DMEM registered-output.** Covered above. The single highest-consequence
  detail in this plan.
- **IMEM read timing.** Assumed combinational so FETCH stays one cycle. If
  that's wrong, the FSM changes.
- **x0 protection.** Only this module can do it.
- **`bw_o` ownership.** The CU drives it. Don't build it here too.
- **LSU port directions.** Figure 2's names are from the core's perspective,
  so `core_data_o` is an LSU input. Easy to wire backwards at `top.v`.
