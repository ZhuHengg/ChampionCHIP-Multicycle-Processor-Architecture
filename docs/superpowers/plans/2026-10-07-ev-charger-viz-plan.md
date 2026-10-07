# EV Charger Visualization — Implementation Plan (v2)

**Spec:** `docs/superpowers/specs/2026-10-07-ev-charger-viz-design.md`  
**Design System:** `ChampionCHIP-Stage3/viz/design-system/championchip-ev-charger/MASTER.md`  
**Date:** 2026-10-07  
**Execution:** 6 builder agents (Sonnet) run in parallel where possible, 1 verifier agent runs after each phase completes.

---

## Execution Strategy

Phases 1 must complete first (data layer is foundation).  
Then Phases 2+3 can run in parallel (3D scene and UI panels are independent).  
Phase 4 depends on Phase 3.  
Phase 5 can run in parallel with Phase 4 (Grid View is independent of Station evidence).  
Phase 6 depends on all prior phases.  
Verifier runs after each phase.

```
Phase 1 (scaffold + data) ──► Phase 2 (3D scene) ──► Phase 4 (evidence) ──► Phase 6 (polish)
                           ├─► Phase 3 (UI panels) ─┘                    ─┘
                           └─► Phase 5 (grid view) ──────────────────────┘
```

---

## Design System Context (include in every agent prompt)

```
DESIGN SYSTEM — ChampionCHIP EV Charger
Style: Glassmorphism (backdrop-blur, subtle borders, layered depth)
Theme: Dark-first

COLORS (CSS variables):
  --color-background: #0F172A (dark navy)
  --color-card: #1B2336
  --color-primary: #1E293B
  --color-secondary: #334155
  --color-accent: #22C55E (green — power/charging)
  --color-foreground: #F8FAFC
  --color-muted: #272F42
  --color-muted-foreground: #94A3B8
  --color-border: #475569
  --color-destructive: #EF4444

STATUS COLORS:
  IDLE: #7C8A83 (grey)
  CONNECTED: #6EA8FF (blue)
  CHARGING: #22C55E (green)
  GRID_HOLD: #F2B134 (amber)
  FAULT: #FF5A5F (red)

TYPOGRAPHY:
  Headings: Fira Code (400-700)
  Body: Fira Sans (300-700)
  Google Fonts: https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500;600;700&family=Fira+Sans:wght@300;400;500;600;700&display=swap

EFFECTS:
  Cards: backdrop-blur(10-20px), border 1px solid rgba(255,255,255,0.1), border-radius 12px
  Buttons: border-radius 8px, transition 200ms, cursor-pointer
  Shadows: 0 4px 6px rgba(0,0,0,0.1) cards, 0 10px 15px rgba(0,0,0,0.1) modals
  Motion: 300-450ms stagger, back.out(1.4) easing

RULES:
  - No emojis as icons (use Lucide React SVGs)
  - cursor-pointer on all clickable elements
  - Hover transitions 150-300ms
  - Focus states visible for keyboard nav
  - prefers-reduced-motion respected
  - Responsive: 375px, 768px, 1024px, 1440px
  - No horizontal scroll on mobile
```

---

## Phase 1: Scaffold + Data Layer

### Agent prompt

```
You are building a React + TypeScript visualization frontend for a RISC-V
EV charging station controller (ChampionCHIP competition project). This is
Phase 1: scaffold the project and port the Python data layer to TypeScript.

IMPORTANT: Read the Python source files carefully before porting. Every
CRC value, state transition, and threshold must match exactly.

## Design System

[INSERT DESIGN SYSTEM CONTEXT BLOCK FROM ABOVE]

## Location

Create the project at: ChampionCHIP-Stage3/viz/
(this directory may already have a design-system/ subfolder — preserve it)

## Step 1: Scaffold

1. cd to ChampionCHIP-Stage3/viz/
2. npm create vite@latest . -- --template react-ts
   (if prompted about existing files, proceed — design-system/ should be kept)
3. npm install
4. npm install @react-three/fiber @react-three/drei three recharts lucide-react
5. npm install -D tailwindcss @tailwindcss/vite @types/three

6. Configure vite.config.ts:
```ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
})
```

7. Create src/styles/globals.css:
```css
@import "tailwindcss";
@import url('https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500;600;700&family=Fira+Sans:wght@300;400;500;600;700&display=swap');

