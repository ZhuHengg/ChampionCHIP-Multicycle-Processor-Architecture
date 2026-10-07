import { useCallback, useEffect, useRef, useState } from 'react';
import { Pause, Play, StepForward } from 'lucide-react';

export type Phase = 'normal' | 'dip' | 'hold' | 'stagger' | 'recovered';

interface GridTimelineProps {
  onPhaseChange?: (phase: Phase, staggerFrame: number) => void;
}

interface PhaseDef {
  phase: Phase;
  label: string;
  /** Duration of this phase in ms. Stagger uses STAGGER_SUBFRAME_MS * STAGGER_SUBFRAMES instead. */
  durationMs: number;
}

const STAGGER_SUBFRAMES = 8;
const STAGGER_SUBFRAME_MS = 375; // 0.375s per sub-frame, per spec

const PHASES: PhaseDef[] = [
  { phase: 'normal', label: 'Normal', durationMs: 2000 },
  { phase: 'dip', label: 'Grid Dip', durationMs: 1000 },
  { phase: 'hold', label: 'All Hold', durationMs: 2000 },
  { phase: 'stagger', label: 'Restart', durationMs: STAGGER_SUBFRAME_MS * STAGGER_SUBFRAMES },
  { phase: 'recovered', label: 'Recovered', durationMs: 2000 },
];

// Deviation (handoff-style doc note, §8 analog for this frontend-only module):
// the spec says "loop back to normal after recovered, or stop -- your
// choice, document which." This implementation loops: after `recovered`
// completes, it advances back to `normal` and continues playing, so the
// showcase is self-running on a public-facing tab instead of going idle.

function phaseGlowColor(phase: Phase): string {
  // Semantics borrowed from STATE_COLORS: amber for hold/dip-like urgency,
  // green for normal/recovered healthy states. 'dip' reads as a fault-ish
  // transient so it leans amber/red; 'stagger' is the in-between recovery.
  switch (phase) {
    case 'normal':
    case 'recovered':
      return '#22C55E';
    case 'dip':
      return '#FF5A5F';
    case 'hold':
      return '#F2B134';
    case 'stagger':
      return '#6EA8FF';
    default:
      return '#22C55E';
  }
}

export default function GridTimeline({ onPhaseChange }: GridTimelineProps) {
  const [phaseIndex, setPhaseIndex] = useState(0);
  const [staggerFrame, setStaggerFrame] = useState(0);
  const [playing, setPlaying] = useState(false);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const staggerTimerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const currentPhase = PHASES[phaseIndex].phase;

  const clearTimers = useCallback(() => {
    if (timerRef.current !== null) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
    if (staggerTimerRef.current !== null) {
      clearInterval(staggerTimerRef.current);
      staggerTimerRef.current = null;
    }
  }, []);

  // Notify parent whenever phase or staggerFrame changes.
  useEffect(() => {
    onPhaseChange?.(currentPhase, staggerFrame);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentPhase, staggerFrame]);

  // Playback driver: advances phaseIndex on a timer while playing.
  useEffect(() => {
    if (!playing) {
      clearTimers();
      return;
    }

    if (currentPhase === 'stagger') {
      setStaggerFrame(0);
      let frame = 0;
      staggerTimerRef.current = setInterval(() => {
        frame += 1;
        if (frame > STAGGER_SUBFRAMES - 1) {
          if (staggerTimerRef.current !== null) {
            clearInterval(staggerTimerRef.current);
            staggerTimerRef.current = null;
          }
          setPhaseIndex((i) => (i + 1) % PHASES.length);
          return;
        }
        setStaggerFrame(frame);
      }, STAGGER_SUBFRAME_MS);
      return () => {
        if (staggerTimerRef.current !== null) {
          clearInterval(staggerTimerRef.current);
          staggerTimerRef.current = null;
        }
      };
    }

    timerRef.current = setTimeout(() => {
      setPhaseIndex((i) => (i + 1) % PHASES.length);
    }, PHASES[phaseIndex].durationMs);

    return () => {
      if (timerRef.current !== null) {
        clearTimeout(timerRef.current);
        timerRef.current = null;
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playing, phaseIndex]);

  useEffect(() => clearTimers, [clearTimers]);

  const handleStep = () => {
    setPlaying(false);
    clearTimers();
    setStaggerFrame(0);
    setPhaseIndex((i) => (i + 1) % PHASES.length);
  };

  const handleTogglePlay = () => {
    setPlaying((p) => !p);
  };

  return (
    <div className="rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
      <div className="mb-4 flex items-center gap-4">
        {PHASES.map((p, i) => {
          const isCurrent = i === phaseIndex;
          const isPast = i < phaseIndex;
          const dotColor = isCurrent ? phaseGlowColor(p.phase) : isPast ? '#94A3B8' : '#475569';
          return (
            <div key={p.phase} className="flex flex-1 items-center">
              <div className="flex flex-col items-center gap-1.5">
                <span
                  className="rounded-full transition-all duration-300"
                  style={{
                    width: isCurrent ? 16 : 10,
                    height: isCurrent ? 16 : 10,
                    backgroundColor: dotColor,
                    boxShadow: isCurrent ? `0 0 10px 2px ${dotColor}` : 'none',
                  }}
                />
                <span
                  className="font-sans text-[11px] whitespace-nowrap"
                  style={{ color: isCurrent ? '#F8FAFC' : '#94A3B8' }}
                >
                  {p.label}
                </span>
              </div>
              {i < PHASES.length - 1 && (
                <div
                  className="mx-1 h-px flex-1"
                  style={{ backgroundColor: isPast ? '#94A3B8' : '#475569' }}
                />
              )}
            </div>
          );
        })}
      </div>

      <div className="flex items-center justify-center gap-3">
        <button
          type="button"
          onClick={handleTogglePlay}
          aria-label={playing ? 'Pause' : 'Play'}
          className="cursor-pointer rounded-lg border border-white/10 bg-[#272F42] p-2 text-[#F8FAFC] transition-colors hover:bg-[#334155] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A]"
        >
          {playing ? <Pause size={18} /> : <Play size={18} />}
        </button>
        <button
          type="button"
          onClick={handleStep}
          aria-label="Step"
          className="cursor-pointer rounded-lg border border-white/10 bg-[#272F42] p-2 text-[#F8FAFC] transition-colors hover:bg-[#334155] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A]"
        >
          <StepForward size={18} />
        </button>
        <span className="font-mono text-sm text-[#94A3B8]">
          Phase: {phaseIndex + 1}/{PHASES.length}
          {currentPhase === 'stagger' ? ` · batch ${staggerFrame + 1}/${STAGGER_SUBFRAMES}` : ''}
        </span>
      </div>
    </div>
  );
}
