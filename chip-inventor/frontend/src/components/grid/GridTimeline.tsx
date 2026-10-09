// Grid-event playback for two fleets side by side in time: one where every
// charger waits a fixed delay ("without"), one running RVBL-2 ("with").
// Autoplay alternates the two so the page shows the contrast on its own;
// picking a mode restarts that mode just before the reconnect.

import { useCallback, useEffect, useState } from 'react';

export type Mode = 'without' | 'with';
export type Phase = 'normal' | 'dip' | 'hold' | 'stagger' | 'recovered' | 'surge' | 'rebound';

export const STAGGER_WAVES = 8;
const WAVE_MS = 650;

export const PHASES: Record<Mode, { phase: Phase; label: string; ms: number }[]> = {
  without: [
    { phase: 'normal', label: 'Charging', ms: 2400 },
    { phase: 'dip', label: 'Grid dip', ms: 2000 },
    { phase: 'hold', label: 'All paused', ms: 2200 },
    { phase: 'surge', label: 'All restart at once', ms: 2200 },
    { phase: 'rebound', label: 'Grid dips again', ms: 3000 },
  ],
  with: [
    { phase: 'normal', label: 'Charging', ms: 2400 },
    { phase: 'dip', label: 'Grid dip', ms: 2000 },
    { phase: 'hold', label: 'All paused', ms: 2200 },
    { phase: 'stagger', label: 'Restart in 8 waves', ms: WAVE_MS * STAGGER_WAVES },
    { phase: 'recovered', label: 'Recovered', ms: 3000 },
  ],
};

/** Index of the "All paused" phase, shared by both modes. */
const HOLD_INDEX = 2;

export interface GridTimeline {
  mode: Mode;
  phaseIndex: number;
  phase: Phase;
  wave: number;
  playing: boolean;
  toggle: () => void;
  jump: (phaseIndex: number) => void;
  pickMode: (mode: Mode) => void;
}

export function useGridTimeline(autoPlay: boolean): GridTimeline {
  const [mode, setMode] = useState<Mode>('without');
  const [phaseIndex, setPhaseIndex] = useState(0);
  const [wave, setWave] = useState(0);
  const [playing, setPlaying] = useState(autoPlay);
  const phases = PHASES[mode];
  const phase = phases[phaseIndex].phase;

  useEffect(() => {
    if (!playing) return;
    const inWaves = phase === 'stagger';
    const id = setTimeout(
      () => {
        if (inWaves && wave < STAGGER_WAVES - 1) {
          setWave((w) => w + 1);
        } else if (phaseIndex === phases.length - 1) {
          // End of this fleet's story: play the other one.
          setWave(0);
          setPhaseIndex(0);
          setMode((m) => (m === 'without' ? 'with' : 'without'));
        } else {
          setWave(0);
          setPhaseIndex((i) => i + 1);
        }
      },
      inWaves ? WAVE_MS : phases[phaseIndex].ms,
    );
    return () => clearTimeout(id);
  }, [playing, phase, phaseIndex, phases, wave]);

  const toggle = useCallback(() => setPlaying((p) => !p), []);
  const jump = useCallback(
    (i: number) => {
      setPlaying(false);
      setWave(PHASES[mode][i].phase === 'stagger' ? STAGGER_WAVES - 1 : 0);
      setPhaseIndex(i);
    },
    [mode],
  );
  const pickMode = useCallback((m: Mode) => {
    setMode(m);
    setWave(0);
    setPhaseIndex(HOLD_INDEX);
    setPlaying(true);
  }, []);

  return { mode, phaseIndex, phase, wave, playing, toggle, jump, pickMode };
}