:root {
  --color-background: #0F172A;
  --color-card: #1B2336;
  --color-primary: #1E293B;
  --color-secondary: #334155;
  --color-accent: #22C55E;
  --color-foreground: #F8FAFC;
  --color-muted: #272F42;
  --color-muted-foreground: #94A3B8;
  --color-border: #475569;
  --color-destructive: #EF4444;
}

body {
  background-color: var(--color-background);
  color: var(--color-foreground);
  font-family: 'Fira Sans', system-ui, sans-serif;
}

code, .font-mono {
  font-family: 'Fira Code', monospace;
}
```

8. Import globals.css in src/main.tsx
9. Verify `npm run dev` starts without errors

## Step 2: Port data layer

Read these Python source files and port them to TypeScript:
- chip-inventor/testbench/app/golden.py
- chip-inventor/testbench/app/scenarios.py
- chip-inventor/testbench/app/evidence/rebound_sim.py

### src/data/constants.ts

```ts
export const F_LOW = 4950;
export const V_SAG = 2070;
export const I_MAX = 320;
export const HOLD_BASE = 2;
export const CHARGER_ID = 0x4D590001;

export enum ChargerState {
  IDLE = 0, CONNECTED = 1, CHARGING = 2, GRID_HOLD = 3, FAULT = 4,
}

export const STATE_NAMES: Record<ChargerState, string> = {
  [ChargerState.IDLE]: 'IDLE',
  [ChargerState.CONNECTED]: 'CONNECTED',
  [ChargerState.CHARGING]: 'CHARGING',
  [ChargerState.GRID_HOLD]: 'GRID_HOLD',
  [ChargerState.FAULT]: 'FAULT',
};

export const STATE_COLORS: Record<ChargerState, string> = {
  [ChargerState.IDLE]: '#7C8A83',
  [ChargerState.CONNECTED]: '#6EA8FF',
  [ChargerState.CHARGING]: '#22C55E',
  [ChargerState.GRID_HOLD]: '#F2B134',
  [ChargerState.FAULT]: '#FF5A5F',
};

export const STATE_OUT: Record<ChargerState, number> = {
  [ChargerState.IDLE]: 0x00,
  [ChargerState.CONNECTED]: 0x20,
  [ChargerState.CHARGING]: 0x30,
  [ChargerState.GRID_HOLD]: 0x60,
  [ChargerState.FAULT]: 0x80,
};

export const F_ESTOP = 0x08;
export const F_CP_ERROR = 0x10;
export const F_OVERCURRENT = 0x20;
export const F_CRC_LOST = 0x40;
export const F_GRID_HOLD = 0x80;
export const SAFETY = 0x08;
```

### src/data/crc.ts

Port `golden.crc16()` exactly. Poly 0x1021, MSB-first, no reflection.
Input: Uint8Array + optional seed (default 0xFFFF). Returns number.

### src/data/charger.ts

Port `golden.Charger` class exactly. Every if/else, threshold, flag.
Must include: state, energy, frames, flags, bad, hold, delay, seed, tx.
Methods: setInputs(value), rxFrame(frame: Uint8Array), get out().
Also export: restartDelay(triggerCrc, chargerId?) function.
Also export: recordBytes(energy, status, frames) function.

### src/data/meter.ts

Port `golden.Meter` class. frame(v, i, f) returns Uint8Array(8).
Also export: corrupt(frame: Uint8Array) function.

### src/data/scenarios.ts

Port all S1-S11 + S1X scenarios. Each scenario = array of steps built
by running Charger + Meter models step by step (like scenarios.py does).

```ts
export interface ScenarioStep {
  type: 'datadir' | 'gpio_in' | 'gpio_out' | 'frame' | 'record';
  value?: number;
  frame?: Uint8Array;
  record?: Uint8Array;
  expectedOut?: number;
  stateBefore: ChargerState;
  stateAfter: ChargerState;
  energyAfter: number;
  framesAfter: number;
  flagsAfter: number;
  seedAfter: number;
  label: string;
  // For frame steps, include decoded values
  voltage?: number;
  current?: number;
  frequency?: number;
  crcValid?: boolean;
}

