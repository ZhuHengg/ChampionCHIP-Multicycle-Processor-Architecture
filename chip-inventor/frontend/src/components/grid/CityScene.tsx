// Isometric clay town for the fleet view, in the same visual language as the
// station diorama: an office park with the substation, a shopping mall, a
// street of homes and a highway fast-charge hub, with live traffic, lit
// windows and the feeders that tie them together. Layout and the per-post
// restart waves live in cityLayout.ts; this file is presentation only.
//
// The camera directs the story: it glides to the substation when the grid
// dips or the restart spike lands, and into a district to show a failed
// reboot up close. Nothing snaps -- colours, lights and the camera all ease.
// Reduced motion snaps every value and freezes traffic and spinners.

import { Suspense, useEffect, useMemo, useRef } from 'react';
import type { MutableRefObject } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { ContactShadows, Environment, Html, Lightformer, Line, RoundedBox } from '@react-three/drei';
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import type { Line2 } from 'three-stdlib';
import StatusIcon3D from '../station/StatusIcon3D';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import type { IconKind } from '../station/stationStory';
import type { Phase } from './GridTimeline';
import { F_LOW } from '../../data/constants';
import {
  BUILDINGS,
  CHARGERS_PER_POST,
  DISTRICTS,
  HOUSE_ROWS,
  HOUSE_XS,
  ISLANDS,
  KW,
  PARKED,
  PLINTH_D,
  PLINTH_W,
  STATE_COLOR,
  STATE_LABEL,
  STREET_LAMPS,
  SUBSTATION,
  TREES,
  buildPosts,
  postState,
  shotFor,
} from './cityLayout';
import type { Building, Post, PostState, Vec2, Vec3 } from './cityLayout';

export interface CitySceneProps {
  phase: Phase;
  wave: number;
  icon: IconKind;
  attempt: number;
  rebootFailed: boolean;
  /** MW reconnecting on the current frame, for the substation readout. */
  stepMw: number;
}

const PLINTH = '#6A6F77';
const ROAD = '#42464D';
const WALK = '#8C9198';
const CLAY = '#E7E9EC';
const CLAY_2 = '#C8CCD1';
const METAL = '#9AA0A7';
const RED = '#FF5A5F';

/** Shared, per-frame-mutable state the director writes and parts read. */
interface CityEnv {
  /** Building and street lighting, 0 = dark, 1 = normal. */
  light: number;
  /** Grid stress 0..1: drives substation glow and flicker. */
  stress: number;
}
type EnvRef = MutableRefObject<CityEnv>;

const easeDamp = (reduced: boolean, lambda: number, dt: number) => (reduced ? 1 : 1 - Math.exp(-lambda * dt));

// ---------------------------------------------------------------------------
// Shared geometry: dozens of cars and posts reuse the same buffers.

function useSharedGeometry() {
  return useMemo(
    () => ({
      carBody: new RoundedBoxGeometry(0.5, 0.2, 0.95, 3, 0.07),
      carCabin: new RoundedBoxGeometry(0.44, 0.17, 0.52, 3, 0.06),
      carRoof: new RoundedBoxGeometry(0.42, 0.035, 0.4, 2, 0.015),
      wheel: new THREE.CylinderGeometry(0.09, 0.09, 0.07, 16).rotateZ(Math.PI / 2),
      postBody: new RoundedBoxGeometry(0.24, 0.62, 0.18, 3, 0.05),
      postCap: new RoundedBoxGeometry(0.29, 0.06, 0.23, 2, 0.025),
      postBase: new THREE.BoxGeometry(0.34, 0.05, 0.28),
      lamp: new THREE.SphereGeometry(0.07, 16, 16),
      ring: new THREE.TorusGeometry(0.17, 0.028, 10, 40, Math.PI * 1.5),
      crossBar: new RoundedBoxGeometry(0.36, 0.07, 0.04, 2, 0.02),
      cable: new THREE.CylinderGeometry(0.018, 0.018, 1, 6),
    }),
    [],
  );
}
type Geo = ReturnType<typeof useSharedGeometry>;

// ---------------------------------------------------------------------------
// Facade texture: one tiny canvas, repeated per face, gives every building
// real-looking window grids; its twin drives which panes glow at night.

function makeFacadeTextures() {
  const draw = (wall: string, pane: string) => {
    const c = document.createElement('canvas');
    c.width = c.height = 64;
    const g = c.getContext('2d')!;
    g.fillStyle = wall;
    g.fillRect(0, 0, 64, 64);
    g.fillStyle = pane;
    g.fillRect(12, 14, 40, 34);
    const t = new THREE.CanvasTexture(c);
    t.wrapS = t.wrapT = THREE.RepeatWrapping;
    return t;
  };
  const map = draw('#FFFFFF', '#7D8898');
  map.colorSpace = THREE.SRGBColorSpace;
  const glow = draw('#000000', '#FFFFFF');
  return { map, glow };
}

function useFacadeMaterials(w: number, d: number, h: number, color: string, cell: [number, number]) {
  return useMemo(() => {
    const { map, glow } = makeFacadeTextures();
    const face = (span: number) => {
      const m = map.clone();
      const e = glow.clone();
      for (const t of [m, e]) {
        t.repeat.set(Math.max(1, Math.round(span / cell[0])), Math.max(1, Math.round(h / cell[1])));
        t.needsUpdate = true;
      }
      return new THREE.MeshStandardMaterial({ color, map: m, emissive: '#FFD38A', emissiveMap: e, emissiveIntensity: 0.9, roughness: 0.6 });
    };
    const xFace = face(d);
    const zFace = face(w);
    const plain = new THREE.MeshStandardMaterial({ color, roughness: 0.7 });
    // BoxGeometry material order: +x, -x, +y, -y, +z, -z.
    return [xFace, xFace, plain, plain, zFace, zFace];
  }, [w, d, h, color, cell]);
}

