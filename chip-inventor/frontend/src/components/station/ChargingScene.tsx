// 3D charging station scene (Phase 2). Pure presentation: all state comes
// from props derived upstream (StationView) from the scenario/model data
// layer in src/data/. This file does not import scenario logic directly.

import { Suspense, useMemo, useRef, useState, useEffect } from 'react';
import type { JSX } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import {
  Environment,
  Grid,
  OrbitControls,
  RoundedBox,
  Sparkles,
} from '@react-three/drei';
import * as THREE from 'three';
import { ChargerState, STATE_COLORS } from '../../data/constants';

export interface ChargingSceneProps {
  state: ChargerState;
  charging: boolean;
  cableConnected: boolean;
  pinOutputs: number; // bits 7-4 (ground LED bank: P4 contactor, P5 cable lock, P6 grid hold, P7 fault)
  stateLabel: string;
}

function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    if (typeof window === 'undefined' || !window.matchMedia) return;
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)');
    setReduced(mq.matches);
    const handler = (e: MediaQueryListEvent) => setReduced(e.matches);
    mq.addEventListener('change', handler);
    return () => mq.removeEventListener('change', handler);
  }, []);
  return reduced;
}

function Ground() {
  return (
    <>
      <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
        <planeGeometry args={[20, 20]} />
        <meshStandardMaterial color="#1a1a1a" />
      </mesh>
      <Grid
        position={[0, 0.01, 0]}
        args={[20, 20]}
        cellSize={1}
        cellThickness={0.5}
        cellColor="#2a2f3a"
        sectionSize={5}
        sectionThickness={1}
        sectionColor="#3a4150"
        fadeDistance={25}
        fadeStrength={1}
        infiniteGrid={false}
      />
    </>
  );
}

function ChargerCabinet({ state }: { state: ChargerState }) {
  const color = STATE_COLORS[state];
  return (
    <group position={[0, 0.7, 0]}>
      <RoundedBox args={[0.6, 1.4, 0.4]} radius={0.04} smoothness={4} castShadow>
        <meshStandardMaterial color="#1E293B" metalness={0.7} roughness={0.3} />
      </RoundedBox>
      {/* Screen: inset plane on the front face, emissive = state color */}
      <mesh position={[0, 0.2, 0.201]}>
        <planeGeometry args={[0.4, 0.3]} />
        <meshStandardMaterial
          color="#0a0f1a"
          emissive={color}
          emissiveIntensity={state === ChargerState.IDLE ? 0.3 : 1.1}
          toneMapped={false}
        />
      </mesh>
    </group>
  );
}

function Car({ visible }: { visible: boolean }) {
  const group = useRef<THREE.Group>(null);
  const target = visible ? -1.2 : -5;

  useFrame((_, delta) => {
    if (!group.current) return;
    const current = group.current.position.x;
    const next = THREE.MathUtils.damp(current, target, 4, delta);
    group.current.position.x = next;
    group.current.visible = visible || Math.abs(next - target) > 0.01;
  });

  return (
    <group ref={group} position={[-5, 0, -0.9]}>
      <RoundedBox args={[2.0, 0.6, 0.9]} radius={0.06} smoothness={4} position={[0, 0.45, 0]} castShadow>
        <meshStandardMaterial color="#C0C8D0" metalness={0.4} roughness={0.4} />
      </RoundedBox>
      <RoundedBox args={[1.0, 0.4, 0.8]} radius={0.06} smoothness={4} position={[-0.1, 0.9, 0]} castShadow>
        <meshStandardMaterial color="#C0C8D0" metalness={0.4} roughness={0.4} />
      </RoundedBox>
      {[
        [0.65, 0.15, 0.48],
        [0.65, 0.15, -0.48],
        [-0.65, 0.15, 0.48],
        [-0.65, 0.15, -0.48],
      ].map((pos, i) => (
        <mesh key={i} position={pos as [number, number, number]} rotation={[0, 0, Math.PI / 2]} castShadow>
          <cylinderGeometry args={[0.15, 0.15, 0.1, 16]} />
          <meshStandardMaterial color="#333333" roughness={0.8} />
        </mesh>
      ))}
    </group>
  );
}