export interface Scenario {
  id: string;
  title: string;
  category: 'normal' | 'grid' | 'fault' | 'integrity';
  steps: ScenarioStep[];
}

export const SCENARIOS: Scenario[] = [ /* build all 12 */ ];
```

### src/data/rebound.ts

Port rebound() and delayHistogram() from rebound_sim.py.

## Step 3: Minimal App.tsx

Render app title, list of scenarios with their step counts, and
rebound peak values. This verifies the data layer works.

## Step 4: Verify

- `npm run dev` loads with correct data displayed
- `npx tsc --noEmit` passes with no errors
- S1 scenario has correct number of steps
- rebound() returns peak sync ~7.0 MW and peak staggered ~0.881 MW
```

---

## Phase 2: Station View — 3D Scene

### Agent prompt

```
You are continuing the EV charger visualization frontend.
Project at ChampionCHIP-Stage3/viz/ (React + Vite + Tailwind + R3F).
Phase 1 is complete: scaffold and data layer exist in src/data/.

This is Phase 2: build the 3D charging station scene.

IMPORTANT: Read existing code in src/ first. Use the data layer types.

[INSERT DESIGN SYSTEM CONTEXT BLOCK]

## Files to create:

### src/components/station/ChargingScene.tsx

React Three Fiber Canvas scene. Props:
```tsx
interface ChargingSceneProps {
  state: ChargerState;
  charging: boolean;
  cableConnected: boolean;
  pinOutputs: number;    // bits 7-4
  stateLabel: string;
}
```

Scene contains:
1. **Ground**: PlaneGeometry 20x20, rotation [-PI/2, 0, 0], color #1a1a1a.
   Add Drei Grid helper for subtle grid lines.

2. **Charger cabinet**: Drei RoundedBox 0.6x1.4x0.4, MeshStandardMaterial
   with metalness 0.7, roughness 0.3, color #1E293B. Position [0, 0.7, 0].
   Front face: inset Plane 0.4x0.3 as "screen" — emissiveIntensity changes
   with state, emissive color = STATE_COLORS[state].

3. **Car**: Group of RoundedBox components.
   - Body: 2.0x0.6x0.9, color #C0C8D0
   - Roof: 1.0x0.4x0.8 on top
   - Wheels: 4x Cylinder(0.15, 0.15, 0.1), color #333
   - Animate position.x: -5 (away) to -1.2 (parked) via useFrame lerp
   - Visible only when cableConnected

4. **Cable**: TubeGeometry along CatmullRomCurve3 from [0.3, 0.5, 0]
   (charger) to [-0.8, 0.3, 0] (car port).
   - Color: CONNECTED=#6EA8FF, CHARGING=#22C55E, GRID_HOLD=#F2B134, FAULT=#FF5A5F
   - Visible only when cableConnected

5. **Power particles**: When charging=true, use Drei Sparkles or custom
   Points geometry along the cable curve. Green emissive dots moving
   from charger to car. Use useFrame to animate positions.

6. **Ground LEDs**: 4x SphereGeometry(0.08) at positions near cabinet base.
   Emissive material. Each maps to P4-P7:
   - P4 CONTACTOR: green #22C55E
   - P5 CABLE_LOCK: blue #6EA8FF
   - P6 GRID_HOLD: amber #F2B134
   - P7 FAULT: red #FF5A5F
   On/off derived from pinOutputs bits.

7. **Lighting**: Drei Environment preset="city". DirectionalLight
   position [5, 8, 5], intensity 0.8. AmbientLight intensity 0.3.

8. **Camera**: Drei OrbitControls. Position [5, 4, 5].
   enablePan=false, maxPolarAngle=PI/2.2.
   autoRotate=true, autoRotateSpeed=0.5.

Wrap in React.Suspense with a dark loading fallback.

### src/components/station/StationView.tsx

Layout component that wires the 3D scene to scenario playback.

```tsx
const [scenarioId, setScenarioId] = useState('S1');
const [stepIndex, setStepIndex] = useState(0);
const [playing, setPlaying] = useState(false);
const [speed, setSpeed] = useState(1);
```

Layout:
- Top: scenario picker (simple buttons for now, will be enhanced in Phase 3)
- Middle: Canvas div with h-[55vh] min-h-[300px], bg-[#0F172A], rounded-xl
- Bottom: playback controls [Play/Pause] [Step] [Restart] Speed select

When playing, advance stepIndex via setInterval at 1500ms/speed.
Each step's stateAfter drives ChargingScene props.

## Verify

`npm run dev` shows 3D scene. Charger cabinet visible, car slides in when
selecting S1 and stepping past the first gpio_in step. Power particles
flow during CHARGING. LEDs change color.
```

