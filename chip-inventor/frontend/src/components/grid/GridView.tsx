// Fleet page. Leads with the result (how much smaller the restart spike is),
// shows it happening in the city diorama next to the load chart, then
// explains why it works.

import { useMemo } from 'react';
import type { ReactNode } from 'react';
import { ArrowRight, MessageSquareOff, Pause, Play, TrendingDown, Zap } from 'lucide-react';
import { delayHistogram, rebound } from '../../data/rebound';
import { F_LOW, HOLD_BASE } from '../../data/constants';
import CityScene from './CityScene';
import ReboundChart from './ReboundChart';
import DelayHistogram from './DelayHistogram';
import { PHASES, STAGGER_WAVES, useGridTimeline } from './GridTimeline';
import type { Phase } from './GridTimeline';
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
};

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

  const { peakSync, peakStag, reduction, waveCounts } = useMemo(() => {
    const { sync, stag } = rebound(N_CHARGERS, KW);
    const hist = delayHistogram(N_CHARGERS);
    const peakSync = Math.max(...sync);
    const peakStag = Math.max(...stag);
    return {
      peakSync,
      peakStag,
      reduction: peakSync / peakStag,
      waveCounts: Array.from({ length: STAGGER_WAVES }, (_, w) => hist[HOLD_BASE + w] ?? 0),
    };
  }, []);

  const caption = useMemo((): Caption => {
    const fleetMw = (N_CHARGERS * KW) / 1000;
    const byPhase: Record<Phase, Caption> = {
      normal: { icon: 'bolt', title: `${N_CHARGERS.toLocaleString()} chargers drawing ${fleetMw.toFixed(1)} MW`, sub: 'Each one is an independent RVBL-2 chip. There is no central controller.', backdrop: 'navy' },
      dip: { icon: 'alert', title: `Grid frequency drops below ${(F_LOW / 100).toFixed(2)} Hz`, sub: 'Every meter reports the same dip in the same frame.', backdrop: 'charcoal' },
      hold: { icon: 'pause', title: 'Every charger pauses on its own', sub: `${fleetMw.toFixed(1)} MW leaves the grid at once, which is exactly what the grid needs.`, backdrop: 'charcoal' },
      stagger: {
        icon: 'sync',
        title: `Restart wave ${tl.wave + 1} of ${STAGGER_WAVES}`,
        sub: `${waveCounts[tl.wave]} chargers reconnect in this frame, each in a slot picked by hashing its own ID.`,
        backdrop: 'navy',
      },
      recovered: { icon: 'check', title: 'Load restored without a spike', sub: `Largest single step: ${peakStag.toFixed(2)} MW instead of ${peakSync.toFixed(2)} MW.`, backdrop: 'navy' },
    };
    return byPhase[tl.phase];
  }, [tl.phase, tl.wave, waveCounts, peakStag, peakSync]);

  const highlightFrame = tl.phase === 'stagger' ? HOLD_BASE + tl.wave : tl.phase === 'recovered' ? HOLD_BASE + STAGGER_WAVES - 1 : undefined;

  return (
    <div className="flex flex-col gap-8">
      <header className="flex flex-col gap-8 xl:flex-row xl:items-end xl:justify-between">
        <div className="max-w-2xl">
          <p className="text-sm text-[var(--color-mute)]">Fleet of {N_CHARGERS.toLocaleString()} chargers · one grid event</p>
          <h1 className="mt-2 font-display text-4xl leading-[1.05] font-light tracking-tight text-balance text-[var(--color-ink)] md:text-6xl">
            After a grid dip, chargers return in waves
          </h1>
          <p className="mt-4 max-w-xl text-lg leading-relaxed text-[var(--color-ink-2)]">
            If every charger reconnects in the same instant, the load step can trip the grid again. Each RVBL-2 picks its own restart slot from a CRC hash,
            with no network and no coordinator.
          </p>
        </div>
        <div className="grid shrink-0 grid-cols-3 gap-5 md:gap-10">
          <Stat icon={<TrendingDown size={15} />} value={`${reduction.toFixed(2)}×`} label="smaller restart spike" />
          <Stat icon={<Zap size={15} />} value={peakStag.toFixed(2)} unit="MW" label={`largest step, not ${peakSync.toFixed(1)}`} />
          <Stat icon={<MessageSquareOff size={15} />} value="0" label="messages between chargers" />
        </div>
      </header>

      {/* The event at a glance, doubling as the playback control */}
      <section aria-label="Grid event phases" className="flex items-end gap-3">
        <button
          type="button"
          onClick={tl.toggle}
          aria-label={tl.playing ? 'Pause' : 'Play'}
          className="flex h-12 w-12 shrink-0 cursor-pointer items-center justify-center rounded-full bg-[var(--color-dark)] text-white transition-colors duration-200 hover:bg-black focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)] focus-visible:ring-offset-2"
        >
          {tl.playing ? <Pause size={18} fill="currentColor" /> : <Play size={18} fill="currentColor" className="ml-0.5" />}
        </button>
        <div className="-mx-1 min-w-0 flex-1 overflow-x-auto px-1 pt-1 pb-2">
          <ol className="flex min-w-[520px] items-end gap-1.5">
            {PHASES.map((p, i) => {
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
                      {p.phase === 'stagger' ? (current ? `wave ${tl.wave + 1}/${STAGGER_WAVES}` : `${STAGGER_WAVES} waves`) : `${(p.ms / 1000).toFixed(1)} s`}
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
          <div className="relative h-[360px] sm:h-[420px]" aria-hidden="true">
            <CityScene phase={tl.phase} wave={tl.wave} icon={caption.icon} />
          </div>
          <div className="relative px-6 pb-6" aria-live="polite">
            <p className="font-display text-2xl font-semibold text-white md:text-3xl">{caption.title}</p>
            <p className="mt-1.5 min-h-5 text-sm text-white/65">{caption.sub}</p>
          </div>
        </section>

        <div className="xl:col-span-5">
          <ReboundChart highlightFrame={highlightFrame} nChargers={N_CHARGERS} />
        </div>

        <section aria-labelledby="why-label" className="rounded-[28px] bg-[var(--color-dark)] p-6 text-white md:p-8 xl:col-span-5">
          <h2 id="why-label" className="font-display text-xl font-medium">
            Why it works with no coordination
          </h2>
          <ol className="mt-6 flex flex-col gap-5">
            {[
              {
                t: 'Everyone sees the same event',
                d: 'The meter frame that triggers the hold carries a CRC-16. Every charger on the feeder receives that same frame, so every charger holds the same number.',
              },
              {
                t: 'Each charger hashes its own ID',
                d: (
                  <>
                    Delay = <code className="rounded-md bg-white/10 px-1.5 py-0.5 font-mono text-[12px] text-white">2 + (CRC16(ID, seed = event CRC) &amp; 7)</code> healthy
                    frames, one custom <code className="font-mono text-[12px] text-white">crcb</code> instruction per byte.
                  </>
                ),
              },
              {
                t: 'Different IDs land in different slots',
                d: 'Delays scatter evenly across 8 frames, so the fleet spreads itself out with no clock, no network and no configuration.',
              },
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
            Watch one charger do this
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
