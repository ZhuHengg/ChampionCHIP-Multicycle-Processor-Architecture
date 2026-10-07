# EV Charger Visualization Frontend — Design Spec

**Date:** 2026-10-07  
**Status:** Draft — awaiting approval  
**Location:** `ChampionCHIP-Stage3/viz/` (new React app in the repo root)

---

## 1. Purpose

A hackathon-grade interactive frontend that showcases our grid-aware EV
charging-station controller to competition judges. Two views:

1. **Station View** — one charger, one session: 3D charging station scene +
   step-through of each scenario (S1–S11), showing state transitions, meter
   data, CRC integrity, and session records.
2. **Grid View** — fleet scale: the CRC-hashed restart innovation visualised
   as a 3D city grid of charger nodes + animated rebound chart proving the
   7.94× peak-load reduction.

Runs on localhost (`npm run dev`). No deploy needed.

---

## 2. Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Framework | React 18 + TypeScript | Component model, state management for scenario playback |
| Build | Vite | Fast dev server, instant HMR |
| Styling | Tailwind CSS 3 | Utility-first, dark theme, responsive |
| 3D | React Three Fiber (R3F) + Drei | React-idiomatic Three.js; Drei has helpers (OrbitControls, Text, Environment, etc.) |
| Charts | Recharts | React-native charting for time-series and bar charts |
| Icons | Lucide React | Lightweight icon set |

### Package list (exact)

```
react react-dom
@react-three/fiber @react-three/drei three
recharts
tailwindcss postcss autoprefixer
lucide-react
typescript @types/react @types/react-dom @types/three
vite @vitejs/plugin-react
```

---

## 3. Project Structure

```
ChampionCHIP-Stage3/viz/
├── index.html
├── package.json
├── vite.config.ts
├── tailwind.config.ts
├── tsconfig.json
├── public/
│   └── favicon.svg
├── src/
│   ├── main.tsx
│   ├── App.tsx                    # top-level: navbar + tab router
│   ├── theme.ts                   # dark/light CSS tokens
│   │
│   ├── data/
│   │   ├── crc.ts                 # CRC-16 (port from golden.py)
│   │   ├── charger.ts             # Charger state machine (port from golden.py)
│   │   ├── meter.ts               # Meter frame generator (port from golden.py)
│   │   ├── scenarios.ts           # S1–S11 scenario definitions (port from scenarios.py)
│   │   ├── rebound.ts             # Fleet rebound simulation (port from rebound_sim.py)
│   │   └── constants.ts           # F_LOW, V_SAG, I_MAX, HOLD_BASE, CHARGER_ID, etc.
│   │
│   ├── components/
│   │   ├── Navbar.tsx             # Station | Grid tab switcher
│   │   │
│   │   ├── station/               # Tab 1: Station View
│   │   │   ├── StationView.tsx    # layout: 3D scene + sidebar panels
│   │   │   ├── ChargingScene.tsx  # R3F: 3D charging station
│   │   │   ├── CarModel.tsx       # R3F: 3D car geometry (procedural)
│   │   │   ├── CableFlow.tsx      # R3F: animated power flow particles
│   │   │   ├── StationBox.tsx     # R3F: charger cabinet with screen
│   │   │   ├── ScenarioPicker.tsx # scenario buttons S1–S11
│   │   │   ├── StateIndicator.tsx # FSM state diagram, current state glows
│   │   │   ├── PinLEDs.tsx        # P4-P7 indicator lights
│   │   │   ├── MeterChart.tsx     # Recharts: V, I, F time series
│   │   │   ├── EnergyGauge.tsx    # accumulated energy display
│   │   │   ├── CRCChainViz.tsx    # SVG: frame-to-frame CRC chain
│   │   │   ├── FrameInspector.tsx # click-to-corrupt meter bytes
│   │   │   └── SessionRecord.tsx  # session record with CRC check
│   │   │
│   │   └── grid/                  # Tab 2: Grid View
│   │       ├── GridView.tsx       # layout: 3D city + charts
│   │       ├── CityScene.tsx      # R3F: 3D city block with charger nodes
│   │       ├── ChargerNode.tsx    # R3F: one charger in the city (glows on/off)
│   │       ├── ReboundChart.tsx   # Recharts: animated sync vs staggered bars
│   │       ├── DelayHistogram.tsx # Recharts: 10k IDs × 8 buckets
│   │       ├── GridTimeline.tsx   # animated timeline: freq drops → hold → stagger
│   │       └── DisputePanel.tsx   # "dispute" button: corrupt a frame, show chain break
│   │
│   └── styles/
│       └── globals.css            # Tailwind directives + custom tokens
```

---

## 4. Data Layer — Porting from Python

All logic ports come from our existing tested Python golden model. No new
logic — only translation to TypeScript.

