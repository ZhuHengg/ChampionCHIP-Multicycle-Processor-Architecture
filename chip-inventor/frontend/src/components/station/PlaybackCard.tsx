// Playback controls around a progress ring: the solid arc is how far through
// the scenario we are, the ticks are what is left.

import type { ReactNode } from 'react';
import { ArrowRight, Pause, Play, RotateCcw, SkipBack, SkipForward } from 'lucide-react';

const SPEEDS = [0.5, 1, 2];
const TICKS = 64;
const R_ARC = 70;
const R_TICK = 86;

function Ring({ value, total }: { value: number; total: number }) {
  const frac = total > 1 ? value / (total - 1) : 1;
  const circ = 2 * Math.PI * R_ARC;
  return (
    <svg viewBox="0 0 200 200" className="h-full w-full -rotate-90" aria-hidden="true">
      {Array.from({ length: TICKS }, (_, i) => {
        const a = (i / TICKS) * 2 * Math.PI;
        const done = i / TICKS <= frac;
        const r2 = R_TICK + (i % 4 === 0 ? 7 : 4);
        return (
          <line
            key={i}
            x1={100 + R_TICK * Math.cos(a)}
            y1={100 + R_TICK * Math.sin(a)}
            x2={100 + r2 * Math.cos(a)}
            y2={100 + r2 * Math.sin(a)}
            stroke={done ? 'transparent' : '#B9B4A8'}
            strokeWidth={1.4}
            strokeLinecap="round"
          />
        );
      })}
      <circle cx={100} cy={100} r={R_ARC} fill="none" stroke="#EDE9DF" strokeWidth={14} />
      <circle
        cx={100}
        cy={100}
        r={R_ARC}
        fill="none"
        stroke="var(--color-accent)"
        strokeWidth={14}
        strokeLinecap="round"
        strokeDasharray={`${Math.max(0.001, frac) * circ} ${circ}`}
        style={{ transition: 'stroke-dasharray 500ms ease-out' }}
      />
    </svg>
  );
}

function RoundButton({ label, onClick, disabled, dark, children }: { label: string; onClick: () => void; disabled?: boolean; dark?: boolean; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      disabled={disabled}
      className={`flex cursor-pointer items-center justify-center rounded-full transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)] focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-35 ${
        dark ? 'h-14 w-14 bg-[var(--color-dark)] text-white hover:bg-black' : 'h-11 w-11 bg-white text-[var(--color-ink)] shadow-sm hover:bg-[var(--color-panel-2)]'
      }`}
    >
      {children}
    </button>
  );
}

interface PlaybackCardProps {
  index: number;
  total: number;
  playing: boolean;
  speed: number;
  onToggle: () => void;
  onStep: (delta: number) => void;
  onRestart: () => void;
  onSpeed: (s: number) => void;
  /** Shown once the scenario has played to the end. */
  nextScenario?: { id: string; name: string; go: () => void };
}

export default function PlaybackCard({ index, total, playing, speed, onToggle, onStep, onRestart, onSpeed, nextScenario }: PlaybackCardProps) {
  const done = index >= total - 1;
  return (
    <div className="card flex h-full flex-col p-6">
      <div className="flex items-baseline justify-between gap-3">
        <h2 className="font-display text-xl font-medium text-[var(--color-ink)]">Playback</h2>
        <span className="hidden text-xs text-[var(--color-mute)] sm:inline">Space · ← →</span>
      </div>

      <div className="relative mx-auto my-6 aspect-square w-full max-w-[250px] xl:my-auto">
        <Ring value={index} total={total} />
        <div className="absolute inset-0 flex flex-col items-center justify-center">
          <span className="tabular font-display text-5xl font-light tracking-tight text-[var(--color-ink)]">
            {String(index + 1).padStart(2, '0')}
            <span className="text-2xl text-[var(--color-mute)]">/{total}</span>
          </span>
          <span className="mt-1 text-sm text-[var(--color-mute)]">{done ? 'finished' : playing ? 'playing' : 'paused'}</span>
        </div>
      </div>

      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2">
          <RoundButton label="Restart" onClick={onRestart}>
            <RotateCcw size={17} />
          </RoundButton>
          <RoundButton label="Previous step" onClick={() => onStep(-1)} disabled={index === 0}>
            <SkipBack size={17} />
          </RoundButton>
        </div>
        <RoundButton label={playing ? 'Pause' : 'Play'} onClick={onToggle} dark>
          {playing ? <Pause size={20} fill="currentColor" /> : <Play size={20} fill="currentColor" className="ml-0.5" />}
        </RoundButton>
        <div className="flex items-center gap-2">
          <RoundButton label="Next step" onClick={() => onStep(1)} disabled={done}>
            <SkipForward size={17} />
          </RoundButton>
          <RoundButton label={`Speed ${speed}×, click to change`} onClick={() => onSpeed(SPEEDS[(SPEEDS.indexOf(speed) + 1) % SPEEDS.length])}>
            <span className="font-mono text-xs font-semibold">{speed}×</span>
          </RoundButton>
        </div>
      </div>

      {nextScenario && done && (
        <button
          type="button"
          onClick={nextScenario.go}
          className="mt-4 flex min-h-11 cursor-pointer items-center justify-between gap-2 rounded-full bg-[var(--color-accent)] px-5 text-sm font-semibold text-[var(--color-ink)] transition-colors duration-200 hover:bg-[#E9B71F] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)]"
        >
          <span className="truncate">
            Next: {nextScenario.id} · {nextScenario.name}
          </span>
          <ArrowRight size={16} aria-hidden="true" />
        </button>
      )}
    </div>
  );
}