function BuildingBlock({ b, env, reducedMotion }: { b: Building; env: EnvRef; reducedMotion: boolean }) {
  const mats = useFacadeMaterials(b.w, b.d, b.h, b.color, b.cell);
  const sign = useRef<THREE.MeshStandardMaterial>(null);
  useFrame(() => {
    const lit = env.current.light;
    mats[0].emissiveIntensity = mats[4].emissiveIntensity = 0.9 * lit;
    if (sign.current) sign.current.emissiveIntensity = 1.6 * lit;
  });
  void reducedMotion;
  return (
    <group position={[b.x, 0, b.z]}>
      <mesh position={[0, b.h / 2, 0]} material={mats} castShadow receiveShadow>
        <boxGeometry args={[b.w, b.h, b.d]} />
      </mesh>
      {/* Roof parapet keeps the clay-render softness on top */}
      <RoundedBox args={[b.w + 0.1, 0.12, b.d + 0.1]} radius={0.05} smoothness={3} position={[0, b.h + 0.04, 0]} castShadow>
        <meshStandardMaterial color={b.color} roughness={0.6} />
      </RoundedBox>
      {/* Rooftop plant on the taller blocks */}
      {b.h > 2.5 && (
        <RoundedBox args={[b.w * 0.35, 0.28, b.d * 0.35]} radius={0.05} smoothness={3} position={[b.w * 0.15, b.h + 0.24, -b.d * 0.12]} castShadow>
          <meshStandardMaterial color={CLAY_2} roughness={0.6} />
        </RoundedBox>
      )}
      {b.sign && (
        <mesh position={[0, b.h - 0.22, b.d / 2 + 0.03]}>
          <boxGeometry args={[Math.min(b.w * 0.5, 2.4), 0.16, 0.04]} />
          <meshStandardMaterial ref={sign} color={b.sign} emissive={b.sign} emissiveIntensity={1.6} toneMapped={false} />
        </mesh>
      )}
    </group>
  );
}

function useRoofGeometry() {
  return useMemo(() => {
    const s = new THREE.Shape();
    s.moveTo(-0.66, 0);
    s.lineTo(0.66, 0);
    s.lineTo(0, 0.5);
    s.closePath();
    const g = new THREE.ExtrudeGeometry(s, { depth: 1.6, bevelEnabled: false });
    g.rotateY(Math.PI / 2);
    g.translate(-0.8, 0, 0);
    return g;
  }, []);
}

