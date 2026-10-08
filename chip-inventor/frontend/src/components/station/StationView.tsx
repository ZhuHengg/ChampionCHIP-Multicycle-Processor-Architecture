// Station page. Reading order, left to right then down:
//   1 choose a scenario -> 2 watch the bay -> 3 follow what the chip decided
//   -> 4 inspect the evidence.
// All values come from the scenario step snapshots (data/scenarios.ts); this
// file only arranges and narrates them.

import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { Pause, Play, RotateCcw, SkipBack, SkipForward } from 'lucide-react';
import ChargingScene from './ChargingScene';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import ScenarioPicker from './ScenarioPicker';
import StepTimeline from './StepTimeline';
import LiveReadings from './LiveReadings';
import StateIndicator from './StateIndicator';
import MeterChart from './MeterChart';
import type { MeterFrame } from './MeterChart';
import CRCChainViz from './CRCChainViz';
import type { CRCChainFrame } from './CRCChainViz';
import FrameInspector from './FrameInspector';
import SessionRecord from './SessionRecord';
import { SCENARIOS, replayScenario } from '../../data/scenarios';
import { corrupt } from '../../data/meter';
import { ChargerState, STATE_COLORS } from '../../data/constants';
import { crc16 } from '../../data/crc';
import { buildPlayback, flagNames, GROUP_TONE, SCENARIO_META, STATE_LABEL, statusFor, TONE_COLOR } from './stationStory';

const SPEEDS = [0.5, 1, 2];
const STEP_MS = 1900;

function SectionLabel({ n, children }: { n: number; children: ReactNode }) {
  return (
    <div className="mb-3 flex items-center gap-2.5">
      <span className="flex h-6 w-6 items-center justify-center rounded-full bg-white/[0.08] font-mono text-xs font-semibold text-[var(--color-ink)]">
        {n}
      </span>
      <h2 className="font-display text-sm font-bold tracking-wide text-[var(--color-ink)]">{children}</h2>
    </div>
  );
}

function IconButton({ label, onClick, disabled, primary, children }: { label: string; onClick: () => void; disabled?: boolean; primary?: boolean; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      disabled={disabled}
      className={`flex cursor-pointer items-center justify-center rounded-full transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70 disabled:cursor-not-allowed disabled:opacity-35 ${
        primary ? 'h-12 w-12 bg-white text-[#0A2A66] hover:bg-white/90' : 'h-11 w-11 text-white/85 hover:bg-white/10'
      }`}
    >
      {children}
    </button>
  );
}

type Tab = 'meter' | 'integrity' | 'fsm' | 'record';
const TABS: { id: Tab; label: string }[] = [
  { id: 'meter', label: 'Meter readings' },
  { id: 'integrity', label: 'Frame integrity' },
  { id: 'fsm', label: 'State machine' },
  { id: 'record', label: 'Session record' },
];

interface StationViewProps {
  initialScenarioId?: string;
  /** 0-based step to open paused at; omitted = start from the top and play. */
  initialStep?: number;
  onScenarioChange?: (id: string) => void;
}

