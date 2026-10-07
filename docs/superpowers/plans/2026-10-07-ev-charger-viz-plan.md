# EV Charger Visualization — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-10-07-ev-charger-viz-design.md`  
**Date:** 2026-10-07  
**Execution:** 6 phases, each as one Sonnet agent task. Run sequentially.

---

## Phase 1: Scaffold + Data Layer

### Agent prompt

```
You are building a React + TypeScript visualization frontend for a RISC-V
EV charging station controller. This is Phase 1: scaffold the project and
port the Python data layer to TypeScript.

## Location

Create the project at: ChampionCHIP-Stage3/viz/

## Step 1: Scaffold

Run these commands:
1. cd to the repo root
2. mkdir -p ChampionCHIP-Stage3/viz && cd ChampionCHIP-Stage3/viz
3. npm create vite@latest . -- --template react-ts
4. npm install
5. npm install @react-three/fiber @react-three/drei three recharts lucide-react
6. npm install -D tailwindcss @tailwindcss/vite @types/three
7. Configure Tailwind: in vite.config.ts add the tailwindcss plugin import, 
   in src/styles/globals.css add @import "tailwindcss"
8. Verify `npm run dev` starts without errors

## Step 2: Port data layer

Read these Python source files and port them to TypeScript:
- chip-inventor/testbench/app/golden.py → src/data/crc.ts, constants.ts, charger.ts, meter.ts
- chip-inventor/testbench/app/scenarios.py → src/data/scenarios.ts
- chip-inventor/testbench/app/evidence/rebound_sim.py → src/data/rebound.ts

### crc.ts
Port the `crc16()` function exactly. Same algorithm: poly 0x1021, MSB-first,
no reflection. Input: Uint8Array + optional seed (default 0xFFFF).
Returns number (16-bit).

### constants.ts
```ts
export const F_LOW = 4950;       // 49.50 Hz threshold
export const V_SAG = 2070;       // 207.0 V threshold
export const I_MAX = 320;        // 32.0 A over-current
export const HOLD_BASE = 2;      // min healthy frames before restart
export const CHARGER_ID = 0x4D590001;

export enum ChargerState {
  IDLE = 0,
  CONNECTED = 1,
  CHARGING = 2,
  GRID_HOLD = 3,
  FAULT = 4,
}

export const STATE_NAMES = ['IDLE', 'CONNECTED', 'CHARGING', 'GRID_HOLD', 'FAULT'];

export const STATE_COLORS = {
  [ChargerState.IDLE]: '#7C8A83',
  [ChargerState.CONNECTED]: '#6EA8FF',
  [ChargerState.CHARGING]: '#39C47A',
  [ChargerState.GRID_HOLD]: '#F2B134',
  [ChargerState.FAULT]: '#FF5A5F',
};

// GPIO output per state
export const STATE_OUT: Record<ChargerState, number> = {
  [ChargerState.IDLE]: 0x00,
  [ChargerState.CONNECTED]: 0x20,
  [ChargerState.CHARGING]: 0x30,
  [ChargerState.GRID_HOLD]: 0x60,
  [ChargerState.FAULT]: 0x80,
};

