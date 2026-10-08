// Ported 1:1 from chip-inventor/testbench/app/golden.py: restart_delay(),
// record_bytes(), and the Charger class. Every if/else, threshold, and
// flag mirrors the Python source; see golden.py for the spec citations
// (SS7.3 / SS7.4 / SS7.5 / SS7.6) plus "improvement made.md" for the
// meter watchdog and protocol-v2 frame recovery added on top.

import { crc16 } from './crc';
import { concatBytes, u16ToBytesLE, u32ToBytesLE } from './binutil';
import { encodeFrame, MARKER, ESCAPE } from './meterProtocol';
import {
  CHARGER_ID,
  ChargerState,
  F_CP_ERROR,
  F_CRC_LOST,
  F_ESTOP,
  F_GRID_HOLD,
  F_LOW,
  F_OVERCURRENT,
  HOLD_BASE,
  METER_TIMEOUT_MS,
  RX_TIMEOUT_MS,
  SAFETY,
  STATE_OUT,
  V_SAG,
  I_MAX,
} from './constants';

const { IDLE, CONNECTED, CHARGING, GRID_HOLD, FAULT, METER_TIMEOUT } = ChargerState;

/**
 * Healthy frames to wait before leaving GRID_HOLD (spec SS7.6).
 *
 * Hashing the charger ID with the triggering frame's CRC as seed de-syncs
 * the fleet: same grid event, different restart frame per charger.
 */
export function restartDelay(triggerCrc: number, chargerId: number = CHARGER_ID): number {
  const idBytes = u32ToBytesLE(chargerId >>> 0);
  return HOLD_BASE + (crc16(idBytes, triggerCrc) & 7);
}

/** The 8-byte session record (spec SS7.5). */
export function recordBytes(energy: number, status: number, frames: number): Uint8Array {
  const body = concatBytes(
    u32ToBytesLE(energy >>> 0),
    new Uint8Array([status & 0xFF]),
    new Uint8Array([frames & 0xFF]),
  );
  const crc = crc16(body);
  return concatBytes(body, u16ToBytesLE(crc));
}

export class Charger {
  state: ChargerState = IDLE;
  energy = 0;
  frames = 0;
  flags = 0;
  bad = 0;                     // consecutive bad frames (capped at 2)
  hold = 0;                     // healthy frames seen in GRID_HOLD
  delay = 0;                     // healthy frames required
  lastSequence: number | null = null;
  pins = 0;
  tx: number[] = [];
  rxAgeMs = 0;                   // ms since last UART activity while framing
  ageMs = 0;                     // ms since last healthy meter frame
  healthy = false;
  private _buf: number[] = [];
  private _active = false;
  private _escape = false;

  get out(): number {
    return STATE_OUT[this.state];
  }

  private _record(newState: number): void {
    this.tx.push(...recordBytes(this.energy, newState | this.flags, this.frames));
  }

  private _enterFault(flag: number): void {
    this.flags |= flag;
    this._record(FAULT);
    this.state = FAULT;
  }

  /**
   * Advance hardware time explicitly; silence and partial frames count.
   * A large time step must preserve which deadline expires first.
   */
  advanceMs(elapsed: number): void {
    if (elapsed < 0) {
      throw new Error('elapsed time must be non-negative');
    }
    const partialDue = this._active ? RX_TIMEOUT_MS - this.rxAgeMs : Infinity;
    const meterDue =
      this.state === CONNECTED || this.state === CHARGING || this.state === GRID_HOLD
        ? METER_TIMEOUT_MS - this.ageMs
        : Infinity;
    this.ageMs = Math.min(0xFFFFFFFF, this.ageMs + elapsed);
    this.rxAgeMs = Math.min(0xFFFFFFFF, this.rxAgeMs + elapsed);
    if (partialDue < meterDue) {
      this._checkPartialTimeout();
      this.checkTimeout();
    } else {
      this.checkTimeout();
      this._checkPartialTimeout();
    }
  }

  checkTimeout(): void {
    if (
      (this.state === CONNECTED || this.state === CHARGING || this.state === GRID_HOLD) &&
      this.ageMs >= METER_TIMEOUT_MS
    ) {
      this.healthy = false;
      this.state = METER_TIMEOUT;
      this._record(METER_TIMEOUT);
    }
  }

  /** Apply pilot/safety rules until stable; charging needs healthy data. */
  setInputs(value: number): void {
    this.pins = value & 0xFF;
    for (;;) {
      const before = this.state;
      this._stepPins();
      if (this.state === before) {
        this.checkTimeout();
        return;
      }
    }
  }