---

## Phase 3: Station View — UI Panels

### Agent prompt

```
You are continuing the EV charger visualization frontend.
Project at ChampionCHIP-Stage3/viz/. Phase 1 (data) and Phase 2 (3D) done.

This is Phase 3: build the UI panels around the 3D scene.

IMPORTANT: Read existing code first. Preserve StationView.tsx structure.

[INSERT DESIGN SYSTEM CONTEXT BLOCK]

## Files to create:

### src/components/Navbar.tsx

Top nav bar. Tailwind: bg-[#0F172A] border-b border-[#475569]/30.
Left: Cpu icon (from lucide-react) + "ChampionCHIP" (Fira Code, bold) +
"RVBL-2 EV Controller" (Fira Sans, text-sm, text-[#94A3B8]).
Center/Right: Two tab buttons — "Station" and "Grid".
Active tab: text-[#22C55E] with bottom border-2 border-[#22C55E].
Inactive: text-[#94A3B8] hover:text-[#F8FAFC] transition-colors.

Props: activeTab, onTabChange.

### Update src/App.tsx

Import Navbar. Toggle between StationView and a placeholder GridView div.
Simple state, no router.

### src/components/station/StateIndicator.tsx

SVG component ~300x250px showing 5 state nodes as rounded rects.

Layout (vertical flow):
```
         IDLE (top)
           |
       CONNECTED
        /     \
   CHARGING    → IDLE (return arrow)
    /     \
GRID_HOLD  FAULT
```

Each node: rounded rect 100x36, rx=8.
- Current state: fill=STATE_COLORS[state], filter drop-shadow glow,
  scale(1.05) transform
- Other states: fill=transparent, stroke=STATE_COLORS[state] at 40% opacity,
  stroke-width=1.5

Transition arrows: polyline with arrowhead marker. The arrow from
stateBefore to stateAfter: stroke-width=2, STATE_COLORS[stateAfter],
opacity pulse animation (CSS @keyframes).

Other arrows: stroke=#475569, stroke-width=1.

Labels: Fira Code, 11px, fill matching node color.

Props: currentState: ChargerState, previousState?: ChargerState.

### src/components/station/PinLEDs.tsx

Horizontal row of 4 LED indicators.

Each LED:
```tsx
<div className="flex items-center gap-2">
  <div className={`w-3.5 h-3.5 rounded-full transition-all duration-300
    ${on ? `bg-[${color}] shadow-[0_0_12px_${color}]` : 'bg-[#272F42] border border-[#475569]'}`} />
  <span className="font-mono text-xs text-[#94A3B8]">{label}</span>
</div>
```

Props: pinOutputs: number (bits 7-4).

### src/components/station/MeterChart.tsx

Recharts ResponsiveContainer + ComposedChart.

Props: frames: Array<{v: number, i: number, f: number, valid: boolean, index: number}>

- Line: Voltage (v/10 to get V), stroke=#6EA8FF, yAxisId="left"
- Line: Frequency (f/100 to get Hz), stroke=#22C55E, yAxisId="right"
- Bar: Current (i/10 to get A), fill=#F2B134, yAxisId="left"
- ReferenceLine: V_SAG/10=207 V, stroke=#FF5A5F, strokeDasharray="5 5"
- ReferenceLine: F_LOW/100=49.5 Hz, stroke=#FF5A5F, strokeDasharray="5 5"
- ReferenceLine: I_MAX/10=32 A, stroke=#FF5A5F, strokeDasharray="5 5"

Dark theme: cartesianGrid stroke=#272F42, axis tick fill=#94A3B8.
Height: 200px.

Invalid frames: use a custom dot that renders an X shape in red.

### src/components/station/EnergyGauge.tsx

Card panel showing accumulated energy.

```
⚡ Energy Metered
  736,000
  Wh (V×I accumulated)
  [████████░░░] 2 frames
