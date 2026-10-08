// Fleet page. Leads with the result (how much smaller the restart spike is),
// then shows it happening in the city diorama, then explains why it works.

import { useMemo } from 'react';
import type { ReactNode } from 'react';
import { ArrowRight, Pause, Play } from 'lucide-react';
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

interface GridViewProps {
  onOpenStation: (scenarioId: string) => void;
}

function Kpi({ value, label, accent }: { value: ReactNode; label: string; accent?: boolean }) {
  return (
    <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-panel)] px-5 py-4">
      <div className={`tabular font-display text-3xl font-extrabold ${accent ? 'text-[var(--color-ok)]' : 'text-[var(--color-ink)]'}`}>{value}</div>
      <div className="mt-1 text-sm text-[var(--color-mute)]">{label}</div>
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
      <header className="max-w-4xl">
        <p className="mb-2 text-xs font-semibold uppercase tracking-[0.16em] text-[var(--color-ok)]">Fleet of {N_CHARGERS.toLocaleString()} chargers</p>
        <h1 className="font-display text-2xl font-extrabold leading-tight text-[var(--color-ink)] md:text-[2rem]">
          After a grid dip, the chargers come back in waves, not all at once.
        </h1>
        <p className="mt-3 text-base leading-relaxed text-[var(--color-ink-2)]">
          When the whole fleet reconnects in the same instant, the grid takes a load step big enough to trip it again. Each RVBL-2 picks its own restart
          slot from a CRC hash, so the fleet spreads itself out with no network and no coordinator.
        </p>
      </header>

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi value={`${reduction.toFixed(2)}×`} label="smaller restart spike" accent />
        <Kpi
          value={
            <>
              {peakStag.toFixed(2)} <span className="text-base font-bold text-[var(--color-mute)]">MW</span>
            </>
          }
          label={`largest step, vs ${peakSync.toFixed(2)} MW all at once`}
        />
        <Kpi value={STAGGER_WAVES} label="restart slots from one CRC" />
        <Kpi value="0" label="messages between chargers" />
      </div>

      <div className="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1.45fr)_minmax(0,1fr)]">
        {/* City diorama */}
        <section aria-label="City simulation" className="relative overflow-hidden rounded-2xl" style={{ boxShadow: '0 30px 60px -30px rgba(0,0,0,0.7)' }}>
          <div
            className="absolute inset-0 transition-opacity duration-700"
            style={{ background: 'radial-gradient(120% 90% at 50% 30%, #12408F 0%, #0A2A66 45%, #061C47 100%)', opacity: caption.backdrop === 'navy' ? 1 : 0 }}
          />
          <div
            className="absolute inset-0 transition-opacity duration-700"
            style={{ background: 'radial-gradient(120% 90% at 50% 30%, #34363B 0%, #232427 45%, #141517 100%)', opacity: caption.backdrop === 'charcoal' ? 1 : 0 }}
          />
          <div className="relative h-[380px] sm:h-[440px]" aria-hidden="true">
            <CityScene phase={tl.phase} wave={tl.wave} icon={caption.icon} />
          </div>
          <div className="relative px-6 text-center" aria-live="polite">
            <p className="font-display text-2xl font-extrabold text-white md:text-[1.9rem]">{caption.title}</p>
            <p className="mt-1.5 min-h-5 text-sm text-white/70">{caption.sub}</p>
          </div>
          <div className="relative flex items-center gap-3 px-5 pt-4 pb-5">
            <button
              type="button"
              onClick={tl.toggle}
              aria-label={tl.playing ? 'Pause' : 'Play'}
              className="flex h-12 w-12 shrink-0 cursor-pointer items-center justify-center rounded-full bg-white text-[#0A2A66] transition-colors duration-200 hover:bg-white/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70"
            >
              {tl.playing ? <Pause size={20} fill="currentColor" /> : <Play size={20} fill="currentColor" className="ml-0.5" />}
            </button>
            <div className="grid flex-1 grid-cols-5 gap-1.5" role="group" aria-label="Grid event phases">
              {PHASES.map((p, i) => {
                const current = i === tl.phaseIndex;
                const done = i < tl.phaseIndex;
                return (
                  <button
                    key={p.phase}
                    type="button"
                    onClick={() => tl.jump(i)}
                    aria-current={current ? 'step' : undefined}
                    className="group flex min-h-11 cursor-pointer flex-col justify-center gap-1.5 rounded-lg px-1 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/70"
                  >
                    <span className="h-1.5 w-full overflow-hidden rounded-full bg-white/15">
                      <span
                        className="block h-full rounded-full bg-white transition-[width] duration-500"
                        style={{
                          width: done ? '100%' : current ? (p.phase === 'stagger' ? `${((tl.wave + 1) / STAGGER_WAVES) * 100}%` : '100%') : '0%',
                          opacity: current ? 1 : 0.55,
                        }}
                      />
                    </span>
                    <span className={`truncate text-xs ${current ? 'font-semibold text-white' : 'text-white/60 group-hover:text-white/85'}`}>{p.label}</span>
                  </button>
                );
              })}
            </div>
          </div>
        </section>

        <ReboundChart highlightFrame={highlightFrame} nChargers={N_CHARGERS} />
      </div>

      <section aria-labelledby="why-label" className="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1.45fr)_minmax(0,1fr)]">
        <div className="rounded-2xl border border-[var(--color-line)] bg-[var(--color-panel)] p-6">
          <h2 id="why-label" className="font-display text-xl font-extrabold text-[var(--color-ink)]">
            Why it works with no coordination
          </h2>
          <ol className="mt-5 flex flex-col gap-5">
            {[
              {
                t: 'Everyone sees the same event',
                d: 'The meter frame that triggers the hold carries a CRC-16. Every charger on the feeder receives that same frame, so every charger holds the same number.',
              },
              {
                t: 'Each charger hashes its own ID',
                d: (
                  <>
                    Restart delay = <code className="rounded bg-white/[0.06] px-1.5 py-0.5 font-mono text-[13px] text-[var(--color-ink)]">2 + (CRC16(charger ID, seed = event CRC) &amp; 7)</code>{' '}
                    healthy frames. It costs one custom <code className="font-mono text-[13px] text-[var(--color-ink)]">crcb</code> instruction per byte.
                  </>
                ),
              },
              {
                t: 'Different IDs land in different slots',
                d: 'IDs differ, so delays scatter across 8 frames (right). The fleet spreads itself out with no clock, no network and no configuration.',
              },
            ].map((s, i) => (
              <li key={s.t} className="flex gap-4">
                <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-[var(--color-ok)]/15 font-mono text-sm font-semibold text-[var(--color-ok)]">
                  {i + 1}
                </span>
                <div>
                  <p className="font-medium text-[var(--color-ink)]">{s.t}</p>
                  <p className="mt-1 text-sm leading-relaxed text-[var(--color-ink-2)]">{s.d}</p>
                </div>
              </li>
            ))}
          </ol>
          <button
            type="button"
            onClick={() => onOpenStation('S2')}
            className="mt-6 inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-full bg-white px-5 text-sm font-semibold text-[#0A2A66] transition-colors duration-200 hover:bg-white/90 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ok)] focus-visible:ring-offset-2 focus-visible:ring-offset-[var(--color-panel)]"
          >
            See one charger do this (scenario S2)
            <ArrowRight size={16} aria-hidden="true" />
          </button>
        </div>
        <DelayHistogram />
      </section>
    </div>
  );
}