export default function StationView({ initialScenarioId = 'S1', initialStep, onScenarioChange }: StationViewProps) {
  const [scenarioId, setScenarioId] = useState(initialScenarioId);
  const [index, setIndex] = useState(() => {
    const sc = SCENARIOS.find((s) => s.id === initialScenarioId) ?? SCENARIOS[0];
    return Math.min(initialStep ?? 0, buildPlayback(sc).length - 1);
  });
  const reducedMotion = usePrefersReducedMotion();
  const [playing, setPlaying] = useState(initialStep === undefined && !reducedMotion);
  const [speed, setSpeed] = useState(1);
  const [tab, setTab] = useState<Tab>('meter');
  const [corrupted, setCorrupted] = useState<Set<number>>(new Set());
  const [inspected, setInspected] = useState<number | null>(null);

  const scenario = useMemo(() => SCENARIOS.find((s) => s.id === scenarioId) ?? SCENARIOS[0], [scenarioId]);
  const meta = SCENARIO_META[scenario.id];
  const steps = useMemo(() => buildPlayback(scenario), [scenario]);
  const last = steps.length - 1;
  const step = steps[Math.min(index, last)];
  // Playback stops by itself at the last step; derived, not stored.
  const isPlaying = playing && index < last;
  const status = statusFor(step);
  const accent = TONE_COLOR[status.tone];
  const groupColor = TONE_COLOR[GROUP_TONE[meta.group]];

  const selectScenario = useCallback(
    (id: string) => {
      setScenarioId(id);
      setIndex(0);
      setCorrupted(new Set());
      setInspected(null);
      setPlaying(!reducedMotion);
      onScenarioChange?.(id);
    },
    [reducedMotion, onScenarioChange],
  );

  useEffect(() => {
    if (!isPlaying) return;
    const id = setTimeout(() => setIndex((i) => Math.min(i + 1, last)), STEP_MS / speed);
    return () => clearTimeout(id);
  }, [isPlaying, index, last, speed]);

  const togglePlay = useCallback(() => {
    if (isPlaying) {
      setPlaying(false);
      return;
    }
    if (index >= last) setIndex(0);
    setPlaying(true);
  }, [isPlaying, index, last]);

  // Space toggles playback, arrow keys step, when focus is not in a control.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      if (t && (t.closest('button, input, select, textarea, [role="tab"]') || t.isContentEditable)) return;
      if (e.key === ' ') {
        e.preventDefault();
        togglePlay();
      } else if (e.key === 'ArrowRight') {
        setPlaying(false);
        setIndex((i) => Math.min(i + 1, last));
      } else if (e.key === 'ArrowLeft') {
        setPlaying(false);
        setIndex((i) => Math.max(i - 1, 0));
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [last, togglePlay]);

  const frameSteps = useMemo(() => steps.filter((s) => s.kind === 'frame'), [steps]);

  const meterFrames: MeterFrame[] = useMemo(
    () =>
      steps
        .slice(0, index + 1)
        .filter((s) => s.kind === 'frame' && s.raw.frame)
        .map((s) => {
          const f = s.raw.frame!;
          return {
            v: s.raw.voltage ?? 0,
            i: s.raw.current ?? 0,
            f: s.raw.frequency ?? 0,
            valid: crc16(f.subarray(0, 7)) === (f[7] | (f[8] << 8)),
            index: s.frameIndex ?? 0,
          };
        }),
    [steps, index],
  );

  const chainFrames: CRCChainFrame[] = useMemo(
    () => frameSteps.map((s) => ({ original: s.raw.frame!, current: s.raw.frame! })),
    [frameSteps],
  );

  const baseline = useMemo(() => replayScenario(scenario, new Set()), [scenario]);
  const whatIf = useMemo(() => replayScenario(scenario, corrupted), [scenario, corrupted]);

  const toggleCorrupt = (i: number) =>
    setCorrupted((prev) => {
      const next = new Set(prev);
      if (next.has(i)) next.delete(i);
      else next.add(i);
      return next;
    });

  const recordStep = steps.find((s) => s.kind === 'record');
  const recordIndex = recordStep ? steps.indexOf(recordStep) : -1;
  const previousState = index > 0 ? steps[index - 1].stateAfter : undefined;

  return (
    <div className="flex flex-col gap-7">
      {/* Page objective */}
      <header className="max-w-5xl">
        <p className="mb-1.5 text-xs font-semibold uppercase tracking-[0.16em] text-[var(--color-ok)]">Single charger · firmware replay</p>
        <h1 className="font-display text-2xl font-extrabold leading-tight text-[var(--color-ink)] md:text-[2rem]">
          Watch the chip run a charging session, decision by decision.
        </h1>
        <p className="mt-2 text-[15px] leading-relaxed text-[var(--color-ink-2)]">
          Pick a scenario, watch the bay, and read why the RVBL-2 firmware did each thing. Every state, pin and byte comes from its golden model.
        </p>
      </header>

      <div className="grid grid-cols-1 gap-6 xl:grid-cols-[240px_minmax(0,1fr)_340px]">
        {/* 1 · Choose */}
        <section aria-labelledby="choose-label">
          <SectionLabel n={1}>
            <span id="choose-label">Choose a scenario</span>
          </SectionLabel>
          <ScenarioPicker scenarios={SCENARIOS} activeId={scenarioId} onSelect={selectScenario} />
        </section>

        {/* 2 · Watch */}
        <section aria-labelledby="watch-label" className="min-w-0">
          <SectionLabel n={2}>
            <span id="watch-label">Watch the charging bay</span>
          </SectionLabel>
          <div className="relative overflow-hidden rounded-2xl" style={{ boxShadow: '0 30px 60px -30px rgba(0,0,0,0.7)' }}>
            {/* Backdrops cross-fade between navy (calm) and charcoal (active/alert). */}
            <div
              className="absolute inset-0 transition-opacity duration-700"
              style={{ background: 'radial-gradient(120% 90% at 50% 30%, #12408F 0%, #0A2A66 45%, #061C47 100%)', opacity: status.backdrop === 'navy' ? 1 : 0 }}
            />
            <div
              className="absolute inset-0 transition-opacity duration-700"
              style={{ background: 'radial-gradient(120% 90% at 50% 30%, #34363B 0%, #232427 45%, #141517 100%)', opacity: status.backdrop === 'charcoal' ? 1 : 0 }}
            />

            <div className="relative flex items-start justify-between gap-3 px-5 pt-4">
              <span className="flex items-center gap-2 rounded-full bg-black/25 px-3 py-1.5 text-xs font-medium text-white/90 backdrop-blur-sm">
                <span className="h-2 w-2 rounded-full" style={{ backgroundColor: groupColor }} aria-hidden="true" />
                <span className="font-mono">{scenario.id}</span> {meta.name}
              </span>
              <span className="tabular rounded-full bg-black/25 px-3 py-1.5 font-mono text-xs text-white/80 backdrop-blur-sm">
                step {index + 1} / {steps.length}
              </span>
            </div>

            <div className="relative h-[340px] sm:h-[400px] xl:h-[440px]" aria-hidden="true">
              <ChargingScene
                icon={status.icon}
                accent={accent}
                carPresent={step.stateAfter !== ChargerState.IDLE}
                charging={step.stateAfter === ChargerState.CHARGING}
                pins={step.pinsOut}
              />
            </div>

            <div className="relative px-6 pb-2 text-center" aria-live="polite">
              <p className="font-display text-2xl font-extrabold text-white md:text-[2rem]">{status.caption}</p>
              <p className="mt-1.5 min-h-5 text-sm text-white/70">{status.sub}</p>
            </div>

            {/* Playback */}
            <div className="relative px-5 pt-3 pb-4">
              <div className="mb-3 flex gap-1" role="group" aria-label="Scenario progress">
                {steps.map((s, i) => (
                  <button
                    key={i}
                    type="button"
                    aria-label={`Go to step ${i + 1}: ${s.title}`}
                    onClick={() => {
                      setPlaying(false);
                      setIndex(i);
                    }}
                    className="group flex h-5 flex-1 cursor-pointer items-center focus-visible:outline-none"
                  >
                    <span
                      className="h-1.5 w-full rounded-full transition-colors duration-300 group-hover:h-2 group-focus-visible:ring-2 group-focus-visible:ring-white/70"
                      style={{ backgroundColor: i <= index ? STATE_COLORS[s.stateAfter] : 'rgba(255,255,255,0.16)' }}
                    />
                  </button>
                ))}
              </div>
              <div className="flex items-center justify-between gap-3">
                <div className="flex items-center gap-1">
                  <IconButton label="Restart" onClick={() => { setPlaying(false); setIndex(0); }}>
                    <RotateCcw size={18} />
                  </IconButton>
                  <IconButton label="Previous step" onClick={() => { setPlaying(false); setIndex((i) => Math.max(0, i - 1)); }} disabled={index === 0}>
                    <SkipBack size={18} />
                  </IconButton>
                  <IconButton label={isPlaying ? 'Pause' : 'Play'} onClick={togglePlay} primary>
                    {isPlaying ? <Pause size={20} fill="currentColor" /> : <Play size={20} fill="currentColor" className="ml-0.5" />}
                  </IconButton>
                  <IconButton label="Next step" onClick={() => { setPlaying(false); setIndex((i) => Math.min(last, i + 1)); }} disabled={index >= last}>
                    <SkipForward size={18} />
                  </IconButton>
                </div>
                <div className="hidden items-center gap-1 rounded-full bg-black/25 p-1 sm:flex" role="radiogroup" aria-label="Playback speed">
                  {SPEEDS.map((sp) => (
                    <button
                      key={sp}
                      type="button"
                      role="radio"
                      aria-checked={speed === sp}
                      onClick={() => setSpeed(sp)}
                      className={`min-h-9 min-w-11 cursor-pointer rounded-full px-2.5 font-mono text-xs transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70 ${
                        speed === sp ? 'bg-white text-[#0A2A66]' : 'text-white/75 hover:text-white'
                      }`}
                    >
                      {sp}×
                    </button>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* 3 · Follow */}
        <section aria-labelledby="follow-label" className="flex min-w-0 flex-col">
          <SectionLabel n={3}>
            <span id="follow-label">What the chip decided</span>
          </SectionLabel>
          <div className="flex min-h-0 flex-1 flex-col rounded-2xl border border-[var(--color-line)] bg-[var(--color-panel)]">
            <div className="border-b border-[var(--color-line)] px-4 py-3.5">
              <p className="text-xs font-semibold uppercase tracking-[0.12em]" style={{ color: groupColor }}>
                This scenario proves
              </p>
              <p className="mt-1 text-sm leading-relaxed text-[var(--color-ink)]">{meta.proves}</p>
            </div>
            <div className="relative min-h-[420px] flex-1">
              <StepTimeline
                steps={steps}
                index={index}
                onJump={(i) => {
                  setPlaying(false);
                  setIndex(i);
                }}
              />
            </div>
          </div>
        </section>
      </div>

      <section aria-label="Live readings">
        <LiveReadings step={step} />
      </section>

      {/* 4 · Inspect */}
      <section aria-labelledby="inspect-label">
        <SectionLabel n={4}>
          <span id="inspect-label">Inspect the evidence</span>
        </SectionLabel>
        <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-panel)]">
          <div role="tablist" aria-label="Evidence" className="flex gap-1 overflow-x-auto border-b border-[var(--color-line)] px-3">
            {TABS.map((t) => (
              <button
                key={t.id}
                type="button"
                role="tab"
                id={`tab-${t.id}`}
                aria-selected={tab === t.id}
                aria-controls={`panel-${t.id}`}
                onClick={() => setTab(t.id)}
                className={`min-h-12 shrink-0 cursor-pointer border-b-2 px-3 text-sm font-medium transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[var(--color-ok)] ${
                  tab === t.id ? 'border-[var(--color-ok)] text-[var(--color-ink)]' : 'border-transparent text-[var(--color-mute)] hover:text-[var(--color-ink)]'
                }`}
              >
                {t.label}
              </button>
            ))}
          </div>

          <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`} className="p-4 md:p-5">
            {tab === 'meter' && <MeterChart frames={meterFrames} />}

            {tab === 'integrity' && (
              <div className="flex flex-col gap-5">
                <CRCChainViz
                  frames={chainFrames}
                  corrupted={corrupted}
                  onToggleCorrupt={toggleCorrupt}
                  onReset={() => setCorrupted(new Set())}
                  selectedIndex={inspected}
                  onSelect={(i) => setInspected((cur) => (cur === i ? null : i))}
                />
                {chainFrames.length > 0 && (
                  <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                    {[
                      { title: 'As recorded', r: baseline, muted: true },
                      { title: corrupted.size ? `With ${corrupted.size} corrupted frame${corrupted.size > 1 ? 's' : ''}` : 'With your changes', r: whatIf, muted: false },
                    ].map(({ title, r, muted }) => {
                      const changed = !muted && corrupted.size > 0;
                      const reasons = flagNames(r.flags);
                      return (
                        <div
                          key={title}
                          className="rounded-xl border px-4 py-3"
                          style={{ borderColor: changed ? `${STATE_COLORS[r.state]}66` : 'var(--color-line)', backgroundColor: 'var(--color-panel-2)' }}
                        >
                          <p className="text-xs font-medium text-[var(--color-mute)]">{title}</p>
                          <p className="tabular mt-1 font-display text-lg font-bold text-[var(--color-ink)]">
                            {(r.energy / 100).toLocaleString()} W billed over {r.frames} frame{r.frames === 1 ? '' : 's'}
                          </p>
                          <p className="mt-1 text-sm text-[var(--color-ink-2)]">
                            Ends in <span style={{ color: STATE_COLORS[r.state] }}>{STATE_LABEL[r.state]}</span>
                            {reasons.length > 0 && <span className="text-[var(--color-mute)]"> · {reasons.join(', ')}</span>}
                          </p>
                        </div>
                      );
                    })}
                  </div>
                )}
                {chainFrames.length > 0 && (
                  <p className="text-xs text-[var(--color-mute)]">
                    Both results are computed by re-running this scenario through the charger model. Corrupted frames are never billed; two bad frames in a row
                    latch a fault.
                  </p>
                )}
                {inspected !== null && chainFrames[inspected] && (
                  <div className="rounded-xl border border-[var(--color-line)] bg-[var(--color-panel-2)] p-4">
                    <FrameInspector frame={corrupted.has(inspected) ? corrupt(chainFrames[inspected].current) : chainFrames[inspected].current} index={inspected} />
                  </div>
                )}
              </div>
            )}

            {tab === 'fsm' && (
              <div className="mx-auto max-w-4xl">
                <StateIndicator currentState={step.stateAfter} previousState={previousState} />
              </div>
            )}

            {tab === 'record' &&
              (recordStep?.raw.record ? (
                <div className="flex flex-col gap-3">
                  <p className="text-sm text-[var(--color-ink-2)]">
                    Sent at step {recordIndex + 1} of {steps.length}. A dispute can be settled from these 8 bytes alone: the CRC-16 proves they were not altered
                    after the chip sealed them.
                  </p>
                  <SessionRecord record={recordStep.raw.record} />
                </div>
              ) : (
                <p className="text-sm text-[var(--color-mute)]">This scenario ends without reading a session record.</p>
              ))}
          </div>
        </div>
      </section>
    </div>
  );
}
