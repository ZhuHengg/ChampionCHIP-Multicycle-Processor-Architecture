// Layout wiring the 3D charging scene to scenario playback (Phase 2),
// extended in Phase 3 with the surrounding telemetry panels (state diagram,
// meter chart, pin LEDs, energy gauge) and the shared ScenarioPicker.
// The 3D scene section and playback control logic are left as Phase 2 built
// them; Phase 3 additions are called out below.

import { useEffect, useMemo, useState } from 'react';
import ChargingScene from './ChargingScene';
import StateIndicator from './StateIndicator';
import PinLEDs from './PinLEDs';
import MeterChart from './MeterChart';
import type { MeterFrame } from './MeterChart';
import EnergyGauge from './EnergyGauge';
import ScenarioPicker from './ScenarioPicker';
import CRCChainViz from './CRCChainViz';
import type { CRCChainFrame } from './CRCChainViz';
import FrameInspector from './FrameInspector';
import SessionRecord from './SessionRecord';
import { SCENARIOS } from '../../data/scenarios';
import { ChargerState, STATE_COLORS, STATE_NAMES, STATE_OUT } from '../../data/constants';
import { crc16 } from '../../data/crc';
import { bytesToU16LE } from '../../data/binutil';

const SPEED_OPTIONS = [0.5, 1, 2, 4];
const MAX_METER_POINTS = 12;

