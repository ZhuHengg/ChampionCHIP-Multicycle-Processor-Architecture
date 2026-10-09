// Fleet page. Same 1,000 chargers, same grid dip, played twice: first with a
// fixed restart delay (everyone reconnects at once), then with RVBL-2's
// CRC-hashed delay. The comparison card puts both on one scale.

import { useMemo } from 'react';
import type { ReactNode } from 'react';
import { ArrowRight, MessageSquareOff, Pause, Play, TrendingDown, Zap } from 'lucide-react';
import { delayHistogram, rebound } from '../../data/rebound';
import { F_LOW, HOLD_BASE } from '../../data/constants';
import CityScene from './CityScene';
import ComparisonCard from './ComparisonCard';
import DelayHistogram from './DelayHistogram';
import { PHASES, STAGGER_WAVES, useGridTimeline } from './GridTimeline';
import type { Mode, Phase } from './GridTimeline';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import type { IconKind } from '../station/stationStory';

const N_CHARGERS = 1000;
const KW = 7;

const PHASE_PILL: Record<Phase, string> = {
  normal: 'bg-[var(--color-dark)] text-white',
  dip: 'bg-[var(--color-bad)] text-white',
  hold: 'hatch border border-[var(--color-line-strong)] bg-white/40 text-[var(--color-ink)]',
  stagger: 'bg-[var(--color-accent)] text-[var(--color-ink)]',
  recovered: 'border border-[var(--color-line-strong)] text-[var(--color-ink-2)]',
  surge: 'bg-[var(--color-bad)] text-white',
  rebound: 'border-2 border-[var(--color-bad)] text-[var(--color-bad)]',
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
  backdrop: 'navy' | 'charcoal';
}

