// Presentation layer for the Station page: turns the model's ScenarioStep
// records into plain-language narration, captions and status icons. Every
// value shown is read from the step snapshots produced by data/scenarios.ts;
// nothing here changes model behaviour.

import { crc16 } from '../../data/crc';
import { restartDelay } from '../../data/charger';
import {
  ChargerState,
  F_CP_ERROR,
  F_CRC_LOST,
  F_ESTOP,
  F_GRID_HOLD,
  F_LOW,
  F_OVERCURRENT,
  V_SAG,
  METER_TIMEOUT_MS,
  SAFETY,
  STATE_OUT,
} from '../../data/constants';
import type { Scenario, ScenarioStep } from '../../data/scenarios';

export type Tone = 'ok' | 'info' | 'warn' | 'bad' | 'mute';
export type IconKind = 'power' | 'sync' | 'bolt' | 'pause' | 'alert' | 'syncBroken' | 'check';
export type Backdrop = 'navy' | 'charcoal';

export const TONE_COLOR: Record<Tone, string> = {
  ok: '#3CCF5A',
  info: '#6EA8FF',
  warn: '#F2B134',
  bad: '#FF5A5F',
  mute: '#94A3B8',
};

export type ScenarioGroup = 'Everyday' | 'Grid support' | 'Data integrity' | 'Safety';

export const GROUP_ORDER: ScenarioGroup[] = ['Everyday', 'Grid support', 'Data integrity', 'Safety'];

export const GROUP_TONE: Record<ScenarioGroup, Tone> = {
  Everyday: 'ok',
  'Grid support': 'warn',
  'Data integrity': 'info',
  Safety: 'bad',
};

export interface ScenarioMeta {
  name: string;
  proves: string;
  group: ScenarioGroup;
}

export const SCENARIO_META: Record<string, ScenarioMeta> = {
  S1: { name: 'Normal session', group: 'Everyday', proves: 'Plug in, charge, unplug: only verified meter frames are billed.' },
  S1X: { name: 'Full-speed UART', group: 'Everyday', proves: 'Back-to-back meter bytes with no gap are still parsed and billed.' },
  S6: { name: 'Straight to charge', group: 'Everyday', proves: 'The contactor stays open until the first healthy meter reading arrives.' },
  S11: { name: 'Power-up with car attached', group: 'Everyday', proves: 'Booting with the pilot already at "charge" still starts safe.' },
  S2: { name: 'Grid frequency dip', group: 'Grid support', proves: 'The charger pauses for the grid, then restarts on its own CRC-hashed slot.' },
  S3: { name: 'Corrupt & missing frames', group: 'Data integrity', proves: 'A bad frame is rejected; the next valid frame recovers billing.' },
  S10: { name: 'Replay attack', group: 'Data integrity', proves: 'Replayed meter frames are rejected by sequence number, then fault.' },
  S4: { name: 'Meter link lost', group: 'Data integrity', proves: 'Two bad frames in a row latch a fault and stop the session.' },
  S12: { name: 'Meter goes silent', group: 'Safety', proves: 'A 500 ms watchdog opens the contactor when meter data stops.' },
  S5: { name: 'Emergency stop', group: 'Safety', proves: 'E-stop latches a fault until it is released and the car unplugs.' },
  S7: { name: 'Limits & over-current', group: 'Safety', proves: 'Readings exactly on a limit are billed; one step over trips.' },
  S8: { name: 'Unsupported pilot states', group: 'Safety', proves: 'Ventilation (CP D) is refused and pilot error (CP E) faults.' },
  S9: { name: 'Invalid pilot code', group: 'Safety', proves: 'A garbage pilot code latches a fault with the CP-error flag.' },
};

export const CP_NAME: Record<number, string> = {
  0: 'A · no vehicle',
  1: 'B · vehicle connected',
  2: 'C · vehicle requests charge',
  3: 'D · ventilation required',
  4: 'E · pilot error',
  5: 'F · charger fault',
  6: 'invalid code 6',
  7: 'invalid code 7',
};

export const STATE_LABEL: Record<ChargerState, string> = {
  [ChargerState.IDLE]: 'Idle',
  [ChargerState.CONNECTED]: 'Connected',
  [ChargerState.CHARGING]: 'Charging',
  [ChargerState.GRID_HOLD]: 'Grid hold',
  [ChargerState.FAULT]: 'Fault',
  [ChargerState.METER_TIMEOUT]: 'Meter timeout',
};

export type StepKind = 'pins' | 'frame' | 'time' | 'record';

export interface Reading {
  v: number;
  i: number;
  f: number;
}

