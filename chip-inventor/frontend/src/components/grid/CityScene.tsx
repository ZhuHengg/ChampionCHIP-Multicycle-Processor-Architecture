import { Suspense, useMemo, useRef, useState } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { Grid, Line, OrbitControls } from '@react-three/drei';
import * as THREE from 'three';
import type { Phase } from './GridTimeline';

interface CitySceneProps {
  phase: Phase;
  staggerFrame?: number; // 0-7, which batch is currently restarting
}

interface Building {
  x: number;
  z: number;
  width: number;
  depth: number;
  height: number;
}

interface ChargerNode {
  x: number;
  z: number;
  bucket: number; // 0-7, which stagger batch this node belongs to
}

const NUM_BUILDINGS = 18;
const NUM_NODES = 30;
const NUM_BUCKETS = 8;

// Small seeded PRNG (mulberry32) so building/node layout is stable across
// renders and reloads instead of re-randomizing on every mount.
function mulberry32(seed: number) {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function useCityLayout() {
  return useMemo(() => {
    const rand = mulberry32(0xC17159); // fixed seed, chosen arbitrarily for stable layout
    const buildings: Building[] = [];
    for (let i = 0; i < NUM_BUILDINGS; i++) {
      const gx = (i % 6) - 2.5;
      const gz = Math.floor(i / 6) - 1.5;
      buildings.push({
        x: gx * 4.2 + (rand() - 0.5) * 1.8,
        z: gz * 4.2 + (rand() - 0.5) * 1.8,
        width: 1 + rand() * 1,
        depth: 1 + rand() * 1,
        height: 0.5 + rand() * 2.5,
      });
    }

    const nodes: ChargerNode[] = [];
    for (let i = 0; i < NUM_NODES; i++) {
      const angle = (i / NUM_NODES) * Math.PI * 2 + rand() * 0.3;
      const radius = 3 + (i % 5) * 2.2 + rand() * 1.2;
      nodes.push({
        x: Math.cos(angle) * radius,
        z: Math.sin(angle) * radius,
        bucket: i % NUM_BUCKETS,
      });
    }

    return { buildings, nodes };
  }, []);
}

function Buildings({ buildings }: { buildings: Building[] }) {
  return (
    <>
      {buildings.map((b, i) => (
        <mesh key={i} position={[b.x, b.height / 2, b.z]} castShadow receiveShadow>
          <boxGeometry args={[b.width, b.height, b.depth]} />
          <meshStandardMaterial color="#1E293B" roughness={0.8} />
        </mesh>
      ))}
    </>
  );
}

function nodeColorForPhase(phase: Phase, bucket: number, staggerFrame: number): string {
  switch (phase) {
    case 'normal':
    case 'recovered':
      return '#22C55E';
    case 'dip':
      return '#272F42';
    case 'hold':
      return '#F2B134';
    case 'stagger':
      return staggerFrame >= bucket ? '#22C55E' : '#272F42';
    default:
      return '#272F42';
  }
}

function ChargerNodeMesh({
  node,
  phase,
  staggerFrame,
}: {
  node: ChargerNode;
  phase: Phase;
  staggerFrame: number;
}) {
  const materialRef = useRef<THREE.MeshStandardMaterial>(null);
  const lightRef = useRef<THREE.PointLight>(null);
  const targetColor = useMemo(() => new THREE.Color(), []);

  useFrame((_, delta) => {
    const colorHex = nodeColorForPhase(phase, node.bucket, staggerFrame);
    targetColor.set(colorHex);
    const isLit = colorHex !== '#272F42';
    const targetIntensity = isLit ? (phase === 'hold' ? 1.4 : 1.8) : 0.15;

    if (materialRef.current) {
      materialRef.current.color.lerp(targetColor, Math.min(1, delta * 6));
      materialRef.current.emissive.lerp(targetColor, Math.min(1, delta * 6));
      materialRef.current.emissiveIntensity = THREE.MathUtils.lerp(
        materialRef.current.emissiveIntensity,
        targetIntensity,
        Math.min(1, delta * 6),
      );
    }
    if (lightRef.current) {
      lightRef.current.intensity = THREE.MathUtils.lerp(
        lightRef.current.intensity,
        isLit ? 0.3 : 0.03,
        Math.min(1, delta * 6),
      );
      lightRef.current.color.lerp(targetColor, Math.min(1, delta * 6));
    }
  });

  return (
    <group position={[node.x, 0.15, node.z]}>
      <mesh>
        <sphereGeometry args={[0.15, 16, 16]} />
        <meshStandardMaterial
          ref={materialRef}
          color="#272F42"
          emissive="#272F42"
          emissiveIntensity={0.15}
        />
      </mesh>
      <pointLight ref={lightRef} intensity={0.03} distance={3} color="#272F42" />
    </group>
  );
}

function Substation({ phase }: { phase: Phase }) {
  const materialRef = useRef<THREE.MeshStandardMaterial>(null);
  const tRef = useRef(0);

  useFrame((_, delta) => {
    tRef.current += delta;
    if (!materialRef.current) return;
    if (phase === 'dip') {
      // Pulse red via a sine wave while dipping.
      const pulse = (Math.sin(tRef.current * 10) + 1) / 2; // 0..1
      materialRef.current.emissive.set('#FF5A5F');
      materialRef.current.emissiveIntensity = 0.4 + pulse * 1.2;
    } else {
      materialRef.current.emissive.set('#FF5A5F');
      materialRef.current.emissiveIntensity = THREE.MathUtils.lerp(
        materialRef.current.emissiveIntensity,
        0,
        Math.min(1, delta * 4),
      );
    }
  });

  return (
    <mesh position={[0, 0.4, 0]} castShadow>
      <boxGeometry args={[1.5, 0.8, 1.5]} />
      <meshStandardMaterial ref={materialRef} color="#334155" emissive="#FF5A5F" emissiveIntensity={0} />
    </mesh>
  );
}

function PowerLines({ nodes, phase }: { nodes: ChargerNode[]; phase: Phase }) {
  // Connect substation to a subset of nearby nodes to avoid visual clutter.
  const nearby = useMemo(() => nodes.filter((_, i) => i % 3 === 0), [nodes]);
  const [flash, setFlash] = useState(false);

  useFrame((state) => {
    if (phase === 'dip') {
      setFlash((Math.sin(state.clock.elapsedTime * 10) + 1) / 2 > 0.5);
    } else if (flash) {
      setFlash(false);
    }
  });

  const color = phase === 'dip' && flash ? '#FF5A5F' : '#475569';

  return (
    <>
      {nearby.map((n, i) => (
        <Line
          key={i}
          points={[
            [0, 0.3, 0],
            [n.x, 0.15, n.z],
          ]}
          color={color}
          lineWidth={1}
          transparent
          opacity={0.5}
        />
      ))}
    </>
  );
}

function Scene({ phase, staggerFrame = 0 }: CitySceneProps) {
  const { buildings, nodes } = useCityLayout();
  const prefersReducedMotion = useMemo(
    () =>
      typeof window !== 'undefined' &&
      window.matchMedia?.('(prefers-reduced-motion: reduce)').matches,
    [],
  );

  return (
    <>
      <color attach="background" args={['#0F172A']} />
      <ambientLight intensity={0.4} />
      <directionalLight position={[10, 15, 5]} intensity={0.5} color="#F8FAFC" />

      <mesh rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
        <planeGeometry args={[30, 30]} />
        <meshStandardMaterial color="#0F172A" />
      </mesh>
      <Grid
        args={[30, 30]}
        position={[0, 0.01, 0]}
        cellColor="#1E293B"
        sectionColor="#334155"
        fadeDistance={30}
        infiniteGrid={false}
      />

      <Buildings buildings={buildings} />
      <Substation phase={phase} />
      <PowerLines nodes={nodes} phase={phase} />
      {nodes.map((n, i) => (
        <ChargerNodeMesh key={i} node={n} phase={phase} staggerFrame={staggerFrame} />
      ))}

      <OrbitControls
        enablePan={false}
        autoRotate={!prefersReducedMotion}
        autoRotateSpeed={0.3}
        minDistance={10}
        maxDistance={35}
      />
    </>
  );
}

export default function CityScene({ phase, staggerFrame = 0 }: CitySceneProps) {
  return (
    <div className="h-full w-full overflow-hidden rounded-xl border border-white/10 bg-[#0F172A]">
      <Suspense
        fallback={
          <div className="flex h-full w-full items-center justify-center bg-[#0F172A] font-mono text-sm text-[#94A3B8]">
            Loading city…
          </div>
        }
      >
        <Canvas shadows camera={{ position: [0, 20, 15], fov: 50 }} onCreated={({ camera }) => camera.lookAt(0, 0, 0)}>
          <Scene phase={phase} staggerFrame={staggerFrame} />
        </Canvas>
      </Suspense>
    </div>
  );
}
