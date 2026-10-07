// Ported 1:1 from chip-inventor/testbench/app/evidence/rebound_sim.py:
// rebound(). Fleet rebound: what the CRC-hashed restart delay is actually
// worth (P2).
//
// One grid event pauses a whole fleet of chargers. If every charger waits
// the same number of healthy frames, they all reconnect on the same frame
// and the grid sees the entire fleet's load return as one step -- the
// "rebound" that makes naive demand response dangerous.
//
// Our restart delay is HOLD_BASE + (CRC-16(CHARGER_ID, seed=trigger CRC) & 7),
// so chargers that saw the *same* event still restart on different frames,
// with no coordination, no clock and no configuration.

import { HOLD_BASE } from './constants';
import { restartDelay } from './charger';

export const BASE_ID = 0x4D590000;    // fleet of sequential charger IDs
export const TRIGGER_CRC = 0x1D0F;    // one shared grid event

export interface ReboundResult {
  sync: number[];
  stag: number[];
}

/**
 * Load restored per frame, in MW, for both strategies.
 *
 * Returns { sync, stag }: arrays indexed by frames since the grid
 * recovered. Index i holds the load that reconnects on frame i.
 */
export function rebound(
  nChargers = 1000,
  kw = 7.0,
  triggerCrc = TRIGGER_CRC,
  baseId = BASE_ID,
): ReboundResult {
  const fleetMw = (nChargers * kw) / 1000.0;

  // Every charger waits the same fixed delay.
  const span = HOLD_BASE + 8;
  const sync = new Array(span).fill(0.0);
  sync[HOLD_BASE] = fleetMw;

  // Each charger hashes its own ID with the event's CRC.
  const stag = new Array(span).fill(0.0);
  for (let k = 0; k < nChargers; k++) {
    const idx = restartDelay(triggerCrc, baseId + k);
    stag[idx] += kw / 1000.0;
  }

  return { sync, stag };
}

/** Histogram of restart delays across a fleet (frame index -> count). */
export function delayHistogram(
  nChargers = 1000,
  triggerCrc = TRIGGER_CRC,
  baseId = BASE_ID,
): Record<number, number> {
  const hist: Record<number, number> = {};
  for (let k = 0; k < nChargers; k++) {
    const d = restartDelay(triggerCrc, baseId + k);
    hist[d] = (hist[d] ?? 0) + 1;
  }
  return hist;
}
