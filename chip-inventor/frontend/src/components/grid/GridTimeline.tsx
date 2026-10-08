// Grid-event playback: normal -> dip -> hold -> 8 restart waves -> recovered,
// looping so the page runs itself. The hook owns the clock; GridView renders
// the controls inside the city diorama.

import { useCallback, useEffect, useState } from 'react';

export type Phase = 'normal' | 'dip' | 'hold' | 'stagger' | 'recovered';

export const STAGGER_WAVES = 8;
const WAVE_MS = 650;

export const PHASES: { phase: Phase; label: string; ms: number }[] = [
  { phase: 'normal', label: 'Charging', ms: 2600 },
  { phase: 'dip', label: 'Grid dip', ms: 2200 },
  { phase: 'hold', label: 'All paused', ms: 2600 },
  { phase: 'stagger', label: 'Restart waves', ms: WAVE_MS * STAGGER_WAVES },
  { phase: 'recovered', label: 'Recovered', ms: 3200 },
];

export interface GridTimeline {
  phaseIndex: number;
  phase: Phase;
  wave: number;
  playing: boolean;
  toggle: () => void;
  jump: (phaseIndex: number) => void;
}

export function useGridTimeline(autoPlay: boolean): GridTimeline {
  const [phaseIndex, setPhaseIndex] = useState(0);
  const [wave, setWave] = useState(0);
  const [playing, setPlaying] = useState(autoPlay);
  const phase = PHASES[phaseIndex].phase;

  useEffect(() => {
    if (!playing) return;
    const inWaves = phase === 'stagger';
    const id = setTimeout(
      () => {
        if (inWaves && wave < STAGGER_WAVES - 1) {
          setWave((w) => w + 1);
        } else {
          setWave(0);
          setPhaseIndex((i) => (i + 1) % PHASES.length);
        }
      },
      inWaves ? WAVE_MS : PHASES[phaseIndex].ms,
    );
    return () => clearTimeout(id);
  }, [playing, phase, phaseIndex, wave]);

  const toggle = useCallback(() => setPlaying((p) => !p), []);
  const jump = useCallback((i: number) => {
    setPlaying(false);
    setWave(PHASES[i].phase === 'stagger' ? STAGGER_WAVES - 1 : 0);
    setPhaseIndex(i);
  }, []);

  return { phaseIndex, phase, wave, playing, toggle, jump };
}