### 4.1 `crc.ts`

Port of `golden.crc16()`. Identical algorithm: poly 0x1021, MSB-first, no
reflection, xorout 0. Must pass the same test vectors as `test_golden.py`.

### 4.2 `charger.ts`

Port of `golden.Charger` class. Same state machine:
- States: IDLE, CONNECTED, CHARGING, GRID_HOLD, FAULT
- Inputs: `set_inputs(value)` for GPIO, `rx_frame(frame)` for meter bytes
- Outputs: `out` (GPIO output byte), `energy`, `frames`, `flags`, `tx` (session record)
- Grid hold: `restart_delay(trigger_crc, charger_id)` = HOLD_BASE + (CRC-16(id, seed=trigger_crc) & 7)

### 4.3 `meter.ts`

Port of `golden.Meter`. Chain CRC seed advances on every frame produced.

### 4.4 `scenarios.ts`

Port of `scenarios.py._app()`: S1–S11 + S1X. Each scenario is a sequence of
operations: `d(value)`, `i(value)`, `frame(bytes)`, `o()`, `record()`. The
frontend steps through these operations to drive the visualization.

Export format:
```ts
interface ScenarioStep {
  type: 'gpio_in' | 'gpio_out' | 'frame' | 'record';
  value?: number;
  frame?: Uint8Array;
  expected_out?: number;
  state_before: ChargerState;
  state_after: ChargerState;
  energy_after: number;
  label: string;         // human-readable description
}

interface Scenario {
  id: string;            // "S1", "S2", etc.
  title: string;
  steps: ScenarioStep[];
}
```

### 4.5 `rebound.ts`

Port of `rebound_sim.py.rebound()`. 1000 chargers × 7 kW, one trigger CRC.
Returns two arrays: synchronised load per frame, staggered load per frame.

---

## 5. Station View — Detailed Design

### 5.1 3D Charging Station Scene (`ChargingScene.tsx`)

**Procedural geometry** (no external models):

| Object | Geometry | Material |
|---|---|---|
| Ground plane | Plane 20×20 | Dark asphalt texture (generated noise) |
| Charger cabinet | Rounded Box 0.6×1.4×0.4 | Dark metallic, emissive screen panel |
| Screen on cabinet | Plane 0.4×0.3 inset | Emissive, shows current state text |
| Car | Group of boxes (body, roof, wheels) | Colored metal, changes opacity on connect/disconnect |
| Cable | CatmullRomCurve3 tube | Green when charging, amber when holding, red on fault, pulsing |
| Power particles | Points along cable path | Green emissive dots flowing along curve when charging |
| Ground LEDs | 4 small spheres near cabinet base | Map to P4-P7, color-coded like reference team's lamps |
| Grid pylon (background) | Cylinder + cross beams | Subtle, far side of scene |
| Environment | Drei Environment preset="city" | Ambient lighting, reflections |

**Camera:** OrbitControls, default angle looking at charger+car from 45°
above. Auto-rotates slowly when idle, stops on interaction.

**Animations tied to state:**
- IDLE: car absent or far, cable retracted, all dark
- CONNECTED: car slides in, cable extends (tube animation), lock LED on
- CHARGING: power particles flow along cable, energy counter ticks up, contactor LED on
- GRID_HOLD: particles stop, cable turns amber, grid-hold LED pulses, grid pylon flickers
- FAULT: cable turns red, fault LED pulses fast, car stays

### 5.2 Scenario Picker (`ScenarioPicker.tsx`)