```

- Number uses tabular-nums, Fira Code, text-3xl, text-[#22C55E]
- Progress bar: h-2 rounded-full bg-[#272F42], inner div bg-[#22C55E]
  width = (frames/maxFrames)*100%
- Animate number changes with CSS transition on the numeric span

Props: energy: number, frames: number, maxFrames: number.

### src/components/station/ScenarioPicker.tsx

Horizontal scrollable row of pill buttons. overflow-x-auto flex gap-2.

Each button:
- Inactive: bg-[#1B2336] border border-[#475569]/50 text-[#94A3B8]
  hover:border-[#94A3B8] transition-all cursor-pointer
- Active: bg-[categoryColor]/20 border-[categoryColor] text-[#F8FAFC]

Category dot: w-2 h-2 rounded-full bg-[categoryColor] inline before text.

Category colors:
  normal: #22C55E, grid: #F2B134, fault: #FF5A5F, integrity: #A78BFA

Show: "S1" + truncated title (max 20ch).

Props: scenarios, activeId, onSelect.

### Update src/components/station/StationView.tsx

Wire all panels into responsive grid:

```
[ScenarioPicker - full width, scrollable]
[3D Scene - full width, h-[55vh]]
[Playback Controls - full width]
[StateIndicator | MeterChart  ] ← grid-cols-1 lg:grid-cols-2
[PinLEDs       | EnergyGauge  ]
```

All panels in glassmorphism cards: bg-[#1B2336]/80 backdrop-blur-sm
border border-white/10 rounded-xl p-4.

Extract frame data from scenario steps for MeterChart.

## Verify

Select S2. Step through. State diagram highlights CHARGING, then GRID_HOLD
(amber glow), then back to CHARGING. Meter chart shows frequency dip.
Pin LEDs change. Energy gauge ticks up.
```

---

## Phase 4: Station View — Evidence Features

### Agent prompt

```
You are continuing the EV charger visualization frontend.
Project at ChampionCHIP-Stage3/viz/. Phases 1-3 done.

This is Phase 4: add CRC evidence/integrity features to Station View.

[INSERT DESIGN SYSTEM CONTEXT BLOCK]

## Files to create:

### src/components/station/CRCChainViz.tsx

Interactive SVG showing CRC chain across meter frames.

Layout: horizontal chain, overflow-x-auto.

Each frame node: rounded rect ~130x55, rx=8.
- Fill: #1B2336
- Border: 1px solid rgba(255,255,255,0.1)
- Top line: "Frame N" in Fira Sans 11px, #94A3B8
- Middle: CRC hex value in Fira Code 14px, #F8FAFC
- Bottom: ✓ or ✗ icon (Lucide Check/X, 14px)
- Valid: border-[#22C55E]/50, check icon #22C55E
- Invalid: border-[#FF5A5F]/50, X icon #FF5A5F, bg-[#FF5A5F]/10

First node: "Seed: 0xFFFF" (no check needed).

Arrows between nodes: SVG path with arrowhead, stroke #475569.
Small label on arrow: the CRC value that becomes next seed, Fira Code 10px.

Click interaction:
- Click a frame node → toggle corruption (flip byte 0 bit 0)
- Recompute CRC chain from that frame onward
- All downstream nodes that now fail → turn red
- Add "corrupted" class: small diagonal strikethrough line over the node
- Click again to restore
- "Reset All" button: Lucide RotateCcw icon + text, top-right

Props: frames: Array<{original: Uint8Array, current: Uint8Array}>,
       onCorrupt: (index: number) => void.

Manage corrupted state internally with useState<Set<number>>.
Recompute CRC chain: start from seed 0xFFFF, check each frame's bytes[6:8]
against computed CRC of bytes[0:6] seeded with previous frame's CRC field.

### src/components/station/FrameInspector.tsx

Detailed byte view of one frame. Opens when clicking a CRC chain node.

Each byte: clickable box (w-8 h-8 flex items-center justify-center
font-mono text-sm rounded), bg-[#272F42] hover:bg-[#334155] cursor-pointer.
Corrupted byte: bg-[#FF5A5F]/20 text-[#FF5A5F].

Decoded fields below:
  Voltage: 2300 → 230.0 V
  Current: 160 → 16.0 A
  Frequency: 5000 → 50.00 Hz
  CRC: 0xCC77

Seed and expected CRC with match/mismatch indicator.

Props: frame: Uint8Array, seed: number, index: number,
       onFlipByte: (byteIndex: number) => void.

### src/components/station/SessionRecord.tsx

8-byte record display. Glassmorphism card.

Bytes displayed as clickable boxes (same style as FrameInspector).
Decoded: Energy (u32 LE), Status byte, Frames count, CRC-16.
Status flags shown as checkboxes (Lucide Square/CheckSquare):
  ☐/☑ E-Stop, CP Error, Over-current, CRC Lost, Grid Hold

Green verdict box when CRC OK: bg-[#22C55E]/10 border border-[#22C55E]/30
  text "CRC-16 verified ✓"
Red verdict when CRC fails: bg-[#FF5A5F]/10 border border-[#FF5A5F]/30

Show only after scenario's last step.

Props: record: Uint8Array.

### Update StationView.tsx

Add new panels below existing grid:
- CRCChainViz: spans full width
- FrameInspector: opens in a slide-over or inline panel when chain node clicked
- SessionRecord: appears after last step

## Verify

S3 (corrupted frame): step through, see CRC chain with red X on bad frame.
Click frame 1 to corrupt → downstream all break red.
S1 complete: session record shows with verified CRC.
```

