// Video-style chapter track shared by the station and fleet players, drawn
// for a dark player bar: chapter labels on top, one segment per chapter
// (sized by its weight), finished chapters filled in their colour, the
// current one filled up to a knob. Click or drag to pick a chapter and a
// position inside it.
//
// The current chapter's fill is either static (`from` === `to`, eased with a
// short transition) or runs from `from` to `to` over `ms` as a CSS animation,
// for players that advance on a clock rather than in steps. `key` restarts it.

import { useRef, useState } from 'react';
import type { PointerEvent as ReactPointerEvent, ReactNode } from 'react';

export interface Chapter {
  key: string | number;
  label: string;
  weight: number;
  color: string;
}

export interface CurrentFill {
  from: number;
  to: number;
  /** 0 = static. */
  ms: number;
  key: string;
  paused?: boolean;
}

interface TimelineTrackProps {
  chapters: Chapter[];
  current: number;
  fill: CurrentFill;
  /** Chapter index and 0..1 position inside it. */
  onPick: (chapter: number, frac: number) => void;
  hoverLabel?: (chapter: number, frac: number) => ReactNode;
  ariaLabel: string;
  ariaValueText: string;
  ariaValueNow: number;
  ariaValueMax: number;
}

// Chapter widths, shared by the label row and the track so they line up.
const chapterStyle = (w: number) => ({ flexGrow: w, flexBasis: 0, minWidth: 24 });

export default function TimelineTrack({ chapters, current, fill, onPick, hoverLabel, ariaLabel, ariaValueText, ariaValueNow, ariaValueMax }: TimelineTrackProps) {
  const chapterRefs = useRef<(HTMLDivElement | null)[]>([]);
  const trackRef = useRef<HTMLDivElement>(null);
  const [hover, setHover] = useState<{ chapter: number; frac: number; x: number } | null>(null);

  // Pointer x -> the chapter under (or nearest to) it, and the position inside.
  const pick = (clientX: number) => {
    let best = { chapter: 0, frac: 0 };
    let bestDist = Infinity;
    chapters.forEach((_, i) => {
      const el = chapterRefs.current[i];
      if (!el) return;
      const box = el.getBoundingClientRect();
      const dist = clientX < box.left ? box.left - clientX : clientX > box.right ? clientX - box.right : 0;
      if (dist < bestDist) {
        bestDist = dist;
        best = { chapter: i, frac: Math.min(Math.max((clientX - box.left) / box.width, 0), 0.9999) };
      }
    });
    return best;
  };

  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    const p = pick(e.clientX);
    onPick(p.chapter, p.frac);
  };

  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const p = pick(e.clientX);
    const box = trackRef.current?.getBoundingClientRect();
    if (box) setHover({ ...p, x: e.clientX - box.left });
    if (e.currentTarget.hasPointerCapture(e.pointerId)) onPick(p.chapter, p.frac);
  };

  const animated = fill.ms > 0;

  return (
    <div className="flex flex-col gap-3">
      {/* Chapter labels */}
      <ol className="flex gap-[3px]" aria-label={`${ariaLabel} chapters`}>
        {chapters.map((c, i) => (
          <li key={c.key} style={chapterStyle(c.weight)} className="min-w-0">
            <button
              type="button"
              onClick={() => onPick(i, 0)}
              aria-current={i === current ? 'step' : undefined}
              className={`block w-full cursor-pointer truncate text-left text-xs transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white ${
                i === current ? 'font-semibold text-white' : i > current ? 'text-white/40 hover:text-white/80' : 'text-white/65 hover:text-white'
              }`}
            >
              {c.label}
            </button>
          </li>
        ))}
      </ol>

      {/* Track */}
      <div
        ref={trackRef}
        role="slider"
        tabIndex={0}
        aria-label={ariaLabel}
        aria-valuemin={1}
        aria-valuemax={ariaValueMax}
        aria-valuenow={ariaValueNow}
        aria-valuetext={ariaValueText}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerLeave={() => setHover(null)}
        className="group relative -my-2 cursor-pointer touch-none py-2 focus-visible:outline-none"
      >
        <div className="flex gap-[3px]">
          {chapters.map((c, i) => {
            const isCurrent = i === current;
            const staticFrac = i < current ? 1 : i > current ? 0 : fill.to;
            return (
              <div
                key={c.key}
                ref={(el) => {
                  chapterRefs.current[i] = el;
                }}
                style={chapterStyle(c.weight)}
                className="relative h-1.5 rounded-full bg-white/20 transition-[height] duration-150 group-hover:h-2.5 group-focus-visible:h-2.5"
              >
                <div
                  key={isCurrent && animated ? fill.key : undefined}
                  className={`absolute inset-y-0 left-0 rounded-full ${isCurrent && animated ? 'chapter-fill' : 'transition-[width] duration-300 ease-out'}`}
                  style={{
                    width: `${staticFrac * 100}%`,
                    backgroundColor: c.color,
                    ...(isCurrent && animated
                      ? {
                          ['--from' as string]: `${fill.from * 100}%`,
                          ['--to' as string]: `${fill.to * 100}%`,
                          animationDuration: `${fill.ms}ms`,
                          animationPlayState: fill.paused ? 'paused' : 'running',
                        }
                      : {}),
                  }}
                >
                  {isCurrent && (
                    <span
                      className="absolute top-1/2 right-0 h-4 w-4 translate-x-1/2 -translate-y-1/2 rounded-full bg-white shadow-[0_0_0_4px_rgba(255,255,255,0.18)] group-focus-visible:ring-2 group-focus-visible:ring-white"
                      aria-hidden="true"
                    />
                  )}
                </div>
              </div>
            );
          })}
        </div>

        {hover && hoverLabel && (
          <div
            className="pointer-events-none absolute bottom-full mb-1 -translate-x-1/2 rounded-md bg-black/80 px-2 py-1 text-xs whitespace-nowrap text-white"
            style={{ left: Math.min(Math.max(hover.x, 60), (trackRef.current?.clientWidth ?? 0) - 60) }}
            aria-hidden="true"
          >
            {hoverLabel(hover.chapter, hover.frac)}
          </div>
        )}
      </div>
    </div>
  );
}

/** Round control for the dark player bars. */
export function PlayerButton({ label, onClick, disabled, primary, children }: { label: string; onClick: () => void; disabled?: boolean; primary?: boolean; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      disabled={disabled}
      className={`flex shrink-0 cursor-pointer items-center justify-center rounded-full transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white disabled:cursor-not-allowed disabled:opacity-35 ${
        primary ? 'h-12 w-12 bg-white text-[var(--color-navy)] hover:bg-white/85' : 'h-10 w-10 bg-white/10 text-white hover:bg-white/20'
      }`}
    >
      {children}
    </button>
  );
}
