// Isometric clay city block for the fleet view, in the same visual language
// as the station diorama. 40 charger posts stand in for the 1,000-charger
// fleet; each post's restart wave is its real CRC-hashed delay
// (restartDelay(TRIGGER_CRC, id)), so the lamps light in the true order.
// The 'surge' and 'rebound' phases show the fixed-delay fleet instead: every
// lamp at once, then the grid alarm again.

import { Suspense, useEffect, useMemo, useRef } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { ContactShadows, Environment, Lightformer, Line, RoundedBox } from '@react-three/drei';
import * as THREE from 'three';
import { HOLD_BASE } from '../../data/constants';
import { restartDelay } from '../../data/charger';
import { BASE_ID, TRIGGER_CRC } from '../../data/rebound';
import StatusIcon3D from '../station/StatusIcon3D';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import type { IconKind } from '../station/stationStory';
import type { Phase } from './GridTimeline';

interface CitySceneProps {
  phase: Phase;
  wave: number;
  icon: IconKind;
}

const PLINTH = '#6A6F77';
const ROAD = '#42464D';
const CLAY = '#E7E9EC';
const CLAY_2 = '#C8CCD1';
const GREEN = '#3CCF5A';
const AMBER = '#F2B134';
const RED = '#FF5A5F';

function mulberry32(seed: number) {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface Post {
  x: number;
  z: number;
  wave: number;
  car: boolean;
}

// Crossroads through the middle; one parking lot per quadrant, the
// substation in the NW quadrant, buildings along the outer edges.
const SUBSTATION: [number, number] = [-2.0, -2.3];
const PYLON_TOP: [number, number, number] = [SUBSTATION[0], 2.35, SUBSTATION[1] - 0.5];
const LOT_COLS = 5;
const LOT_DX = 0.7;
const LOT_DZ = 1.45;
const LOTS: { x: number; z: number }[] = [
  { x: 1.4, z: -3.5 },
  { x: 1.4, z: 1.15 },
  { x: -4.4, z: 1.15 },
  { x: -6.9, z: -3.5 },
];
const lotCenter = (l: { x: number; z: number }): [number, number] => [l.x + ((LOT_COLS - 1) * LOT_DX) / 2, l.z + LOT_DZ / 2 + 0.3];

function useLayout() {
  return useMemo(() => {
    const rand = mulberry32(0xc17159);
    const posts: Post[] = [];
    let k = 0;
    for (const lot of LOTS) {
      for (let row = 0; row < 2; row++) {
        for (let col = 0; col < LOT_COLS; col++) {
          // Each post stands for 25 chargers; use its first ID's real delay.
          const id = BASE_ID + k * 25;
          posts.push({
            x: lot.x + col * LOT_DX,
            z: lot.z + row * LOT_DZ,
            wave: restartDelay(TRIGGER_CRC, id) - HOLD_BASE,
            car: rand() > 0.2,
          });
          k++;
        }
      }
    }
    const buildings = [
      { x: 6.4, z: -3.4, w: 1.6, d: 2.2, h: 2.6 },
      { x: 6.5, z: 2.6, w: 1.4, d: 1.8, h: 1.8 },
      { x: 3.0, z: -5.0, w: 2.2, d: 1.2, h: 1.4 },
      { x: 3.0, z: 4.8, w: 1.8, d: 1.1, h: 2.0 },
      { x: -2.6, z: 4.8, w: 2.4, d: 1.2, h: 1.3 },
      { x: -6.6, z: 3.4, w: 1.4, d: 2.0, h: 2.2 },
      { x: -4.6, z: -5.0, w: 1.6, d: 1.2, h: 1.6 },
    ];
    return { posts, buildings };
  }, []);
}

function FitCamera() {
  const { camera, size } = useThree();
  useEffect(() => {
    const cam = camera as THREE.OrthographicCamera;
    cam.zoom = Math.min(size.width / 20.5, size.height / 13);
    cam.lookAt(0, 0.5, 0);
    cam.updateProjectionMatrix();
  }, [camera, size]);
  return null;
}

function lampColor(phase: Phase, postWave: number, wave: number): string {
  if (phase === 'dip' || phase === 'rebound') return RED;
  if (phase === 'hold') return AMBER;
  if (phase === 'stagger') return postWave <= wave ? GREEN : AMBER;
  return GREEN;
}

function ChargerPost({ post, phase, wave, reducedMotion }: { post: Post; phase: Phase; wave: number; reducedMotion: boolean }) {
  const mat = useRef<THREE.MeshStandardMaterial>(null);
  const target = useMemo(() => new THREE.Color(), []);
  // Without RVBL-2 every lamp flares on the same frame.
  const justLit = (phase === 'stagger' && post.wave === wave) || phase === 'surge';
  const alarm = phase === 'dip' || phase === 'rebound';

  useFrame(({ clock }, delta) => {
    const m = mat.current;
    if (!m) return;
    target.set(lampColor(phase, post.wave, wave));
    const k = reducedMotion ? 1 : Math.min(1, delta * 8);
    m.color.lerp(target, k);
    m.emissive.lerp(target, k);
    const flash = alarm && !reducedMotion ? 0.6 + 0.6 * Math.sin(clock.getElapsedTime() * 9) : 0;
    m.emissiveIntensity = THREE.MathUtils.lerp(m.emissiveIntensity, (justLit ? 3.4 : 1.8) + flash, k);
  });

  return (
    <group position={[post.x, 0, post.z]}>
      <RoundedBox args={[0.26, 0.62, 0.2]} radius={0.06} smoothness={3} position={[0, 0.31, 0]} castShadow>
        <meshStandardMaterial color={CLAY} roughness={0.55} />
      </RoundedBox>
      <mesh position={[0, 0.74, 0]}>
        <sphereGeometry args={[0.12, 20, 20]} />
        <meshStandardMaterial ref={mat} color={GREEN} emissive={GREEN} emissiveIntensity={1.8} toneMapped={false} />
      </mesh>
      {post.car && (
        <group position={[0, 0, 0.62]}>
          <RoundedBox args={[0.5, 0.22, 0.86]} radius={0.08} smoothness={3} position={[0, 0.17, 0]} castShadow>
            <meshStandardMaterial color={CLAY} roughness={0.45} />
          </RoundedBox>
          <RoundedBox args={[0.44, 0.16, 0.46]} radius={0.06} smoothness={3} position={[0, 0.34, -0.04]} castShadow>
            <meshStandardMaterial color="#16181B" roughness={0.15} />
          </RoundedBox>
        </group>
      )}
    </group>
  );
}

function Substation({ phase, reducedMotion }: { phase: Phase; reducedMotion: boolean }) {
  const lamp = useRef<THREE.MeshStandardMaterial>(null);
  useFrame(({ clock }) => {
    if (!lamp.current) return;
    const alert = phase === 'dip' || phase === 'surge' || phase === 'rebound';
    lamp.current.emissive.set(alert ? RED : GREEN);
    lamp.current.color.set(alert ? RED : GREEN);
    lamp.current.emissiveIntensity = alert && !reducedMotion ? 1.2 + Math.sin(clock.getElapsedTime() * 9) : 1.6;
  });
  return (
    <group position={[SUBSTATION[0], 0, SUBSTATION[1]]}>
      <RoundedBox args={[1.6, 0.16, 1.6]} radius={0.05} smoothness={3} position={[0, 0.08, 0]} receiveShadow>
        <meshStandardMaterial color={CLAY_2} roughness={0.7} />
      </RoundedBox>
      {[-0.35, 0.35].map((x) => (
        <group key={x} position={[x, 0.16, 0.1]}>
          <mesh position={[0, 0.35, 0]} castShadow>
            <cylinderGeometry args={[0.24, 0.26, 0.7, 24]} />
            <meshStandardMaterial color={CLAY} roughness={0.5} />
          </mesh>
          {[0, 1, 2].map((i) => (
            <mesh key={i} position={[(i - 1) * 0.12, 0.8, 0]} castShadow>
              <cylinderGeometry args={[0.035, 0.05, 0.22, 12]} />
              <meshStandardMaterial color="#8A8F96" />
            </mesh>
          ))}
        </group>
      ))}
      {/* Pylon */}
      <mesh position={[0, 1.3, -0.5]} castShadow>
        <boxGeometry args={[0.12, 2.6, 0.12]} />
        <meshStandardMaterial color="#9AA0A7" roughness={0.5} />
      </mesh>
      <mesh position={[0, 2.35, -0.5]} castShadow>
        <boxGeometry args={[1.2, 0.08, 0.08]} />
        <meshStandardMaterial color="#9AA0A7" roughness={0.5} />
      </mesh>
      <mesh position={[0, 2.6, -0.5]}>
        <sphereGeometry args={[0.1, 16, 16]} />
        <meshStandardMaterial ref={lamp} color={GREEN} emissive={GREEN} emissiveIntensity={1.6} toneMapped={false} />
      </mesh>
    </group>
  );
}

function Feeders({ phase }: { phase: Phase }) {
  const color = phase === 'dip' || phase === 'surge' || phase === 'rebound' ? RED : phase === 'hold' ? AMBER : '#9FB3D9';
  return (
    <>
      {LOTS.map((lot, i) => {
        const [cx, cz] = lotCenter(lot);
        return (
          <Line
            key={i}
            points={[PYLON_TOP, [(cx + PYLON_TOP[0]) / 2, 2.1, (cz + PYLON_TOP[2]) / 2], [cx, 1.05, cz]]}
            color={color}
            lineWidth={1.5}
            transparent
            opacity={0.75}
          />
        );
      })}
    </>
  );
}

function Scene({ phase, wave, icon }: CitySceneProps) {
  const reducedMotion = usePrefersReducedMotion();
  const { posts, buildings } = useLayout();
  return (
    <>
      <FitCamera />
      <hemisphereLight args={['#ffffff', '#3b4250', 0.9]} />
      <directionalLight position={[-6, 12, 8]} intensity={1.5} castShadow shadow-mapSize={[2048, 2048]} shadow-camera-left={-10} shadow-camera-right={10} shadow-camera-top={10} shadow-camera-bottom={-10} shadow-bias={-0.0004} />
      <Environment resolution={128} frames={1}>
        <Lightformer form="rect" intensity={2} position={[0, 8, 6]} scale={[14, 5, 1]} />
        <Lightformer form="rect" intensity={1} position={[-8, 4, 0]} rotation-y={Math.PI / 2} scale={[10, 4, 1]} />
      </Environment>

      <RoundedBox args={[15.5, 0.5, 12]} radius={0.3} smoothness={6} position={[0, -0.25, 0]} receiveShadow>
        <meshStandardMaterial color={PLINTH} roughness={0.8} />
      </RoundedBox>
      {/* Crossroads with lane dashes */}
      <mesh position={[0, 0.004, 0]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
        <planeGeometry args={[15.3, 1.0]} />
        <meshStandardMaterial color={ROAD} roughness={0.9} />
      </mesh>
      <mesh position={[0, 0.005, 0]} rotation={[-Math.PI / 2, 0, 0]} receiveShadow>
        <planeGeometry args={[1.0, 11.8]} />
        <meshStandardMaterial color={ROAD} roughness={0.9} />
      </mesh>
      {Array.from({ length: 12 }, (_, i) => -7 + i * 1.25)
        .filter((x) => Math.abs(x) > 0.8)
        .map((x) => (
          <mesh key={`h${x}`} position={[x, 0.007, 0]} rotation={[-Math.PI / 2, 0, 0]}>
            <planeGeometry args={[0.55, 0.06]} />
            <meshBasicMaterial color="#C9CDD2" transparent opacity={0.6} />
          </mesh>
        ))}
      {Array.from({ length: 10 }, (_, i) => -5.4 + i * 1.2)
        .filter((z) => Math.abs(z) > 0.8)
        .map((z) => (
          <mesh key={`v${z}`} position={[0, 0.007, z]} rotation={[-Math.PI / 2, 0, 0]}>
            <planeGeometry args={[0.06, 0.55]} />
            <meshBasicMaterial color="#C9CDD2" transparent opacity={0.6} />
          </mesh>
        ))}

      {buildings.map((b, i) => (
        <RoundedBox key={i} args={[b.w, b.h, b.d]} radius={0.1} smoothness={4} position={[b.x, b.h / 2, b.z]} castShadow receiveShadow>
          <meshStandardMaterial color={i % 3 === 0 ? CLAY_2 : CLAY} roughness={0.6} />
        </RoundedBox>
      ))}

      <Substation phase={phase} reducedMotion={reducedMotion} />
      <Feeders phase={phase} />
      {posts.map((p, i) => (
        <ChargerPost key={i} post={p} phase={phase} wave={wave} reducedMotion={reducedMotion} />
      ))}

      <ContactShadows position={[0, 0.006, 0]} scale={16} blur={2.4} far={4} opacity={0.45} resolution={512} frames={1} />
      <ContactShadows position={[0, -0.52, 0]} scale={20} blur={3} far={2} opacity={0.55} resolution={256} frames={1} />
      <StatusIcon3D kind={icon} position={[0.2, 4.0, 0.2]} size={1.5} reducedMotion={reducedMotion} />
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
      camera={{ position: [12, 10, 12], zoom: 40, near: 0.1, far: 200 }}
      style={{ background: 'transparent' }}
    >
      <Suspense fallback={null}>
        <Scene {...props} />
      </Suspense>
    </Canvas>
  );
}