  private _stepPins(): void {
    const cp = this.pins & 0x07;
    const safety = Boolean(this.pins & SAFETY);

    if (this.state === FAULT || this.state === METER_TIMEOUT) {
      // Latched: only a clear safety pin and CP = A release it, no record.
      if (!safety && cp === 0) {
        this.state = IDLE;
      }
      return;
    }

    if (safety) {
      this._enterFault(F_ESTOP);
      return;
    }
    if (cp >= 4) {
      this._enterFault(F_CP_ERROR);
      return;
    }

    if (this.state === IDLE) {
      if (cp === 1 || cp === 2 || cp === 3) {
        this.energy = this.frames = this.flags = 0;
        this.ageMs = 0;
        this.healthy = false;
        this.lastSequence = null;
        this._buf = [];
        this._active = this._escape = false;
        this.state = CONNECTED;
      }
    } else if (this.state === CONNECTED) {
      if (cp === 2 && this.healthy && this.ageMs < METER_TIMEOUT_MS) {
        this.state = CHARGING;
      } else if (cp === 0) {
        this._record(IDLE);
        this.state = IDLE;
      }
    } else if (this.state === CHARGING || this.state === GRID_HOLD) {
      // CP = D (3) refused: no ventilation support, so charging stops.
      if (cp === 1 || cp === 3) {
        this.state = CONNECTED;
      } else if (cp === 0) {
        this._record(IDLE);
        this.state = IDLE;
      }
    }
  }

  private _badFrame(): void {
    this.bad = Math.min(2, this.bad + 1);
    if (this.bad >= 2 && this.state !== FAULT && this.state !== METER_TIMEOUT) {
      this._enterFault(F_CRC_LOST);
    }
  }

  private _checkPartialTimeout(): void {
    if (this._active && this.rxAgeMs >= RX_TIMEOUT_MS) {
      const partial = this._buf.length > 0 || this._escape;
      this._active = this._escape = false;
      this._buf = [];
      if (partial) {
        this._badFrame();
      }
    }
  }

  /** Consume a raw wire byte, recovering at the next unescaped marker. */
  rxByte(b: number): void {
    this._checkPartialTimeout();
    b &= 0xFF;
    if (b === MARKER) {
      if (this._active && (this._buf.length > 0 || this._escape)) {
        if (!this._escape && this._buf.length === 9) {
          this._onFrame(new Uint8Array(this._buf));
        } else {
          this._badFrame();
        }
      }
      this._buf = [];
      this._active = true;
      this._escape = false;
      this.rxAgeMs = 0;
      return;
    }
    if (!this._active) {
      return;
    }
    this.rxAgeMs = 0;
    if (this._escape) {
      if (b !== (MARKER ^ 0x20) && b !== (ESCAPE ^ 0x20)) {
        this._active = this._escape = false;
        this._buf = [];
        this._badFrame();
        return;
      }
      b ^= 0x20;
      this._escape = false;
    } else if (b === ESCAPE) {
      this._escape = true;
      return;
    }
    if (this._buf.length >= 9) {
      this._active = false;
      this._buf = [];
      this._badFrame();
      return;
    }
    this._buf.push(b);
  }

  /** Feed one unescaped 9-byte protocol-v2 body, wire-encoded first. */
  rxFrame(body: Uint8Array): void {
    for (const b of encodeFrame(body)) {
      this.rxByte(b);
    }
  }

  private _onFrame(frame: Uint8Array): void {
    this.checkTimeout();
    const field = frame[7] | (frame[8] << 8);
    if (crc16(frame.subarray(0, 7)) !== field) {
      this._badFrame();
      return;
    }
    const seq = frame[0];
    if (this.lastSequence !== null) {
      const delta = (seq - this.lastSequence) & 0xFF;
      if (delta === 0 || delta >= 128) {
        this._badFrame();
        return;
      }
      if (delta !== 1) {
        this.flags |= F_CRC_LOST;
      }
    }
    this.lastSequence = seq;

    this.bad = 0;                          // rule 3: reset in every state
    const v = frame[1] | (frame[2] << 8);
    const i = frame[3] | (frame[4] << 8);
    const f = frame[5] | (frame[6] << 8);
    this.ageMs = 0;
    this.healthy = i <= I_MAX && f >= F_LOW && v >= V_SAG;

    if (this.state === CONNECTED && (this.pins & 0x0F) === 2) {
      // Evaluate the initial frame before permitting the contactor.
      if (i > I_MAX) {
        this._enterFault(F_OVERCURRENT);
        return;
      }
      if (!this.healthy) {
        this.flags |= F_GRID_HOLD;
        this.delay = restartDelay(field);
        this.hold = 0;
        this.state = GRID_HOLD;
        return;
      }
      this.state = CHARGING;
    }

    if (this.state === CHARGING) {
      if (i > I_MAX) {
        this._enterFault(F_OVERCURRENT);
      } else if (f < F_LOW || v < V_SAG) {
        this.flags |= F_GRID_HOLD;
        this.delay = restartDelay(field);
        this.hold = 0;
        this.state = GRID_HOLD;
      } else {
        this.energy = (this.energy + v * i) >>> 0;
        this.frames = Math.min(this.frames + 1, 255);
      }
    } else if (this.state === GRID_HOLD) {
      // Over-current is ignored here: the contactor is already open.
      if (f >= F_LOW && v >= V_SAG) {
        this.hold += 1;
        if (this.hold >= this.delay) {
          this.state = CHARGING;           // this frame is not billed
        }
      } else {
        this.hold = 0;
      }
    }
  }
}