// Status flags
export const F_ESTOP = 0x08;
export const F_CP_ERROR = 0x10;
export const F_OVERCURRENT = 0x20;
export const F_CRC_LOST = 0x40;
export const F_GRID_HOLD = 0x80;
```

### charger.ts
Port the `Charger` class from golden.py. Must have:
- `state: ChargerState`
- `energy: number`, `frames: number`, `flags: number`
- `bad: number` (consecutive bad frames), `hold: number`, `delay: number`
- `seed: number` (CRC chain, starts 0xFFFF)
- `tx: number[]` (session record bytes)
- `setInputs(value: number): void` — loops _stepPins until stable
- `rxFrame(frame: Uint8Array): void` — 8 bytes, calls _onFrame
- `get out(): number` — STATE_OUT[this.state]
- `restartDelay(triggerCrc: number, chargerId?: number): number`
  = HOLD_BASE + (crc16(le32(chargerId), triggerCrc) & 7)

The state machine logic must match golden.py exactly. Every if/else,
every threshold check, every flag. Read golden.py carefully.

### meter.ts
Port the `Meter` class. Chain CRC seed advances on every frame produced.
`frame(v, i, f)` returns Uint8Array(8): [V_lo, V_hi, I_lo, I_hi, F_lo, F_hi, CRC_lo, CRC_hi].

### scenarios.ts
Port all 12 scenarios (S1, S1X, S2–S11). Each scenario is an array of steps.

```ts
export interface ScenarioStep {
  type: 'gpio_in' | 'gpio_out' | 'frame' | 'record' | 'datadir';
  value?: number;           // for gpio_in, gpio_out, datadir
  frame?: Uint8Array;       // for frame
  record?: Uint8Array;      // for record (8 bytes)
  expectedOut?: number;     // for gpio_out
  stateBefore: ChargerState;
  stateAfter: ChargerState;
  energyAfter: number;
  framesAfter: number;
  flagsAfter: number;
  seedAfter: number;
  label: string;
}

export interface Scenario {
  id: string;
  title: string;
  category: 'normal' | 'grid' | 'fault' | 'integrity';
  steps: ScenarioStep[];
}
```

Build each scenario by running the Charger + Meter models step by step
(like scenarios.py does), capturing state snapshots at each step.

Categories:
- normal: S1, S1X, S6
- grid: S2
- fault: S4, S5, S7, S8, S9
- integrity: S3, S10, S11

### rebound.ts
Port `rebound()` from rebound_sim.py:
```ts
export function rebound(
  nChargers?: number,  // default 1000
  kw?: number,         // default 7.0
  triggerCrc?: number,  // default 0x1D0F
  baseId?: number       // default 0x4D590000
): { sync: number[]; staggered: number[] }
```

Also export:
```ts
export function delayHistogram(
  n?: number,           // default 10000
  triggerCrc?: number
): number[]             // 8 buckets, count per delay value (HOLD_BASE+0 .. HOLD_BASE+7)
```

## Step 3: Minimal App.tsx

Create a minimal App.tsx that imports the data layer and renders:
- The app title "ChampionCHIP EV Charger Controller"
- A list of scenario names
- The rebound peak values (sync vs staggered)
- Verify the data layer works by displaying it

## Step 4: Verify

Run `npm run dev` and confirm the page loads with correct data.
Run `npx tsc --noEmit` to confirm no type errors.
```

---

## Phase 2: Station View — 3D Scene

### Agent prompt