---

## Phase 5: Grid View — 3D + Charts

### Agent prompt

```
You are continuing the EV charger visualization frontend.
Project at ChampionCHIP-Stage3/viz/. Phases 1-4 done.

This is Phase 5: build the Grid View tab (fleet-scale innovation showcase).

[INSERT DESIGN SYSTEM CONTEXT BLOCK]

## Files to create:

### src/components/grid/GridView.tsx

Layout for Grid tab:

Top: 3 stat tiles in a row (grid-cols-3 gap-4):
  - "1,000" / "chargers" / Zap icon
  - "7.94×" / "reduction" / TrendingDown icon
  - "0.881 MW" / "peak load" / Activity icon

Each tile: glassmorphism card (bg-[#1B2336]/80 backdrop-blur-sm
border border-white/10 rounded-xl p-4).
Big number: Fira Code, text-3xl, text-[#22C55E].
Label: Fira Sans, text-sm, text-[#94A3B8].
Icon: Lucide, text-[#22C55E], top-right corner, opacity-50.

Below tiles: 2-column grid (lg:grid-cols-2):
  Left: CityScene (3D) — h-[400px]
  Right: ReboundChart
  Left: GridTimeline
  Right: DelayHistogram

### src/components/grid/CityScene.tsx

R3F Canvas, bird's-eye view.

Objects:
- Ground: PlaneGeometry 30x30, color #0F172A, Grid helper
- Buildings: 15-20 BoxGeometry, random height 0.5-3.0, width 1-2,
  positions scattered on a rough grid. Color #1E293B, roughness 0.8.
  Non-interactive context only.
- Charger nodes: 30x SphereGeometry(0.15), PointLight per node (low intensity).
  Positions along "streets" between buildings.
  Emissive material: green=#22C55E when active, amber=#F2B134 when holding,
  dark=#272F42 when off. Transition via useFrame lerp on emissiveIntensity.
- Substation: BoxGeometry 1.5x0.8x1.5, center, color #334155,
  emissive #FF5A5F when dip phase.
- Power lines: Drei Line from substation to nearby nodes, color #475569.

Camera: position [0, 20, 15], lookAt [0,0,0].
OrbitControls: enablePan=false, autoRotate=true, autoRotateSpeed=0.3.

Props: phase: 'normal' | 'dip' | 'hold' | 'stagger' | 'recovered',
       staggerFrame?: number (0-7, which batch is currently restarting).

Animation by phase:
- normal: all nodes green, steady
- dip: substation flashes red (emissive pulse), power lines flash
- hold: all nodes amber
- stagger: nodes light up in batches per staggerFrame. Use rebound data
  to know how many per frame. Batch assignment: precompute which nodes
  belong to which delay bucket.
- recovered: all green

### src/components/grid/ReboundChart.tsx

Recharts BarChart, two grouped bars per x-tick (frames 2-9).

- Red/orange (#FF5A5F): "All at once" — one tall bar at frame HOLD_BASE
- Green (#22C55E): "CRC-hashed" — spread bars

Use rebound() from data layer. Animate with animationDuration={800}.

Dark theme: bg transparent, cartesianGrid stroke=#272F42.
Tooltip: bg-[#1B2336] border-[#475569].

Chart title: "Load Restored per Frame (MW)" in Fira Code.

### src/components/grid/DelayHistogram.tsx

Recharts BarChart: 8 bars, x = delay value (2-9), y = count.

Use delayHistogram(10000) from data layer.

Gradient fill from #22C55E to #6EA8FF.
Title: "CRC-16 Hash Distribution: 10,000 Charger IDs"
Subtitle: "Each bar ≈ 1,250 — uniform spread, no clustering"

### src/components/grid/GridTimeline.tsx

Horizontal timeline with playback.

5 phase dots connected by lines:
  ● Normal ── ● Grid Dip ── ● All Hold ── ● Restart ── ● Recovered

Current phase dot: larger, glowing (STATE_COLORS match).
Past phases: solid. Future: muted.

Playback controls: [Play/Pause] [Step] "Phase: N/5"

When playing, auto-advance phases with timers:
  normal: 2s, dip: 1s, hold: 2s, stagger: 3s (0.375s per sub-frame),
  recovered: 2s.

During stagger phase, advance staggerFrame 0-7 to drive CityScene
and highlight corresponding ReboundChart bar.

Props drives CityScene phase + staggerFrame.

### Update App.tsx

Wire GridView into the Grid tab.

## Verify

Switch to Grid tab. See 3D city with green nodes. Stat tiles show
correct numbers. Play timeline: nodes go amber, then stagger back green.
Rebound chart bars animate. Histogram shows ~1250 per bucket.
```

