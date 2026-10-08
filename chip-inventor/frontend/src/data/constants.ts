// Ported 1:1 from chip-inventor/testbench/app/golden.py (spec SS7.6).
// Placeholders, not real grid-code values.

export const F_LOW = 4950;            // 49.50 Hz
export const V_SAG = 2070;            // 207.0 V
export const I_MAX = 320;             // 32.0 A, over-current when I > I_MAX
export const HOLD_BASE = 2;           // minimum healthy frames before restart
export const CHARGER_ID = 0x4D590001; // "MY" + 0001, hashed as bytes 01 00 59 4D

// Meter watchdog (chip-inventor/improvement made.md, rtl/meter_timer.v).
export const METER_TIMEOUT_MS = 500;  // no healthy frame in this window -> fault
export const RX_TIMEOUT_MS = 100;     // partial/escaped frame abandoned after this

// Plain `enum` emits runtime code, which tsconfig's erasableSyntaxOnly
// forbids. This const-object + derived-union pattern is erasable (no
// runtime emission beyond the object literal) and is used identically
// at every call site (ChargerState.IDLE as both value and type).
export const ChargerState = {
  IDLE: 0,
  CONNECTED: 1,
  CHARGING: 2,
  GRID_HOLD: 3,
  FAULT: 4,
  METER_TIMEOUT: 5,
} as const;
export type ChargerState = (typeof ChargerState)[keyof typeof ChargerState];

export const STATE_NAMES: Record<ChargerState, string> = {
  [ChargerState.IDLE]: 'IDLE',
  [ChargerState.CONNECTED]: 'CONNECTED',
  [ChargerState.CHARGING]: 'CHARGING',
  [ChargerState.GRID_HOLD]: 'GRID_HOLD',
  [ChargerState.FAULT]: 'FAULT',
  [ChargerState.METER_TIMEOUT]: 'METER_TIMEOUT',
};

export const STATE_COLORS: Record<ChargerState, string> = {
  [ChargerState.IDLE]: '#8A877F',
  [ChargerState.CONNECTED]: '#3B6FD8',
  [ChargerState.CHARGING]: '#2E9E48',
  [ChargerState.GRID_HOLD]: '#C98F00',
  [ChargerState.FAULT]: '#D93F44',
  [ChargerState.METER_TIMEOUT]: '#D9661F',
};

// DATAOUT per state (spec SS7.3/7.6; METER_TIMEOUT shares FAULT's pattern).
export const STATE_OUT: Record<ChargerState, number> = {
  [ChargerState.IDLE]: 0x00,
  [ChargerState.CONNECTED]: 0x20,
  [ChargerState.CHARGING]: 0x30,
  [ChargerState.GRID_HOLD]: 0x60,
  [ChargerState.FAULT]: 0x80,
  [ChargerState.METER_TIMEOUT]: 0x80,
};

// STATUS cause flags (spec SS7.6).
export const F_ESTOP = 0x08;
export const F_CP_ERROR = 0x10;
export const F_OVERCURRENT = 0x20;
export const F_CRC_LOST = 0x40;
export const F_GRID_HOLD = 0x80;

export const SAFETY = 0x08;           // DATAIN bit 3