```
You are continuing the EV charger visualization frontend.
Project is at ChampionCHIP-Stage3/viz/ (React + Vite + Tailwind + R3F).
Phase 1 completed: scaffold and data layer exist.

This is Phase 2: build the 3D charging station scene.

Read the existing code in src/ first to understand the data layer.

## Create these files:

### src/components/station/ChargingScene.tsx

React Three Fiber canvas scene containing:

1. **Ground plane**: 20x20 Plane, dark asphalt color (#1a1a1a), rotated
   flat. Subtle grid lines via a custom shader or Drei Grid helper.

2. **Charger cabinet** (StationBox): Rounded box 0.6×1.4×0.4.
   MeshStandardMaterial, dark metallic (roughness 0.3, metalness 0.7).
   An inset plane on the front face acts as a "screen" — its emissive
   color and text change with charger state.

3. **Car** (CarModel): Procedural low-poly car built from boxes:
   - Body: Box 2.0×0.6×0.9, rounded edges (use Drei RoundedBox)
   - Roof: Box 1.0×0.4×0.8, positioned on top
   - Wheels: 4 Cylinder(0.15, 0.15, 0.1), dark grey
   - Color: light silver (#C0C8D0)
   - Position: slides in from x=-5 to x=-1.2 when state goes to CONNECTED
   - Slides out to x=-5 when state goes to IDLE

4. **Cable** (CableFlow): CatmullRomCurve3 tube from charger front face
   to car's charging port (left side). Use Drei Tube or manual TubeGeometry.
   - Cable appears when CONNECTED
   - Color changes: blue=CONNECTED, green=CHARGING, amber=GRID_HOLD, red=FAULT
   - When CHARGING: particle system (Drei Sparkles or custom Points) flows
     along the cable path. Green glowing dots moving from charger to car.

5. **Ground LEDs**: 4 small sphere meshes (radius 0.08) near the charger
   base, labeled P4-P7. Each has emissive material. LED states:
   - P4 (CONTACTOR): green when charging
   - P5 (CABLE_LOCK): blue when connected/charging/hold
   - P6 (GRID_HOLD): amber when in grid hold
   - P7 (FAULT): red when faulted

6. **Lighting**: Drei Environment preset="city" or "warehouse".
   One directional light for shadows. Ambient light low (0.3).

7. **Camera**: Drei OrbitControls. Default position: [5, 4, 5] looking
   at origin. enablePan=false, maxPolarAngle=Math.PI/2.2 (don't go below ground).
   Auto-rotate when no interaction (autoRotate, autoRotateSpeed=0.5).

### Props interface:
```tsx
interface ChargingSceneProps {
  state: ChargerState;
  charging: boolean;      // power particles flowing
  cableConnected: boolean;
  pinOutputs: number;     // P7-P4 as bits 7-4
  stateLabel: string;     // text on the charger screen
}
```

### src/components/station/StationView.tsx

Layout component:
```
┌─────────────────────────────────────────────────────┐
│                  3D Scene (60% height)               │
│                                                      │
├──────────────────────┬──────────────────────────────┤
│  Scenario Picker     │  State Indicator (placeholder)│
│  [S1] [S2] [S3] ...  │                              │
├──────────────────────┤  Pin LEDs (placeholder)       │
│  Playback Controls   │                              │
│  [▶] [⏭] [⏮] 1x    │  Energy: 0 Wh (placeholder)  │
└──────────────────────┴──────────────────────────────┘
```

Use Tailwind for layout. The 3D scene goes in a div with h-[60vh].
Below it, a grid with controls on the left and info panels on the right.

For now, wire up ScenarioPicker and playback to drive the ChargingScene
props via React state. Use the scenarios data to step through.

### Playback logic in StationView:

```tsx
const [scenarioId, setScenarioId] = useState('S1');
const [stepIndex, setStepIndex] = useState(0);
const [playing, setPlaying] = useState(false);

// Current step determines scene state
const scenario = SCENARIOS.find(s => s.id === scenarioId);
const step = scenario.steps[stepIndex];
```

When playing, advance stepIndex on a timer (speed-dependent interval).
Each step's stateAfter drives the scene.

## Verify

`npm run dev` shows the 3D scene with a charger, car slides in/out based
on state. Clicking scenario buttons changes the scene. Power particles
flow during CHARGING state.
```

---

## Phase 3: Station View — UI Panels

### Agent prompt

```
You are continuing the EV charger visualization frontend.
Project at ChampionCHIP-Stage3/viz/. Phase 1 (data) and Phase 2 (3D scene) done.

This is Phase 3: build the Station View UI panels alongside the 3D scene.

Read existing code first: src/data/*, src/components/station/StationView.tsx,
src/components/station/ChargingScene.tsx.

## Create these files:

### src/components/Navbar.tsx

Top navigation bar. Two tabs: "Station" and "Grid". Dark background
(bg-gray-900). Active tab has a green (#39C47A) bottom border.
Logo text: "ChampionCHIP" in bold + "RVBL-2 EV Controller" in muted text.

### Update src/App.tsx

Use Navbar to switch between StationView and a placeholder GridView.
Simple state toggle, no router needed.

### src/components/station/StateIndicator.tsx

SVG state diagram showing all 5 states as rounded rectangles connected
by arrows. Current state has:
- Fill color matching STATE_COLORS
- Glow effect (SVG filter: drop-shadow with state color)
- Slightly larger scale (transform)

Other states are outlined, muted color.

Transition arrows: thin lines with arrowheads. The arrow that was just
traversed (stateBefore → stateAfter) pulses briefly.

Layout the 5 states in a cross pattern:
```
              IDLE
               |
           CONNECTED
            /     \
       CHARGING   (back to IDLE)
        /     \
   GRID_HOLD  FAULT
