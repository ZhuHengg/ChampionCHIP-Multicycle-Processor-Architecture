// Every meter frame in the scenario as a lollipop: height is the power it
// reports (V x I). Billed frames are dark, verified-but-unbilled are grey,
// rejected ones are red, the latest one is highlighted, and frames that have
// not arrived yet wait as faint dotted stubs.

import { formatReading } from './stationStory';
import type { PlayStep } from './stationStory';

interface ReadingBar {
  stepIndex: number;
  seq: number;
  watts: number;
  rejected: boolean;
  billed: boolean;
}

function readingBars(steps: PlayStep[]): ReadingBar[] {
  const bars: ReadingBar[] = [];
  steps.forEach((s, i) => {
    if (s.kind !== 'frame' || !s.raw.frame) return;
    const prevFrames = i > 0 ? steps[i - 1].frames : 0;
    bars.push({
      stepIndex: i,
      seq: s.raw.frame[0],
      watts: ((s.raw.voltage ?? 0) / 10) * ((s.raw.current ?? 0) / 10),
      rejected: s.verdict?.text.startsWith('Rejected') ?? false,
      billed: s.frames > prevFrames,
    });
  });
  return bars;
}

function kw(w: number): string {
  return (w / 1000).toFixed(2);
}

export default function ReadingsCard({ steps, index }: { steps: PlayStep[]; index: number }) {
  const bars = readingBars(steps);
  const arrived = bars.filter((b) => b.stepIndex <= index);
  const latest = arrived[arrived.length - 1];
  const reading = steps[index].lastReading;
  // Zoomed scale: readings sit within a few hundred watts of each other, so
  // a zero-based axis would draw identical bars. The legend says so.
  const valid = bars.filter((b) => !b.rejected).map((b) => b.watts);
  const hiW = Math.max(1, ...valid);
  const loW = valid.length ? Math.min(...valid) * 0.8 : 0;
  const scale = (w: number) => 22 + Math.max(0, Math.min(1, (w - loW) / (hiW - loW || 1))) * 68;

  return (
    <div className="card flex h-full flex-col p-6">
      <div className="flex flex-wrap items-start justify-between gap-x-6 gap-y-2">
        <div>
          <h2 className="font-display text-xl font-medium text-[var(--color-ink)]">Meter readings</h2>
          <p className="mt-1 text-sm text-[var(--color-mute)]">
            {arrived.length}/{bars.length} frames
          </p>
        </div>
        <div className="flex items-end gap-3">
          <span className="tabular font-display text-5xl font-light tracking-tight text-[var(--color-ink)]">
            {reading ? kw((reading.v / 10) * (reading.i / 10)) : '0.00'}
            <span className="ml-1 text-xl text-[var(--color-mute)]">kW</span>
          </span>
          <span className="mb-1.5 max-w-[9rem] text-xs leading-snug text-[var(--color-mute)]">
            {reading ? formatReading(reading) : 'no verified reading yet'}
          </span>
        </div>
      </div>

      {bars.length === 0 ? (
        <p className="mt-6 flex flex-1 items-center justify-center rounded-2xl border border-dashed border-[var(--color-line-strong)] p-6 text-sm text-[var(--color-mute)]">
          This scenario sends no meter frames.
        </p>
      ) : (
        <ol className="mt-auto flex items-end justify-between gap-1 pt-8" aria-label="Meter frames">
          {bars.map((b) => {
            const future = b.stepIndex > index;
            const isLatest = b === latest;
            const h = b.rejected ? 22 : scale(b.watts);
            const color = b.rejected ? 'var(--color-bad)' : isLatest ? 'var(--color-accent)' : b.billed ? 'var(--color-dark)' : '#B9B4A8';
            const status = future ? 'not received yet' : b.rejected ? 'rejected' : b.billed ? 'billed' : 'verified, not billed';
            return (
              <li key={b.stepIndex} className="flex min-w-0 flex-1 flex-col items-center" aria-label={`Frame ${b.seq}: ${kw(b.watts)} kW, ${status}`}>
                <div className="relative flex h-40 w-full flex-col items-center justify-end">
                  {isLatest && !b.rejected && (
                    <span className="tabular absolute z-10 -translate-y-1 rounded-full bg-[var(--color-accent-soft)] px-2 py-0.5 text-[11px] font-semibold whitespace-nowrap text-[var(--color-ink)]" style={{ bottom: `calc(${h}% + 16px)` }}>
                      {kw(b.watts)} kW
                    </span>
                  )}
                  {future ? (
                    <span className="w-1.5 rounded-full border-l-[3px] border-dotted border-[#CFC9BC]" style={{ height: '40%' }} />
                  ) : (
                    <span className="relative w-2 rounded-full transition-[height] duration-500" style={{ height: `${h}%`, backgroundColor: color }}>
                      {b.rejected && <span className="absolute -top-5 left-1/2 -translate-x-1/2 text-sm font-bold text-[var(--color-bad)]">×</span>}
                    </span>
                  )}
                  <span className="mt-2 h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: future ? '#DDD8CC' : color }} />
                </div>
                <span className={`mt-2 font-mono text-[11px] ${isLatest ? 'font-semibold text-[var(--color-ink)]' : 'text-[var(--color-mute)]'}`}>{b.seq}</span>
              </li>
            );
          })}
        </ol>
      )}

      <div className="mt-4 flex flex-wrap gap-x-4 gap-y-1 text-xs text-[var(--color-mute)]">
        <span className="flex items-center gap-1.5">
          <span className="h-2 w-2 rounded-full bg-[var(--color-dark)]" /> billed
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-2 w-2 rounded-full bg-[#B9B4A8]" /> verified, not billed
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-2 w-2 rounded-full bg-[var(--color-bad)]" /> rejected
        </span>
        <span className="ml-auto">height zoomed · label = seq #</span>
      </div>
    </div>
  );
}
