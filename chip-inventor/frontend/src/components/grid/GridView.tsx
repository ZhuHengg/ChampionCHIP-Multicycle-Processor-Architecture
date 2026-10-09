// Fleet page. Same 1,000 chargers, same grid dip, played twice: first with a
// fixed restart delay (everyone reconnects at once), then with RVBL-2's
// CRC-hashed delay. The comparison card puts both on one scale.

import { useCallback, useEffect, useMemo, useState } from 'react';
import type { ReactNode } from 'react';
import { ArrowRight, MessageSquareOff, Pause, Play, RotateCcw, SkipBack, SkipForward, TrendingDown, Zap } from 'lucide-react';
import { delayHistogram, rebound } from '../../data/rebound';
import { F_LOW, HOLD_BASE } from '../../data/constants';
import CityScene from './CityScene';
import SceneBackdrop, { MOOD_TEXT } from '../SceneBackdrop';
import type { Mood } from '../SceneBackdrop';
import ComparisonCard from './ComparisonCard';
import FleetHandoff from './FleetHandoff';
import DelayHistogram from './DelayHistogram';
import { MAX_ATTEMPTS, PHASES, REBOOT_TRY_MS, STAGGER_WAVES, WAVE_MS, useGridTimeline } from './GridTimeline';
import TimelineTrack, { PlayerButton } from '../TimelineTrack';
import type { CurrentFill } from '../TimelineTrack';
import type { Mode, Phase } from './GridTimeline';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import type { IconKind } from '../station/stationStory';

const N_CHARGERS = 1000;
const KW = 7;

// Chapter colours for the dark player bar.
const PHASE_COLOR: Record<Phase, string> = {
  normal: '#D6D3CB',
  dip: '#FF5A5F',
  hold: '#F2B134',
  stagger: '#F2C230',
  recovered: '#3CCF5A',
  surge: '#FF5A5F',
  rebound: '#FF8A3D',
  reboot: '#B9A3FF',
};

const MODES: { mode: Mode; label: string }[] = [
  { mode: 'without', label: 'Without RVBL-2' },
  { mode: 'with', label: 'With RVBL-2' },
];

interface GridViewProps {
  onOpenStation: (scenarioId: string) => void;
}

function Stat({ icon, value, unit, label }: { icon: ReactNode; value: string; unit?: string; label: string }) {
  return (
    <div className="min-w-0">
      <div className="flex items-end gap-2.5">
        <span className="mb-1.5 hidden h-8 w-8 shrink-0 items-center justify-center rounded-full border border-[var(--color-line-strong)] text-[var(--color-ink-2)] sm:flex" aria-hidden="true">
          {icon}
        </span>
        <span className="tabular font-display text-4xl leading-none font-light tracking-tight text-[var(--color-ink)] sm:text-5xl xl:text-6xl">
          {value}
          {unit && <span className="ml-1 text-base font-normal text-[var(--color-mute)] sm:text-lg">{unit}</span>}
        </span>
      </div>
      <div className="mt-2 text-sm text-[var(--color-mute)]">{label}</div>
    </div>
  );
}

interface Caption {
  icon: IconKind;
  title: string;
  sub: string;
  /** calm while running, alert under grid stress, night for the blackout. */
  mood: Mood;
}

