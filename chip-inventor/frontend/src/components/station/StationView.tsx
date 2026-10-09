// Station page. One focal point at a time:
//   headline (what this scenario proves) + three live numbers
//   -> state journey (the whole scenario in one row of pills)
//   -> the charging bay, the chip's decisions, playback
//   -> meter readings and the scenario library
//   -> evidence, closed until asked for.
// All values come from the scenario step snapshots (data/scenarios.ts); this
// file only arranges and narrates them.

import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { Radio, Timer, X, Zap } from 'lucide-react';
import ChargingScene from './ChargingScene';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import ScenarioPicker from './ScenarioPicker';
import StepTimeline from './StepTimeline';
import StateJourney from './StateJourney';
import PlaybackCard from './PlaybackCard';
import ReadingsCard from './ReadingsCard';
import StateIndicator from './StateIndicator';
import MeterChart from './MeterChart';
import type { MeterFrame } from './MeterChart';
import CRCChainViz from './CRCChainViz';
import type { CRCChainFrame } from './CRCChainViz';
import FrameInspector from './FrameInspector';
import SessionRecord from './SessionRecord';
import { SCENARIOS, replayScenario } from '../../data/scenarios';
import { corrupt } from '../../data/meter';
import { ChargerState, METER_TIMEOUT_MS, STATE_COLORS } from '../../data/constants';
import { crc16 } from '../../data/crc';
import { buildPlayback, flagNames, GROUP_ORDER, SCENARIO_META, STATE_LABEL, statusFor, TONE_COLOR } from './stationStory';

const STEP_MS = 1900;

const PINS = [
  { bit: 4, name: 'P4', label: 'Contactor', color: '#3CCF5A' },
  { bit: 5, name: 'P5', label: 'Cable lock', color: '#8DB6FF' },
  { bit: 6, name: 'P6', label: 'Grid hold', color: '#F2C230' },
  { bit: 7, name: 'P7', label: 'Fault', color: '#FF6B6F' },
];

// Scenario order for "Next", following the library's grouping.
const ORDERED = GROUP_ORDER.flatMap((g) => SCENARIOS.filter((s) => SCENARIO_META[s.id]?.group === g));

function Stat({ icon, value, unit, label, alert }: { icon: ReactNode; value: string; unit?: string; label: string; alert?: boolean }) {
  return (
    <div className="min-w-0">
      <div className="flex items-end gap-2.5">
        <span className="mb-1.5 hidden h-8 w-8 shrink-0 items-center justify-center rounded-full border border-[var(--color-line-strong)] text-[var(--color-ink-2)] sm:flex" aria-hidden="true">
          {icon}
        </span>
        <span className={`tabular font-display text-4xl leading-none font-light tracking-tight sm:text-5xl xl:text-6xl ${alert ? 'text-[var(--color-bad)]' : 'text-[var(--color-ink)]'}`}>
          {value}
          {unit && <span className="ml-1 text-base font-normal text-[var(--color-mute)] sm:text-lg">{unit}</span>}
        </span>
      </div>
      <div className="mt-2 text-sm text-[var(--color-mute)]">{label}</div>
    </div>
  );
}

