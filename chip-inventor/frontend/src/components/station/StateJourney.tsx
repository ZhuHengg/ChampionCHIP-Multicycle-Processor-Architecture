// The scenario at a glance: one pill per run of consecutive steps in the same
// charger state, sized by how many steps it lasts. Runs already played are
// solid, the current one is outlined, the rest wait faded.

import { ChargerState } from '../../data/constants';
import { STATE_LABEL } from './stationStory';
import type { PlayStep } from './stationStory';

const PILL: Record<ChargerState, string> = {
  [ChargerState.IDLE]: 'border border-[var(--color-line-strong)] text-[var(--color-ink-2)]',
  [ChargerState.CONNECTED]: 'bg-[var(--color-dark)] text-white',
  [ChargerState.CHARGING]: 'bg-[var(--color-accent)] text-[var(--color-ink)]',
  [ChargerState.GRID_HOLD]: 'hatch border border-[var(--color-line-strong)] bg-white/40 text-[var(--color-ink)]',
  [ChargerState.FAULT]: 'bg-[var(--color-bad)] text-white',
  [ChargerState.METER_TIMEOUT]: 'bg-[var(--color-timeout)] text-white',
};

interface Run {
  state: ChargerState;
  start: number;
  end: number;
}

function runsOf(steps: PlayStep[]): Run[] {
  const runs: Run[] = [];
  steps.forEach((s, i) => {
    const last = runs[runs.length - 1];
    if (last && last.state === s.stateAfter) last.end = i;
    else runs.push({ state: s.stateAfter, start: i, end: i });
  });
  return runs;
}

interface StateJourneyProps {
  steps: PlayStep[];
  index: number;
  onJump: (index: number) => void;
}

export default function StateJourney({ steps, index, onJump }: StateJourneyProps) {
  const runs = runsOf(steps);
  return (
    <ol className="flex w-full items-end gap-1.5" aria-label="Charger states over this scenario">
      {runs.map((r) => {
        const n = r.end - r.start + 1;
        const current = index >= r.start && index <= r.end;
        const future = index < r.start;
        return (
          <li key={r.start} className="min-w-11 basis-0" style={{ flexGrow: n }}>
            <button
              type="button"
              onClick={() => onJump(r.start)}
              aria-current={current ? 'step' : undefined}
              aria-label={`${STATE_LABEL[r.state]}, steps ${r.start + 1} to ${r.end + 1}`}
              className="group block w-full cursor-pointer text-left focus-visible:outline-none"
            >
              <span
                className={`mb-2 block truncate pl-1 text-sm transition-colors duration-200 ${current ? 'font-semibold text-[var(--color-ink)]' : 'text-[var(--color-mute)] group-hover:text-[var(--color-ink)]'}`}
              >
                {STATE_LABEL[r.state]}
              </span>
              <span
                className={`flex h-12 items-center truncate rounded-full px-4 font-mono text-xs transition-opacity duration-300 group-focus-visible:ring-2 group-focus-visible:ring-[var(--color-ink)] ${PILL[r.state]} ${
                  future ? 'opacity-35' : 'opacity-100'
                } ${current ? 'shadow-[0_0_0_3px_var(--color-page),0_0_0_5px_var(--color-ink)]' : ''}`}
              >
                {n > 1 ? `${r.start + 1}–${r.end + 1}` : r.start + 1}
              </span>
            </button>
          </li>
        );
      })}
    </ol>
  );
}