export interface PlayStep {
  kind: StepKind;
  title: string;
  detail: string;
  verdict?: { tone: Tone; text: string };
  stateBefore: ChargerState;
  stateAfter: ChargerState;
  energy: number;
  frames: number;
  flags: number;
  ageMs: number;
  /** DATAOUT byte; the model's output is STATE_OUT[state] by construction. */
  pinsOut: number;
  /** True when the scenario's emulator command checks the pins (-o) right after this step. */
  pinsChecked: boolean;
  lastReading: Reading | null;
  sessionEnded: boolean;
  /** Restart countdown while in GRID_HOLD: healthy frames seen / required. */
  hold?: { count: number; delay: number };
  frameIndex?: number;
  raw: ScenarioStep;
}

export function formatReading(r: Reading): string {
  return `${(r.v / 10).toFixed(1)} V · ${(r.i / 10).toFixed(1)} A · ${(r.f / 100).toFixed(2)} Hz`;
}

export function flagNames(flags: number): string[] {
  const out: string[] = [];
  if (flags & F_ESTOP) out.push('E-stop');
  if (flags & F_CP_ERROR) out.push('Pilot error');
  if (flags & F_OVERCURRENT) out.push('Over-current');
  if (flags & F_CRC_LOST) out.push('Meter frames lost');
  if (flags & F_GRID_HOLD) out.push('Grid hold occurred');
  return out;
}

/**
 * Collapse a scenario into the steps a viewer should walk through. The
 * emulator's `o()` checks only read the pins, so they are folded into the
 * preceding step as its verified output instead of being steps of their own.
 */
export function buildPlayback(scenario: Scenario): PlayStep[] {
  const out: PlayStep[] = [];
  let lastSeq: number | null = null;
  let lastReading: Reading | null = null;
  let prevFrames = 0;
  let seenActive = scenario.presetIn !== 0;
  let frameIndex = 0;
  let holdDelay = 0;
  let holdCount = 0;

  for (const s of scenario.steps) {
    if (s.type === 'gpio_out') {
      const prev = out[out.length - 1];
      if (prev) prev.pinsChecked = true;
      continue;
    }

    let kind: StepKind = 'pins';
    let title = '';
    let detail = '';
    let verdict: PlayStep['verdict'];
    let thisFrame: number | undefined;

    if (s.type === 'gpio_in') {
      const v = s.value ?? 0;
      const cp = v & 0x07;
      if (v & SAFETY) {
        title = 'Emergency stop pressed';
        detail = `Safety input high · pilot ${CP_NAME[cp]}`;
      } else {
        title = `Pilot ${CP_NAME[cp]}`;
        detail = `GPIO in = 0x${v.toString(16).padStart(2, '0').toUpperCase()}`;
      }
    } else if (s.type === 'frame' && s.frame) {
      kind = 'frame';
      thisFrame = frameIndex++;
      const reading = { v: s.voltage ?? 0, i: s.current ?? 0, f: s.frequency ?? 0 };
      const crcOk = crc16(s.frame.subarray(0, 7)) === (s.frame[7] | (s.frame[8] << 8));
      const seq = s.frame[0];
      const delta = lastSeq === null ? 1 : (seq - lastSeq) & 0xff;
      title = `Meter reading #${seq}`;
      detail = formatReading(reading);
      if (!crcOk) {
        verdict = { tone: 'bad', text: 'Rejected · CRC check failed' };
      } else if (delta === 0 || delta >= 128) {
        verdict = { tone: 'bad', text: 'Rejected · replayed sequence number' };
      } else {
        lastSeq = seq;
        lastReading = reading;
        const gap = delta > 1 ? ` · ${delta - 1} missed frame flagged` : '';
        const field = s.frame[7] | (s.frame[8] << 8);
        const gridHealthy = reading.f >= F_LOW && reading.v >= V_SAG;
        if (s.stateBefore !== ChargerState.GRID_HOLD && s.stateAfter === ChargerState.GRID_HOLD) {
          // Same delay the model computes from the triggering frame's CRC.
          holdDelay = restartDelay(field);
          holdCount = 0;
          verdict = { tone: 'warn', text: `Verified · grid unhealthy, pause; restart after ${holdDelay} healthy frames${gap}` };
        } else if (s.stateBefore === ChargerState.GRID_HOLD && s.stateAfter === ChargerState.CHARGING) {
          holdCount = holdDelay;
          verdict = { tone: 'ok', text: `Verified · healthy ${holdDelay} of ${holdDelay}: restart slot reached (not billed)${gap}` };
        } else if (s.stateBefore === ChargerState.GRID_HOLD && s.stateAfter === ChargerState.GRID_HOLD) {
          if (gridHealthy) {
            holdCount += 1;
            verdict = { tone: 'info', text: `Verified · healthy ${holdCount} of ${holdDelay} toward restart${gap}` };
          } else {
            holdCount = 0;
            verdict = { tone: 'warn', text: `Verified · grid still unhealthy, countdown reset${gap}` };
          }
        } else if (s.framesAfter > prevFrames) verdict = { tone: 'ok', text: `Verified and billed${gap}` };
        else if (s.stateAfter === ChargerState.FAULT) verdict = { tone: 'bad', text: 'Verified · outside safe limits' };
        else verdict = { tone: 'info', text: `Verified · not billed${gap}` };
      }
      const rejected = !crcOk || delta === 0 || delta >= 128;
      if (rejected && verdict && s.stateAfter === ChargerState.FAULT && s.stateBefore !== ChargerState.FAULT) {
        verdict = { tone: 'bad', text: `${verdict.text} · 2nd bad frame in a row, fault latched` };
      }
      prevFrames = s.framesAfter;
    } else if (s.type === 'tick') {
      kind = 'time';
      title = `${s.elapsedMs} ms pass with no meter data`;
      detail = `Watchdog age ${Math.min(s.ageMsAfter, METER_TIMEOUT_MS)} / ${METER_TIMEOUT_MS} ms`;
      if (s.stateAfter === ChargerState.METER_TIMEOUT && s.stateBefore !== ChargerState.METER_TIMEOUT) {
        verdict = { tone: 'bad', text: 'Watchdog fired · contactor opened' };
      }
    } else if (s.type === 'record') {
      kind = 'record';
      title = 'Session record sent';
      detail = '8 bytes over UART, sealed with CRC-16';
    }

    if (s.stateAfter !== ChargerState.IDLE) seenActive = true;

    out.push({
      kind,
      title,
      detail,
      verdict,
      stateBefore: s.stateBefore,
      stateAfter: s.stateAfter,
      energy: s.energyAfter,
      frames: s.framesAfter,
      flags: s.flagsAfter,
      ageMs: s.ageMsAfter,
      pinsOut: STATE_OUT[s.stateAfter],
      pinsChecked: false,
      lastReading,
      sessionEnded: seenActive && s.stateAfter === ChargerState.IDLE,
      hold: s.stateAfter === ChargerState.GRID_HOLD ? { count: holdCount, delay: holdDelay } : undefined,
      frameIndex: thisFrame,
      raw: s,
    });
  }

  return out;
}