---

## Phase 6: Polish + Dispute Panel

### Agent prompt

```
You are finishing the EV charger visualization frontend.
Project at ChampionCHIP-Stage3/viz/. Phases 1-5 done.

This is Phase 6: Dispute panel and final polish.

[INSERT DESIGN SYSTEM CONTEXT BLOCK]

## Files to create:

### src/components/grid/DisputePanel.tsx

Collapsible panel at bottom of GridView. Default: collapsed, shows
"What if someone disputes a charge?" with ChevronDown icon.

Expand animation: max-height transition 300ms.

When expanded:

1. Mini CRC chain (3 frames): simplified inline version.
   Three rounded-rect nodes + arrows + final "Record" node.
   All start green/valid.

2. "Corrupt Frame 2" button: bg-[#FF5A5F]/20 border border-[#FF5A5F]/50
   text-[#FF5A5F] hover:bg-[#FF5A5F]/30 cursor-pointer.

   When clicked:
   - Frame 2 node turns red, X icon
   - Frame 3 node turns red (chain broken)
   - Energy display: animated count-down from 1,104,000 to 368,000
   - Record node: shows CRC_LOST flag in red
   - Status text changes

3. Explanation text below in text-sm text-[#94A3B8]:
   "The chip stopped billing the instant the meter link broke.
    The session record proves exactly how much energy was delivered
    before the fault. No human override. No network required."

4. "Reset" button: RotateCcw icon, restores all nodes to green.

### Polish checklist (apply across all files):

1. **Typography consistency:**
   - Verify all headings use Fira Code (font-mono)
   - Verify all body text uses Fira Sans (font-sans)
   - Data values: font-mono tabular-nums
   - Minimum body text: 14px (text-sm = 14px with Tailwind v4)

2. **Glassmorphism cards:**
   - Every panel: bg-[#1B2336]/80 backdrop-blur-sm border border-white/10
     rounded-xl p-4 shadow-md
   - Hover on interactive cards: border-white/20 transition-all duration-200

3. **Transitions:**
   - Tab switch: CSS transition opacity 150ms
   - 3D scene state changes: useFrame lerp (not instant)
   - Chart animations: animationDuration={800} on Recharts
   - Scenario switch: fade out old data, fade in new

4. **Loading:**
   - React.Suspense around Canvas components
   - Fallback: centered spinner in Fira Code "Loading 3D scene..."
   - Use Drei Loader progress indicator

5. **Responsive:**
   - Mobile (<768px): single column, 3D scene h-[300px], panels stack
   - Tablet (768-1024): 3D scene h-[400px], 2-col grid
   - Desktop (1024+): full layout as designed

6. **Accessibility:**
   - aria-label on all icon-only buttons
   - focus-visible outlines: ring-2 ring-[#22C55E] ring-offset-2
     ring-offset-[#0F172A]
   - prefers-reduced-motion: disable autoRotate, skip animations

7. **Footer:**
   Bottom of page, py-6, text-center text-xs text-[#94A3B8]:
   "Every value on this page comes from the chip's own firmware,
    verified against the Python golden model. The visualization
    reads bytes — it makes no decisions."

## Verify

Full walkthrough:
1. Page loads dark, Station tab, S1 selected
2. Step through S2: car connects, grid dip, hold, restart
3. CRC chain shows chain breaking on S3
4. Switch to Grid tab: 3D city, animated timeline, rebound chart
5. Dispute panel: corrupt frame, energy drops, chain breaks
6. Resize to mobile: layout adapts, no horizontal scroll
7. `npx tsc --noEmit` — no type errors
8. Browser console — no errors
```