```

Size: fits in a ~300×250px container.

### src/components/station/PinLEDs.tsx

Four circular LED indicators in a horizontal row:

```
  ● P4 Contactor    ● P5 Cable Lock    ● P6 Grid Hold    ● P7 Fault
```

Each LED:
- Off: dark grey circle with subtle border
- On: colored circle with box-shadow glow
  - P4: green
  - P5: blue
  - P6: amber
  - P7: red

Derive on/off from pinOutputs prop (bits 4-7 of the GPIO output byte).

### src/components/station/MeterChart.tsx

Recharts ComposedChart showing meter data over the scenario's frames.

Props: `frames: Array<{v: number, i: number, f: number, valid: boolean}>`

- Line for Voltage (scaled to V, divide by 10): blue, left Y-axis
- Line for Frequency (scaled to Hz, divide by 100): green, right Y-axis
- Bar for Current (scaled to A, divide by 10): amber
- Reference lines: V_SAG (207.0V dashed red), F_LOW (49.50Hz dashed red),
  I_MAX (32.0A dashed red)
- Invalid frames: data point shown with red X marker
- Dark theme: bg transparent, grid lines subtle, axis labels light grey

Chart height: ~200px. Responsive width.

### src/components/station/EnergyGauge.tsx

Simple display showing accumulated energy:

```
┌────────────────────────┐
│  ⚡ Energy Metered      │
│  736,000               │
│  Wh (V×I accumulated)  │
│  ████████░░░  2 frames │
└────────────────────────┘
```

A progress-bar-style fill showing frames counted. The number animates
up when energy increases (use CSS transition or requestAnimationFrame).

### src/components/station/ScenarioPicker.tsx

Update if it exists, or create. Horizontal scrollable row of buttons.
Each button shows: scenario ID + short title + colored dot for category.

```tsx
const CATEGORY_COLORS = {
  normal: '#39C47A',
  grid: '#F2B134',
  fault: '#FF5A5F',
  integrity: '#A78BFA',
};
```

Active scenario button has filled background matching its category color.

### Update StationView.tsx

Wire all panels into a responsive grid layout:

```
┌──────────────────────────────────────────────────────────────┐
│  [S1 Normal] [S2 Grid] [S3 Bad Frame] [S4 Link Lost] ...    │
├──────────────────────────────────────────────────────────────┤
│                                                              │
│                    3D Charging Scene                          │
│                      (h-[55vh])                              │
│                                                              │
├──────────────────────────────────────────────────────────────┤
│  [▶ Play] [⏭ Step] [⏮ Restart]  1x  Step 3 of 12          │
├────────────────────────────┬─────────────────────────────────┤
│                            │                                 │
│  State Indicator           │  Meter Chart                    │
│  (state diagram SVG)       │  (V, I, F over frames)          │
│                            │                                 │
├────────────────────────────┤                                 │
│  Pin LEDs                  │                                 │
│  ● ● ● ●                  │                                 │
├────────────────────────────┼─────────────────────────────────┤
│  Energy Gauge              │  (Phase 4: CRC / Session)       │
│  ⚡ 736,000 Wh             │                                 │
└────────────────────────────┴─────────────────────────────────┘
```

Use Tailwind grid: `grid grid-cols-1 lg:grid-cols-2 gap-4`.

## Verify

`npm run dev`: select different scenarios, step through them. State diagram
highlights current state. Pin LEDs change. Meter chart shows data points
appearing. Energy gauge ticks up during CHARGING steps.
```