export interface StatusView {
  icon: IconKind;
  caption: string;
  sub: string;
  tone: Tone;
  backdrop: Backdrop;
}

export function statusFor(step: PlayStep): StatusView {
  const reading = step.lastReading ? formatReading(step.lastReading) : 'no meter reading yet';
  switch (step.stateAfter) {
    case ChargerState.CHARGING:
      return { icon: 'bolt', caption: 'Charge session in progress', sub: `Contactor closed · ${reading}`, tone: 'ok', backdrop: 'charcoal' };
    case ChargerState.CONNECTED:
      return {
        icon: 'sync',
        caption: step.lastReading ? 'Vehicle connected' : 'Contacting meter',
        sub: 'Cable locked · contactor stays open until a healthy reading',
        tone: 'info',
        backdrop: 'navy',
      };
    case ChargerState.GRID_HOLD:
      return {
        icon: 'pause',
        caption: 'Paused to support the grid',
        sub: step.hold ? `Restart slot: ${step.hold.count} of ${step.hold.delay} healthy frames · ${reading}` : `Waiting for its restart slot · ${reading}`,
        tone: 'warn',
        backdrop: 'charcoal',
      };
    case ChargerState.FAULT: {
      const why = flagNames(step.flags).filter((f) => f !== 'Grid hold occurred');
      return { icon: 'alert', caption: 'Fault latched · charging stopped', sub: why.length ? why.join(' · ') : 'Unplug to release', tone: 'bad', backdrop: 'charcoal' };
    }
    case ChargerState.METER_TIMEOUT:
      return { icon: 'syncBroken', caption: 'Unable to sync to meter', sub: `No meter data for ${METER_TIMEOUT_MS} ms · contactor opened`, tone: 'bad', backdrop: 'charcoal' };
    default:
      if (step.sessionEnded) {
        const why = flagNames(step.flags);
        return {
          icon: 'check',
          caption: 'Session stopped successfully',
          sub: why.length ? `Recorded: ${why.join(' · ')}` : `${step.frames} frame${step.frames === 1 ? '' : 's'} billed and recorded`,
          tone: 'ok',
          backdrop: 'navy',
        };
      }
      return { icon: 'power', caption: 'Ready for a vehicle', sub: 'Charger idle · contactor open', tone: 'mute', backdrop: 'navy' };
  }
}
