// The dark card: every decision the chip made, as a checklist. Only the
// current step is expanded with its verdict and state change; the rest stay
// one line so the card reads at a glance.

import { useEffect, useRef } from 'react';
import { ArrowRight, Check, OctagonAlert, Plug, Radio, Receipt, Timer, X } from 'lucide-react';
import { ChargerState, SAFETY } from '../../data/constants';
import { STATE_LABEL, TONE_COLOR } from './stationStory';
import type { PlayStep } from './stationStory';

// State colours bright enough to read on the dark card.
const ON_DARK: Record<ChargerState, string> = {
  [ChargerState.IDLE]: '#B9B4A8',
  [ChargerState.CONNECTED]: '#8DB6FF',
  [ChargerState.CHARGING]: '#F2C230',
  [ChargerState.GRID_HOLD]: '#F2B134',
  [ChargerState.FAULT]: '#FF6B6F',
  [ChargerState.METER_TIMEOUT]: '#FF9A55',
};

function StepIcon({ step }: { step: PlayStep }) {
  const size = 16;
  if (step.kind === 'frame') return <Radio size={size} aria-hidden="true" />;
  if (step.kind === 'time') return <Timer size={size} aria-hidden="true" />;
  if (step.kind === 'record') return <Receipt size={size} aria-hidden="true" />;
  if ((step.raw.value ?? 0) & SAFETY) return <OctagonAlert size={size} aria-hidden="true" />;
  return <Plug size={size} aria-hidden="true" />;
}

function Outcome({ step, done, current }: { step: PlayStep; done: boolean; current: boolean }) {
  if (!done && !current) return <span className="h-5 w-5 rounded-full bg-white/10" aria-hidden="true" />;
  const bad = step.verdict?.tone === 'bad';
  if (current)
    return (
      <span className="flex h-5 w-5 items-center justify-center rounded-full ring-2 ring-[var(--color-accent)]" aria-hidden="true">
        <span className="h-2 w-2 rounded-full bg-[var(--color-accent)]" />
      </span>
    );
  return (
    <span
      className={`flex h-5 w-5 items-center justify-center rounded-full ${bad ? 'bg-[#FF6B6F] text-white' : 'bg-[var(--color-accent)] text-[var(--color-dark)]'}`}
      aria-hidden="true"
    >
      {bad ? <X size={12} strokeWidth={3} /> : <Check size={12} strokeWidth={3} />}
    </span>
  );
}

interface StepTimelineProps {
  steps: PlayStep[];
  index: number;
  onJump: (index: number) => void;
}

export default function StepTimeline({ steps, index, onJump }: StepTimelineProps) {
  const listRef = useRef<HTMLOListElement>(null);

  // Keep the current step visible inside the card without scrolling the page.
  useEffect(() => {
    const list = listRef.current;
    const item = list?.children[index] as HTMLElement | undefined;
    if (!list || !item) return;
    // The list is absolutely positioned, so it is each item's offsetParent.
    const top = item.offsetTop;
    const bottom = top + item.offsetHeight;
    if (top < list.scrollTop + 8) list.scrollTo({ top: Math.max(0, top - 8), behavior: 'smooth' });
    else if (bottom > list.scrollTop + list.clientHeight - 8) list.scrollTo({ top: bottom - list.clientHeight + 8, behavior: 'smooth' });
  }, [index]);

  return (
    <ol ref={listRef} className="absolute inset-0 flex flex-col gap-1 overflow-y-auto px-3 pb-3 [scrollbar-color:#55555a_transparent]" aria-label="Scenario steps">
      {steps.map((step, i) => {
        const current = i === index;
        const done = i < index;
        const changed = step.stateAfter !== step.stateBefore;
        return (
          <li key={i}>
            <button
              type="button"
              onClick={() => onJump(i)}
              aria-current={current ? 'step' : undefined}
              className={`flex w-full cursor-pointer items-start gap-3 rounded-2xl px-3 py-2.5 text-left transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-accent)] ${
                current ? 'bg-white/[0.08]' : 'hover:bg-white/[0.04]'
              }`}
            >
              <span
                className={`flex h-10 w-10 shrink-0 items-center justify-center rounded-full transition-colors duration-200 ${
                  current ? 'bg-white text-[var(--color-dark)]' : 'bg-white/[0.07] text-white/70'
                }`}
              >
                <StepIcon step={step} />
              </span>
              <span className="min-w-0 flex-1 pt-0.5">
                <span className={`block text-sm leading-snug ${current ? 'font-semibold text-white' : done ? 'text-white/75' : 'text-white/40'}`}>{step.title}</span>
                <span className={`mt-0.5 block truncate font-mono text-[11px] ${current ? 'text-white/65' : 'text-white/35'}`}>{step.detail}</span>
                {current && step.verdict && (
                  <span className="mt-2 block text-[13px] leading-snug font-medium" style={{ color: TONE_COLOR[step.verdict.tone] }}>
                    {step.verdict.text}
                  </span>
                )}
                {current && changed && (
                  <span className="mt-2 flex items-center gap-1.5 text-xs font-semibold">
                    <span style={{ color: ON_DARK[step.stateBefore] }}>{STATE_LABEL[step.stateBefore]}</span>
                    <ArrowRight size={12} className="text-white/50" aria-hidden="true" />
                    <span style={{ color: ON_DARK[step.stateAfter] }}>{STATE_LABEL[step.stateAfter]}</span>
                  </span>
                )}
              </span>
              <span className="pt-2.5">
                <Outcome step={step} done={done} current={current} />
              </span>
            </button>
          </li>
        );
      })}
    </ol>
  );
}