export default function StationView() {
  const [scenarioId, setScenarioId] = useState('S1');
  const [stepIndex, setStepIndex] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [speed, setSpeed] = useState(1);
  const [inspectedFrame, setInspectedFrame] = useState<number | null>(null);

  const scenario = useMemo(
    () => SCENARIOS.find((s) => s.id === scenarioId) ?? SCENARIOS[0],
    [scenarioId],
  );

  const steps = scenario.steps;
  const step = steps[Math.min(stepIndex, steps.length - 1)];

  // Reset playback position when switching scenarios.
  useEffect(() => {
    setStepIndex(0);
    setPlaying(false);
    setInspectedFrame(null);
  }, [scenarioId]);

  // Autoplay.
  useEffect(() => {
    if (!playing) return;
    const id = setInterval(() => {
      setStepIndex((i) => {
        if (i >= steps.length - 1) {
          setPlaying(false);
          return i;
        }
        return i + 1;
      });
    }, 1500 / speed);
    return () => clearInterval(id);
  }, [playing, speed, steps.length]);

  const state = step.stateAfter;
  const previousState = stepIndex > 0 ? steps[Math.min(stepIndex, steps.length - 1) - 1]?.stateAfter : undefined;
  const cableConnected = state !== ChargerState.IDLE;
  const charging = state === ChargerState.CHARGING;
  // pinOutputs: the DATAOUT byte for this state already carries the P4-P7
  // bank in its upper nibble (STATE_OUT values are 0x00/0x20/0x30/0x60/0x80 —
  // see constants.ts), so it doubles directly as the ground-LED driver.
  const pinOutputs = STATE_OUT[state];
  const stateLabel = STATE_NAMES[state];

  // Meter frames up to and including the current step, for the chart.
  // crcValid isn't populated by the Phase 1 ScenarioBuilder (the interface
  // declares the field but `frame()` never sets it), so it's re-derived
  // here the same way Charger._onFrame does: seed starts at 0xFFFF and
  // always advances to the frame's own trailing CRC field, valid or not
  // (data/charger.ts rule 1/2). This is read-only display logic, not a
  // change to the model.
  const meterFrames: MeterFrame[] = useMemo(() => {
    const visibleSteps = steps.slice(0, Math.min(stepIndex, steps.length - 1) + 1);
    let seed = 0xFFFF;
    const out: MeterFrame[] = [];
    let idx = 0;
    for (const s of visibleSteps) {
      if (s.type !== 'frame' || !s.frame) continue;
      const field = bytesToU16LE(s.frame, 6);
      const valid = crc16(s.frame.subarray(0, 6), seed) === field;
      seed = field;
      out.push({
        v: s.voltage ?? 0,
        i: s.current ?? 0,
        f: s.frequency ?? 0,
        valid,
        index: idx++,
      });
    }
    return out.slice(-MAX_METER_POINTS);
  }, [steps, stepIndex]);

  const maxFrames = useMemo(
    () => steps.reduce((max, s) => Math.max(max, s.framesAfter), 0) || 1,
    [steps],
  );

  // Full set of meter frames for this scenario (not just those played so
  // far) -- the CRC chain viz shows the whole scenario's chain and lets the
  // user explore corruption independently of playback position.
  const chainFrames: CRCChainFrame[] = useMemo(
    () =>
      steps
        .filter((s): s is typeof s & { frame: Uint8Array } => s.type === 'frame' && !!s.frame)
        .map((s) => ({ original: s.frame, current: s.frame })),
    [steps],
  );

  // Seed feeding each chain frame (0xFFFF, then each frame's own CRC field),
  // needed by FrameInspector when a node is selected for inspection.
  const chainSeeds = useMemo(() => {
    const seeds: number[] = [];
    let seed = 0xFFFF;
    for (const f of chainFrames) {
      seeds.push(seed);
      seed = bytesToU16LE(f.original, 6);
    }
    return seeds;
  }, [chainFrames]);

  const lastStep = steps[steps.length - 1];
  const showSessionRecord =
    stepIndex >= steps.length - 1 && lastStep?.type === 'record' && !!lastStep.record;

  const handleStep = () => {
    setPlaying(false);
    setStepIndex((i) => Math.min(i + 1, steps.length - 1));
  };

  const handleRestart = () => {
    setPlaying(false);
    setStepIndex(0);
  };

  return (
    <div className="flex flex-col gap-4">
      {/* Scenario picker */}
      <div className="rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
        <ScenarioPicker scenarios={SCENARIOS} activeId={scenarioId} onSelect={setScenarioId} />
      </div>

      {/* 3D canvas */}
      <div className="overflow-hidden rounded-xl border border-white/10 bg-[#1B2336]/80 backdrop-blur-sm">
        <div className="h-[55vh] min-h-[300px] overflow-hidden rounded-xl bg-[#0F172A]">
          <ChargingScene
            state={state}
            charging={charging}
            cableConnected={cableConnected}
            pinOutputs={pinOutputs}
            stateLabel={stateLabel}
          />
        </div>

        {/* Step/state readout */}
        <div className="flex flex-wrap items-center justify-between gap-2 border-t border-white/10 px-4 py-2 text-sm text-[var(--color-muted-foreground)]">
          <span>
            Step {Math.min(stepIndex, steps.length - 1) + 1} / {steps.length} — {step.label}
          </span>
          <span
            className="rounded px-2 py-0.5 font-mono text-xs font-medium"
            style={{ backgroundColor: `${STATE_COLORS[state]}22`, color: STATE_COLORS[state] }}
          >
            {stateLabel}
          </span>
        </div>
      </div>

      {/* Playback controls */}
      <div className="flex flex-wrap items-center gap-3 rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
        <button
          type="button"
          onClick={() => setPlaying((p) => !p)}
          className="cursor-pointer rounded-lg border border-[var(--color-border)]/40 bg-[var(--color-card)]/70 px-4 py-1.5 text-sm font-medium text-[var(--color-foreground)] transition-colors duration-150 hover:border-[var(--color-accent)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A]"
        >
          {playing ? 'Pause' : 'Play'}
        </button>
        <button
          type="button"
          onClick={handleStep}
          disabled={stepIndex >= steps.length - 1}
          className="cursor-pointer rounded-lg border border-[var(--color-border)]/40 bg-[var(--color-card)]/70 px-4 py-1.5 text-sm font-medium text-[var(--color-foreground)] transition-colors duration-150 hover:border-[var(--color-accent)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A] disabled:cursor-not-allowed disabled:opacity-40"
        >
          Step
        </button>
        <button
          type="button"
          onClick={handleRestart}
          className="cursor-pointer rounded-lg border border-[var(--color-border)]/40 bg-[var(--color-card)]/70 px-4 py-1.5 text-sm font-medium text-[var(--color-foreground)] transition-colors duration-150 hover:border-[var(--color-accent)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A]"
        >
          Restart
        </button>
        <label className="ml-auto flex items-center gap-2 text-sm text-[var(--color-muted-foreground)]">
          Speed
          <select
            value={speed}
            onChange={(e) => setSpeed(Number(e.target.value))}
            className="cursor-pointer rounded-lg border border-[var(--color-border)]/40 bg-[var(--color-card)]/70 px-2 py-1 text-sm text-[var(--color-foreground)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A]"
          >
            {SPEED_OPTIONS.map((sp) => (
              <option key={sp} value={sp}>
                {sp}x
              </option>
            ))}
          </select>
        </label>
      </div>

      {/* Telemetry panels */}
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div className="rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
          <h3 className="mb-2 font-mono text-sm font-medium text-[#F8FAFC]">Charger State</h3>
          <div className="flex justify-center">
            <StateIndicator currentState={state} previousState={previousState} />
          </div>
        </div>
        <div className="rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
          <h3 className="mb-2 font-mono text-sm font-medium text-[#F8FAFC]">Meter Telemetry</h3>
          <MeterChart frames={meterFrames} />
        </div>
        <div className="rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
          <h3 className="mb-3 font-mono text-sm font-medium text-[#F8FAFC]">Output Pins</h3>
          <PinLEDs pinOutputs={pinOutputs} />
        </div>
        <div className="rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
          <EnergyGauge energy={step.energyAfter} frames={step.framesAfter} maxFrames={maxFrames} />
        </div>
      </div>

      {/* CRC chain evidence/integrity viz (Phase 4) */}
      <div className="rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
        <CRCChainViz
          frames={chainFrames}
          selectedIndex={inspectedFrame}
          onSelect={(i) => setInspectedFrame((cur) => (cur === i ? null : i))}
        />
      </div>

      {/* Frame inspector: inline panel for whichever chain node is selected */}
      {inspectedFrame !== null && chainFrames[inspectedFrame] && (
        <div className="rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
          <FrameInspector
            frame={chainFrames[inspectedFrame].current}
            seed={chainSeeds[inspectedFrame] ?? 0xFFFF}
            index={inspectedFrame}
          />
        </div>
      )}

      {/* Session record: only once the scenario has reached its final
          record() step (spec: shown only after scenario's last step). */}
      {showSessionRecord && lastStep.record && <SessionRecord record={lastStep.record} />}
    </div>
  );
}
