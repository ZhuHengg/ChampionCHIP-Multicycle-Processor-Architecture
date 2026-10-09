// The same fleet and the same grid event, two restart strategies, drawn on
// one shared MW scale so the size difference is literal. Rows are buttons:
// picking one replays the city diorama in that mode.

import type { Mode } from './GridTimeline';

interface ComparisonCardProps {
  mode: Mode;
  sync: number[];
  stag: number[];
  /** Frame (since grid recovery) the diorama is on, or undefined. */
  highlightFrame?: number;
  onPick: (mode: Mode) => void;
}

const ROWS: { mode: Mode; name: string; how: string; color: string }[] = [
  { mode: 'without', name: 'Without RVBL-2', how: 'fixed restart delay', color: 'var(--color-bad)' },
  { mode: 'with', name: 'With RVBL-2', how: 'CRC-hashed delay', color: 'var(--color-accent)' },
];

function lastNonZero(xs: number[]): number {
  for (let i = xs.length - 1; i >= 0; i--) if (xs[i] > 0) return i;
  return 0;
}

export default function ComparisonCard({ mode, sync, stag, highlightFrame, onPick }: ComparisonCardProps) {
  const max = Math.max(...sync, ...stag);
  const peakSync = Math.max(...sync);
  const peakStag = Math.max(...stag);

  return (
    <div className="card flex h-full flex-col p-6">
      <h2 className="font-display text-xl font-medium text-[var(--color-ink)]">Load returning per frame</h2>
      <p className="mt-1 text-sm text-[var(--color-mute)]">Same fleet, same dip. One scale.</p>

      <div className="mt-5 flex flex-1 flex-col gap-3">
        {ROWS.map((r) => {
          const data = r.mode === 'without' ? sync : stag;
          const peak = r.mode === 'without' ? peakSync : peakStag;
          const active = r.mode === mode;
          return (
            <button
              key={r.mode}
              type="button"
              onClick={() => onPick(r.mode)}
              aria-pressed={active}
              className={`flex flex-1 cursor-pointer flex-col rounded-[22px] p-4 text-left transition-[background-color,opacity] duration-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)] ${
                active ? 'bg-white shadow-sm' : 'opacity-55 hover:opacity-80'
              }`}
            >
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-medium text-[var(--color-ink)]">{r.name}</p>
                  <p className="text-xs text-[var(--color-mute)]">{r.how}</p>
                </div>
                <p className="tabular font-display text-3xl leading-none font-light tracking-tight text-[var(--color-ink)]">
                  {peak.toFixed(2)}
                  <span className="ml-1 text-sm text-[var(--color-mute)]">MW peak</span>
                </p>
              </div>
              <ol className="mt-3 flex min-h-20 flex-1 items-end justify-between gap-1" aria-label={`${r.name}: load per frame`}>
                {data.map((v, f) => {
                  const dim = active && highlightFrame !== undefined && f > highlightFrame;
                  return (
                    <li key={f} className="flex h-full flex-1 flex-col items-center justify-end" aria-label={`Frame ${f}: ${v.toFixed(2)} MW`}>
                      {v > 0 ? (
                        <>
                          <span className="tabular mb-1 font-mono text-[10px] text-[var(--color-ink-2)]" style={{ opacity: dim ? 0.4 : 1 }}>
                            {v.toFixed(2)}
                          </span>
                          <span
                            className="w-2.5 rounded-full transition-opacity duration-300"
                            style={{ height: `${Math.max(8, (v / max) * 82)}%`, backgroundColor: r.color, opacity: dim ? 0.3 : 1 }}
                          />
                        </>
                      ) : (
                        <span className="h-0.5 w-3 rounded-full bg-[var(--color-line-strong)]" />
                      )}
                    </li>
                  );
                })}
              </ol>
            </button>
          );
        })}
        <div className="flex justify-between gap-1 px-4 font-mono text-[11px] text-[var(--color-mute)]" aria-hidden="true">
          {sync.map((_, f) => (
            <span key={f} className="flex-1 text-center">
              {f}
            </span>
          ))}
        </div>
        <p className="text-center text-xs text-[var(--color-mute)]">frames after the grid recovers</p>
      </div>

      <p className="mt-5 border-t border-dashed border-[var(--color-line-strong)] pt-4 text-sm text-[var(--color-ink-2)]">
        Trade-off: full load back by frame {lastNonZero(stag)} instead of {lastNonZero(sync)}.
      </p>
    </div>
  );
}
