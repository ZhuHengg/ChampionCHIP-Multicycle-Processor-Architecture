// Playback for the charging bay, laid out like a video timeline: one chapter
// per run of consecutive steps in the same charger state (sized by how many
// steps it lasts), the played part filled in that state's colour, controls
// underneath. Click or drag the track to scrub; Space and the arrow keys are
// handled by StationView.

import { useRef, useState } from 'react';
import type { PointerEvent as ReactPointerEvent, ReactNode } from 'react';
import { ArrowRight, Pause, Play, RotateCcw, SkipBack, SkipForward } from 'lucide-react';
import { ChargerState } from '../../data/constants';
import { STATE_LABEL } from './stationStory';
import type { PlayStep } from './stationStory';

const SPEEDS = [0.5, 1, 2];

// Brighter than STATE_COLORS so they read on the bay's navy/charcoal backdrop.
const CHAPTER_COLOR: Record<ChargerState, string> = {
  [ChargerState.IDLE]: '#D6D3CB',
  [ChargerState.CONNECTED]: '#6EA8FF',
  [ChargerState.CHARGING]: '#3CCF5A',
  [ChargerState.GRID_HOLD]: '#F2B134',
  [ChargerState.FAULT]: '#FF5A5F',
  [ChargerState.METER_TIMEOUT]: '#FF8A3D',
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

// Chapter widths, shared by the label row and the track so they line up.
const chapterStyle = (n: number) => ({ flexGrow: n, flexBasis: 0, minWidth: 24 });

function ControlButton({ label, onClick, disabled, primary, children }: { label: string; onClick: () => void; disabled?: boolean; primary?: boolean; children: ReactNode }) {
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

interface PlaybackBarProps {
  steps: PlayStep[];
  index: number;
  playing: boolean;
  speed: number;
  onToggle: () => void;
  /** Jump to a step and pause. */
  onJump: (index: number) => void;
  onSpeed: (s: number) => void;
  /** Shown once the scenario has played to the end. */
  nextScenario?: { id: string; name: string; go: () => void };
}

export default function PlaybackBar({ steps, index, playing, speed, onToggle, onJump, onSpeed, nextScenario }: PlaybackBarProps) {
  const runs = runsOf(steps);
  const total = steps.length;
  const last = total - 1;
  const done = index >= last;
  const chapterRefs = useRef<(HTMLDivElement | null)[]>([]);
  const trackRef = useRef<HTMLDivElement>(null);
  const [hover, setHover] = useState<{ step: number; x: number } | null>(null);

  // Pointer x -> step: find the chapter under (or nearest to) the pointer,
  // then the step slot within it.
  const stepAt = (clientX: number): number => {
    let best = 0;
    let bestDist = Infinity;
    runs.forEach((r, i) => {
      const el = chapterRefs.current[i];
      if (!el) return;
      const box = el.getBoundingClientRect();
      const dist = clientX < box.left ? box.left - clientX : clientX > box.right ? clientX - box.right : 0;
      if (dist < bestDist) {
        bestDist = dist;
        const n = r.end - r.start + 1;
        const f = Math.min(Math.max((clientX - box.left) / box.width, 0), 0.9999);
        best = r.start + Math.floor(f * n);
      }
    });
    return best;
  };

  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    e.currentTarget.setPointerCapture(e.pointerId);
    onJump(stepAt(e.clientX));
  };

  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const step = stepAt(e.clientX);
    const box = trackRef.current?.getBoundingClientRect();
    if (box) setHover({ step, x: e.clientX - box.left });
    if (e.currentTarget.hasPointerCapture(e.pointerId) && step !== index) onJump(step);
  };

  const currentRun = runs.find((r) => index >= r.start && index <= r.end);

  return (
    <div className="flex flex-col gap-3">
      {/* Chapter labels */}
      <ol className="flex gap-[3px]" aria-label="Charger states over this scenario">
        {runs.map((r) => {
          const n = r.end - r.start + 1;
          const current = r === currentRun;
          return (
            <li key={r.start} style={chapterStyle(n)} className="min-w-0">
              <button
                type="button"
                onClick={() => onJump(r.start)}
                aria-current={current ? 'step' : undefined}
                aria-label={`${STATE_LABEL[r.state]}, steps ${r.start + 1} to ${r.end + 1}`}
                className={`block w-full cursor-pointer truncate text-left text-xs transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white ${
                  current ? 'font-semibold text-white' : index < r.start ? 'text-white/40 hover:text-white/80' : 'text-white/65 hover:text-white'
                }`}
              >
                {STATE_LABEL[r.state]}
              </button>
            </li>
          );
        })}
      </ol>

      {/* Track */}
      <div
        ref={trackRef}
        role="slider"
        tabIndex={0}
        aria-label="Scenario step"
        aria-valuemin={1}
        aria-valuemax={total}
        aria-valuenow={index + 1}
        aria-valuetext={`Step ${index + 1} of ${total}, ${STATE_LABEL[steps[index].stateAfter]}`}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerLeave={() => setHover(null)}
        className="group relative -my-2 cursor-pointer touch-none py-2 focus-visible:outline-none"
      >
        <div className="flex gap-[3px]">
          {runs.map((r, i) => {
            const n = r.end - r.start + 1;
            const frac = Math.min(Math.max((index + 1 - r.start) / n, 0), 1);
            const current = r === currentRun;
            return (
              <div
                key={r.start}
                ref={(el) => {
                  chapterRefs.current[i] = el;
                }}
                style={chapterStyle(n)}
                className="relative h-1.5 rounded-full bg-white/20 transition-[height] duration-150 group-hover:h-2.5 group-focus-visible:h-2.5"
              >
                <div
                  className="absolute inset-y-0 left-0 rounded-full transition-[width] duration-300 ease-out"
                  style={{ width: `${frac * 100}%`, backgroundColor: CHAPTER_COLOR[r.state] }}
                />
                {current && (
                  <div
                    className="absolute top-1/2 h-4 w-4 -translate-x-1/2 -translate-y-1/2 rounded-full bg-white shadow-[0_0_0_4px_rgba(255,255,255,0.18)] transition-[left] duration-300 ease-out group-focus-visible:ring-2 group-focus-visible:ring-white group-focus-visible:ring-offset-2 group-focus-visible:ring-offset-transparent"
                    style={{ left: `${frac * 100}%` }}
                    aria-hidden="true"
                  />
                )}
              </div>
            );
          })}
        </div>

        {hover && (
          <div
            className="pointer-events-none absolute bottom-full mb-1 -translate-x-1/2 rounded-md bg-black/80 px-2 py-1 text-xs whitespace-nowrap text-white"
            style={{ left: Math.min(Math.max(hover.x, 40), (trackRef.current?.clientWidth ?? 0) - 40) }}
            aria-hidden="true"
          >
            Step {hover.step + 1} · {STATE_LABEL[steps[hover.step].stateAfter]}
          </div>
        )}
      </div>

      {/* Controls */}
      <div className="mt-1 flex flex-wrap items-center gap-2">
        <ControlButton label={playing ? 'Pause' : 'Play'} onClick={onToggle} primary>
          {playing ? <Pause size={20} fill="currentColor" /> : <Play size={20} fill="currentColor" className="ml-0.5" />}
        </ControlButton>
        <ControlButton label="Previous step" onClick={() => onJump(Math.max(0, index - 1))} disabled={index === 0}>
          <SkipBack size={16} />
        </ControlButton>
        <ControlButton label="Next step" onClick={() => onJump(Math.min(last, index + 1))} disabled={done}>
          <SkipForward size={16} />
        </ControlButton>
        <ControlButton label="Restart" onClick={() => onJump(0)}>
          <RotateCcw size={16} />
        </ControlButton>

        <span className="ml-2 font-mono text-sm text-white tabular">
          {String(index + 1).padStart(2, '0')}
          <span className="text-white/45"> / {String(total).padStart(2, '0')}</span>
        </span>
        <span className="text-sm text-white/55">{done ? 'finished' : playing ? 'playing' : 'paused'}</span>

        <div className="ml-auto flex items-center gap-2">
          <span className="hidden text-xs text-white/45 md:inline">Space · ← →</span>
          {nextScenario && done && (
            <button
              type="button"
              onClick={nextScenario.go}
              className="flex min-h-10 max-w-[260px] cursor-pointer items-center gap-2 rounded-full bg-[var(--color-accent)] px-4 text-sm font-semibold text-[var(--color-ink)] transition-colors duration-200 hover:bg-[#E9B71F] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white"
            >
              <span className="truncate">
                Next: {nextScenario.id} · {nextScenario.name}
              </span>
              <ArrowRight size={16} className="shrink-0" aria-hidden="true" />
            </button>
          )}
          <ControlButton label={`Speed ${speed}×, click to change`} onClick={() => onSpeed(SPEEDS[(SPEEDS.indexOf(speed) + 1) % SPEEDS.length])}>
            <span className="font-mono text-xs font-semibold">{speed}×</span>
          </ControlButton>
        </div>
      </div>
    </div>
  );
}