---

## Phase 4: Station View — Evidence Features

### Agent prompt

```
You are continuing the EV charger visualization frontend.
Project at ChampionCHIP-Stage3/viz/. Phases 1-3 done.

This is Phase 4: add the evidence/integrity features to Station View.

Read existing code first.

## Create these files:

### src/components/station/CRCChainViz.tsx

Interactive SVG showing the CRC chain across meter frames.

Visual: horizontal chain of nodes connected by arrows.

```
[Seed: 0xFFFF] ──► [Frame 1: 0xCC77 ✓] ──► [Frame 2: 0x0DE6 ✓] ──► ...
```

Each node:
- Rounded rect, ~120×50px
- Shows: "Frame N" on top, CRC value (hex) in mono font, check mark below
- Fill: dark panel color, border matches state
- Valid: green check mark, green border
- Invalid: red X, red border, all downstream nodes turn red too

Click interaction:
- Click a frame node to "corrupt" it (flip bit 0 of byte 0)
- Recompute CRC chain from that point
- All downstream CRCs change → checks fail → nodes turn red
- Click again to restore
- A "Reset" button restores all frames

The chain data comes from the current scenario's frame steps. Only frames
(type === 'frame') appear in the chain.

Arrow between nodes: shows the CRC value that becomes the next seed.
Arrow label in small mono font.

### src/components/station/FrameInspector.tsx

Detailed byte-level view of the currently selected meter frame.

```
┌─────────────────────────────────────────────────┐
│  Frame 1 of 2                                    │
│                                                  │
│  Bytes: [FC] [08] [A0] [00] [88] [13] [77] [CC] │
│                                                  │
│  Decoded:                                        │
│    Voltage:   2300 → 230.0 V                     │
│    Current:    160 → 16.0 A                      │
│    Frequency: 5000 → 50.00 Hz                    │
│    CRC:     0xCC77                               │
│                                                  │
│  Seed: 0xFFFF                                    │
│  Expected CRC: 0xCC77  ✓ match                   │
└─────────────────────────────────────────────────┘
```

Each byte is a clickable box (like the reference team's .byte buttons).
Click to flip bit 0. CRC recomputes. If CRC mismatches, show ✗ in red.

### src/components/station/SessionRecord.tsx

Displays the 8-byte session record at the end of a scenario.

```
┌─────────────────────────────────────────────────────┐
│  📋 Session Record (charge detail record)           │
│                                                      │
│  Bytes: [00] [3B] [0B] [00] [00] [02] [5C] [D0]    │
│                                                      │
│  Decoded:                                            │
│    Energy:  736,000 (V×I units)                      │
│    Status:  0x00 (normal)                            │
│    Frames:  2                                        │
│    CRC-16:  0xD05C  ✓ verified                       │
│                                                      │
│  Flags: (none)                                       │
│         ☐ E-Stop  ☐ CP Error  ☐ Over-current         │
│         ☐ CRC Lost  ☐ Grid Hold                      │
└─────────────────────────────────────────────────────┘
```

For fault scenarios, flags light up red. The status byte maps to the
flag constants from constants.ts.

Show this panel only after the last step of a scenario (when record exists).

### Update StationView.tsx

Add the new panels to the grid:
- CRCChainViz: spans full width below the meter chart
- FrameInspector: appears when a frame node is clicked in the chain
- SessionRecord: appears after the last step

## Verify

Select S3 (corrupted frame). Step through. See the CRC chain: frame 2
has a red X. Click frame 1 to corrupt it → downstream all break.
Select S1, complete it. Session record shows with verified CRC.
```

---

## Phase 5: Grid View — 3D + Charts

### Agent prompt

