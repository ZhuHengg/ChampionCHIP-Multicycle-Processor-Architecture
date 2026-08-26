# OpenLane synthesis — how to run it

Target: Sky130 (`sky130A` / `sky130_fd_sc_hd`) via **OpenLane 1**.

OpenLane 1, not 2 — the guide's section 9 asks for the gate-level netlist
at `results/final/verilog/gl`, which is OpenLane 1's directory layout.

Config lives at [`config.json`](../config.json) in the repo root, which is
where OpenLane 1 expects a design's config to sit.

---

## 1. Read this before your first run

Two things will silently produce a meaningless result rather than an error.

### 1a. IMEM must have a firmware file, or the core vanishes

`imem.v` initialises its array with `$readmemh` inside an `initial` block,
guarded by `INIT_FILE != ""`. If that guard is false, the array is never
written and never initialised — so yosys optimises the whole thing away,
`data_o` goes constant, and the entire datapath constant-folds behind it.

**The flow still completes.** You get a GDSII of almost nothing and a
suspiciously small area number.

This is already handled: `top.v`'s `IMEM_INIT_FILE` defaults to
`firmware/validation.hex`. Every testbench overrides the parameter
explicitly, so the default only ever matters to synthesis.

**Always sanity-check the cell count after synthesis** (step 5 below). That
is the check that catches this.

### 1b. The memories are flip-flops, not SRAM macros

`imem` and `dmem` are behavioural arrays with no PDK macro behind them, so
they map to standard cells:

| Config | imem | dmem | Storage bits | dmem flops |
|---|---|---|---|---|
| Defaults | 1024 words | 2048 words | 98,304 | 65,536 (~1.3 mm² alone) |
| Area run | 512 words | 256 words | 24,576 | 8,192 |

At the defaults, storage dominates your area number and place-and-route can
run for many hours or fail outright.

**The 512/256 configuration is verified** — it runs the full validation
firmware to `ALL TESTS PASSED` in the same 980 cycles. To use it, change the
two defaults in `top.v`:

```verilog
parameter IMEM_DEPTH_WORDS = 512,   // was 1024
parameter DMEM_DEPTH_WORDS = 256,   // was 2048
```

then re-run the testbenches (step 6) to confirm, and **state the sizing in
the report** — it is a deliberate area tradeoff, not the guide's address-map
sizes.

Floors you cannot go below:
- **imem ≥ 512.** `firmware/validation.hex` is 413 words; less truncates the
  program.
- **dmem**: any depth works — `DMEM_BASE`'s word address has its low bits
  clear, so the base always maps to index 0. Depth only limits how far above
  the base the firmware may reach. The firmware's highest use is
  `DMEM_BASE + 0x100` (word 64), so 256 is comfortable.

If you want real SRAM instead, that means OpenRAM macros plus macro
placement, power straps, and blockages — considerably more work. Get the
flow working at 512/256 first, then decide with real numbers in hand.

---

## 2. Environment (Windows)

Docker Desktop's own `docker-desktop` WSL distro is **not** a usable dev
environment. You need a real Ubuntu distro; OpenLane 1's Makefile flow does
not work properly from Git Bash on Windows.

```powershell
wsl --install -d Ubuntu
```

Reboot, set a username, then in Docker Desktop enable
**Settings → Resources → WSL Integration → Ubuntu**, and confirm the daemon
is running (`docker info` should succeed inside Ubuntu).

---

## 3. Install OpenLane

**Clone into WSL's own filesystem, not `/mnt/c`.** WSL2's `/mnt/c` I/O is
slow enough that place-and-route will crawl.

```bash
cd ~
git clone https://github.com/ZhuHengg/ChampionCHIP-Multicycle-Processor-Architecture.git rvbl2
git clone https://github.com/The-OpenROAD-Project/OpenLane.git

cd ~/OpenLane
make          # pulls the docker image and the sky130A PDK via volare
make test     # ~10 min sanity run on a tiny design
```

**Do not skip `make test`.** If it fails, the problem is your Docker or PDK
setup, not your RTL — and you want to know that before a multi-hour run.

---

## 4. Run the flow

```bash
cd ~/OpenLane
cp -r ~/rvbl2 designs/rvbl2
./flow.tcl -design rvbl2 -tag run1
```

Iterate on synthesis alone before committing to full place-and-route:

```bash
./flow.tcl -design rvbl2 -tag synth_only -to synthesis
```

That gives area and cell count in minutes instead of hours. Use it to check
the memory sizing before running the full flow.

---

## 5. Verify the result is real

Before trusting any number, confirm the design did not collapse (§1a):

```bash
cd designs/rvbl2/runs/run1
cat reports/synthesis/1-synthesis.stat.rpt   # cell counts by type
cat reports/metrics.csv                      # area, density, timing
```

Expect **tens of thousands of cells**, dominated by DFFs from imem/dmem. A
few hundred cells means the memories were optimised away — go back to §1a.

Also check post-synthesis STA slack. If it is badly negative, adjust
`CLOCK_PERIOD` in `config.json` and re-run synthesis only.

---

## 6. Re-run the simulations after any RTL change

Changing memory depths is an RTL change. Confirm the design still works:

```bash
cd ~/rvbl2
# system-level (the one that matters most)
iverilog -o sim/tb_top_system.vvp -I rtl \
  rtl/top.v rtl/control_unit.v \
  rtl/memory/imem.v rtl/memory/dmem.v rtl/memory/address_decoder.v \
  rtl/memory/regfile.v rtl/memory/lsu.v \
  rtl/datapath/alu.v rtl/datapath/imm_extend.v rtl/datapath/branch_comparator.v \
  rtl/datapath/mult.v rtl/datapath/crc.v \
  tb/system/tb_top_system.v
vvp sim/tb_top_system.vvp
```

The guide's Note 1 requires the submitted RTL, testbenches, and physical
results to correspond to the same implementation. Synthesising a
configuration you never simulated breaks that.

---

## 7. Deliverables

Guide section 9 wants four things from the flow. All paths are relative to
`designs/rvbl2/runs/run1/`:

| Deliverable | Path |
|---|---|
| GDSII file | `results/final/gds/top.gds` |
| GL netlist (`.v`) | `results/final/verilog/gl/top.v` |
| Total area + density | `reports/metrics.csv`, `reports/signoff/` |
| GDSII image for the report | render `top.gds` in KLayout |

`config.json` is the fifth — already in the repo root, and it must be the
same file the run actually used.

---

## 8. Config values that are guesses, not requirements

The guide never states a target frequency or a die size, so these are ours
to choose. Tune them from run 1's reports rather than guessing twice.

| Key | Value | Why |
|---|---|---|
| `CLOCK_PERIOD` | 40 ns (25 MHz) | Starting point. The 32×32 combinational multiplier in `mult.v` is the expected critical path. |
| `FP_CORE_UTIL` | 35 | Conservative. Raise if area looks wasteful. |
| `PL_TARGET_DENSITY` | 0.45 | Lower it if the flow fails on congestion. |
| `SYNTH_STRATEGY` | `AREA 0` | Area is what the guide asks you to report. |

---

## 9. Known synthesis concerns (CLAUDE.md step 9)

Flagged during RTL development, to revisit with real numbers:

- **`mult.v`'s 32×32 combinational multiplier** is the design's largest
  block and the expected critical path. The fallback (iterative shift-add)
  changes the FSM, not just `mult.v` — do not pre-optimise before measuring.
- **`imem`/`dmem` as flip-flops** — see §1b. The dominant area term.
- **`address_decoder.v`** does two 32-bit range comparisons combinationally
  in the address path, every cycle. Cheap, but it is on a hot path.
