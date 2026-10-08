import { useEffect, useRef } from 'react';
import { ArrowRight, OctagonAlert, Plug, Radio, Receipt, Timer } from 'lucide-react';
import { SAFETY, STATE_COLORS } from '../../data/constants';
import { STATE_LABEL, TONE_COLOR } from './stationStory';
import type { PlayStep } from './stationStory';

interface StepTimelineProps {
  steps: PlayStep[];
  index: number;
  onJump: (index: number) => void;
}

function StepIcon({ step }: { step: PlayStep }) {
  const size = 15;
  if (step.kind === 'frame') return <Radio size={size} aria-hidden="true" />;
  if (step.kind === 'time') return <Timer size={size} aria-hidden="true" />;
  if (step.kind === 'record') return <Receipt size={size} aria-hidden="true" />;
  if ((step.raw.value ?? 0) & SAFETY) return <OctagonAlert size={size} aria-hidden="true" />;
  return <Plug size={size} aria-hidden="true" />;
}

function StateChip({ state }: { state: PlayStep['stateAfter'] }) {
  const c = STATE_COLORS[state];
  return (
    <span className="rounded px-1.5 py-0.5 text-[11px] font-semibold" style={{ color: c, backgroundColor: `${c}1A` }}>
      {STATE_LABEL[state]}
    </span>
  );
}

export default function StepTimeline({ steps, index, onJump }: StepTimelineProps) {
  const listRef = useRef<HTMLOListElement>(null);

  // Keep the current step visible inside the panel without scrolling the page.
  useEffect(() => {
    const list = listRef.current;
    const item = list?.children[index] as HTMLElement | undefined;
    if (!list || !item) return;
    // The list is absolutely positioned, so it is each item's offsetParent.
    const top = item.offsetTop;
    const bottom = top + item.offsetHeight;
    if (top < list.scrollTop + 8) list.scrollTo({ top: Math.max(0, top - 8), behavior: 'smooth' });
    else if (bottom > list.scrollTop + list.clientHeight - 8)
      list.scrollTo({ top: bottom - list.clientHeight + 8, behavior: 'smooth' });
  }, [index]);

  return (
    <ol ref={listRef} className="absolute inset-2 flex flex-col gap-1 overflow-y-auto pr-1" aria-label="Scenario steps">
      {steps.map((step, i) => {
        const current = i === index;
        const future = i > index;
        const changed = step.stateAfter !== step.stateBefore;
        return (
          <li key={i}>
            <button
              type="button"
              onClick={() => onJump(i)}
              aria-current={current ? 'step' : undefined}
              className={`flex w-full cursor-pointer gap-3 rounded-lg px-3 py-2.5 text-left transition-[background-color,opacity] duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ok)] ${
                current ? 'bg-white/[0.06]' : 'hover:bg-white/[0.03]'
              } ${future ? 'opacity-45' : 'opacity-100'}`}
            >
              <span
                className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-full border"
                style={{
                  borderColor: current ? STATE_COLORS[step.stateAfter] : 'var(--color-line)',
                  color: current ? STATE_COLORS[step.stateAfter] : 'var(--color-mute)',
                }}
              >
                <StepIcon step={step} />
              </span>
              <span className="min-w-0 flex-1">
                <span className="flex items-baseline justify-between gap-2">
                  <span className={`text-sm font-medium ${current ? 'text-[var(--color-ink)]' : 'text-[var(--color-ink-2)]'}`}>
                    {step.title}
                  </span>
                  <span className="shrink-0 font-mono text-[11px] text-[var(--color-mute)]">{i + 1}</span>
                </span>
                <span className="mt-0.5 block font-mono text-xs text-[var(--color-mute)]">{step.detail}</span>
                {step.verdict && (
                  <span className="mt-1 block text-xs font-medium" style={{ color: TONE_COLOR[step.verdict.tone] }}>
                    {step.verdict.text}
                  </span>
                )}
                {changed && (
                  <span className="mt-1.5 flex items-center gap-1.5">
                    <StateChip state={step.stateBefore} />
                    <ArrowRight size={12} className="text-[var(--color-mute)]" aria-hidden="true" />
                    <StateChip state={step.stateAfter} />
                  </span>
                )}
              </span>
            </button>
          </li>
        );
      })}
    </ol>
  );
}
