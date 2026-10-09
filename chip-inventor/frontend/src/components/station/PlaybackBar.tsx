// Playback for the charging bay, laid out like a video timeline: one chapter
// per run of consecutive steps in the same charger state (sized by how many
// steps it lasts), the played part filled in that state's colour, controls
// underneath. Click or drag the track to scrub; Space and the arrow keys are
// handled by StationView.

import { ArrowRight, Pause, Play, RotateCcw, SkipBack, SkipForward } from 'lucide-react';
import { ChargerState } from '../../data/constants';
import TimelineTrack, { PlayerButton } from '../TimelineTrack';
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
  const current = runs.findIndex((r) => index >= r.start && index <= r.end);
  const run = runs[current];
  const frac = (index + 1 - run.start) / (run.end - run.start + 1);
  const stepAt = (chapter: number, f: number) => {
    const r = runs[chapter];
    return r.start + Math.floor(f * (r.end - r.start + 1));
  };

  return (
    <div className="flex flex-col gap-3">
      <TimelineTrack
        chapters={runs.map((r) => ({ key: r.start, label: STATE_LABEL[r.state], weight: r.end - r.start + 1, color: CHAPTER_COLOR[r.state] }))}
        current={current}
        fill={{ from: frac, to: frac, ms: 0, key: String(index) }}
        onPick={(c, f) => {
          const s = stepAt(c, f);
          if (s !== index) onJump(s);
        }}
        hoverLabel={(c, f) => {
          const s = stepAt(c, f);
          return `Step ${s + 1} · ${STATE_LABEL[steps[s].stateAfter]}`;
        }}
        ariaLabel="Scenario step"
        ariaValueNow={index + 1}
        ariaValueMax={total}
        ariaValueText={`Step ${index + 1} of ${total}, ${STATE_LABEL[steps[index].stateAfter]}`}
      />

      {/* Controls */}
      <div className="mt-1 flex flex-wrap items-center gap-2">
        <PlayerButton label={playing ? 'Pause' : 'Play'} onClick={onToggle} primary>
          {playing ? <Pause size={20} fill="currentColor" /> : <Play size={20} fill="currentColor" className="ml-0.5" />}
        </PlayerButton>
        <PlayerButton label="Previous step" onClick={() => onJump(Math.max(0, index - 1))} disabled={index === 0}>
          <SkipBack size={16} />
        </PlayerButton>
        <PlayerButton label="Next step" onClick={() => onJump(Math.min(last, index + 1))} disabled={done}>
          <SkipForward size={16} />
        </PlayerButton>
        <PlayerButton label="Restart" onClick={() => onJump(0)}>
          <RotateCcw size={16} />
        </PlayerButton>

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
          <PlayerButton label={`Speed ${speed}×, click to change`} onClick={() => onSpeed(SPEEDS[(SPEEDS.indexOf(speed) + 1) % SPEEDS.length])}>
            <span className="font-mono text-xs font-semibold">{speed}×</span>
          </PlayerButton>
        </div>
      </div>
    </div>
  );
}