function Cable({ state, visible }: { state: ChargerState; visible: boolean }) {
  const color = STATE_COLORS[state];
  const geometry = useMemo(() => {
    const curve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(0.3, 0.5, 0),
      new THREE.Vector3(-0.2, 0.35, -0.1),
      new THREE.Vector3(-0.5, 0.25, -0.15),
      new THREE.Vector3(-0.8, 0.3, 0),
    ]);
    return new THREE.TubeGeometry(curve, 32, 0.025, 8, false);
  }, []);

  const curve = useMemo(
    () =>
      new THREE.CatmullRomCurve3([
        new THREE.Vector3(0.3, 0.5, 0),
        new THREE.Vector3(-0.2, 0.35, -0.1),
        new THREE.Vector3(-0.5, 0.25, -0.15),
        new THREE.Vector3(-0.8, 0.3, 0),
      ]),
    [],
  );

  if (!visible) return null;

  return (
    <>
      <mesh geometry={geometry}>
        <meshStandardMaterial color={color} emissive={color} emissiveIntensity={0.4} roughness={0.5} />
      </mesh>
      <PowerParticles curve={curve} active={state === ChargerState.CHARGING} />
    </>
  );
}

function PowerParticles({ curve, active }: { curve: THREE.CatmullRomCurve3; active: boolean }) {
  const count = 12;
  const pointsRef = useRef<THREE.Points>(null);
  const offsets = useMemo(() => Array.from({ length: count }, (_, i) => i / count), [count]);
  const positions = useMemo(() => new Float32Array(count * 3), [count]);

  useFrame(({ clock }) => {
    if (!pointsRef.current) return;
    const t0 = clock.getElapsedTime() * 0.4;
    const posAttr = pointsRef.current.geometry.attributes.position as THREE.BufferAttribute;
    for (let i = 0; i < count; i++) {
      const t = (offsets[i] + t0) % 1;
      const p = curve.getPointAt(t);
      posAttr.setXYZ(i, p.x, p.y, p.z);
    }
    posAttr.needsUpdate = true;
  });

  if (!active) return null;

  return (
    <points ref={pointsRef}>
      <bufferGeometry>
        <bufferAttribute attach="attributes-position" args={[positions, 3]} count={count} array={positions} itemSize={3} />
      </bufferGeometry>
      <pointsMaterial color="#22C55E" size={0.05} sizeAttenuation transparent opacity={0.9} />
    </points>
  );
}

interface LedSpec {
  key: string;
  bit: number;
  color: string;
  position: [number, number, number];
}

const LEDS: LedSpec[] = [
  { key: 'P4_CONTACTOR', bit: 4, color: '#22C55E', position: [-0.3, 0.04, 0.3] },
  { key: 'P5_CABLE_LOCK', bit: 5, color: '#6EA8FF', position: [-0.1, 0.04, 0.3] },
  { key: 'P6_GRID_HOLD', bit: 6, color: '#F2B134', position: [0.1, 0.04, 0.3] },
  { key: 'P7_FAULT', bit: 7, color: '#FF5A5F', position: [0.3, 0.04, 0.3] },
];

function GroundLeds({ pinOutputs }: { pinOutputs: number }) {
  return (
    <>
      {LEDS.map((led) => {
        const on = Boolean(pinOutputs & (1 << led.bit));
        return (
          <mesh key={led.key} position={led.position}>
            <sphereGeometry args={[0.08, 16, 16]} />
            <meshStandardMaterial
              color={on ? led.color : '#1a1a1a'}
              emissive={led.color}
              emissiveIntensity={on ? 1.4 : 0}
              toneMapped={false}
            />
          </mesh>
        );
      })}
    </>
  );
}

function SceneContents({ state, charging, cableConnected, pinOutputs }: ChargingSceneProps) {
  return (
    <>
      <Ground />
      <ChargerCabinet state={state} />
      <Car visible={cableConnected} />
      <Cable state={state} visible={cableConnected} />
      <GroundLeds pinOutputs={pinOutputs} />

      <Environment preset="city" />
      <directionalLight position={[5, 8, 5]} intensity={0.8} castShadow />
      <ambientLight intensity={0.3} />

      {charging && cableConnected && (
        <Sparkles
          count={30}
          scale={[1.2, 0.6, 0.6]}
          position={[-0.25, 0.4, 0]}
          size={2}
          speed={0.4}
          color="#22C55E"
          opacity={0.6}
        />
      )}
    </>
  );
}

function LoadingFallback() {
  return (
    <div className="flex h-full w-full items-center justify-center bg-[#0F172A]">
      <span className="font-mono text-sm text-[var(--color-muted-foreground,#94A3B8)]">
        Loading 3D scene...
      </span>
    </div>
  );
}

export default function ChargingScene(props: ChargingSceneProps): JSX.Element {
  const reducedMotion = usePrefersReducedMotion();

  return (
    <Suspense fallback={<LoadingFallback />}>
      <Canvas
        shadows
        camera={{ position: [5, 4, 5], fov: 50 }}
        dpr={[1, 2]}
      >
        <SceneContents {...props} />
        <OrbitControls
          enablePan={false}
          maxPolarAngle={Math.PI / 2.2}
          autoRotate={!reducedMotion}
          autoRotateSpeed={0.5}
        />
      </Canvas>
    </Suspense>
  );
}