export default function GridView({ onOpenStation }: GridViewProps) {
  const reducedMotion = usePrefersReducedMotion();
  const tl = useGridTimeline(!reducedMotion);
  const phases = PHASES[tl.mode];

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
      normal: { icon: 'bolt', title: `${N_CHARGERS.toLocaleString()} chargers, ${fleetMw.toFixed(1)} MW`, sub: 'No central controller.', backdrop: 'navy' },
      dip: { icon: 'alert', title: `Grid drops below ${(F_LOW / 100).toFixed(2)} Hz`, sub: 'Every charger sees it in the same frame.', backdrop: 'charcoal' },
      hold: { icon: 'pause', title: 'All pause', sub: `${fleetMw.toFixed(1)} MW off the grid. That part is good.`, backdrop: 'charcoal' },
      surge: { icon: 'alert', title: 'All restart at once', sub: `${peakSync.toFixed(2)} MW lands in a single frame.`, backdrop: 'charcoal' },
      rebound: { icon: 'syncBroken', title: 'Grid dips again', sub: 'A step that large can pull frequency back down, and the cycle repeats.', backdrop: 'charcoal' },
      stagger: { icon: 'sync', title: `Wave ${tl.wave + 1} of ${STAGGER_WAVES}`, sub: `${waveCounts[tl.wave]} chargers reconnect.`, backdrop: 'navy' },
      recovered: { icon: 'check', title: 'Back to normal', sub: `Peak step ${peakStag.toFixed(2)} MW, not ${peakSync.toFixed(2)}.`, backdrop: 'navy' },
    };
    return byPhase[tl.phase];
  }, [tl.phase, tl.wave, waveCounts, peakStag, peakSync]);

  let highlightFrame: number | undefined;
  if (tl.phase === 'stagger') highlightFrame = HOLD_BASE + tl.wave;
  else if (tl.phase === 'surge' || tl.phase === 'rebound' || tl.phase === 'recovered') highlightFrame = sync.length - 1;
  else highlightFrame = -1;

  const pillText = (p: Phase, current: boolean, ms: number) => {
    if (p === 'stagger') return current ? `wave ${tl.wave + 1}/${STAGGER_WAVES}` : `${STAGGER_WAVES} waves`;
    if (p === 'surge') return `${peakSync.toFixed(1)} MW in 1 frame`;
    return `${(ms / 1000).toFixed(1)} s`;
  };

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

      {/* Which fleet, and where in the event: doubles as the playback control */}
      <section aria-label="Grid event" className="flex flex-col gap-4">
        <div className="flex items-center gap-3">
          <button
            type="button"
            onClick={tl.toggle}
            aria-label={tl.playing ? 'Pause' : 'Play'}
            className="flex h-12 w-12 shrink-0 cursor-pointer items-center justify-center rounded-full bg-[var(--color-dark)] text-white transition-colors duration-200 hover:bg-black focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)] focus-visible:ring-offset-2"
          >
            {tl.playing ? <Pause size={18} fill="currentColor" /> : <Play size={18} fill="currentColor" className="ml-0.5" />}
          </button>
          <div role="radiogroup" aria-label="Restart strategy" className="flex rounded-full border border-white bg-white/60 p-1 shadow-sm backdrop-blur">
            {MODES.map((m) => {
              const on = tl.mode === m.mode;
              return (
                <button
                  key={m.mode}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  onClick={() => tl.pickMode(m.mode)}
                  className={`min-h-10 cursor-pointer rounded-full px-4 text-sm font-medium transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)] ${
                    on ? (m.mode === 'without' ? 'bg-[var(--color-bad)] text-white' : 'bg-[var(--color-dark)] text-white') : 'text-[var(--color-ink-2)] hover:text-[var(--color-ink)]'
                  }`}
                >
                  {m.label}
                </button>
              );
            })}
          </div>
        </div>
        <div className="-mx-1 overflow-x-auto px-1 pt-1 pb-2">
          <ol className="flex min-w-[560px] items-end gap-1.5">
            {phases.map((p, i) => {
              const current = i === tl.phaseIndex;
              const future = i > tl.phaseIndex;
              return (
                <li key={p.phase} className="basis-0" style={{ flexGrow: p.ms }}>
                  <button
                    type="button"
                    onClick={() => tl.jump(i)}
                    aria-current={current ? 'step' : undefined}
                    className="group block w-full cursor-pointer text-left focus-visible:outline-none"
                  >
                    <span className={`mb-2 block truncate pl-1 text-sm ${current ? 'font-semibold text-[var(--color-ink)]' : 'text-[var(--color-mute)] group-hover:text-[var(--color-ink)]'}`}>
                      {p.label}
                    </span>
                    <span
                      className={`flex h-12 items-center truncate rounded-full px-4 font-mono text-xs transition-opacity duration-300 group-focus-visible:ring-2 group-focus-visible:ring-[var(--color-ink)] ${PHASE_PILL[p.phase]} ${
                        future ? 'opacity-35' : ''
                      } ${current ? 'shadow-[0_0_0_3px_var(--color-page),0_0_0_5px_var(--color-ink)]' : ''}`}
                    >
                      {pillText(p.phase, current, p.ms)}
                    </span>
                  </button>
                </li>
              );
            })}
          </ol>
        </div>
      </section>

      <div className="grid grid-cols-1 gap-5 xl:grid-cols-12">
        {/* City diorama */}
        <section aria-label="City simulation" className="relative overflow-hidden rounded-[28px] xl:col-span-7" style={{ boxShadow: '0 30px 60px -34px rgba(20,24,40,0.55)' }}>
          <div
            className="absolute inset-0 transition-opacity duration-700"
            style={{ background: 'radial-gradient(120% 90% at 50% 30%, #12408F 0%, #0A2A66 45%, #061C47 100%)', opacity: caption.backdrop === 'navy' ? 1 : 0 }}
          />
          <div
            className="absolute inset-0 transition-opacity duration-700"
            style={{ background: 'radial-gradient(120% 90% at 50% 30%, #34363B 0%, #232427 45%, #141517 100%)', opacity: caption.backdrop === 'charcoal' ? 1 : 0 }}
          />
          <span
            className={`absolute top-5 left-5 z-10 rounded-full px-3 py-1.5 text-xs font-semibold ${
              tl.mode === 'without' ? 'bg-[var(--color-bad)] text-white' : 'bg-[var(--color-accent)] text-[var(--color-ink)]'
            }`}
          >
            {tl.mode === 'without' ? 'Without RVBL-2' : 'With RVBL-2'}
          </span>
          <div className="relative h-[360px] sm:h-[420px]" aria-hidden="true">
            <CityScene phase={tl.phase} wave={tl.wave} icon={caption.icon} />
          </div>
          <div className="relative px-6 pb-6" aria-live="polite">
            <p className="font-display text-2xl font-semibold text-white md:text-3xl">{caption.title}</p>
            <p className="mt-1.5 min-h-5 text-sm text-white/65">{caption.sub}</p>
          </div>
        </section>

        <div className="xl:col-span-5">
          <ComparisonCard mode={tl.mode} sync={sync} stag={stag} highlightFrame={highlightFrame} onPick={tl.pickMode} />
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

        <div className="xl:col-span-7">
          <DelayHistogram />
        </div>
      </div>
    </div>
  );
}
