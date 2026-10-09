// Static layout for the fleet diorama: four districts on a 26 x 19 plinth,
// split by a crossroads, fed from one substation. Every charging post stands
// for 25 real chargers (40 posts = the 1,000-charger fleet) and carries its
// first charger's real CRC-hashed restart delay, so lamps light in the true
// order. Everything else here (buildings, trees, poles) is set dressing.

import { HOLD_BASE } from '../../data/constants';
import { restartDelay } from '../../data/charger';
import { BASE_ID, TRIGGER_CRC } from '../../data/rebound';
import type { Phase } from './GridTimeline';

export type Vec2 = [number, number];
export type Vec3 = [number, number, number];

export const PLINTH_W = 26;
export const PLINTH_D = 19;
export const CHARGERS_PER_POST = 25;
export const KW = 7;

export const SUBSTATION: Vec2 = [-9.6, -5.2];

export interface District {
  name: string;
  /** Where the floating status badge sits. */
  badge: Vec3;
  /** Camera target when the story zooms into this district. */
  focus: Vec3;
  /** Pad-mount transformer at the end of the district's feeder. */
  pad: Vec2;
  /** Feeder route from the substation, pole tops between the ends. */
  route: Vec2[];
}

export const DISTRICTS: District[] = [
  {
    name: 'Office park',
    badge: [-4.0, 2.2, -3.3],
    focus: [-4.6, 0.4, -4.2],
    pad: [-6.75, -3.3],
    route: [[-7.6, -4.4]],
  },
  {
    name: 'Shopping mall',
    badge: [6.4, 2.6, -3.3],
    focus: [6.6, 0.4, -4.4],
    pad: [3.5, -5.2],
    route: [[-7.6, -5.2], [-1.15, -5.2], [1.15, -5.2]],
  },
  {
    name: 'Homes',
    badge: [-6.6, 2.4, 5.2],
    focus: [-6.6, 0.4, 5.0],
    pad: [-1.6, 4.5],
    route: [[-9.6, -2.6], [-12.2, -1.2], [-12.2, 1.2], [-12.2, 4.5], [-7.6, 4.5]],
  },
  {
    name: 'Highway hub',
    badge: [5.6, 2.9, 3.6],
    focus: [6.4, 0.4, 4.4],
    pad: [3.0, 1.9],
    route: [[-7.6, -5.2], [-1.15, -5.2], [1.15, -1.2], [1.15, 1.2]],
  },
];

export type PostKind = 'island' | 'home';

export interface Post {
  x: number;
  z: number;
  /** +1: the car parks on the +z side of the post, -1 on the -z side. */
  side: 1 | -1;
  kind: PostKind;
  district: number;
  /** Restart wave 0..7: the real hashed delay minus HOLD_BASE. */
  wave: number;
  car: string | null;
}

export interface ParkedCar {
  x: number;
  z: number;
  rot: number;
  color: string;
}

export const CAR_COLORS = ['#ECEEF1', '#C9CDD2', '#8A8F96', '#9FB1C9', '#D9CBB4', '#5B6068', '#E6E1D6'];

