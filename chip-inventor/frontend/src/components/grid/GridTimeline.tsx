// Grid-event playback for two fleets side by side in time: one where every
// charger waits a fixed delay ("without"), one running RVBL-2 ("with").
// Autoplay alternates the two so the page shows the contrast on its own;
// picking a mode restarts that mode just before the reconnect.
//
// The fixed-delay fleet never settles: after the rebound every charger tries
// to reboot, the grid trips on the same synchronised spike, and the story
// loops back to "All paused". It plays MAX_ATTEMPTS loops before autoplay
// hands over to the RVBL-2 fleet through a two-beat interlude: a "verdict"
// card over the failed town, then a "handoff" card while the town resets
// behind it. The mode switches at the start of the handoff.

import { useCallback, useEffect, useState } from 'react';

export type Mode = 'without' | 'with';
export type Phase = 'normal' | 'dip' | 'hold' | 'stagger' | 'recovered' | 'surge' | 'rebound' | 'reboot';

export const STAGGER_WAVES = 8;
export const WAVE_MS = 650;
/** Reboot phase: spinners run this long before the attempt fails. */
export const REBOOT_TRY_MS = 1700;
export const MAX_ATTEMPTS = 2;
const VERDICT_MS = 3200;
export const HANDOFF_MS = 2400;

export type Interlude = 'verdict' | 'handoff' | null;

export const PHASES: Record<Mode, { phase: Phase; label: string; ms: number }[]> = {
  without: [
    { phase: 'normal', label: 'Charging', ms: 2400 },
    { phase: 'dip', label: 'Grid dip', ms: 2000 },
    { phase: 'hold', label: 'All paused', ms: 2200 },
    { phase: 'surge', label: 'All restart at once', ms: 2200 },
    { phase: 'rebound', label: 'Grid dips again', ms: 2600 },
    { phase: 'reboot', label: 'Reboot fails, loop', ms: 3200 },
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
  /** 1-based loop count for the fixed-delay fleet. */
  attempt: number;
  /** Reboot phase only: the attempt has failed. */
  rebootFailed: boolean;
  /** Overlay beat between the two fleets, or null while a fleet plays. */
  interlude: Interlude;
  /** Jump straight past the interlude into the RVBL-2 fleet. */
  skipInterlude: () => void;
  playing: boolean;
  toggle: () => void;
  jump: (phaseIndex: number) => void;
  pickMode: (mode: Mode) => void;
}

export function useGridTimeline(autoPlay: boolean): GridTimeline {
  const [mode, setMode] = useState<Mode>('without');
  const [phaseIndex, setPhaseIndex] = useState(0);
  const [wave, setWave] = useState(0);
  const [attempt, setAttempt] = useState(1);
  const [rebootFailed, setRebootFailed] = useState(false);
  const [interlude, setInterlude] = useState<Interlude>(null);
  const [playing, setPlaying] = useState(autoPlay);
  const phases = PHASES[mode];
  const phase = phases[phaseIndex].phase;

  const startWith = useCallback(() => {
    setMode('with');
    setPhaseIndex(0);
    setWave(0);
    setAttempt(1);
    setRebootFailed(false);
  }, []);

  useEffect(() => {
    if (!playing || !interlude) return;
    const id = setTimeout(
      () => {
        if (interlude === 'verdict') {
          // Reset the town to the RVBL-2 fleet behind the handoff card.
          startWith();
          setInterlude('handoff');
        } else setInterlude(null);
      },
      interlude === 'verdict' ? VERDICT_MS : HANDOFF_MS,
    );
    return () => clearTimeout(id);
  }, [playing, interlude, startWith]);

  useEffect(() => {
    if (!playing || interlude) return;
    const inWaves = phase === 'stagger';
    const trying = phase === 'reboot' && !rebootFailed;
    let ms = phases[phaseIndex].ms;
    if (inWaves) ms = WAVE_MS;
    else if (phase === 'reboot') ms = trying ? REBOOT_TRY_MS : ms - REBOOT_TRY_MS;
    const id = setTimeout(() => {
      if (inWaves && wave < STAGGER_WAVES - 1) {
        setWave((w) => w + 1);
      } else if (trying) {
        setRebootFailed(true);
      } else if (phase === 'reboot' && attempt < MAX_ATTEMPTS) {
        // Same fixed delay, same spike: back to the hold and try again.
        setRebootFailed(false);
        setAttempt((a) => a + 1);
        setPhaseIndex(HOLD_INDEX);
      } else if (phase === 'reboot') {
        // The fixed-delay fleet has run out of retries: show the verdict.
        setInterlude('verdict');
      } else if (phaseIndex === phases.length - 1) {
        // End of this fleet's story: play the other one.
        setWave(0);
        setAttempt(1);
        setRebootFailed(false);
        setPhaseIndex(0);
        setMode((m) => (m === 'without' ? 'with' : 'without'));
      } else {
        setWave(0);
        setPhaseIndex((i) => i + 1);
      }
    }, ms);
    return () => clearTimeout(id);
  }, [playing, interlude, phase, phaseIndex, phases, wave, attempt, rebootFailed]);

  const toggle = useCallback(() => setPlaying((p) => !p), []);
  const jump = useCallback(
    (i: number) => {
      setPlaying(false);
      setInterlude(null);
      const p = PHASES[mode][i].phase;
      setWave(p === 'stagger' ? STAGGER_WAVES - 1 : 0);
      // A paused jump shows the phase's end state, like the last wave.
      setRebootFailed(p === 'reboot');
      setPhaseIndex(i);
    },
    [mode],
  );
  const pickMode = useCallback((m: Mode) => {
    setInterlude(null);
    setMode(m);
    setWave(0);
    setAttempt(1);
    setRebootFailed(false);
    setPhaseIndex(HOLD_INDEX);
    setPlaying(true);
  }, []);

  const skipInterlude = useCallback(() => {
    if (interlude === 'verdict') startWith();
    setInterlude(null);
    setPlaying(true);
  }, [interlude, startWith]);

  return { mode, phaseIndex, phase, wave, attempt, rebootFailed, interlude, skipInterlude, playing, toggle, jump, pickMode };
}