Horizontal button bar (like reference team's vehicle-kind buttons):

```
[S1: Normal] [S2: Grid Event] [S3: Bad Frame] [S4: Link Lost] [S5: E-Stop] ...
```

Each button has a colored dot indicating scenario category:
- Green: normal operation (S1, S1X, S6)
- Amber: grid events (S2)
- Red: fault scenarios (S4, S5, S7, S8, S9)
- Purple: integrity tests (S3, S10, S11)

### 5.3 Playback Controls

Below the 3D scene:
```
[Play/Pause] [Step] [Restart]  Speed: [0.5x] [1x] [2x]   Step 3/12
```

Steps through scenario operations. Each step:
1. Updates the Charger model
2. Triggers 3D scene animation
3. Updates all sidebar panels

### 5.4 State Indicator (`StateIndicator.tsx`)

SVG state diagram showing all 5 states as nodes with transition arrows.
Current state node glows with its color. Transition arrows animate when
traversed. Layout:

```
         ┌──────────┐
    ┌───►│   IDLE   │◄───────────────┐
    │    └────┬─────┘                │
    │         │ car plugs in         │ unplug
    │    ┌────▼──────┐               │
    │    │ CONNECTED  │──────────────┘
    │    └────┬──────┘
    │         │ CP = C
    │    ┌────▼──────┐    grid dip    ┌───────────┐
    │    │ CHARGING   │──────────────►│ GRID_HOLD │
    │    └────┬──────┘◄──────────────┘
    │         │ fault                  delay met
    │    ┌────▼──────┐
    └────│   FAULT   │
         └──────────┘
```

### 5.5 Meter Chart (`MeterChart.tsx`)

Recharts `ComposedChart` with three Y-axes:
- Line: Voltage (V) — blue, with V_SAG threshold dashed line
- Line: Frequency (Hz) — green, with F_LOW threshold dashed line
- Bar: Current (A) — amber, with I_MAX threshold line

X-axis = frame number. Data points appear as scenario steps advance.
When a value crosses a threshold, the line/bar turns red.

### 5.6 CRC Chain Visualizer (`CRCChainViz.tsx`)

Horizontal SVG chain:

```
[0xFFFF] ──seed──► [Frame 1: CRC=0xCC77] ──seed──► [Frame 2: CRC=0x0DE6] ──► ...
    ✓                   ✓                               ✓
```

Each node is a rounded rect with the CRC value. Arrow shows seed flow.
Check mark below each = CRC verified. Click a frame node to flip byte 0
→ CRC changes → all downstream checks fail → nodes turn red.

### 5.7 Session Record (`SessionRecord.tsx`)

At end of scenario, displays the 8-byte record:

```
┌─────────────────────────────────────────────────┐
│  Energy: 736,000    Status: 0x00    Frames: 2   │
│  Bytes: 00 3B 0B 00 00 02 5C D0                 │
│  CRC-16: 0xD05C  ✓ verified                     │
└─────────────────────────────────────────────────┘
```

---

## 6. Grid View — Detailed Design

### 6.1 3D City Scene (`CityScene.tsx`)

Bird's-eye view of a city block with 20–50 charger nodes (representing the
1000-charger fleet abstractly). Procedural:

| Object | Geometry | Purpose |
|---|---|---|
| Ground | Plane with grid lines | City block |
| Buildings | Random-height boxes | Context |
| Charger nodes | Glowing spheres on the ground | Each represents ~20–50 chargers |
| Power lines | Lines connecting nodes to a central substation | Grid connection |
| Substation | Larger box, center | Grid source |

**Animation sequence (auto-plays on tab switch):**

1. All nodes green (charging)
2. Grid frequency dips — substation flashes red, power lines pulse red
3. All nodes turn amber simultaneously (GRID_HOLD)
4. Synchronized restart: ALL nodes flash green at once (bad — spike!)
5. Reset, replay with CRC-hashed: nodes turn green one-by-one over 8 frames
   (good — smooth ramp)

Camera slowly orbits overhead. Timeline scrubber at the bottom.

### 6.2 Rebound Chart (`ReboundChart.tsx`)

The centrepiece evidence chart. Recharts `BarChart`, animated:

```
Load restored per frame (MW)
│
│  ████ 7.0                        synchronized (all together)
│  ████
│  ████                            CRC-hashed (spread)
│  ████                     ▓▓▓▓
│  ████              ▓▓▓▓   ▓▓▓▓   ▓▓▓▓
│  ████       ▓▓▓▓   ▓▓▓▓   ▓▓▓▓   ▓▓▓▓   ▓▓▓▓
│  ████       ▓▓▓▓   ▓▓▓▓   ▓▓▓▓   ▓▓▓▓   ▓▓▓▓   ▓▓▓▓   ▓▓▓▓
└──────────────────────────────────────────────────────────────────
   Frame 2    Frame 3  Frame 4  Frame 5  Frame 6  Frame 7  Frame 8  Frame 9

Peak: 7.000 MW → 0.881 MW  (7.94× reduction)
```

Animated: bars grow from zero as the timeline advances. Big stat tiles above:

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  1,000       │  │  7.94×       │  │  0.881 MW    │
│  chargers    │  │  reduction   │  │  peak load   │
└──────────────┘  └──────────────┘  └──────────────┘
```

### 6.3 Delay Histogram (`DelayHistogram.tsx`)

Bar chart: 10,000 charger IDs × CRC hash → 8 delay buckets (2–9 frames).
Shows even distribution (~1,250 per bucket). Proves the hash doesn't cluster.

### 6.4 Dispute Panel (`DisputePanel.tsx`)

"What if someone disputes a charge?" button. Opens a panel:
1. Shows a normal 3-frame session's CRC chain
2. "Corrupt frame 2" button
3. Chain breaks visually, energy billing stops at frame 1
4. Session record shows reduced energy + CRC-lost flag
5. Text: "The chip stopped billing the instant the meter link broke. The
   session record proves it."

---

## 7. Theming

Dark theme primary (matching the reference team's dark-panel aesthetic, but
with our EV/energy colour palette):

| Token | Light | Dark |
|---|---|---|
| `--bg` | `#F4F6F5` | `#0A0F0D` |
| `--panel` | `#FFFFFF` | `#141A17` |
| `--border` | `#D5DDD8` | `#1F2925` |
| `--text` | `#14201A` | `#E6ECE8` |
| `--muted` | `#5E6B64` | `#8E9C95` |
| `--charging` | `#22C55E` | `#39C47A` (green — power flowing) |
| `--grid-hold` | `#F59E0B` | `#F2B134` (amber — paused) |
| `--fault` | `#EF4444` | `#FF5A5F` (red — fault) |
| `--connected` | `#3B82F6` | `#6EA8FF` (blue — connected) |
| `--idle` | `#6B7280` | `#7C8A83` (grey — idle) |
| `--accent` | `#10B981` | `#34D399` (teal — primary accent) |