```
You are continuing the EV charger visualization frontend.
Project at ChampionCHIP-Stage3/viz/. Phases 1-4 done (Station View complete).

This is Phase 5: build the Grid View (fleet-scale innovation showcase).

Read existing code, especially src/data/rebound.ts.

## Create these files:

### src/components/grid/GridView.tsx

Layout for the Grid tab:

```
┌─────────────────────────────────────────────────────────────┐
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  1,000       │  │  7.94×       │  │  0.881 MW    │      │
│  │  chargers    │  │  reduction   │  │  peak load   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
├──────────────────────────────┬──────────────────────────────┤
│                              │                              │
│    3D City Scene             │    Rebound Chart             │
│    (charger nodes)           │    (animated bar chart)      │
│                              │                              │
├──────────────────────────────┼──────────────────────────────┤
│                              │                              │
│    Grid Timeline             │    Delay Histogram           │
│    (event replay)            │    (hash distribution)       │
│                              │                              │
└──────────────────────────────┴──────────────────────────────┘
```

### src/components/grid/CityScene.tsx

R3F scene: bird's-eye view of a city block.

Objects:
- Ground: dark plane with subtle grid (Drei Grid)
- Buildings: 15-20 random-height boxes (0.5-3.0 tall), grey/dark,
  scattered in a roughly grid pattern. Not interactive, just context.
- Charger nodes: 30 glowing spheres (SphereGeometry 0.15) placed along
  "streets" (between buildings). Each represents ~33 chargers.
  Color: green=charging, amber=holding, dark=off.
- Central substation: larger box (1.0×0.5×1.0), slightly glowing,
  with thin Line segments connecting to nearby nodes (power grid).
- Camera: top-down angled view, OrbitControls, auto-rotate slowly.

Animation states (driven by a `gridPhase` prop):
1. `normal`: all nodes green, steady glow
2. `dip`: substation flashes red, nodes transition to amber over 0.5s
3. `sync_restart`: all nodes flash green simultaneously (bad)
4. `stagger_restart`: nodes light up one-by-one over 8 "frames"
   (each frame = 0.3s). Use the rebound data to determine how many
   per frame. Visually dramatic: scattered activation across the city.

### src/components/grid/ReboundChart.tsx

Recharts BarChart. Two series side by side per frame:
- Red/orange: "Synchronized" (all together) — one tall bar at frame 2
- Green: "CRC-hashed" — spread bars across frames 2-9

Animated: bars grow from zero when the component mounts or when the
timeline reaches the restart phase.

Above the chart, three stat tiles (Tailwind cards):
```tsx
<div className="grid grid-cols-3 gap-4 mb-6">
  <StatTile value="1,000" label="chargers" icon={Zap} />
  <StatTile value="7.94×" label="reduction" icon={TrendingDown} />
  <StatTile value="0.881" label="MW peak" icon={Activity} />
</div>
```

Use data from rebound.ts. Compute peak values dynamically.

### src/components/grid/DelayHistogram.tsx

Recharts BarChart: 8 bars (delay values 2-9), each showing the count
of charger IDs that hash to that delay.

Use delayHistogram(10000) from rebound.ts.

Title: "CRC-16 Hash Distribution: 10,000 Charger IDs"
Subtitle: "Each charger's restart delay is deterministic and auditable"

Bars should be roughly even (~1,250 each). Color: gradient from teal
to green.

### src/components/grid/GridTimeline.tsx

A horizontal timeline with playback controls, specific to the grid event:

```
  ● Normal ──── ● Grid Dip ──── ● All Hold ──── ● Restart ──── ● Recovered
  [▶ Play]  [Step]  Frame: 3/10
```

Each phase drives the CityScene animation state and the chart highlights.

When playing:
1. Normal (2s): nodes green
2. Grid Dip (1s): substation flashes, nodes go amber
3. All Hold (2s): nodes stay amber
4. Restart (3s): nodes light up per the stagger pattern
5. Recovered (2s): all green again

## Verify

Switch to Grid tab. See 3D city with green nodes. Play the timeline.
Watch nodes go amber, then light up staggered. Rebound chart bars
animate. Histogram shows even distribution.
```

---

## Phase 6: Polish + Dispute Panel

