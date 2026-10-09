// Glossy floating status icons in the style of the clay-render references:
// a single large 3D glyph above the car (check, bolt, sync arrows, broken
// sync, pause, alert, power). Built from extruded shapes and rounded bars,
// so no model files or network fetches are needed.

import { useMemo, useRef, useState } from 'react';
import type { ReactNode } from 'react';
import { useFrame } from '@react-three/fiber';
import { RoundedBox } from '@react-three/drei';
import * as THREE from 'three';
import type { IconKind } from './stationStory';

const GREEN = '#3CCF5A';
const RED = '#F0453F';
const AMBER = '#F2B134';
const SLATE = '#8EA2C0';
const WHITE = '#F7F8FA';

function Glossy({ color }: { color: string }) {
  return <meshPhysicalMaterial color={color} roughness={0.28} metalness={0} clearcoat={1} clearcoatRoughness={0.12} />;
}

const EXTRUDE: THREE.ExtrudeGeometryOptions = {
  depth: 0.16,
  bevelEnabled: true,
  bevelThickness: 0.04,
  bevelSize: 0.03,
  bevelSegments: 4,
  curveSegments: 48,
};

function useExtruded(build: () => THREE.Shape | THREE.Shape[]) {
  return useMemo(() => {
    const g = new THREE.ExtrudeGeometry(build(), EXTRUDE);
    g.center();
    return g;
    // Shapes are static per icon kind.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
}

function polar(r: number, a: number): [number, number] {
  return [Math.cos(a) * r, Math.sin(a) * r];
}

function Disc({ color }: { color: string }) {
  return (
    <mesh rotation={[Math.PI / 2, 0, 0]} castShadow>
      <cylinderGeometry args={[0.55, 0.55, 0.2, 72]} />
      <Glossy color={color} />
    </mesh>
  );
}

function Bar({ w, h, x = 0, y = 0, rot = 0, color = WHITE, z = 0.12 }: { w: number; h: number; x?: number; y?: number; rot?: number; color?: string; z?: number }) {
  return (
    <RoundedBox args={[w, h, 0.1]} radius={Math.min(w, h) / 2 - 0.001} smoothness={6} position={[x, y, z]} rotation={[0, 0, rot]} castShadow>
      <Glossy color={color} />
    </RoundedBox>
  );
}

function CheckIcon() {
  // Two rounded strokes meeting at the check's elbow (-0.08, -0.15).
  return (
    <group>
      <Disc color={GREEN} />
      <Bar w={0.3} h={0.11} x={-0.17} y={-0.06} rot={-Math.PI / 4} />
      <Bar w={0.52} h={0.11} x={0.08} y={0.02} rot={Math.PI / 3.6} />
    </group>
  );
}

function BoltIcon() {
  const geo = useExtruded(() => {
    const s = new THREE.Shape();
    const pts: [number, number][] = [
      [-0.02, 0.62], [0.32, 0.62], [0.11, 0.13], [0.36, 0.13],
      [-0.12, -0.62], [0.02, -0.07], [-0.32, -0.07],
    ];
    s.moveTo(...pts[0]);
    pts.slice(1).forEach((p) => s.lineTo(...p));
    s.closePath();
    return s;
  });
  return (
    <mesh geometry={geo} castShadow scale={1.15}>
      <Glossy color={GREEN} />
    </mesh>
  );
}

/** Two curved arrows chasing each other, built from torus arcs and cone heads. */
function SyncArrows({ color }: { color: string }) {
  const R = 0.42;
  const arcs = [THREE.MathUtils.degToRad(30), THREE.MathUtils.degToRad(210)];
  const sweep = THREE.MathUtils.degToRad(120);
  return (
    <group>
      {arcs.map((a0) => {
        const a1 = a0 + sweep;
        return (
          <group key={a0}>
            <mesh rotation={[0, 0, a0]} castShadow>
              <torusGeometry args={[R, 0.075, 20, 48, sweep]} />
              <Glossy color={color} />
            </mesh>
            {/* Head points along the CCW tangent (-sin a1, cos a1). */}
            <mesh
              position={[Math.cos(a1) * R - Math.sin(a1) * 0.1, Math.sin(a1) * R + Math.cos(a1) * 0.1, 0]}
              rotation={[0, 0, a1]}
              castShadow
            >
              <coneGeometry args={[0.17, 0.26, 32]} />
              <Glossy color={color} />
            </mesh>
          </group>
        );
      })}
    </group>
  );
}

function SyncIcon() {
  return <SyncArrows color={GREEN} />;
}

function SyncBrokenIcon() {
  return (
    <group>
      <SyncArrows color={RED} />
      <Bar w={0.1} h={1.2} rot={-Math.PI / 6} color={RED} z={0.02} />
    </group>
  );
}

function PauseIcon() {
  return (
    <group>
      <Disc color={AMBER} />
      <Bar w={0.11} h={0.42} x={-0.1} />
      <Bar w={0.11} h={0.42} x={0.1} />
    </group>
  );
}

function AlertIcon() {
  return (
    <group>
      <Disc color={RED} />
      <Bar w={0.11} h={0.36} y={0.08} />
      <mesh position={[0, -0.21, 0.12]} castShadow>
        <sphereGeometry args={[0.065, 24, 24]} />
        <Glossy color={WHITE} />
      </mesh>
    </group>
  );
}

function PowerIcon() {
  const geo = useExtruded(() => {
    const a0 = THREE.MathUtils.degToRad(120);
    const a1 = THREE.MathUtils.degToRad(420);
    const s = new THREE.Shape();
    s.moveTo(...polar(0.5, a0));
    s.absarc(0, 0, 0.5, a0, a1, false);
    s.lineTo(...polar(0.37, a1));
    s.absarc(0, 0, 0.37, a1, a0, true);
    s.closePath();
    return s;
  });
  return (
    <group>
      <mesh geometry={geo} castShadow>
        <Glossy color={SLATE} />
      </mesh>
      <Bar w={0.13} h={0.5} y={0.28} color={SLATE} z={0} />
    </group>
  );
}

const ICONS: Record<IconKind, () => ReactNode> = {
  check: () => <CheckIcon />,
  bolt: () => <BoltIcon />,
  sync: () => <SyncIcon />,
  syncBroken: () => <SyncBrokenIcon />,
  pause: () => <PauseIcon />,
  alert: () => <AlertIcon />,
  power: () => <PowerIcon />,
};

interface StatusIcon3DProps {
  kind: IconKind;
  position: [number, number, number];
  reducedMotion: boolean;
  size?: number;
}

/**
 * Faces the camera (with a slight turn so the extrusion depth reads) and
 * bobs gently unless reduced motion is on. A new kind never swaps in place:
 * the old glyph shrinks away with a quarter turn, then the new one springs
 * up with a little overshoot.
 */
export default function StatusIcon3D({ kind, position, reducedMotion, size = 1 }: StatusIcon3DProps) {
  const group = useRef<THREE.Group>(null);
  const [shown, setShown] = useState(kind);
  // Scale spring; starts at 0 so the first icon grows in too.
  const spring = useRef({ s: 0, v: 0 });
  const swapping = useRef(false);
  const spin = shown === 'sync' && !reducedMotion;

  useFrame(({ camera, clock }, delta) => {
    const g = group.current;
    if (!g) return;
    const sp = spring.current;
    const target = shown === kind ? 1 : 0;
    if (reducedMotion) {
      sp.s = 1;
      sp.v = 0;
      if (shown !== kind) setShown(kind);
    } else {
      const dt = Math.min(delta, 0.05);
      // Shrink fast and flat; grow with a soft bounce.
      const [stiff, damping] = target === 0 ? [260, 30] : [140, 11];
      sp.v += (target - sp.s) * stiff * dt;
      sp.v *= Math.exp(-damping * dt);
      sp.s += sp.v * dt;
      if (target === 0 && sp.s <= 0.02) {
        sp.s = 0;
        sp.v = 0;
        if (!swapping.current) {
          swapping.current = true;
          setShown(kind);
        }
      }
    }
    if (shown === kind) swapping.current = false;
    const s = Math.max(sp.s, 0);
    const t = clock.getElapsedTime();
    g.position.set(position[0], position[1] + (reducedMotion ? 0 : Math.sin(t * 1.6) * 0.07), position[2]);
    g.lookAt(camera.position);
    g.rotateY(-0.38 + (reducedMotion ? 0 : Math.sin(t * 0.7) * 0.08) + (1 - Math.min(s, 1)) * 1.4);
    if (spin) g.rotateZ(-t * 1.2);
    g.visible = s > 0.005;
    g.scale.setScalar(Math.max(s, 0.001) * size);
  });

  return <group ref={group}>{ICONS[shown]()}</group>;
}