Font: Inter (body), JetBrains Mono (data/hex values).

---

## 8. Build Tasks — Phased Agent Plan

### Phase 1: Scaffold + Data Layer (no UI yet)

**Task 1.1:** Scaffold React + Vite + Tailwind + R3F project  
**Task 1.2:** Port `crc.ts`, `constants.ts` from golden.py  
**Task 1.3:** Port `charger.ts`, `meter.ts` from golden.py  
**Task 1.4:** Port `scenarios.ts` — all S1–S11 with step-by-step events  
**Task 1.5:** Port `rebound.ts` from rebound_sim.py  
**Task 1.6:** Unit tests for data layer (CRC matches Python, charger state
transitions match golden model for each scenario)

### Phase 2: Station View — 3D Scene

**Task 2.1:** `ChargingScene.tsx` — ground, charger cabinet, environment  
**Task 2.2:** `CarModel.tsx` — procedural car, connect/disconnect animation  
**Task 2.3:** `CableFlow.tsx` — cable tube + power flow particles  
**Task 2.4:** `StationBox.tsx` — cabinet screen showing state text  
**Task 2.5:** Integrate scene with charger state (state changes drive animations)

### Phase 3: Station View — UI Panels

**Task 3.1:** `Navbar.tsx` + `App.tsx` tab routing  
**Task 3.2:** `ScenarioPicker.tsx` — scenario buttons  
**Task 3.3:** `StateIndicator.tsx` — SVG state diagram with glow  
**Task 3.4:** `PinLEDs.tsx` — P4–P7 indicator lights  
**Task 3.5:** `MeterChart.tsx` — V/I/F time series with thresholds  
**Task 3.6:** `EnergyGauge.tsx` — accumulated energy display  
**Task 3.7:** Playback controls (play/pause/step/restart/speed)

### Phase 4: Station View — Evidence Features

**Task 4.1:** `CRCChainViz.tsx` — chain diagram with click-to-corrupt  
**Task 4.2:** `FrameInspector.tsx` — byte-level frame view  
**Task 4.3:** `SessionRecord.tsx` — decoded record with CRC check

### Phase 5: Grid View — 3D + Charts

**Task 5.1:** `CityScene.tsx` — procedural city with charger nodes  
**Task 5.2:** `ChargerNode.tsx` — node glow states + animation sequence  
**Task 5.3:** `GridTimeline.tsx` — timeline scrubber for grid event  
**Task 5.4:** `ReboundChart.tsx` — animated bar chart with stat tiles  
**Task 5.5:** `DelayHistogram.tsx` — hash distribution chart

### Phase 6: Grid View — Dispute + Polish

**Task 6.1:** `DisputePanel.tsx` — interactive CRC chain corruption demo  
**Task 6.2:** Dark/light theme toggle  
**Task 6.3:** Responsive layout polish  
**Task 6.4:** Loading states, transitions between tabs  
**Task 6.5:** Final integration test — every scenario plays through correctly

---

## 9. Agent Task Prompts

Each phase becomes one Sonnet agent prompt. Agent receives:
- This spec (relevant section)
- The Python source files to port from
- The project structure context

See `docs/superpowers/plans/2026-10-07-ev-charger-viz-plan.md` for
the exact agent prompts.

---

## 10. Open Questions

1. **3D detail level:** Should the car be a realistic-ish low-poly model
   (more work) or stylised boxes (faster, still reads well)? Recommend:
   stylised boxes with good materials — matches hackathon aesthetic.

2. **Number of charger nodes in city scene:** 20–50 visible nodes
   representing the 1000 abstractly, or try to render 1000 instanced
   meshes? Recommend: 50 nodes with labels like "×20 chargers each."

3. **Blind test feature:** The reference team's blind test is their killer
   feature. Should we port an equivalent (generate random scenario, run on
   chip, paste results, compare)? Not in initial scope — can add in Phase 7
   if time allows.
