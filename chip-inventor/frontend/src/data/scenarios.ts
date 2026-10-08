// Ported from chip-inventor/testbench/app/scenarios.py: the S1-S11 + S1X
// application scenario set (spec SS7.8). The harness-only scenarios
// (H0-H2, firmware == ORGANISER_FIRMWARE) are not backed by the Charger
// model and are out of scope for this viewer, so only the APP_FIRMWARE
// scenarios are ported here.
//
// Each step below corresponds to one option appended to a Python Scenario
// (an `i()`, `frame()`, or `record()` call) and records the model's state
// before/after, mirroring what `o()` would have asserted against the
// emulator.

import { ChargerState } from './constants';
import { Charger, restartDelay, recordBytes } from './charger';
import { Meter, corrupt } from './meter';

export interface ScenarioStep {
  type: 'datadir' | 'gpio_in' | 'gpio_out' | 'frame' | 'record' | 'tick';
  value?: number;
  frame?: Uint8Array;
  record?: Uint8Array;
  expectedOut?: number;
  stateBefore: ChargerState;
  stateAfter: ChargerState;
  energyAfter: number;
  framesAfter: number;
  flagsAfter: number;
  sequenceAfter: number | null;
  ageMsAfter: number;
  label: string;
  voltage?: number;
  current?: number;
  frequency?: number;
  sequence?: number;
  crcValid?: boolean;
  elapsedMs?: number;
}

export interface Scenario {
  id: string;
  title: string;
  category: 'normal' | 'grid' | 'fault' | 'integrity' | 'timeout';
  presetIn: number;
  steps: ScenarioStep[];
}

/**
 * Builder that mirrors scenarios.py's Scenario class for APP_FIRMWARE
 * scenarios only: it drives a Charger model and records one ScenarioStep
 * per operation, with before/after model snapshots for the viewer.
 */
class ScenarioBuilder {
  readonly model: Charger;
  readonly steps: ScenarioStep[] = [];
  readonly presetIn: number;

  constructor(presetIn = 0) {
    this.presetIn = presetIn;
    this.model = new Charger();
    // emu.c resets per command but the GPIO input value persists, so the
    // firmware can boot with pins already asserted.
    this.model.setInputs(presetIn);
  }

  private snapshot(type: ScenarioStep['type'], label: string, before: ChargerState, extra: Partial<ScenarioStep> = {}): ScenarioStep {
    return {
      type,
      label,
      stateBefore: before,
      stateAfter: this.model.state,
      energyAfter: this.model.energy,
      framesAfter: this.model.frames,
      flagsAfter: this.model.flags,
      sequenceAfter: this.model.lastSequence,
      ageMsAfter: this.model.ageMs,
      ...extra,
    };
  }

  /** Advance hardware time without any UART/GPIO activity (meter watchdog). */
  tick(elapsedMs: number, label = `tick(${elapsedMs}ms)`): this {
    const before = this.model.state;
    this.model.advanceMs(elapsedMs);
    this.steps.push(this.snapshot('tick', label, before, { elapsedMs }));
    return this;
  }

  /** -i value: drive GPIO input pins. */
  i(value: number, label = `i(0x${value.toString(16).padStart(2, '0')})`): this {
    const before = this.model.state;
    this.model.setInputs(value);
    this.steps.push(this.snapshot('gpio_in', label, before, { value }));
    return this;
  }

  /** Expected GPIO output, taken from the model's current state. */
  o(label = 'o()'): this {
    const before = this.model.state;
    this.steps.push(this.snapshot('gpio_out', label, before, { expectedOut: this.model.out }));
    return this;
  }

  /** Feed one unescaped 9-byte protocol-v2 frame body to the model. */
  frame(body: Uint8Array, label = 'frame()'): this {
    if (body.length !== 9) {
      throw new Error('protocol v2 requires a nine-byte unescaped body');
    }
    const before = this.model.state;
    const sequence = body[0];
    const v = body[1] | (body[2] << 8);
    const i = body[3] | (body[4] << 8);
    const f = body[5] | (body[6] << 8);
    this.model.rxFrame(body);
    this.steps.push(
      this.snapshot('frame', label, before, { frame: body, sequence, voltage: v, current: i, frequency: f }),
    );
    return this;
  }

  /** Read the session record: the model's tx buffer (one record). */
  record(label = 'record()'): this {
    const before = this.model.state;
    const tx = new Uint8Array(this.model.tx);
    if (tx.length !== 8) {
      throw new Error(
        `model transmitted ${tx.length} bytes, expected exactly 8 (one record per command)`,
      );
    }
    this.steps.push(this.snapshot('record', label, before, { record: tx }));
    return this;
  }
}