function House({ x, z, side, env, roof }: { x: number; z: number; side: 1 | -1; env: EnvRef; roof: THREE.BufferGeometry }) {
  const mats = useFacadeMaterials(1.4, 1.1, 0.85, '#ECE8E1', [0.5, 0.45]);
  useFrame(() => {
    mats[0].emissiveIntensity = mats[4].emissiveIntensity = 0.75 * env.current.light;
  });
  return (
    <group position={[x, 0, z]}>
      <mesh position={[0, 0.425, 0]} material={mats} castShadow receiveShadow>
        <boxGeometry args={[1.4, 0.85, 1.1]} />
      </mesh>
      <mesh geometry={roof} position={[0, 0.85, 0]} castShadow>
        <meshStandardMaterial color="#A9A196" roughness={0.75} />
      </mesh>
      {/* Front door, facing the street */}
      <mesh position={[-0.35, 0.2, side * 0.556]}>
        <boxGeometry args={[0.2, 0.36, 0.02]} />
        <meshStandardMaterial color="#6F6A63" roughness={0.6} />
      </mesh>
      {/* Driveway */}
      <mesh position={[0.42, 0.006, side * 1.25]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
        <planeGeometry args={[0.7, 1.35]} />
        <meshStandardMaterial color="#9A9EA4" roughness={0.9} />
      </mesh>
    </group>
  );
}

function Tree({ x, z, k }: { x: number; z: number; k: number }) {
  const s = 0.85 + ((k * 37) % 10) / 30;
  return (
    <group position={[x, 0, z]} scale={s}>
      <mesh position={[0, 0.22, 0]} castShadow>
        <cylinderGeometry args={[0.05, 0.07, 0.44, 8]} />
        <meshStandardMaterial color="#8A7B6B" roughness={0.8} />
      </mesh>
      <mesh position={[0, 0.62, 0]} castShadow>
        <sphereGeometry args={[0.32, 18, 14]} />
        <meshStandardMaterial color="#A7B89F" roughness={0.75} />
      </mesh>
      <mesh position={[0.12, 0.84, -0.05]} castShadow>
        <sphereGeometry args={[0.2, 14, 12]} />
        <meshStandardMaterial color="#B6C6AE" roughness={0.75} />
      </mesh>
    </group>
  );
}

function StreetLamp({ x, z, env }: { x: number; z: number; env: EnvRef }) {
  const head = useRef<THREE.MeshStandardMaterial>(null);
  useFrame(() => {
    if (head.current) head.current.emissiveIntensity = 1.4 * env.current.light;
  });
  return (
    <group position={[x, 0, z]}>
      <mesh position={[0, 0.55, 0]}>
        <cylinderGeometry args={[0.022, 0.03, 1.1, 8]} />
        <meshStandardMaterial color={METAL} roughness={0.5} />
      </mesh>
      <mesh position={[0, 1.12, 0]}>
        <sphereGeometry args={[0.06, 12, 12]} />
        <meshStandardMaterial ref={head} color="#FFF3D6" emissive="#FFE2A8" emissiveIntensity={1.4} toneMapped={false} />
      </mesh>
    </group>
  );
}

// ---------------------------------------------------------------------------
// Cars

function Car({ geo, color, glass = '#16181B' }: { geo: Geo; color: string; glass?: string }) {
  return (
    <group>
      <mesh geometry={geo.carBody} position={[0, 0.17, 0]} castShadow>
        <meshStandardMaterial color={color} roughness={0.42} />
      </mesh>
      <mesh geometry={geo.carCabin} position={[0, 0.33, -0.04]} castShadow>
        <meshStandardMaterial color={glass} roughness={0.12} metalness={0.3} />
      </mesh>
      <mesh geometry={geo.carRoof} position={[0, 0.42, -0.04]}>
        <meshStandardMaterial color={color} roughness={0.4} />
      </mesh>
      {[
        [0.24, 0.3],
        [-0.24, 0.3],
        [0.24, -0.3],
        [-0.24, -0.3],
      ].map(([wx, wz]) => (
        <mesh key={`${wx},${wz}`} geometry={geo.wheel} position={[wx, 0.09, wz]}>
          <meshStandardMaterial color="#1C1E21" roughness={0.85} />
        </mesh>
      ))}
    </group>
  );
}

// ---------------------------------------------------------------------------
// Charging post: lamp, screen, cable to the car, and the reboot spinner that
// turns into a red cross when the fixed-delay fleet fails to come back.

function ChargerPost({ post, state, geo, reducedMotion, surge }: { post: Post; state: PostState; geo: Geo; reducedMotion: boolean; surge: boolean }) {
  const lamp = useRef<THREE.MeshStandardMaterial>(null);
  const screen = useRef<THREE.MeshStandardMaterial>(null);
  const port = useRef<THREE.MeshStandardMaterial>(null);
  const badge = useRef<THREE.Group>(null);
  const ring = useRef<THREE.Mesh>(null);
  const ringMat = useRef<THREE.MeshStandardMaterial>(null);
  const cross = useRef<THREE.Group>(null);
  const target = useMemo(() => new THREE.Color(), []);
  const anim = useRef({ ring: 0, cross: 0, shake: 0, lastState: state });
  const scale = post.kind === 'home' ? 0.82 : 1;
  const carZ = post.side * (post.kind === 'home' ? 0.6 : 0.79);

  useFrame(({ clock, camera }, delta) => {
    const t = clock.getElapsedTime();
    const a = anim.current;
    if (a.lastState !== state) {
      if (state === 'failed') a.shake = 1;
      a.lastState = state;
    }
    const k = easeDamp(reducedMotion, 7, delta);
    target.set(STATE_COLOR[state]);
    let glow = 1.8;
    if (state === 'alarm' && !reducedMotion) glow = 1.2 + 1.0 * (0.5 + 0.5 * Math.sin(t * 9));
    if (state === 'rebooting' && !reducedMotion) glow = 0.6 + 1.6 * (Math.sin(t * 6 + post.x) > 0 ? 1 : 0.15);
    if (surge && state === 'charging') glow = 3.6;
    for (const m of [lamp.current, screen.current]) {
      if (!m) continue;
      m.emissive.lerp(target, k);
      if (m === lamp.current) m.color.lerp(target, k);
    }
    if (lamp.current) lamp.current.emissiveIntensity = THREE.MathUtils.lerp(lamp.current.emissiveIntensity, glow, k);
    if (screen.current) screen.current.emissiveIntensity = THREE.MathUtils.lerp(screen.current.emissiveIntensity, glow * 0.35, k);
    if (port.current) {
      const on = state === 'charging' ? 0.9 + 0.5 * Math.sin(t * 3 + post.z) : 0;
      port.current.emissiveIntensity = THREE.MathUtils.lerp(port.current.emissiveIntensity, reducedMotion ? (state === 'charging' ? 1 : 0) : on, k);
    }

    // Reboot spinner -> failure cross, billboarded toward the camera.
    const g = badge.current;
    if (!g) return;
    a.ring = THREE.MathUtils.lerp(a.ring, state === 'rebooting' ? 1 : 0, easeDamp(reducedMotion, state === 'rebooting' ? 6 : 12, delta));
    a.cross = THREE.MathUtils.lerp(a.cross, state === 'failed' ? 1 : 0, easeDamp(reducedMotion, 9, delta));
    a.shake = reducedMotion ? 0 : Math.max(0, a.shake - delta * 1.6);
    g.visible = a.ring > 0.01 || a.cross > 0.01;
    if (!g.visible) return;
    g.quaternion.copy(camera.quaternion);
    g.position.x = Math.sin(t * 46) * 0.05 * a.shake;
    if (ring.current) {
      ring.current.scale.setScalar(Math.max(a.ring, 0.001));
      if (!reducedMotion) ring.current.rotation.z = -t * 5;
    }
    if (ringMat.current) ringMat.current.emissiveIntensity = 1.6;
    if (cross.current) {
      // Springy pop: overshoot then settle.
      const s = a.cross * (1 + 0.35 * Math.sin(a.cross * Math.PI));
      cross.current.scale.setScalar(Math.max(s, 0.001));
    }
  });

  return (
    <group position={[post.x, 0, post.z]}>
      <group scale={scale} rotation={[0, post.side === 1 ? 0 : Math.PI, 0]}>
        <mesh geometry={geo.postBase} position={[0, 0.025, 0]} receiveShadow>
          <meshStandardMaterial color="#8A8F96" roughness={0.7} />
        </mesh>
        <mesh geometry={geo.postBody} position={[0, 0.36, 0]} castShadow>
          <meshStandardMaterial color={CLAY} roughness={0.55} />
        </mesh>
        <mesh geometry={geo.postCap} position={[0, 0.69, 0]} castShadow>
          <meshStandardMaterial color="#F4F5F7" roughness={0.5} />
        </mesh>
        {/* Screen faces the car bay */}
        <mesh position={[0, 0.48, 0.092]}>
          <planeGeometry args={[0.15, 0.11]} />
          <meshStandardMaterial ref={screen} color="#0C1018" emissive={STATE_COLOR[state]} emissiveIntensity={0.6} roughness={0.25} />
        </mesh>
        <mesh geometry={geo.lamp} position={[0, 0.78, 0]}>
          <meshStandardMaterial ref={lamp} color={STATE_COLOR[state]} emissive={STATE_COLOR[state]} emissiveIntensity={1.8} toneMapped={false} />
        </mesh>
      </group>

      {post.car && (
        <group position={[0, 0, carZ]} rotation={[0, post.side === 1 ? Math.PI : 0, 0]}>
          <Car geo={geo} color={post.car} />
          {/* Charge port glow on the nose, where the cable lands */}
          <mesh position={[0.16, 0.2, 0.48]}>
            <boxGeometry args={[0.08, 0.05, 0.02]} />
            <meshStandardMaterial ref={port} color="#2A2D33" emissive="#3CCF5A" emissiveIntensity={0} toneMapped={false} />
          </mesh>
        </group>
      )}
      {post.car && (
        <mesh
          geometry={geo.cable}
          position={[0.1, 0.24, post.side * 0.2]}
          rotation={[Math.PI / 2 - post.side * 0.35, 0, 0]}
          scale={[1, 0.36, 1]}
          castShadow
        >
          <meshStandardMaterial color="#1C1E21" roughness={0.5} />
        </mesh>
      )}

      <group position={[0, 1.15 * scale, 0]}>
        <group ref={badge} visible={false}>
          <mesh ref={ring} geometry={geo.ring}>
            <meshStandardMaterial ref={ringMat} color="#6EA8FF" emissive="#6EA8FF" emissiveIntensity={1.6} toneMapped={false} />
          </mesh>
          <group ref={cross} scale={0.001}>
            <mesh geometry={geo.crossBar} rotation={[0, 0, Math.PI / 4]}>
              <meshStandardMaterial color={RED} emissive={RED} emissiveIntensity={1.4} toneMapped={false} />
            </mesh>
            <mesh geometry={geo.crossBar} rotation={[0, 0, -Math.PI / 4]}>
              <meshStandardMaterial color={RED} emissive={RED} emissiveIntensity={1.4} toneMapped={false} />
            </mesh>
          </group>
        </group>
      </group>
    </group>
  );
}

function Canopy({ x, z, color }: { x: number; z: number; color: string }) {
  const strip = useRef<THREE.MeshStandardMaterial>(null);
  const target = useMemo(() => new THREE.Color(), []);
  useFrame((_, delta) => {
    if (!strip.current) return;
    target.set(color);
    strip.current.emissive.lerp(target, 1 - Math.exp(-6 * delta));
    strip.current.color.copy(strip.current.emissive);
  });
  return (
    <group position={[x, 0, z]}>
      {[-2.4, 0, 2.4].map((px) => (
        <mesh key={px} position={[px, 0.95, 0]} castShadow>
          <cylinderGeometry args={[0.06, 0.06, 1.9, 12]} />
          <meshStandardMaterial color={CLAY_2} roughness={0.5} />
        </mesh>
      ))}
      <RoundedBox args={[5.6, 0.14, 0.95]} radius={0.05} smoothness={3} position={[0, 1.95, 0]} castShadow>
        <meshStandardMaterial color="#F4F5F7" roughness={0.45} />
      </RoundedBox>
      <mesh position={[0, 1.95, 0.48]}>
        <boxGeometry args={[5.4, 0.05, 0.02]} />
        <meshStandardMaterial ref={strip} color={color} emissive={color} emissiveIntensity={1.4} toneMapped={false} />
      </mesh>
    </group>
  );
}

// ---------------------------------------------------------------------------
// Grid: substation, poles, feeders with flowing dashes, pad transformers.

const POLE_H = 2.3;
const GANTRY: Vec3 = [-7.7, 2.4, -5.2];

function sagPoints(route: Vec3[]): Vec3[] {
  const out: Vec3[] = [];
  for (let i = 0; i < route.length - 1; i++) {
    const [a, b] = [route[i], route[i + 1]];
    const n = 10;
    for (let j = 0; j < n; j++) {
      const t = j / n;
      const sag = Math.sin(Math.PI * t) * 0.22;
      out.push([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t - sag, a[2] + (b[2] - a[2]) * t]);
    }
  }
  out.push(route[route.length - 1]);
  return out;
}

interface FeederLook {
  color: string;
  /** Dash travel speed; 0 = no load on the line. */
  flow: number;
  flicker: boolean;
}

function Feeder({ points, look, reducedMotion }: { points: Vec3[]; look: FeederLook; reducedMotion: boolean }) {
  const line = useRef<Line2>(null);
  const target = useMemo(() => new THREE.Color(), []);
  const speed = useRef(look.flow);
  useFrame(({ clock }, delta) => {
    const l = line.current;
    if (!l) return;
    const m = l.material;
    target.set(look.color);
    m.color.lerp(target, easeDamp(reducedMotion, 5, delta));
    speed.current = THREE.MathUtils.lerp(speed.current, look.flow, easeDamp(reducedMotion, 3, delta));
    if (!reducedMotion) m.dashOffset -= speed.current * delta;
    m.opacity = look.flicker && !reducedMotion ? 0.55 + 0.45 * Math.abs(Math.sin(clock.getElapsedTime() * 11)) : 0.9;
  });
  return <Line ref={line} points={points} color={look.color} lineWidth={2.2} dashed dashSize={0.35} gapSize={0.22} transparent opacity={0.9} />;
}

function Pole({ x, z }: { x: number; z: number }) {
  return (
    <group position={[x, 0, z]}>
      <mesh position={[0, POLE_H / 2, 0]} castShadow>
        <cylinderGeometry args={[0.035, 0.05, POLE_H, 8]} />
        <meshStandardMaterial color="#8B7F72" roughness={0.8} />
      </mesh>
      <mesh position={[0, POLE_H - 0.08, 0]}>
        <boxGeometry args={[0.42, 0.04, 0.05]} />
        <meshStandardMaterial color="#8B7F72" roughness={0.8} />
      </mesh>
    </group>
  );
}

function Pad({ x, z, color, reducedMotion }: { x: number; z: number; color: string; reducedMotion: boolean }) {
  const lamp = useRef<THREE.MeshStandardMaterial>(null);
  const target = useMemo(() => new THREE.Color(), []);
  useFrame((_, delta) => {
    if (!lamp.current) return;
    target.set(color);
    lamp.current.emissive.lerp(target, easeDamp(reducedMotion, 6, delta));
    lamp.current.color.copy(lamp.current.emissive);
  });
  return (
    <group position={[x, 0, z]}>
      <RoundedBox args={[0.46, 0.42, 0.36]} radius={0.04} smoothness={3} position={[0, 0.21, 0]} castShadow>
        <meshStandardMaterial color="#A3AE9F" roughness={0.6} />
      </RoundedBox>
      <mesh position={[0, 0.47, 0]}>
        <sphereGeometry args={[0.05, 12, 12]} />
        <meshStandardMaterial ref={lamp} color={color} emissive={color} emissiveIntensity={1.8} toneMapped={false} />
      </mesh>
    </group>
  );
}

function Substation({ env, reducedMotion }: { env: EnvRef; reducedMotion: boolean }) {
  const heat = useRef<THREE.MeshStandardMaterial[]>([]);
  const beacon = useRef<THREE.MeshStandardMaterial>(null);
  const hot = useMemo(() => new THREE.Color('#FF6A3D'), []);
  const ok = useMemo(() => new THREE.Color('#3CCF5A'), []);
  useFrame(({ clock }) => {
    const s = env.current.stress;
    const t = clock.getElapsedTime();
    heat.current.forEach((m) => (m.emissiveIntensity = s * (reducedMotion ? 0.8 : 0.6 + 0.4 * Math.sin(t * 7))));
    if (beacon.current) {
      beacon.current.emissive.copy(ok).lerp(hot, Math.min(1, s * 1.5));
      beacon.current.color.copy(beacon.current.emissive);
      beacon.current.emissiveIntensity = s > 0.2 && !reducedMotion ? 1.2 + Math.sin(t * 9) : 1.6;
    }
  });
  return (
    <group position={[SUBSTATION[0], 0, SUBSTATION[1]]}>
      <RoundedBox args={[4.6, 0.1, 5.0]} radius={0.04} smoothness={3} position={[0, 0.05, 0]} receiveShadow>
        <meshStandardMaterial color="#B4B8BE" roughness={0.85} />
      </RoundedBox>
      {/* Fence */}
      {(
        [
          [0, -2.45, 4.5, 0.02],
          [0, 2.45, 4.5, 0.02],
          [-2.25, 0, 0.02, 4.9],
          [2.25, 0, 0.02, 4.9],
        ] as const
      ).map(([fx, fz, fw, fd], i) => (
        <mesh key={i} position={[fx, 0.3, fz]}>
          <boxGeometry args={[fw, 0.5, fd]} />
          <meshStandardMaterial color="#C9CDD2" transparent opacity={0.45} roughness={0.5} />
        </mesh>
      ))}
      {/* Transformers */}
      {[-1.2, 0, 1.2].map((tz, i) => (
        <group key={tz} position={[-0.6, 0.1, tz]}>
          <RoundedBox args={[1.1, 0.8, 0.8]} radius={0.06} smoothness={3} position={[0, 0.4, 0]} castShadow>
            <meshStandardMaterial
              ref={(m) => {
                if (m) heat.current[i] = m;
              }}
              color="#D7DADF"
              emissive="#FF6A3D"
              emissiveIntensity={0}
              roughness={0.5}
            />
          </RoundedBox>
          {/* Cooling fins */}
          {[-0.3, -0.1, 0.1, 0.3].map((fx) => (
            <mesh key={fx} position={[fx, 0.4, 0.43]}>
              <boxGeometry args={[0.05, 0.6, 0.08]} />
              <meshStandardMaterial color={METAL} roughness={0.5} />
            </mesh>
          ))}
          {[-0.3, 0, 0.3].map((bx) => (
            <mesh key={bx} position={[bx, 0.95, 0]}>
              <cylinderGeometry args={[0.04, 0.06, 0.32, 10]} />
              <meshStandardMaterial color="#8A8F96" />
            </mesh>
          ))}
        </group>
      ))}
      {/* Gantry and busbar */}
      {[-1.8, 1.8].map((gz) => (
        <mesh key={gz} position={[1.25, 1.2, gz]} castShadow>
          <boxGeometry args={[0.12, 2.4, 0.12]} />
          <meshStandardMaterial color={METAL} roughness={0.5} />
        </mesh>
      ))}
      <mesh position={[1.25, 2.38, 0]} castShadow>
        <boxGeometry args={[0.1, 0.1, 3.7]} />
        <meshStandardMaterial color={METAL} roughness={0.5} />
      </mesh>
      {/* Control house with beacon */}
      <RoundedBox args={[1.1, 0.7, 0.9]} radius={0.06} smoothness={3} position={[1.4, 0.45, 1.8]} castShadow>
        <meshStandardMaterial color={CLAY} roughness={0.55} />
      </RoundedBox>
      <mesh position={[1.4, 0.92, 1.8]}>
        <sphereGeometry args={[0.09, 14, 14]} />
        <meshStandardMaterial ref={beacon} color="#3CCF5A" emissive="#3CCF5A" emissiveIntensity={1.6} toneMapped={false} />
      </mesh>
    </group>
  );
}

/** Burst of sparks that re-fires whenever `trigger` changes. */
function Sparks({ at, trigger, reducedMotion }: { at: Vec3; trigger: number; reducedMotion: boolean }) {
  const N = 70;
  const points = useRef<THREE.Points>(null);
  const state = useMemo(() => ({ pos: new Float32Array(N * 3), vel: new Float32Array(N * 3), age: 99 }), []);
  const last = useRef(trigger);
  useFrame((_, rawDelta) => {
    const p = points.current;
    if (!p) return;
    const dt = Math.min(rawDelta, 0.05);
    if (last.current !== trigger) {
      last.current = trigger;
      if (!reducedMotion && trigger > 0) {
        state.age = 0;
        for (let i = 0; i < N; i++) {
          state.pos.set(at, i * 3);
          const a = Math.random() * Math.PI * 2;
          const r = 0.8 + Math.random() * 2.2;
          state.vel.set([Math.cos(a) * r, 1.5 + Math.random() * 2.5, Math.sin(a) * r], i * 3);
        }
      }
    }
    state.age += dt;
    const mat = p.material as THREE.PointsMaterial;
    mat.opacity = Math.max(0, 1 - state.age / 0.9);
    p.visible = mat.opacity > 0;
    if (!p.visible) return;
    for (let i = 0; i < N; i++) {
      state.vel[i * 3 + 1] -= 9 * dt;
      for (let c = 0; c < 3; c++) state.pos[i * 3 + c] += state.vel[i * 3 + c] * dt;
    }
    (p.geometry.attributes.position as THREE.BufferAttribute).needsUpdate = true;
  });
  return (
    <points ref={points} visible={false}>
      <bufferGeometry>
        <bufferAttribute attach="attributes-position" args={[state.pos, 3]} />
      </bufferGeometry>
      <pointsMaterial color="#FFD27A" size={5} sizeAttenuation={false} transparent depthWrite={false} toneMapped={false} />
    </points>
  );
}

// ---------------------------------------------------------------------------
// Traffic: cars on the crossroads with a working signal cycle, so they queue
// and cross instead of driving through each other.

const SIGNAL_CYCLE = 14;
const STOP_S = -1.3;
const VMAX = 1.7;

interface Lane {
  axis: 'h' | 'v';
  dir: 1 | -1;
  offset: number;
  half: number;
}
const LANES: Lane[] = [
  { axis: 'h', dir: 1, offset: 0.45, half: PLINTH_W / 2 + 0.6 },
  { axis: 'h', dir: -1, offset: -0.45, half: PLINTH_W / 2 + 0.6 },
  { axis: 'v', dir: 1, offset: -0.45, half: PLINTH_D / 2 + 0.6 },
  { axis: 'v', dir: -1, offset: 0.45, half: PLINTH_D / 2 + 0.6 },
];

function signalGreen(axis: 'h' | 'v', t: number): boolean {
  const c = t % SIGNAL_CYCLE;
  return axis === 'h' ? c < 5 : c >= 7 && c < 12;
}
function signalColor(axis: 'h' | 'v', t: number): string {
  const c = t % SIGNAL_CYCLE;
  const [g0, g1] = axis === 'h' ? [0, 5] : [7, 12];
  if (c >= g0 && c < g1) return '#3CCF5A';
  if (c >= g1 && c < g1 + 2) return '#F2B134';
  return RED;
}

function Traffic({ geo, reducedMotion }: { geo: Geo; reducedMotion: boolean }) {
  const cars = useMemo(
    () =>
      LANES.flatMap((lane, li) =>
        [0, 1].map((i) => ({
          lane: li,
          s: -lane.half + ((i * 2 * lane.half) / 2 + li * 3.1) % (2 * lane.half),
          v: VMAX,
          color: ['#ECEEF1', '#9FB1C9', '#5B6068', '#D9CBB4', '#C9CDD2', '#8A8F96', '#E6E1D6', '#ECEEF1'][li * 2 + i],
        })),
      ),
    [],
  );
  const refs = useRef<(THREE.Group | null)[]>([]);
  const lights = useRef<(THREE.MeshStandardMaterial | null)[]>([]);

  useFrame(({ clock }, rawDelta) => {
    const dt = reducedMotion ? 0 : Math.min(rawDelta, 0.05);
    const t = clock.getElapsedTime();
    cars.forEach((c, i) => {
      const lane = LANES[c.lane];
      const L = 2 * lane.half;
      let desired = VMAX;
      // Follow the car ahead in the same lane (with wrap-around).
      for (const o of cars) {
        if (o === c || o.lane !== c.lane) continue;
        let gap = o.s - c.s;
        if (gap < 0) gap += L;
        desired = Math.min(desired, Math.max(0, gap - 1.15) * 1.6);
      }
      // Stop at the line on red; amber counts as red if there is room.
      const front = c.s + 0.48;
      if (!signalGreen(lane.axis, t) && front < STOP_S + 0.05) {
        const room = STOP_S - front;
        if (room < 3) desired = Math.min(desired, Math.max(0, room) * 1.4);
      }
      c.v += THREE.MathUtils.clamp(desired - c.v, -6 * dt, 2.5 * dt);
      c.s += c.v * dt;
      if (c.s > lane.half) c.s -= L;

      const g = refs.current[i];
      if (!g) return;
      const along = c.s * lane.dir;
      if (lane.axis === 'h') g.position.set(along, 0, lane.offset);
      else g.position.set(lane.offset, 0, along);
      g.rotation.y = lane.axis === 'h' ? (lane.dir === 1 ? Math.PI / 2 : -Math.PI / 2) : lane.dir === 1 ? 0 : Math.PI;
      // Shrink in and out at the plinth edge rather than popping.
      const edge = lane.half - 0.6 - Math.abs(c.s);
      g.scale.setScalar(THREE.MathUtils.clamp(edge / 0.8, 0.001, 1));
    });
    lights.current.forEach((m, i) => {
      if (!m) return;
      const col = signalColor(i < 2 ? 'h' : 'v', t);
      m.color.set(col);
      m.emissive.set(col);
    });
  });

  return (
    <group>
      {cars.map((c, i) => (
        <group key={i} ref={(g) => void (refs.current[i] = g)}>
          <Car geo={geo} color={c.color} />
        </group>
      ))}
      {/* Signal heads on the four corners: two face the avenue, two the street */}
      {(
        [
          [-1.15, 1.15],
          [1.15, -1.15],
          [1.15, 1.15],
          [-1.15, -1.15],
        ] as const
      ).map(([sx, sz], i) => (
        <group key={i} position={[sx, 0, sz]}>
          <mesh position={[0, 0.45, 0]}>
            <cylinderGeometry args={[0.02, 0.025, 0.9, 8]} />
            <meshStandardMaterial color="#5B6068" />
          </mesh>
          <mesh position={[0, 0.92, 0]}>
            <sphereGeometry args={[0.06, 12, 12]} />
            <meshStandardMaterial ref={(m) => void (lights.current[i] = m)} color="#3CCF5A" emissive="#3CCF5A" emissiveIntensity={1.8} toneMapped={false} />
          </mesh>
        </group>
      ))}
    </group>
  );
}

// ---------------------------------------------------------------------------
// Camera rig: eases target and zoom between the overview and close-ups.

const CAM_OFFSET = new THREE.Vector3(12, 10, 12);
const OVERVIEW: Vec3 = [0, 0, 0.4];

function CameraRig({ shot, follow, reducedMotion }: { shot: ReturnType<typeof shotFor>; follow: MutableRefObject<THREE.Group | null>; reducedMotion: boolean }) {
  const { camera, size } = useThree();
  const target = useRef(new THREE.Vector3(...OVERVIEW));
  const zoomMul = useRef(1);
  const goal = useMemo(() => new THREE.Vector3(), []);
  // Fit the whole plinth (plus building height) in overview.
  const baseZoom = Math.min(size.width / 33, size.height / 21);

  useEffect(() => {
    camera.position.copy(target.current).add(CAM_OFFSET);
    camera.lookAt(target.current);
  }, [camera]);

  useFrame((_, delta) => {
    let mul = 1;
    if (shot.kind === 'substation') {
      goal.set(SUBSTATION[0] + 1.2, 0.6, SUBSTATION[1] + 0.6);
      mul = 1.9;
    } else if (shot.kind === 'district') {
      goal.set(...DISTRICTS[shot.index].focus);
      mul = 2.1;
    } else goal.set(...OVERVIEW);
    // Small screens see the whole town more often; close-ups go less deep.
    if (size.width < 640) mul = 1 + (mul - 1) * 0.6;
    const k = easeDamp(reducedMotion, 1.8, Math.min(delta, 0.05));
    target.current.lerp(goal, k);
    zoomMul.current = THREE.MathUtils.lerp(zoomMul.current, mul, k);
    const cam = camera as THREE.OrthographicCamera;
    cam.position.copy(target.current).add(CAM_OFFSET);
    cam.lookAt(target.current);
    cam.zoom = baseZoom * zoomMul.current;
    cam.updateProjectionMatrix();
    if (follow.current) follow.current.position.copy(target.current);
  });
  return null;
}

// ---------------------------------------------------------------------------
// Story director: lighting and grid stress per phase.

function Director({ env, phase, rebootFailed, reducedMotion }: { env: EnvRef; phase: Phase; rebootFailed: boolean; reducedMotion: boolean }) {
  useFrame(({ clock }, delta) => {
    const t = clock.getElapsedTime();
    let light = 1;
    let stress = 0;
    let flicker = 0;
    switch (phase) {
      case 'dip':
        stress = 0.6;
        flicker = 0.25;
        break;
      case 'surge':
        stress = 1;
        flicker = 0.2;
        break;
      case 'rebound':
        stress = 1;
        light = 0.45;
        flicker = 0.4;
        break;
      case 'reboot':
        stress = rebootFailed ? 0.9 : 0.5;
        light = rebootFailed ? 0.12 : 0.55;
        flicker = rebootFailed ? 0.08 : 0.35;
        break;
    }
    if (!reducedMotion && flicker > 0) {
      // Irregular brownout flicker: two incommensurate sines, thresholded.
      const n = Math.sin(t * 23.0) * Math.sin(t * 7.3 + 1.7);
      if (n > 0.55) light *= 1 - flicker * 2;
      else light *= 1 - flicker * 0.3 * (0.5 + 0.5 * Math.sin(t * 13));
    }
    const k = easeDamp(reducedMotion, 8, delta);
    env.current.light = THREE.MathUtils.lerp(env.current.light, Math.max(0, light), k);
    env.current.stress = THREE.MathUtils.lerp(env.current.stress, stress, easeDamp(reducedMotion, 3, delta));
  });
  return null;
}

// ---------------------------------------------------------------------------
// HTML overlays: district badges and the substation readout.

function DistrictBadge({ name, at, online, total, label, color, show }: { name: string; at: Vec3; online: number; total: number; label: string; color: string; show: boolean }) {
  const mw = (online * CHARGERS_PER_POST * KW) / 1000;
  return (
    <Html position={at} center zIndexRange={[20, 0]} style={{ pointerEvents: 'none', opacity: show ? 1 : 0, transition: 'opacity 400ms ease' }}>
      <div className="w-[150px] rounded-2xl bg-[#14161A]/80 px-3 py-2 text-white shadow-lg ring-1 ring-white/10 backdrop-blur-sm">
        <div className="flex items-center justify-between gap-2">
          <span className="truncate text-[12px] font-semibold">{name}</span>
          <span className="h-2 w-2 shrink-0 rounded-full transition-colors duration-500" style={{ backgroundColor: color, boxShadow: `0 0 8px ${color}` }} />
        </div>
        <div className="mt-0.5 text-[11px] transition-colors duration-500" style={{ color }}>
          {label}
        </div>
        <div className="mt-1.5 h-1 overflow-hidden rounded-full bg-white/15">
          <div className="h-full rounded-full transition-[width,background-color] duration-500" style={{ width: `${(online / total) * 100}%`, backgroundColor: color }} />
        </div>
        <div className="tabular mt-1 flex justify-between font-mono text-[10px] text-white/60">
          <span>
            {online * CHARGERS_PER_POST}/{total * CHARGERS_PER_POST}
          </span>
          <span>{mw.toFixed(2)} MW</span>
        </div>
      </div>
    </Html>
  );
}

function GridReadout({ phase, rebootFailed, stepMw, show }: { phase: Phase; rebootFailed: boolean; stepMw: number; show: boolean }) {
  const low = phase === 'dip' || phase === 'rebound' || (phase === 'reboot' && rebootFailed);
  const spike = phase === 'surge' || (phase === 'stagger' && stepMw > 0);
  const hz = `${(F_LOW / 100).toFixed(2)} Hz`;
  let text = `Grid OK · ≥ ${hz}`;
  let color = '#3CCF5A';
  if (low) {
    text = `Grid < ${hz}`;
    color = RED;
  } else if (spike) {
    text = `Load step +${stepMw.toFixed(2)} MW`;
    color = phase === 'surge' ? RED : '#F2B134';
  } else if (phase === 'reboot') {
    text = 'Breakers reclosing…';
    color = '#6EA8FF';
  }
  return (
    <Html position={[SUBSTATION[0], 3.1, SUBSTATION[1]]} center zIndexRange={[20, 0]} style={{ pointerEvents: 'none', opacity: show ? 1 : 0, transition: 'opacity 400ms ease' }}>
      <div className="flex items-center gap-2 rounded-full bg-[#14161A]/85 px-3 py-1.5 whitespace-nowrap text-white shadow-lg ring-1 ring-white/10 backdrop-blur-sm">
        <span className="text-[11px] text-white/60">Substation</span>
        <span className="tabular font-mono text-[12px] font-semibold transition-colors duration-500" style={{ color }}>
          {text}
        </span>
      </div>
    </Html>
  );
}

// ---------------------------------------------------------------------------

function Ground() {
  return (
    <group>
      <RoundedBox args={[PLINTH_W, 0.5, PLINTH_D]} radius={0.3} smoothness={6} position={[0, -0.25, 0]} receiveShadow>
        <meshStandardMaterial color={PLINTH} roughness={0.85} />
      </RoundedBox>
      {/* Sidewalks, then asphalt on top */}
      {(
        [
          [0, 0, PLINTH_W - 0.3, 2.5],
          [0, 0, 2.5, PLINTH_D - 0.3],
          [-6.85, 5.2, 11.9, 1.8],
        ] as const
      ).map(([x, z, w, d], i) => (
        <mesh key={`w${i}`} position={[x, 0.003, z]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
          <planeGeometry args={[w, d]} />
          <meshStandardMaterial color={WALK} roughness={0.9} />
        </mesh>
      ))}
      {(
        [
          [0, 0, PLINTH_W - 0.3, 1.8],
          [0, 0, 1.8, PLINTH_D - 0.3],
          [-6.85, 5.2, 11.9, 1.1],
        ] as const
      ).map(([x, z, w, d], i) => (
        <mesh key={`r${i}`} position={[x, 0.006, z]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
          <planeGeometry args={[w, d]} />
          <meshStandardMaterial color={ROAD} roughness={0.92} />
        </mesh>
      ))}
      {/* Lane dashes */}
      {Array.from({ length: 20 }, (_, i) => -12 + i * 1.25)
        .filter((x) => Math.abs(x) > 1.6)
        .map((x) => (
          <mesh key={`h${x}`} position={[x, 0.009, 0]} rotation={[-Math.PI / 2, 0, 0]}>
            <planeGeometry args={[0.55, 0.05]} />
            <meshBasicMaterial color="#C9CDD2" transparent opacity={0.55} />
          </mesh>
        ))}
      {Array.from({ length: 15 }, (_, i) => -8.75 + i * 1.25)
        .filter((z) => Math.abs(z) > 1.6)
        .map((z) => (
          <mesh key={`v${z}`} position={[0, 0.009, z]} rotation={[-Math.PI / 2, 0, 0]}>
            <planeGeometry args={[0.05, 0.55]} />
            <meshBasicMaterial color="#C9CDD2" transparent opacity={0.55} />
          </mesh>
        ))}
      {/* Zebra crossings on all four arms */}
      {[-1, 1].flatMap((sgn) =>
        Array.from({ length: 6 }, (_, i) => -0.75 + i * 0.3).flatMap((o) => [
          <mesh key={`zx${sgn}${o}`} position={[sgn * 1.45, 0.01, o]} rotation={[-Math.PI / 2, 0, 0]}>
            <planeGeometry args={[0.45, 0.14]} />
            <meshBasicMaterial color="#E4E6E9" transparent opacity={0.7} />
          </mesh>,
          <mesh key={`zz${sgn}${o}`} position={[o, 0.01, sgn * 1.45]} rotation={[-Math.PI / 2, 0, 0]}>
            <planeGeometry args={[0.14, 0.45]} />
            <meshBasicMaterial color="#E4E6E9" transparent opacity={0.7} />
          </mesh>,
        ]),
      )}
      {/* Parking lot asphalt under each charging island */}
      {ISLANDS.map((isl) => (
        <group key={`${isl.x},${isl.z}`}>
          <mesh position={[isl.x + (isl.district === 1 ? 1.6 : 0), 0.004, isl.z]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
            <planeGeometry args={[isl.district === 1 ? 8.8 : 5.8, 2.9]} />
            <meshStandardMaterial color="#565A61" roughness={0.9} />
          </mesh>
          {/* Bay lines */}
          {Array.from({ length: isl.district === 1 ? 10 : 6 }, (_, c) => isl.x - 2.625 + c * 1.05).map((bx) => (
            <mesh key={bx} position={[bx, 0.008, isl.z]} rotation={[-Math.PI / 2, 0, 0]}>
              <planeGeometry args={[0.035, 2.6]} />
              <meshBasicMaterial color="#C9CDD2" transparent opacity={0.5} />
            </mesh>
          ))}
          {/* Raised island under the posts */}
          <RoundedBox args={[5.4, 0.08, 0.6]} radius={0.03} smoothness={2} position={[isl.x, 0.04, isl.z]} receiveShadow>
            <meshStandardMaterial color="#B9BDC3" roughness={0.8} />
          </RoundedBox>
        </group>
      ))}
    </group>
  );
}

function Scene({ phase, wave, icon, attempt, rebootFailed, stepMw }: CitySceneProps) {
  const reducedMotion = usePrefersReducedMotion();
  const geo = useSharedGeometry();
  const roof = useRoofGeometry();
  const posts = useMemo(buildPosts, []);
  const env = useRef<CityEnv>({ light: 1, stress: 0 });
  const follow = useRef<THREE.Group>(null);
  const { size } = useThree();
  const wide = size.width >= 640;
  const shot = shotFor(phase, attempt);

  const states = posts.map((p) => postState(phase, wave, rebootFailed, p));
  const districts = DISTRICTS.map((d, i) => {
    const mine = states.filter((_, k) => posts[k].district === i);
    const online = mine.filter((s) => s === 'charging').length;
    const lead: PostState = online === mine.length ? 'charging' : online > 0 ? 'charging' : mine[0];
    const mixed = online > 0 && online < mine.length;
    const label = mixed ? `Restarting · ${online}/${mine.length} posts` : STATE_LABEL[mine[0]];
    const color = mixed ? '#F2B134' : STATE_COLOR[lead];
    let look: FeederLook = { color: '#9FB3D9', flow: 1.2, flicker: false };
    if (phase === 'surge') look = { color: RED, flow: 4.5, flicker: false };
    else if (mine[0] === 'alarm' || mine[0] === 'failed') look = { color: RED, flow: 0, flicker: true };
    else if (mine[0] === 'rebooting') look = { color: '#6EA8FF', flow: 0.4, flicker: false };
    else if (online === 0) look = { color: '#7C8798', flow: 0, flicker: false };
    else if (mixed) look = { color: '#F2C26A', flow: 1.2 * (online / mine.length), flicker: false };
    return { ...d, online, total: mine.length, label, color, look };
  });

  const feeders = useMemo(
    () =>
      DISTRICTS.map((d) => {
        const route: Vec3[] = [GANTRY, ...d.route.map(([x, z]): Vec3 => [x, POLE_H - 0.1, z]), [d.pad[0], 0.5, d.pad[1]]];
        return sagPoints(route);
      }),
    [],
  );
  const poles = useMemo(() => {
    const seen = new Set<string>();
    return DISTRICTS.flatMap((d) => d.route).filter(([x, z]) => {
      const key = `${x},${z}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }, []);

  // Sparks: at the substation when the spike lands, in the focused district
  // when its reboot fails.
  let sparkKey = 0;
  if (phase === 'surge' || phase === 'rebound') sparkKey = attempt * 10 + (phase === 'surge' ? 1 : 2);
  const failKey = phase === 'reboot' && rebootFailed ? attempt : 0;
  const failDistrict = shot.kind === 'district' ? DISTRICTS[shot.index] : DISTRICTS[1];
  const failAt: Vec3 = [failDistrict.pad[0], 0.6, failDistrict.pad[1]];

  return (
    <>
      <CameraRig shot={shot} follow={follow} reducedMotion={reducedMotion} />
      <Director env={env} phase={phase} rebootFailed={rebootFailed} reducedMotion={reducedMotion} />
      <hemisphereLight args={['#ffffff', '#3b4250', 0.9]} />
      <directionalLight
        position={[-8, 14, 9]}
        intensity={1.5}
        castShadow
        shadow-mapSize={[2048, 2048]}
        shadow-camera-left={-16}
        shadow-camera-right={16}
        shadow-camera-top={16}
        shadow-camera-bottom={-16}
        shadow-bias={-0.0004}
      />
      <Environment resolution={128} frames={1}>
        <Lightformer form="rect" intensity={2} position={[0, 8, 6]} scale={[14, 5, 1]} />
        <Lightformer form="rect" intensity={1} position={[-8, 4, 0]} rotation-y={Math.PI / 2} scale={[10, 4, 1]} />
      </Environment>

      <Ground />
      {BUILDINGS.map((b, i) => (
        <BuildingBlock key={i} b={b} env={env} reducedMotion={reducedMotion} />
      ))}
      {HOUSE_ROWS.flatMap((row) => HOUSE_XS.map((hx) => <House key={`${hx},${row.z}`} x={hx} z={row.z} side={row.side} env={env} roof={roof} />))}
      {TREES.map(([x, z], i) => (
        <Tree key={i} x={x} z={z} k={i} />
      ))}
      {STREET_LAMPS.map(([x, z]) => (
        <StreetLamp key={`${x},${z}`} x={x} z={z} env={env} />
      ))}
      {PARKED.map((c, i) => (
        <group key={i} position={[c.x, 0, c.z]} rotation={[0, c.rot, 0]}>
          <Car geo={geo} color={c.color} />
        </group>
      ))}
      <Canopy x={ISLANDS[2].x} z={ISLANDS[2].z} color={districts[3].color} />

      <Substation env={env} reducedMotion={reducedMotion} />
      {poles.map(([x, z]: Vec2) => (
        <Pole key={`${x},${z}`} x={x} z={z} />
      ))}
      {DISTRICTS.map((d, i) => (
        <Pad key={i} x={d.pad[0]} z={d.pad[1]} color={districts[i].color} reducedMotion={reducedMotion} />
      ))}
      {feeders.map((pts, i) => (
        <Feeder key={i} points={pts} look={districts[i].look} reducedMotion={reducedMotion} />
      ))}
      {posts.map((p, i) => (
        <ChargerPost key={i} post={p} state={states[i]} geo={geo} reducedMotion={reducedMotion} surge={phase === 'surge'} />
      ))}
      <Traffic geo={geo} reducedMotion={reducedMotion} />
      <Sparks at={[SUBSTATION[0] - 0.6, 1.2, SUBSTATION[1]]} trigger={sparkKey} reducedMotion={reducedMotion} />
      <Sparks at={failAt} trigger={failKey} reducedMotion={reducedMotion} />

      <ContactShadows position={[0, 0.012, 0]} scale={28} blur={2.4} far={4} opacity={0.4} resolution={1024} frames={1} />
      <ContactShadows position={[0, -0.52, 0]} scale={32} blur={3} far={2} opacity={0.55} resolution={256} frames={1} />

      {districts.map((d, i) => (
        <DistrictBadge key={i} name={d.name} at={d.badge} online={d.online} total={d.total} label={d.label} color={d.color} show={wide} />
      ))}
      <GridReadout phase={phase} rebootFailed={rebootFailed} stepMw={stepMw} show={wide} />

      {/* The story icon rides above whatever the camera is looking at */}
      <group ref={follow}>
        <StatusIcon3D kind={icon} position={[0, 4.4, 0]} size={1.6} reducedMotion={reducedMotion} />
      </group>
    </>
  );
}

export default function CityScene(props: CitySceneProps) {
  return (
    <Canvas
      orthographic
      shadows="soft"
      dpr={[1, 2]}
      gl={{ antialias: true, alpha: true }}
      camera={{ position: [12, 10, 12], zoom: 30, near: 0.1, far: 200 }}
      style={{ background: 'transparent' }}
    >
      <Suspense fallback={null}>
        <Scene {...props} />
      </Suspense>
    </Canvas>
  );
}
