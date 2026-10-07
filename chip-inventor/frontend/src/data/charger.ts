// Ported 1:1 from chip-inventor/testbench/app/golden.py: restart_delay(),
// record_bytes(), and the Charger class. Every if/else, threshold, and
// flag mirrors the Python source; see golden.py for the spec citations
// (SS7.3 / SS7.4 / SS7.5 / SS7.6).

import { crc16 } from './crc';
import { bytesToU16LE, concatBytes, u16ToBytesLE, u32ToBytesLE } from './binutil';
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
  SAFETY,
  STATE_OUT,
  V_SAG,
  I_MAX,
} from './constants';

const { IDLE, CONNECTED, CHARGING, GRID_HOLD, FAULT } = ChargerState;

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
  bad = 0;              // consecutive bad frames
  hold = 0;              // healthy frames seen in GRID_HOLD
  delay = 0;              // healthy frames required
  seed = 0xFFFF;          // CRC chain seed
  pins = 0;
  tx: number[] = [];
  private _buf: number[] = [];

  get out(): number {
    return STATE_OUT[this.state];
  }

  private _record(newState: ChargerState): void {
    this.tx.push(...recordBytes(this.energy, newState | this.flags, this.frames));
  }

  private _enterFault(flag: number): void {
    this.flags |= flag;
    this._record(FAULT);
    this.state = FAULT;
  }

  /**
   * Apply the pilot/safety rules until the state is stable, so CP = C
   * straight from IDLE walks IDLE -> CONNECTED -> CHARGING (spec SS7.6).
   */
  setInputs(value: number): void {
    this.pins = value & 0xFF;
    for (;;) {
      const before = this.state;
      this._stepPins();
      if (this.state === before) {
        return;
      }
    }
  }

  private _stepPins(): void {
    const cp = this.pins & 0x07;
    const safety = Boolean(this.pins & SAFETY);

    if (this.state === FAULT) {
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
        this.state = CONNECTED;
      }
    } else if (this.state === CONNECTED) {
      if (cp === 2) {
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

  /**
   * Bytes are framed by count from reset -- no resync byte, the emulator
   * always sends whole frames (spec SS7.6).
   */
  rxByte(b: number): void {
    this._buf.push(b & 0xFF);
    if (this._buf.length === 8) {
      const frame = new Uint8Array(this._buf);
      this._buf = [];
      this._onFrame(frame);
    }
  }

  rxFrame(frame: Uint8Array): void {
    for (const b of frame) {
      this.rxByte(b);
    }
  }

  private _onFrame(frame: Uint8Array): void {
    const field = bytesToU16LE(frame, 6);
    const valid = crc16(frame.subarray(0, 6), this.seed) === field;
    this.seed = field;                     // rule 1: always advance

    if (!valid) {                          // rule 2: counted in FAULT too
      this.bad += 1;
      if (this.bad >= 2 && this.state !== FAULT) {
        this._enterFault(F_CRC_LOST);
      }
      return;
    }

    this.bad = 0;                          // rule 3: reset in every state
    const v = bytesToU16LE(frame, 0);
    const i = bytesToU16LE(frame, 2);
    const f = bytesToU16LE(frame, 4);

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