export default function GridView({ onOpenStation }: GridViewProps) {
  const reducedMotion = usePrefersReducedMotion();
  const tl = useGridTimeline(!reducedMotion);
  const phases = PHASES[tl.mode];
  // The current chapter fills on the same clock as the timeline hook. Resuming
  // restarts the phase timer there, so `runId` restarts the fill with it; a
  // jump shows the phase's end state, so `ended` shows it full.
  const [runId, setRunId] = useState(0);
  const [ended, setEnded] = useState(false);
  const { toggle: tlToggle, jump: tlJump, pickMode: tlPickMode, playing } = tl;
  const toggle = useCallback(() => {
    if (!playing) {
      setRunId((r) => r + 1);
      setEnded(false);
    }
    tlToggle();
  }, [playing, tlToggle]);
  const jumpTo = useCallback(
    (i: number) => {
      setEnded(true);
      tlJump(i);
    },
    [tlJump],
  );
  const pickMode = useCallback(
    (m: Mode) => {
      setEnded(false);
      tlPickMode(m);
    },
    [tlPickMode],
  );

  // Space toggles playback, arrow keys step through phases, when focus is not in a control.
  const lastPhase = phases.length - 1;
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const t = e.target as HTMLElement | null;
      if (t && (t.closest('button, input, select, textarea, [role="tab"]') || t.isContentEditable)) return;
      if (e.key === ' ') {
        e.preventDefault();
        toggle();
      } else if (e.key === 'ArrowRight') jumpTo(Math.min(tl.phaseIndex + 1, lastPhase));
      else if (e.key === 'ArrowLeft') jumpTo(Math.max(tl.phaseIndex - 1, 0));
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [toggle, jumpTo, tl.phaseIndex, lastPhase]);

  const { sync, stag, peakSync, peakStag, reduction, waveCounts } = useMemo(() => {
    const { sync, stag } = rebound(N_CHARGERS, KW);
    const hist = delayHistogram(N_CHARGERS);
    const peakSync = Math.max(...sync);
    const peakStag = Math.max(...stag);
    return {
      sync,
      stag,
      peakSync,
      peakStag,
      reduction: peakSync / peakStag,
      waveCounts: Array.from({ length: STAGGER_WAVES }, (_, w) => hist[HOLD_BASE + w] ?? 0),
    };
  }, []);

  const caption = useMemo((): Caption => {
    const fleetMw = (N_CHARGERS * KW) / 1000;
    const byPhase: Record<Phase, Caption> = {
      normal: { icon: 'bolt', title: `${N_CHARGERS.toLocaleString()} chargers, ${fleetMw.toFixed(1)} MW`, sub: 'No central controller.', mood: 'calm' },
      dip: { icon: 'alert', title: `Grid drops below ${(F_LOW / 100).toFixed(2)} Hz`, sub: 'Every charger sees it in the same frame.', mood: 'alert' },
      hold: { icon: 'pause', title: 'All pause', sub: `${fleetMw.toFixed(1)} MW off the grid. That part is good.`, mood: 'alert' },
      surge: {
        icon: 'alert',
        title: tl.attempt > 1 ? `Retry ${tl.attempt}: all restart at once` : 'All restart at once',
        sub: `${peakSync.toFixed(2)} MW lands in a single frame.`,
        mood: 'alert',
      },
      rebound: { icon: 'syncBroken', title: 'Grid dips again', sub: 'A step that large can pull frequency back down, and the cycle repeats.', mood: 'alert' },
      reboot: tl.rebootFailed
        ? {
            icon: 'syncBroken',
            title: `Reboot failed · attempt ${tl.attempt}`,
            sub: tl.attempt < MAX_ATTEMPTS ? 'Same fixed delay, same spike. Back to "All paused" to try again.' : 'It never settles: every retry lands on the same frame.',
            mood: 'night',
          }
        : { icon: 'sync', title: `Rebooting · attempt ${tl.attempt}`, sub: 'Every charger counts the same fixed delay again.', mood: 'alert' },
      stagger: { icon: 'sync', title: `Wave ${tl.wave + 1} of ${STAGGER_WAVES}`, sub: `${waveCounts[tl.wave]} chargers reconnect.`, mood: 'calm' },
      recovered: { icon: 'check', title: 'Back to normal', sub: `Peak step ${peakStag.toFixed(2)} MW, not ${peakSync.toFixed(2)}.`, mood: 'calm' },
    };
    return byPhase[tl.phase];
  }, [tl.phase, tl.wave, tl.attempt, tl.rebootFailed, waveCounts, peakStag, peakSync]);

  let stepMw = 0;
  if (tl.phase === 'surge') stepMw = peakSync;
  else if (tl.phase === 'stagger') stepMw = stag[HOLD_BASE + tl.wave] ?? 0;

  let highlightFrame: number | undefined;
  if (tl.phase === 'stagger') highlightFrame = HOLD_BASE + tl.wave;
  else if (tl.phase === 'surge' || tl.phase === 'rebound' || tl.phase === 'reboot' || tl.phase === 'recovered') highlightFrame = sync.length - 1;
  else highlightFrame = -1;

  const pillText = (p: Phase, current: boolean, ms: number) => {
    if (p === 'stagger') return current ? `wave ${tl.wave + 1}/${STAGGER_WAVES}` : `${STAGGER_WAVES} waves`;
    if (p === 'surge') return `${peakSync.toFixed(1)} MW in 1 frame`;
    if (p === 'reboot') return current ? `attempt ${tl.attempt}/${MAX_ATTEMPTS}` : 'back to paused';
    return `${(ms / 1000).toFixed(1)} s`;
  };

  const currentMs = phases[tl.phaseIndex].ms;
  const fillKey = `${tl.mode}-${tl.phaseIndex}-${tl.attempt}-${tl.wave}-${tl.rebootFailed}-${runId}`;
  let fill: CurrentFill;
  if (ended && !tl.playing) fill = { from: 1, to: 1, ms: 0, key: fillKey };
  else if (tl.phase === 'stagger') fill = { from: tl.wave / STAGGER_WAVES, to: (tl.wave + 1) / STAGGER_WAVES, ms: WAVE_MS, key: fillKey };
  else if (tl.phase === 'reboot') {
    const split = REBOOT_TRY_MS / currentMs;
    fill = tl.rebootFailed ? { from: split, to: 1, ms: currentMs - REBOOT_TRY_MS, key: fillKey } : { from: 0, to: split, ms: REBOOT_TRY_MS, key: fillKey };
  } else fill = { from: 0, to: 1, ms: currentMs, key: fillKey };
  fill.paused = !tl.playing;

  return (
    <div className="flex flex-col gap-8">
      <header className="flex flex-col gap-8 xl:flex-row xl:items-end xl:justify-between">
        <div className="max-w-2xl">
          <p className="text-sm text-[var(--color-mute)]">{N_CHARGERS.toLocaleString()} chargers · one grid dip</p>
          <h1 className="mt-2 font-display text-4xl leading-[1.05] font-light tracking-tight text-balance text-[var(--color-ink)] md:text-6xl">
            Back in waves, not all at once
          </h1>
          <p className="mt-4 text-lg text-[var(--color-ink-2)]">No network, no coordinator. Each charger picks its own restart slot.</p>
        </div>
        <div className="grid shrink-0 grid-cols-3 gap-5 md:gap-10">
          <Stat icon={<TrendingDown size={15} />} value={`${reduction.toFixed(2)}×`} label="smaller spike" />
          <Stat icon={<Zap size={15} />} value={peakStag.toFixed(2)} unit="MW" label={`peak step, was ${peakSync.toFixed(2)}`} />
          <Stat icon={<MessageSquareOff size={15} />} value="0" label="messages sent" />
        </div>
      </header>

      <div className="grid grid-cols-1 gap-5 xl:grid-cols-12">
        {/* City diorama */}
        <section aria-label="City simulation" className="relative overflow-hidden rounded-[28px] xl:col-span-12" style={{ boxShadow: '0 30px 60px -36px rgba(70,58,20,0.38)' }}>
          <SceneBackdrop mood={caption.mood} />
          <FleetHandoff interlude={tl.interlude} peakSyncMw={peakSync} peakStagMw={peakStag} chargers={N_CHARGERS} onSkip={tl.skipInterlude} />
          <span
            className={`absolute top-5 left-5 z-10 rounded-full px-3 py-1.5 text-xs font-semibold ${
              tl.mode === 'without' ? 'bg-[var(--color-bad)] text-white' : 'bg-[var(--color-accent)] text-[var(--color-ink)]'
            }`}
          >
            {tl.mode === 'without' ? 'Without RVBL-2' : 'With RVBL-2'}
          </span>
          <div className="relative h-[480px] sm:h-[620px] xl:h-[720px]">
            <div className="absolute inset-0" aria-hidden="true">
              <CityScene phase={tl.phase} wave={tl.wave} icon={caption.icon} attempt={tl.attempt} rebootFailed={tl.rebootFailed} stepMw={stepMw} mood={caption.mood} />
            </div>
            {/* Caption floats in the empty corner below the plinth, so the town gets the full scene height. */}
            <div className="pointer-events-none absolute bottom-0 left-0 z-10 max-w-[min(36rem,92%)] px-6 pb-5" aria-live="polite">
              {/* Keyed so each new caption fades in rather than swapping in place. */}
              <p key={caption.title} className={`fade-rise font-display text-2xl font-semibold transition-colors duration-700 md:text-3xl ${MOOD_TEXT[caption.mood].title}`}>
                {caption.title}
              </p>
              <p key={`sub:${caption.sub}`} className={`fade-rise mt-1.5 min-h-5 text-sm transition-colors duration-700 ${MOOD_TEXT[caption.mood].sub}`}>
                {caption.sub}
              </p>
            </div>
          </div>

          {/* Player bar: which fleet, and where in the event */}
          <div className="relative z-10 bg-[#1E1F22]/92 px-6 pt-5 pb-5 backdrop-blur-sm">
            <div className="flex flex-col gap-3">
              <TimelineTrack
                chapters={phases.map((p) => ({ key: p.phase, label: p.label, weight: p.ms, color: PHASE_COLOR[p.phase] }))}
                current={tl.phaseIndex}
                fill={fill}
                onPick={(c) => jumpTo(c)}
                hoverLabel={(c) => `${phases[c].label} · ${pillText(phases[c].phase, c === tl.phaseIndex, phases[c].ms)}`}
                ariaLabel="Grid event phase"
                ariaValueNow={tl.phaseIndex + 1}
                ariaValueMax={phases.length}
                ariaValueText={`${phases[tl.phaseIndex].label}, phase ${tl.phaseIndex + 1} of ${phases.length}`}
              />
              <div className="mt-1 flex flex-wrap items-center gap-2">
                <PlayerButton label={tl.playing ? 'Pause' : 'Play'} onClick={toggle} primary>
                  {tl.playing ? <Pause size={20} fill="currentColor" /> : <Play size={20} fill="currentColor" className="ml-0.5" />}
                </PlayerButton>
                <PlayerButton label="Previous phase" onClick={() => jumpTo(Math.max(0, tl.phaseIndex - 1))} disabled={tl.phaseIndex === 0}>
                  <SkipBack size={16} />
                </PlayerButton>
                <PlayerButton label="Next phase" onClick={() => jumpTo(Math.min(lastPhase, tl.phaseIndex + 1))} disabled={tl.phaseIndex === lastPhase}>
                  <SkipForward size={16} />
                </PlayerButton>
                <PlayerButton label="Restart" onClick={() => jumpTo(0)}>
                  <RotateCcw size={16} />
                </PlayerButton>

                <span className="ml-2 font-mono text-sm text-white tabular">
                  {String(tl.phaseIndex + 1).padStart(2, '0')}
                  <span className="text-white/45"> / {String(phases.length).padStart(2, '0')}</span>
                </span>
                <span className="truncate font-mono text-xs text-white/55">{pillText(tl.phase, true, currentMs)}</span>

                <div className="ml-auto flex items-center gap-3">
                  <span className="hidden text-xs text-white/45 md:inline">Space · ← →</span>
                  <div role="radiogroup" aria-label="Restart strategy" className="flex rounded-full bg-white/10 p-1">
                    {MODES.map((m) => {
                      const on = tl.mode === m.mode;
                      return (
                        <button
                          key={m.mode}
                          type="button"
                          role="radio"
                          aria-checked={on}
                          onClick={() => pickMode(m.mode)}
                          className={`min-h-9 cursor-pointer rounded-full px-4 text-sm font-medium transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white ${
                            on
                              ? m.mode === 'without'
                                ? 'bg-[var(--color-bad)] text-white'
                                : 'bg-[var(--color-accent)] text-[var(--color-ink)]'
                              : 'text-white/70 hover:text-white'
                          }`}
                        >
                          {m.label}
                        </button>
                      );
                    })}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <div className="xl:col-span-7">
          <ComparisonCard mode={tl.mode} sync={sync} stag={stag} highlightFrame={highlightFrame} onPick={pickMode} />
        </div>

        <section aria-labelledby="why-label" className="rounded-[28px] bg-[var(--color-dark)] p-6 text-white md:p-8 xl:col-span-5">
          <h2 id="why-label" className="font-display text-xl font-medium">
            How it works
          </h2>
          <ol className="mt-6 flex flex-col gap-5">
            {[
              { t: 'Same event, same seed', d: "Every charger receives the trigger frame's CRC-16." },
              {
                t: 'Hash your own ID',
                d: (
                  <code className="rounded-md bg-white/10 px-1.5 py-0.5 font-mono text-[12px] text-white">delay = 2 + (CRC16(ID, seed) &amp; 7)</code>
                ),
              },
              { t: 'Land in 1 of 8 slots', d: 'Spread evenly. No clock, no network.' },
            ].map((s, i) => (
              <li key={s.t} className="flex gap-4">
                <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-[var(--color-accent)] font-mono text-sm font-semibold text-[var(--color-dark)]">
                  {i + 1}
                </span>
                <div>
                  <p className="font-medium text-white">{s.t}</p>
                  <p className="mt-1 text-sm leading-relaxed text-white/65">{s.d}</p>
                </div>
              </li>
            ))}
          </ol>
          <button
            type="button"
            onClick={() => onOpenStation('S2')}
            className="mt-7 inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-full bg-white px-5 text-sm font-semibold text-[var(--color-dark)] transition-colors duration-200 hover:bg-[var(--color-accent)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-accent)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--color-dark)]"
          >
            Watch one charger
            <ArrowRight size={16} aria-hidden="true" />
          </button>
        </section>

        <div className="xl:col-span-12">
          <DelayHistogram />
        </div>
      </div>
    </div>
  );
}