type Tab = 'meter' | 'integrity' | 'fsm' | 'record';
const TABS: { id: Tab; label: string }[] = [
  { id: 'meter', label: 'Meter charts' },
  { id: 'integrity', label: 'Corrupt a frame' },
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
  const [tab, setTab] = useState<Tab | null>(null);
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

  const jump = useCallback((i: number) => {
    setPlaying(false);
    setIndex(i);
  }, []);

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

  const age = Math.min(step.ageMs, METER_TIMEOUT_MS);
  const next = ORDERED[(ORDERED.findIndex((s) => s.id === scenario.id) + 1) % ORDERED.length];

  return (
    <div className="flex flex-col gap-8">
      {/* Headline + live numbers */}
      <header className="flex flex-col gap-8 xl:flex-row xl:items-end xl:justify-between">
        <div className="max-w-2xl">
          <p className="text-sm text-[var(--color-mute)]">
            Scenario <span className="font-mono text-[var(--color-ink-2)]">{scenario.id}</span> · {meta.group}
          </p>
          <h1 className="mt-2 font-display text-4xl leading-[1.05] font-light tracking-tight text-balance text-[var(--color-ink)] md:text-6xl">{meta.name}</h1>
          <p className="mt-4 max-w-xl text-lg leading-relaxed text-[var(--color-ink-2)]">{meta.proves}</p>
        </div>
        <div className="grid shrink-0 grid-cols-3 gap-5 md:gap-10">
          <Stat icon={<Radio size={15} />} value={String(step.frames)} label="frames billed" />
          <Stat icon={<Zap size={15} />} value={(step.energy / 100 / 1000).toFixed(2)} unit="kW" label="Σ V×I billed" />
          <Stat
            icon={<Timer size={15} />}
            value={String(age)}
            unit="ms"
            label={age >= METER_TIMEOUT_MS ? 'watchdog tripped' : 'since meter data'}
            alert={age >= METER_TIMEOUT_MS}
          />
        </div>
      </header>

      <section aria-label="Charger states over the scenario" className="-mx-1 overflow-x-auto px-1 pt-1 pb-2">
        <div className="min-w-[520px]">
          <StateJourney steps={steps} index={index} onJump={jump} />
        </div>
      </section>

      <div className="grid grid-cols-1 gap-5 md:grid-cols-2 xl:grid-cols-12">
        {/* The bay */}
        <section
          aria-label="Charging bay"
          className="relative overflow-hidden rounded-[28px] md:col-span-2 xl:col-span-6"
          style={{ boxShadow: '0 30px 60px -34px rgba(20,24,40,0.55)' }}
        >
          {/* Backdrops cross-fade between navy (calm) and charcoal (active/alert). */}
          <div
            className="absolute inset-0 transition-opacity duration-700"
            style={{ background: 'radial-gradient(120% 90% at 50% 30%, #12408F 0%, #0A2A66 45%, #061C47 100%)', opacity: status.backdrop === 'navy' ? 1 : 0 }}
          />
          <div
            className="absolute inset-0 transition-opacity duration-700"
            style={{ background: 'radial-gradient(120% 90% at 50% 30%, #34363B 0%, #232427 45%, #141517 100%)', opacity: status.backdrop === 'charcoal' ? 1 : 0 }}
          />

          <div className="relative flex items-center justify-between gap-3 px-6 pt-5">
            <span className="flex items-center gap-2 rounded-full bg-white/10 px-3.5 py-1.5 text-sm font-medium text-white backdrop-blur-sm">
              <span className="h-2 w-2 rounded-full" style={{ backgroundColor: accent }} aria-hidden="true" />
              {STATE_LABEL[step.stateAfter]}
            </span>
            <span
              className="flex items-center gap-2 rounded-full bg-white/10 px-3.5 py-1.5 backdrop-blur-sm"
              title={`DATAOUT 0x${step.pinsOut.toString(16).padStart(2, '0').toUpperCase()}`}
            >
              <span className="font-mono text-xs text-white/70">pins</span>
              {PINS.map((p) => {
                const on = (step.pinsOut & (1 << p.bit)) !== 0;
                return (
                  <span
                    key={p.bit}
                    role="img"
                    aria-label={`${p.name} ${p.label} ${on ? 'on' : 'off'}`}
                    className="h-2.5 w-2.5 rounded-full transition-colors duration-300"
                    style={{ backgroundColor: on ? p.color : 'transparent', boxShadow: on ? `0 0 8px ${p.color}` : 'inset 0 0 0 1.5px rgba(255,255,255,0.35)' }}
                  />
                );
              })}
            </span>
          </div>

          <div className="relative h-[300px] sm:h-[360px]" aria-hidden="true">
            <ChargingScene
              icon={status.icon}
              accent={accent}
              carPresent={step.stateAfter !== ChargerState.IDLE}
              charging={step.stateAfter === ChargerState.CHARGING}
              pins={step.pinsOut}
            />
          </div>

          <div className="relative px-6 pb-6" aria-live="polite">
            <p className="font-display text-2xl font-semibold text-white md:text-3xl">{status.caption}</p>
            <p className="mt-1.5 min-h-5 text-sm text-white/65">{status.sub}</p>
          </div>
        </section>

        {/* Playback */}
        <div className="xl:col-span-3">
          <PlaybackCard
            index={index}
            total={steps.length}
            playing={isPlaying}
            speed={speed}
            onToggle={togglePlay}
            onStep={(d) => jump(Math.max(0, Math.min(last, index + d)))}
            onRestart={() => jump(0)}
            onSpeed={setSpeed}
            nextScenario={{ id: next.id, name: SCENARIO_META[next.id]?.name ?? next.title, go: () => selectScenario(next.id) }}
          />
        </div>

        {/* What the chip decided: the one dark card */}
        <section
          aria-labelledby="decided-label"
          className="flex h-[560px] flex-col overflow-hidden rounded-[28px] bg-[var(--color-dark)] text-white xl:col-span-3 xl:row-span-2 xl:h-auto"
        >
          <div className="flex items-end justify-between gap-3 px-6 pt-6 pb-4">
            <h2 id="decided-label" className="font-display text-xl leading-snug font-medium">
              What the chip
              <br />
              decided
            </h2>
            <span className="tabular font-display text-5xl leading-none font-light">
              {index + 1}
              <span className="text-2xl text-white/45">/{steps.length}</span>
            </span>
          </div>
          <div className="relative min-h-0 flex-1">
            <StepTimeline steps={steps} index={index} onJump={jump} />
          </div>
        </section>

        <div className="md:col-span-2 xl:col-span-6 xl:col-start-4 xl:row-start-2">
          <ReadingsCard steps={steps} index={index} />
        </div>

        <div className="md:col-span-2 xl:col-span-3 xl:col-start-1 xl:row-start-2">
          <ScenarioPicker key={scenario.id} scenarios={SCENARIOS} activeId={scenarioId} onSelect={selectScenario} />
        </div>
      </div>

      {/* Evidence, closed by default */}
      <section aria-labelledby="evidence-label" className="card p-6 md:p-8">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <h2 id="evidence-label" className="font-display text-xl font-medium text-[var(--color-ink)]">
              Check the evidence
            </h2>
            <p className="mt-1 text-sm text-[var(--color-mute)]">Optional. The bytes behind the story.</p>
          </div>
          <div role="tablist" aria-label="Evidence" className="flex flex-wrap gap-2">
            {TABS.map((t) => {
              const selected = tab === t.id;
              return (
                <button
                  key={t.id}
                  type="button"
                  role="tab"
                  id={`tab-${t.id}`}
                  aria-selected={selected}
                  aria-controls={selected ? `panel-${t.id}` : undefined}
                  onClick={() => setTab(selected ? null : t.id)}
                  className={`min-h-11 cursor-pointer rounded-full px-5 text-sm font-medium transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)] focus-visible:ring-offset-2 ${
                    selected ? 'bg-[var(--color-dark)] text-white' : 'bg-white text-[var(--color-ink-2)] shadow-sm hover:text-[var(--color-ink)]'
                  }`}
                >
                  {t.label}
                </button>
              );
            })}
            {tab && (
              <button
                type="button"
                onClick={() => setTab(null)}
                aria-label="Close evidence"
                className="flex h-11 w-11 cursor-pointer items-center justify-center rounded-full text-[var(--color-mute)] transition-colors duration-200 hover:bg-white hover:text-[var(--color-ink)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)]"
              >
                <X size={18} />
              </button>
            )}
          </div>
        </div>

        {tab && (
          <div role="tabpanel" id={`panel-${tab}`} aria-labelledby={`tab-${tab}`} className="mt-6 border-t border-dashed border-[var(--color-line-strong)] pt-6">
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
                      {
                        title: corrupted.size ? `With ${corrupted.size} corrupted frame${corrupted.size > 1 ? 's' : ''}` : 'With your changes',
                        r: whatIf,
                        muted: false,
                      },
                    ].map(({ title, r, muted }) => {
                      const changed = !muted && corrupted.size > 0;
                      const reasons = flagNames(r.flags);
                      return (
                        <div key={title} className="rounded-2xl border bg-white px-5 py-4" style={{ borderColor: changed ? STATE_COLORS[r.state] : 'var(--color-line)' }}>
                          <p className="text-xs font-medium text-[var(--color-mute)]">{title}</p>
                          <p className="tabular mt-1 font-display text-lg font-semibold text-[var(--color-ink)]">
                            {(r.energy / 100).toLocaleString()} W billed over {r.frames} frame{r.frames === 1 ? '' : 's'}
                          </p>
                          <p className="mt-1 text-sm text-[var(--color-ink-2)]">
                            Ends in{' '}
                            <span className="font-semibold" style={{ color: STATE_COLORS[r.state] }}>
                              {STATE_LABEL[r.state]}
                            </span>
                            {reasons.length > 0 && <span className="text-[var(--color-mute)]"> · {reasons.join(', ')}</span>}
                          </p>
                        </div>
                      );
                    })}
                  </div>
                )}
                {chainFrames.length > 0 && (
                  <p className="text-xs text-[var(--color-mute)]">
                    Re-run through the charger model. Bad frames are never billed; two in a row latch a fault.
                  </p>
                )}
                {inspected !== null && chainFrames[inspected] && (
                  <div className="rounded-2xl border border-[var(--color-line)] bg-white p-4">
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
                    Sent at step {recordIndex + 1}. CRC-16 sealed: any edit is detectable.
                  </p>
                  <SessionRecord record={recordStep.raw.record} />
                </div>
              ) : (
                <p className="text-sm text-[var(--color-mute)]">No session record in this scenario.</p>
              ))}
          </div>
        )}
      </section>
    </div>
  );
}
