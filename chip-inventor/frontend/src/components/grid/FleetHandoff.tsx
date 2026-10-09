// Full-card interlude between the two fleets. Beat one is the verdict on the
// fixed-delay fleet, laid over the town it just failed; beat two hands over
// to RVBL-2 while the town resets behind the card. Both beats cross-fade, and
// the card fades out to reveal the new run. A Skip button ends it early.

import { useState } from 'react';
import { ArrowRight, ShieldCheck, X } from 'lucide-react';
import type { Interlude } from './GridTimeline';
import { HANDOFF_MS, MAX_ATTEMPTS } from './GridTimeline';

interface FleetHandoffProps {
  interlude: Interlude;
  peakSyncMw: number;
  peakStagMw: number;
  chargers: number;
  onSkip: () => void;
  /** Playback paused: freeze the handoff countdown with the timeline. */
  paused: boolean;
}

const FADE = 'absolute inset-0 transition-opacity duration-700 ease-out';

export default function FleetHandoff({ interlude, peakSyncMw, peakStagMw, chargers, onSkip, paused }: FleetHandoffProps) {
  // Keep the last beat on screen while the card fades out.
  const [beat, setBeat] = useState<Exclude<Interlude, null>>('verdict');
  if (interlude && interlude !== beat) setBeat(interlude);
  const open = interlude !== null;

  return (
    <div
      className={`absolute inset-0 z-30 overflow-hidden transition-opacity duration-500 ${open ? 'opacity-100' : 'pointer-events-none opacity-0'}`}
      role="status"
      aria-live="polite"
      aria-hidden={!open}
    >
      {/* Verdict field: failed town seen through smoked, red-lit glass */}
      <div
        className={`${FADE} backdrop-blur-md`}
        style={{
          background:
            'radial-gradient(60% 55% at 50% 38%, rgba(255,90,95,0.30) 0%, rgba(255,90,95,0) 70%), linear-gradient(180deg, rgba(28,20,26,0.78) 0%, rgba(20,18,26,0.86) 100%)',
          opacity: beat === 'verdict' ? 1 : 0,
        }}
      />
      {/* Handoff field: warm paper with the accent glow */}
      <div
        className={`${FADE} backdrop-blur-md`}
        style={{
          background:
            'radial-gradient(55% 50% at 50% 36%, rgba(242,194,48,0.40) 0%, rgba(242,194,48,0) 70%), linear-gradient(180deg, rgba(250,246,236,0.86) 0%, rgba(244,239,228,0.92) 100%)',
          opacity: beat === 'handoff' ? 1 : 0,
        }}
      />

      <div className="relative flex h-full flex-col items-center justify-center px-6 text-center">
        {open && beat === 'verdict' && (
          <div key="verdict" className="flex max-w-2xl flex-col items-center">
            <span className="handoff-pop flex h-20 w-20 items-center justify-center rounded-full bg-[var(--color-bad)] text-white shadow-[0_0_0_10px_rgba(255,90,95,0.18),0_18px_40px_-12px_rgba(217,63,68,0.8)]">
              <X size={40} strokeWidth={3} aria-hidden="true" />
            </span>
            <span className="fade-rise mt-6 rounded-full bg-[var(--color-bad)] px-3 py-1 text-xs font-semibold tracking-wide text-white uppercase" style={{ animationDelay: '120ms' }}>
              Without RVBL-2 · failed
            </span>
            <h3 className="fade-rise mt-4 font-display text-4xl font-semibold tracking-tight text-balance text-white md:text-6xl" style={{ animationDelay: '220ms' }}>
              The grid never settles
            </h3>
            <p className="fade-rise mt-3 max-w-lg text-base text-white/70 md:text-lg" style={{ animationDelay: '320ms' }}>
              Every retry brings all {chargers.toLocaleString()} chargers back on the same frame, and the dip comes straight back.
            </p>
            <dl className="mt-8 grid w-full max-w-xl grid-cols-3 gap-3">
              {[
                { v: String(MAX_ATTEMPTS), l: 'restart attempts' },
                { v: `${peakSyncMw.toFixed(2)} MW`, l: 'in one frame, each time' },
                { v: '0', l: 'recoveries' },
              ].map((s, i) => (
                <div
                  key={s.l}
                  className="fade-rise rounded-2xl bg-white/[0.07] px-3 py-4 ring-1 ring-white/10"
                  style={{ animationDelay: `${440 + i * 110}ms` }}
                >
                  <dt className="sr-only">{s.l}</dt>
                  <dd className="tabular font-display text-2xl font-semibold text-[#FF8A8D] md:text-3xl">{s.v}</dd>
                  <dd className="mt-1 text-xs text-white/60 md:text-sm">{s.l}</dd>
                </div>
              ))}
            </dl>
          </div>
        )}

        {open && beat === 'handoff' && (
          <div key="handoff" className="flex max-w-2xl flex-col items-center">
            <span className="handoff-pop flex h-20 w-20 items-center justify-center rounded-full bg-[var(--color-accent)] text-[var(--color-ink)] shadow-[0_0_0_10px_rgba(242,194,48,0.25),0_18px_40px_-12px_rgba(181,127,0,0.6)]">
              <ShieldCheck size={38} strokeWidth={2.4} aria-hidden="true" />
            </span>
            <span className="fade-rise mt-6 rounded-full bg-[var(--color-dark)] px-3 py-1 text-xs font-semibold tracking-wide text-white uppercase" style={{ animationDelay: '120ms' }}>
              Now · with RVBL-2
            </span>
            <h3 className="fade-rise mt-4 font-display text-4xl font-semibold tracking-tight text-balance text-[var(--color-ink)] md:text-6xl" style={{ animationDelay: '220ms' }}>
              Same dip. Same {chargers.toLocaleString()} chargers.
            </h3>
            <p className="fade-rise mt-3 max-w-lg text-base text-[var(--color-ink-2)] md:text-lg" style={{ animationDelay: '320ms' }}>
              Each charger hashes its own ID into 1 of 8 restart slots. Peak step drops to {peakStagMw.toFixed(2)} MW.
            </p>
            {/* Countdown to the replay */}
            <div className="fade-rise mt-8 h-1.5 w-full max-w-sm overflow-hidden rounded-full bg-[var(--color-ink)]/10" style={{ animationDelay: '420ms' }}>
              <div className="handoff-progress h-full rounded-full bg-[var(--color-accent)]" style={{ animationDuration: `${HANDOFF_MS}ms`, animationPlayState: paused ? 'paused' : 'running' }} />
            </div>
            <p className="fade-rise mt-2 text-xs text-[var(--color-mute)]" style={{ animationDelay: '420ms' }}>
              Replaying the event
            </p>
          </div>
        )}

        <button
          type="button"
          onClick={onSkip}
          tabIndex={open ? 0 : -1}
          className={`absolute right-5 bottom-5 inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-full px-4 text-sm font-semibold transition-colors duration-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 ${
            beat === 'verdict'
              ? 'bg-white/10 text-white ring-1 ring-white/15 hover:bg-white/20 focus-visible:ring-white focus-visible:ring-offset-transparent'
              : 'bg-[var(--color-dark)] text-white hover:bg-black focus-visible:ring-[var(--color-ink)]'
          }`}
        >
          {beat === 'verdict' ? 'Show RVBL-2' : 'Skip'}
          <ArrowRight size={16} aria-hidden="true" />
        </button>
      </div>
    </div>
  );
}
