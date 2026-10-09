// The dark card as a terminal: the chip's decisions printed one line at a
// time, down a vertical timeline rail. A step appears only once playback
// reaches it, so the log grows with the story and follows the newest line
// like a terminal; stepping back removes the lines after it. The newest line
// carries its verdict and state change.

import { useEffect, useRef } from 'react';
import { ChargerState, SAFETY } from '../../data/constants';
import { STATE_LABEL, TONE_COLOR } from './stationStory';
import type { PlayStep } from './stationStory';

// State colours bright enough to read on the dark card.
const ON_DARK: Record<ChargerState, string> = {
  [ChargerState.IDLE]: '#B9B4A8',
  [ChargerState.CONNECTED]: '#8DB6FF',
  [ChargerState.CHARGING]: '#3CCF5A',
  [ChargerState.GRID_HOLD]: '#F2B134',
  [ChargerState.FAULT]: '#FF6B6F',
  [ChargerState.METER_TIMEOUT]: '#FF9A55',
};

function tagOf(step: PlayStep): string {
  if (step.kind === 'frame') return 'meter';
  if (step.kind === 'time') return 'clock';
  if (step.kind === 'record') return 'uart';
  return (step.raw.value ?? 0) & SAFETY ? 'safety' : 'pilot';
}

interface ChipLogProps {
  steps: PlayStep[];
  scenarioId: string;
  index: number;
  playing: boolean;
  onJump: (index: number) => void;
}

export default function ChipLog({ steps, scenarioId, index, playing, onJump }: ChipLogProps) {
  const scrollRef = useRef<HTMLDivElement>(null);
  const shown = steps.slice(0, index + 1);
  const done = index >= steps.length - 1;

  // Follow the newest line, scrolling inside the card only.
  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
  }, [index]);

  return (
    <div ref={scrollRef} className="absolute inset-0 overflow-y-auto px-5 pb-5 font-mono text-[12.5px] leading-relaxed [scrollbar-color:#55555a_transparent]">
      <p className="text-white/35">$ replay {scenarioId} · {steps.length} steps</p>

      <ol className="relative mt-3" aria-label="Chip decisions so far" aria-live="polite">
        {/* Rail */}
        <span className="absolute top-2 bottom-2 left-[5px] w-px bg-white/15" aria-hidden="true" />
        {shown.map((step, i) => {
          const current = i === index;
          const changed = step.stateAfter !== step.stateBefore;
          const bad = step.verdict?.tone === 'bad';
          const node = bad ? '#FF6B6F' : ON_DARK[step.stateAfter];
          return (
            <li key={i} className="fade-rise relative pb-3 pl-6 last:pb-0">
              <span
                className="absolute top-[7px] left-0 h-[11px] w-[11px] rounded-full"
                style={{
                  backgroundColor: current ? node : 'var(--color-dark)',
                  boxShadow: `inset 0 0 0 2px ${node}${current ? '' : '99'}${current ? `, 0 0 10px ${node}` : ''}`,
                }}
                aria-hidden="true"
              />
              <button
                type="button"
                onClick={() => onJump(i)}
                aria-current={current ? 'step' : undefined}
                className={`-mx-2 block w-[calc(100%+1rem)] cursor-pointer rounded-lg px-2 py-0.5 text-left transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-accent)] ${
                  current ? 'bg-white/[0.06]' : 'hover:bg-white/[0.04]'
                }`}
              >
                <span className="flex items-baseline gap-2">
                  <span className="text-white/35">[{String(i + 1).padStart(2, '0')}]</span>
                  <span style={{ color: node }}>{tagOf(step)}</span>
                </span>
                <span className={`block ${current ? 'font-semibold text-white' : 'text-white/70'}`}>{step.title}</span>
                <span className={`block truncate ${current ? 'text-white/55' : 'text-white/30'}`}>{step.detail}</span>
                {current && step.verdict && (
                  <span className="block" style={{ color: TONE_COLOR[step.verdict.tone] }}>
                    {bad ? '✗' : '✓'} {step.verdict.text}
                  </span>
                )}
                {current && changed && (
                  <span className="block">
                    <span style={{ color: ON_DARK[step.stateBefore] }}>{STATE_LABEL[step.stateBefore]}</span>
                    <span className="text-white/40"> → </span>
                    <span style={{ color: ON_DARK[step.stateAfter] }}>{STATE_LABEL[step.stateAfter]}</span>
                  </span>
                )}
              </button>
            </li>
          );
        })}
      </ol>

      <p className="mt-3 text-white/45">
        {done ? (
          <>
            <span className="text-[var(--color-accent)]">●</span> scenario complete
          </>
        ) : (
          <>
            $ <span className={`inline-block h-[1.05em] w-[0.6em] translate-y-[2px] bg-white/70 ${playing ? 'caret-blink' : ''}`} aria-hidden="true" />
            {!playing && <span className="ml-2">paused</span>}
          </>
        )}
      </p>
    </div>
  );
}