function mulberry32(seed: number) {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Five-column charging island, posts back to back, cars nose-in both sides. */
function island(cx: number, cz: number): { x: number; z: number; side: 1 | -1 }[] {
  const out: { x: number; z: number; side: 1 | -1 }[] = [];
  for (const side of [-1, 1] as const) {
    for (let c = 0; c < 5; c++) out.push({ x: cx + (c - 2) * 1.05, z: cz + side * 0.16, side });
  }
  return out;
}

export const HOUSE_XS = [-11.0, -8.8, -6.6, -4.4, -2.2];
export const HOUSE_ROWS: { z: number; side: 1 | -1 }[] = [
  { z: 2.75, side: 1 },
  { z: 7.65, side: -1 },
];

export const ISLANDS: { district: number; x: number; z: number; canopy: boolean }[] = [
  { district: 0, x: -4.0, z: -3.3, canopy: false },
  { district: 1, x: 6.4, z: -3.3, canopy: false },
  { district: 3, x: 5.6, z: 3.6, canopy: true },
];

export function buildPosts(): Post[] {
  const rand = mulberry32(0xc17159);
  const slots: Omit<Post, 'wave' | 'car'>[] = [];
  for (const isl of ISLANDS) {
    for (const p of island(isl.x, isl.z)) slots.push({ ...p, kind: 'island', district: isl.district });
  }
  for (const row of HOUSE_ROWS) {
    for (const hx of HOUSE_XS) slots.push({ x: hx + 0.42, z: row.z + row.side * 0.7, side: row.side, kind: 'home', district: 2 });
  }
  return slots.map((s, k) => ({
    ...s,
    // Each post stands for 25 chargers; use its first ID's real delay.
    wave: restartDelay(TRIGGER_CRC, BASE_ID + k * CHARGERS_PER_POST) - HOLD_BASE,
    car: rand() > 0.12 ? CAR_COLORS[Math.floor(rand() * CAR_COLORS.length)] : null,
  }));
}

/** Non-charging cars in the mall's overflow bays, for scale. */
export const PARKED: ParkedCar[] = [9.7, 10.75, 11.8].flatMap((x, i) => [
  { x, z: -4.25, rot: 0, color: CAR_COLORS[(i * 3 + 1) % CAR_COLORS.length] },
  { x, z: -2.35, rot: Math.PI, color: CAR_COLORS[(i * 2 + 4) % CAR_COLORS.length] },
]);

export interface Building {
  x: number;
  z: number;
  w: number;
  d: number;
  h: number;
  color: string;
  /** Window cell size in world units; larger = bigger panes. */
  cell: [number, number];
  sign?: string;
}

export const BUILDINGS: Building[] = [
  // Office park towers
  { x: -3.0, z: -7.3, w: 2.0, d: 2.0, h: 4.6, color: '#E7E9EC', cell: [0.4, 0.42] },
  { x: -5.6, z: -7.6, w: 2.1, d: 1.7, h: 3.2, color: '#D3D7DC', cell: [0.42, 0.42] },
  // Mall
  { x: 6.6, z: -7.3, w: 9.0, d: 3.0, h: 1.6, color: '#E7E3DA', cell: [0.9, 0.8], sign: '#F2C230' },
  // Highway hub kiosk and apartments
  { x: 10.4, z: 3.4, w: 2.6, d: 2.0, h: 1.2, color: '#E7E9EC', cell: [0.6, 0.6], sign: '#3CCF5A' },
  { x: 5.0, z: 7.6, w: 3.4, d: 1.6, h: 2.6, color: '#DCD6CC', cell: [0.42, 0.45] },
  { x: 9.8, z: 7.6, w: 3.2, d: 1.6, h: 3.4, color: '#E7E9EC', cell: [0.42, 0.45] },
];

export const TREES: Vec2[] = [
  [-12.0, 1.7], [-9.9, 1.7], [-7.7, 1.7], [-5.5, 1.7], [-3.3, 1.7],
  [-12.0, 8.85], [-9.9, 8.85], [-7.7, 8.85], [-5.5, 8.85], [-3.3, 8.85],
  [-1.6, -8.6], [-1.6, -6.4], [-12.4, -8.8], [-7.0, -8.8],
  [12.4, -1.9], [12.4, -6.2], [12.4, -8.6],
  [1.8, 8.6], [12.5, 1.8], [12.5, 5.6], [7.45, 7.6], [2.0, 5.4],
];

/** Street lamps along the crossroads sidewalks. */
export const STREET_LAMPS: Vec2[] = [
  ...[-11, -8, -5, -2.5, 2.5, 5, 8, 11].flatMap((x): Vec2[] => [[x, -1.25], [x, 1.25]]),
  ...[-8, -4, 4, 7.5].flatMap((z): Vec2[] => [[-1.25, z], [1.25, z]]),
];

// ---------------------------------------------------------------------------
// Per-post state, derived from the timeline. One table so the lamps, badges
// and feeders can never disagree.

export type PostState = 'charging' | 'paused' | 'alarm' | 'rebooting' | 'failed';

export function postState(phase: Phase, wave: number, rebootFailed: boolean, post: Post): PostState {
  switch (phase) {
    case 'dip':
    case 'rebound':
      return 'alarm';
    case 'hold':
      return 'paused';
    case 'stagger':
      return post.wave <= wave ? 'charging' : 'paused';
    case 'reboot':
      return rebootFailed ? 'failed' : 'rebooting';
    default:
      return 'charging';
  }
}

export const STATE_COLOR: Record<PostState, string> = {
  charging: '#3CCF5A',
  paused: '#F2B134',
  alarm: '#FF5A5F',
  rebooting: '#6EA8FF',
  failed: '#FF5A5F',
};

export const STATE_LABEL: Record<PostState, string> = {
  charging: 'Charging',
  paused: 'Paused',
  alarm: 'Under-frequency',
  rebooting: 'Rebooting',
  failed: 'Reboot failed',
};

/** Shot the camera frames for each moment of the story. */
export type Shot = { kind: 'overview' } | { kind: 'substation' } | { kind: 'district'; index: number };

export function shotFor(phase: Phase, attempt: number): Shot {
  switch (phase) {
    case 'dip':
    case 'surge':
      return { kind: 'substation' };
    case 'reboot':
      // Alternate districts across loops so each retry shows a new place.
      return { kind: 'district', index: attempt % 2 === 1 ? 1 : 2 };
    default:
      return { kind: 'overview' };
  }
}