### Agent prompt

```
You are finishing the EV charger visualization frontend.
Project at ChampionCHIP-Stage3/viz/. Phases 1-5 done.

This is Phase 6: add the Dispute panel and polish everything.

## Create:

### src/components/grid/DisputePanel.tsx

"What if someone disputes a charge?" interactive demo.

A collapsible panel (click to expand). When expanded:

1. Shows a 3-frame session's CRC chain (like CRCChainViz but simpler,
   inline in this panel):
   ```
   [0xFFFF] → [Frame 1 ✓] → [Frame 2 ✓] → [Frame 3 ✓] → Record ✓
   Energy: 1,104,000 (3 frames × 230V × 16A)
   ```

2. A "Corrupt Frame 2" button. When clicked:
   - Frame 2's byte flips, CRC fails
   - Frame 3's chain seed is wrong, also fails
   - Energy recalculates: only Frame 1 counted (368,000)
   - Session record's status shows CRC_LOST flag
   - Visual: Frame 2 and 3 turn red, energy shrinks with animation

3. Text explanation below:
   "The chip stopped billing the instant the meter link broke.
    The session record proves exactly how much energy was delivered
    before the fault. No human override. No network required."

4. "Reset" button to restore the chain.

## Polish tasks:

### Dark theme consistency
- Ensure all components use Tailwind dark: classes or CSS variables
- Background: bg-gray-950 for page, bg-gray-900 for panels
- Text: text-gray-100 primary, text-gray-400 muted
- Borders: border-gray-800

### Responsive layout
- Station View: single column on mobile, two columns on lg+
- Grid View: single column on mobile, two columns on lg+
- 3D scenes: min-height 300px, aspect-ratio maintained
- Charts: responsive width, fixed height

### Transitions
- Tab switch: fade transition (CSS transition opacity 150ms)
- Scenario switch: 3D scene smoothly transitions states (use useSpring
  from @react-three/drei or simple lerp in useFrame)
- Chart animations: Recharts animationDuration={800}

### Loading state
- Show a subtle loading spinner while Three.js initialises
- Use React.Suspense with Drei Loader for the 3D scenes

### Typography
- Import Inter and JetBrains Mono from Google Fonts in index.html
- Body: Inter
- Data/hex values: JetBrains Mono
- Configure in tailwind.config.ts: fontFamily

### Navbar polish
- Add a small RISC-V chip icon (from Lucide: Cpu)
- Subtitle: "Grid-Aware EV Charging Station Controller"
- Tab indicators: animated underline that slides between tabs

### Footer
- Small muted text at bottom:
  "Every value on this page comes from the chip's own firmware, verified
   against the Python golden model (chip-inventor/testbench/app/golden.py).
   The visualization reads bytes — it makes no decisions."

## Verify

Full walkthrough:
1. Page loads, dark theme, Station tab active
2. Select S2 (grid event). Step through all steps.
   - Car connects, cable turns green, particles flow
   - Grid dip: cable amber, hold LED on, frequency drops on chart
   - Restart: cable back to green
   - Session record appears with GRID_HOLD flag
3. Switch to Grid tab
   - 3D city with green nodes
   - Play timeline: nodes go amber, then stagger back
   - Rebound chart shows 7.94× reduction
   - Histogram shows even distribution
4. Open Dispute panel
   - Corrupt frame 2, watch chain break
   - Energy drops, CRC_LOST flag appears
5. Responsive: resize window, verify layout adapts
6. No console errors, no type errors (`npx tsc --noEmit`)
```

---

## Execution Notes

- Run phases sequentially: each depends on the previous
- Each agent should read existing code before writing new code
- After each phase, verify with `npm run dev` and `npx tsc --noEmit`
- The data layer (Phase 1) is the foundation — if CRC values don't match
  golden.py, everything downstream is wrong
- 3D scenes (Phase 2, 5) are the most complex — if they block, the UI
  panels (Phase 3, 4, 6) can still proceed with placeholder 3D