---

## Verifier Agent Prompt

Run this after each phase completes:

```
You are a verification agent for the ChampionCHIP EV Charger visualization
frontend at ChampionCHIP-Stage3/viz/.

## Verification checklist

### Build checks
1. Run `npm run dev` — does it start without errors? (check terminal output)
2. Run `npx tsc --noEmit` — any TypeScript errors?
3. Check browser console for runtime errors

### Data layer checks (Phase 1+)
4. Read src/data/crc.ts — does crc16([0xFC, 0x08, 0xA0, 0x00, 0x88, 0x13], 0xFFFF)
   return 0xCC77? (This is the golden test vector from S1 frame 1)
5. Read src/data/scenarios.ts — does S1 exist with correct step count?
6. Read src/data/rebound.ts — does rebound() produce peak sync ~7.0 and
   peak staggered ~0.88?

### Design system checks (Phase 2+)
7. Read src/styles/globals.css — are CSS variables defined per MASTER.md?
8. Are Fira Code + Fira Sans imported from Google Fonts?
9. Do components use the design system colors (not hardcoded random values)?
10. Is background #0F172A, not white or another default?

### Component checks (Phase 3+)
11. Does Navbar exist with two tabs?
12. Does StateIndicator show 5 states?
13. Does MeterChart use Recharts with threshold reference lines?
14. Do PinLEDs map to bits 4-7?

### 3D checks (Phase 2+)
15. Does ChargingScene import from @react-three/fiber and @react-three/drei?
16. Is it wrapped in React.Suspense?
17. Does it use OrbitControls from @react-three/drei (not raw three.js)?

### Evidence checks (Phase 4+)
18. Does CRCChainViz support click-to-corrupt?
19. Does SessionRecord decode the 8-byte format correctly?

### Grid checks (Phase 5+)
20. Does ReboundChart use rebound() data?
21. Does DelayHistogram show 8 bars?
22. Does CityScene respond to phase changes?

### Polish checks (Phase 6)
23. No emojis as icons (Lucide only)?
24. cursor-pointer on all clickable elements?
25. prefers-reduced-motion respected?
26. Responsive layout at 375px width?

Report: list each check as PASS/FAIL with one-line explanation.
If any FAIL, describe the fix needed.
```

---

## How to Execute

1. **Start Phase 1** — paste Phase 1 prompt to a Sonnet agent
2. **Run Verifier** — paste verifier prompt, confirm PASS on checks 1-6
3. **Start Phases 2, 3, 5 in parallel** — three Sonnet agents simultaneously
   (they only depend on Phase 1, not each other). Use worktree isolation
   for each, merge after.
4. **Run Verifier** after each completes
5. **Start Phase 4** — depends on Phase 3
6. **Run Verifier**
7. **Start Phase 6** — depends on all
8. **Final Verifier** — full checklist

If parallel worktree merge conflicts arise, Phase 2 (3D scene) and Phase 3
(UI panels) touch different files and should merge cleanly. Phase 5 (grid/)
is entirely separate components.