/** Healthy nominal frame: 230.0 V, 16.0 A, 50.00 Hz. */
function nominal(m: Meter): Uint8Array {
  return m.frame(2300, 160, 5000);
}

function buildScenarios(): Scenario[] {
  const scenarios: Scenario[] = [];

  // ---- S1: normal session ------------------------------------------------
  {
    const s = new ScenarioBuilder();
    const m = new Meter();
    s.i(0).o().i(1).o().i(2).o();
    s.frame(nominal(m)).o();
    s.frame(nominal(m)).o();
    s.i(1).o().i(0).o().record();
    scenarios.push({ id: 'S1', title: 'normal session: plug in, charge two frames, unplug', category: 'normal', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S1X: same, streamed ------------------------------------------------
  {
    const s = new ScenarioBuilder();
    const m = new Meter();
    s.i(0).o().i(1).o().i(2).o();
    s.frame(nominal(m));
    s.frame(nominal(m));
    s.o();
    s.i(1).o().i(0).o().record();
    scenarios.push({ id: 'S1X', title: 'stress: S1 with back-to-back UART bytes', category: 'normal', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S2: grid under-frequency -> hold -> CRC-timed restart -------------
  {
    const s = new ScenarioBuilder();
    const m = new Meter();
    s.i(1).o().i(2).o();
    s.frame(nominal(m)).o();
    const trigger = m.frame(2300, 160, 4920); // F < F_LOW -> GRID_HOLD
    const triggerField = trigger[7] | (trigger[8] << 8);
    const delay = restartDelay(triggerField);
    s.frame(trigger).o();
    s.frame(m.frame(2300, 160, 4940)).o(); // still unhealthy: count resets
    for (let k = 0; k < delay; k++) {
      s.frame(m.frame(2070, 160, 4950)).o(); // healthy frames; the last restarts charging
    }
    s.frame(nominal(m)).o();
    s.i(1).o().i(0).o().record();
    scenarios.push({ id: 'S2', title: 'grid under-frequency: hold, then CRC-timed restart', category: 'grid', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S3: corrupted frame and dropped frame -------------------------------
  {
    const s = new ScenarioBuilder();
    const m = new Meter();
    s.i(1).o().i(2).o();
    s.frame(nominal(m)).o();
    s.frame(corrupt(nominal(m))).o(); // rejected
    s.frame(nominal(m)).o();          // valid independent CRC recovers
    nominal(m);                        // generated but never delivered
    s.frame(nominal(m)).o();          // accepted: forward sequence gap is flagged
    s.frame(nominal(m)).o();          // accepted again
    s.i(0).o().record();
    scenarios.push({ id: 'S3', title: 'corrupted and missing frames: next valid frame recovers', category: 'integrity', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S4: meter link lost --------------------------------------------------
  {
    const s = new ScenarioBuilder();
    const m = new Meter();
    s.i(1).o().i(2).o();
    s.frame(nominal(m)).o();
    s.frame(corrupt(nominal(m))).o();
    s.frame(corrupt(nominal(m))).o(); // -> 0x80, CRC-lost flag
    s.i(0).o().record();
    scenarios.push({ id: 'S4', title: 'meter link lost: two bad frames in a row latch FAULT', category: 'fault', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S5: emergency stop while charging, latched ----------------------------
  {
    const s = new ScenarioBuilder();
    const m = new Meter();
    s.i(1).o().i(2).o();
    s.frame(nominal(m)).o();
    s.i(0x0A).o(); // CP C + SAFETY_TRIP -> FAULT
    s.i(0x02).o(); // still faulted
    s.i(0x08).o(); // still faulted
    s.i(0x00).o(); // released and unplugged -> IDLE
    s.record();
    scenarios.push({ id: 'S5', title: 'E-stop while charging latches FAULT until released and unplugged', category: 'fault', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S6: straight to C, unplug under load ----------------------------------
  {
    const s = new ScenarioBuilder();
    const m = new Meter();
    s.i(2).o(); // CONNECTED until first healthy frame
    s.frame(nominal(m)).o();
    s.i(0).o().record();
    scenarios.push({ id: 'S6', title: 'plug straight into CP C, then unplug while charging', category: 'normal', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S7: boundaries and over-current ----------------------------------------
  {
    const s = new ScenarioBuilder();
    const m = new Meter();
    s.i(1).o().i(2).o();
    s.frame(m.frame(2070, 320, 4950)).o(); // V_SAG, I_MAX, F_LOW exactly
    s.frame(m.frame(2300, 321, 5000)).o(); // I > I_MAX -> FAULT
    s.i(0).o().record();
    scenarios.push({ id: 'S7', title: 'frame exactly on every limit is billed; I_MAX+1 faults', category: 'fault', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S8: ventilation required, then CP error --------------------------------
  {
    const s = new ScenarioBuilder();
    s.i(1).o().i(3).o(); // D refused, stays CONNECTED
    s.i(2).o();           // C waits for healthy meter data
    s.i(3).o();           // D -> back to CONNECTED
    s.i(4).o();           // E -> FAULT, CP-error flag
    s.i(0).o().record();
    scenarios.push({ id: 'S8', title: 'ventilation (CP D) refused; CP E latches FAULT', category: 'fault', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S9: invalid pilot code ---------------------------------------------------
  {
    const s = new ScenarioBuilder();
    s.i(1).o().i(7).o().i(0).o().record();
    scenarios.push({ id: 'S9', title: 'invalid pilot code 7 latches FAULT with the CP-error flag', category: 'fault', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S10: replayed frame --------------------------------------------------------
  {
    const s = new ScenarioBuilder();
    const m = new Meter();
    s.i(1).o().i(2).o();
    const f1 = nominal(m);
    const f2 = nominal(m);
    s.frame(f1).o();
    s.frame(f2).o();
    s.frame(f1).o();  // replay -> rejected
    s.frame(f1).o();  // second replay -> FAULT
    s.i(0).o().record();
    scenarios.push({ id: 'S10', title: 'two replayed frames rejected -> FAULT', category: 'integrity', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S11: stale input pins at power-up -------------------------------------------
  {
    const s = new ScenarioBuilder(0x02);
    const m = new Meter();
    s.o();                     // 0x20 without any -i
    s.frame(nominal(m)).o();
    s.i(0).o().record();
    scenarios.push({ id: 'S11', title: 'stale pins at boot: CP C waits for healthy meter data', category: 'normal', presetIn: s.presetIn, steps: s.steps });
  }

  // ---- S12: meter watchdog timeout ---------------------------------------
  // Not in scenarios.py (the pytest suite covers this in test_watchdog.py
  // instead); added here so the viewer can show the headline new feature
  // from "improvement made.md" -- 500 ms without a healthy frame opens the
  // contactor and latches METER_TIMEOUT, mirroring
  // test_no_data_at_startup_times_out_with_contactor_open.
  {
    const s = new ScenarioBuilder();
    s.i(1).o().i(2).o(); // CONNECTED, contactor still open: no healthy frame yet
    s.tick(499).o();     // just under the deadline: still CONNECTED
    s.tick(1).o();       // deadline reached: METER_TIMEOUT, fault LED (0x80)
    s.record();
    scenarios.push({ id: 'S12', title: 'meter watchdog: 500 ms silence opens the contactor', category: 'timeout', presetIn: s.presetIn, steps: s.steps });
  }

  return scenarios;
}

export const SCENARIOS: Scenario[] = buildScenarios();

export interface ReplayResult {
  state: ChargerState;
  energy: number;
  frames: number;
  flags: number;
  tx: Uint8Array;
}

/**
 * Re-run a scenario's inputs through a fresh Charger, corrupting the meter
 * frames whose 0-based frame index is in `corruptFrames`. Used by the
 * what-if view so its billing numbers come from the model, not the UI.
 */
export function replayScenario(scenario: Scenario, corruptFrames: ReadonlySet<number>): ReplayResult {
  const c = new Charger();
  c.setInputs(scenario.presetIn);
  let frameIndex = 0;
  for (const step of scenario.steps) {
    if (step.type === 'gpio_in' && step.value !== undefined) {
      c.setInputs(step.value);
    } else if (step.type === 'frame' && step.frame) {
      c.rxFrame(corruptFrames.has(frameIndex) ? corrupt(step.frame) : step.frame);
      frameIndex++;
    } else if (step.type === 'tick' && step.elapsedMs !== undefined) {
      c.advanceMs(step.elapsedMs);
    }
  }
  return { state: c.state, energy: c.energy, frames: c.frames, flags: c.flags, tx: new Uint8Array(c.tx) };
}

// Re-exported for consumers that want the raw model primitives (e.g. the
// rebound viewer or ad-hoc record decoding).
export { restartDelay, recordBytes };
