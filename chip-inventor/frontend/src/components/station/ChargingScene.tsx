// Isometric clay diorama of one charging bay, styled after the clay-render
// references: white car, grey charger post on a rounded plinth, soft contact
// shadows and a single glossy status icon floating above the car. Pure
// presentation: every input is a prop derived from the model upstream.
//
// Lighting comes from an Environment built of local Lightformers rather than
// a drei preset, because presets download an HDR file at runtime -- a blank
// scene on an offline demo laptop.

import { Suspense, useEffect, useMemo, useRef } from 'react';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import type { JSX } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { ContactShadows, Environment, Lightformer, RoundedBox } from '@react-three/drei';
import * as THREE from 'three';
import StatusIcon3D from './StatusIcon3D';
import type { IconKind } from './stationStory';

export interface ChargingSceneProps {
  icon: IconKind;
  accent: string;
  carPresent: boolean;
  charging: boolean;
  /** DATAOUT byte: bit 4 contactor, 5 cable lock, 6 grid hold, 7 fault. */
  pins: number;
}

const CLAY_WHITE = '#ECEEF1';
const CLAY_LIGHT = '#C9CDD2';
const CLAY_MID = '#8A8F96';
const CLAY_DARK = '#55595F';
const RUBBER = '#1C1E21';
const GLASS = '#121417';

function Clay({ color, roughness = 0.62 }: { color: string; roughness?: number }) {
  return <meshStandardMaterial color={color} roughness={roughness} metalness={0} />;
}

/** Fit the orthographic camera to the bay whenever the canvas resizes. */
function FitCamera() {
  const { camera, size } = useThree();
  useEffect(() => {
    const cam = camera as THREE.OrthographicCamera;
    cam.zoom = Math.min(size.width / 7.4, size.height / 5.4);
    cam.lookAt(0, 0.9, 0);
    cam.updateProjectionMatrix();
  }, [camera, size]);
  return null;
}

function Plinth() {
  return (
    <group>
      <RoundedBox args={[6.2, 0.42, 4.4]} radius={0.2} smoothness={6} position={[0, -0.21, 0]} receiveShadow>
        <Clay color={CLAY_DARK} roughness={0.75} />
      </RoundedBox>
      {/* Bay markings */}
      {[-1.9, 1.9].map((x) => (
        <mesh key={x} position={[x * 0.62 - 0.35, 0.002, 0.55]} rotation={[-Math.PI / 2, 0, 0]}>
          <planeGeometry args={[0.06, 2.6]} />
          <meshBasicMaterial color="#7C8188" transparent opacity={0.55} />
        </mesh>
      ))}
    </group>
  );
}

const PIN_LAMPS = [
  { bit: 4, color: '#3CCF5A' },
  { bit: 5, color: '#6EA8FF' },
  { bit: 6, color: '#F2B134' },
  { bit: 7, color: '#FF5A5F' },
];

function Charger({ accent, pins, holsterCable }: { accent: string; pins: number; holsterCable: boolean }) {
  return (
    <group position={[1.55, 0, -1.25]}>
      <RoundedBox args={[1.25, 0.14, 0.95]} radius={0.05} smoothness={4} position={[0, 0.07, 0]} castShadow receiveShadow>
        <Clay color={CLAY_MID} />
      </RoundedBox>
      <RoundedBox args={[0.95, 2.35, 0.62]} radius={0.12} smoothness={6} position={[0, 1.31, 0]} castShadow receiveShadow>
        <Clay color={CLAY_LIGHT} />
      </RoundedBox>
      {/* Cap */}
      <RoundedBox args={[1.02, 0.22, 0.7]} radius={0.09} smoothness={5} position={[0, 2.5, 0]} castShadow>
        <Clay color={CLAY_WHITE} />
      </RoundedBox>
      {/* Front panel (faces +z, toward the camera) */}
      <RoundedBox args={[0.72, 1.7, 0.06]} radius={0.04} smoothness={4} position={[0, 1.25, 0.31]}>
        <Clay color={CLAY_MID} roughness={0.5} />
      </RoundedBox>
      {/* Status light bar under the cap */}
      <mesh position={[0, 2.22, 0.315]}>
        <boxGeometry args={[0.46, 0.05, 0.02]} />
        <meshStandardMaterial color={accent} emissive={accent} emissiveIntensity={1.6} toneMapped={false} />
      </mesh>
      {/* Screen */}
      <RoundedBox args={[0.5, 0.34, 0.03]} radius={0.02} smoothness={3} position={[0, 1.72, 0.35]}>
        <meshStandardMaterial color="#0C1018" emissive={accent} emissiveIntensity={0.35} roughness={0.2} />
      </RoundedBox>
      {/* P4-P7 output lamps */}
      {PIN_LAMPS.map((l, i) => {
        const on = (pins & (1 << l.bit)) !== 0;
        return (
          <mesh key={l.bit} position={[-0.18 + i * 0.12, 1.4, 0.35]}>
            <sphereGeometry args={[0.035, 16, 16]} />
            <meshStandardMaterial
              color={on ? l.color : '#2A2D33'}
              emissive={l.color}
              emissiveIntensity={on ? 2.2 : 0}
              toneMapped={!on}
            />
          </mesh>
        );
      })}
      {/* Holster */}
      <RoundedBox args={[0.22, 0.34, 0.14]} radius={0.05} smoothness={4} position={[0.22, 0.98, 0.36]} castShadow>
        <Clay color={CLAY_DARK} />
      </RoundedBox>
      {holsterCable && (
        <mesh position={[0.22, 0.62, 0.42]} castShadow>
          <torusGeometry args={[0.2, 0.035, 12, 32, Math.PI * 1.6]} />
          <Clay color={RUBBER} roughness={0.5} />
        </mesh>
      )}
    </group>
  );
}

function Wheel({ position }: { position: [number, number, number] }) {
  const outward = position[2] > 0 ? 1 : -1;
  return (
    <group position={position}>
      <mesh rotation={[Math.PI / 2, 0, 0]} castShadow>
        <cylinderGeometry args={[0.33, 0.33, 0.26, 40]} />
        <Clay color={RUBBER} roughness={0.85} />
      </mesh>
      <mesh rotation={[Math.PI / 2, 0, 0]} position={[0, 0, outward * 0.12]}>
        <cylinderGeometry args={[0.22, 0.22, 0.04, 40]} />
        <Clay color="#D9DCE0" roughness={0.35} />
      </mesh>
      {Array.from({ length: 5 }, (_, k) => (
        <mesh key={k} position={[0, 0, outward * 0.145]} rotation={[0, 0, (k * Math.PI * 2) / 5]}>
          <boxGeometry args={[0.05, 0.36, 0.02]} />
          <Clay color="#5E636A" />
        </mesh>
      ))}
    </group>
  );
}

function Car({ present, reducedMotion }: { present: boolean; reducedMotion: boolean }) {
  const group = useRef<THREE.Group>(null);
  const home = -0.55;
  const away = -6.5;

  useFrame((_, delta) => {
    const g = group.current;
    if (!g) return;
    const target = present ? home : away;
    g.position.x = reducedMotion ? target : THREE.MathUtils.damp(g.position.x, target, 3.2, delta);
    g.visible = g.position.x > -4.6;
  });

  const { body, glass } = useCarGeometry();

  return (
    <group ref={group} position={[present ? home : away, 0, 0.6]}>
      <mesh geometry={body} castShadow receiveShadow>
        <Clay color={CLAY_WHITE} roughness={0.42} />
      </mesh>
      <mesh geometry={glass} castShadow>
        <meshStandardMaterial color={GLASS} roughness={0.08} metalness={0.4} />
      </mesh>
      {/* White roof panel and B-pillar over the dark glass, as in the reference renders */}
      <RoundedBox args={[1.2, 0.07, 1.16]} radius={0.03} smoothness={4} position={[-0.46, 1.5, 0]} castShadow>
        <Clay color={CLAY_WHITE} roughness={0.38} />
      </RoundedBox>
      <mesh position={[-0.28, 1.22, 0]}>
        <boxGeometry args={[0.09, 0.5, 1.26]} />
        <Clay color={CLAY_WHITE} roughness={0.42} />
      </mesh>
      {/* Lamps */}
      <mesh position={[1.66, 0.66, 0]}>
        <boxGeometry args={[0.04, 0.05, 1.1]} />
        <meshStandardMaterial color="#FFFFFF" emissive="#FFFFFF" emissiveIntensity={1.6} toneMapped={false} />
      </mesh>
      <mesh position={[-1.63, 0.86, 0]}>
        <boxGeometry args={[0.04, 0.05, 1.1]} />
        <meshStandardMaterial color="#FF4D4D" emissive="#FF2A2A" emissiveIntensity={1.1} />
      </mesh>
      {/* Charge port flap on the charger side */}
      <mesh position={[-1.1, 0.84, -0.775]}>
        <boxGeometry args={[0.22, 0.16, 0.02]} />
        <Clay color={CLAY_LIGHT} />
      </mesh>
      <Wheel position={[0.98, 0.32, 0.6]} />
      <Wheel position={[0.98, 0.32, -0.6]} />
      <Wheel position={[-0.98, 0.32, 0.6]} />
      <Wheel position={[-0.98, 0.32, -0.6]} />
    </group>
  );
}

/** Extruded SUV side profile (x = length, y = height) with wheel arches. */
function useCarGeometry() {
  return useMemo(() => {
    const ARCH_Y = 0.3;
    const ARCH_R = 0.4;
    const b = new THREE.Shape();
    b.moveTo(-1.5, ARCH_Y);
    b.lineTo(-0.98 - ARCH_R, ARCH_Y);
    b.absarc(-0.98, ARCH_Y, ARCH_R, Math.PI, 0, true);
    b.lineTo(0.98 - ARCH_R, ARCH_Y);
    b.absarc(0.98, ARCH_Y, ARCH_R, Math.PI, 0, true);
    b.lineTo(1.56, ARCH_Y);
    b.quadraticCurveTo(1.66, 0.34, 1.66, 0.56);
    b.quadraticCurveTo(1.64, 0.82, 1.36, 0.88);
    b.lineTo(0.58, 0.99);
    b.lineTo(-1.25, 1.03);
    b.quadraticCurveTo(-1.58, 1.02, -1.6, 0.76);
    b.lineTo(-1.59, 0.42);
    b.quadraticCurveTo(-1.58, ARCH_Y, -1.5, ARCH_Y);
    const bodyDepth = 1.34;
    const body = new THREE.ExtrudeGeometry(b, { depth: bodyDepth, bevelEnabled: true, bevelThickness: 0.1, bevelSize: 0.08, bevelSegments: 6, curveSegments: 32 });
    body.translate(0, 0, -bodyDepth / 2);

    const g = new THREE.Shape();
    g.moveTo(0.6, 0.98);
    g.quadraticCurveTo(0.22, 1.34, -0.1, 1.42);
    g.lineTo(-0.98, 1.42);
    g.quadraticCurveTo(-1.32, 1.4, -1.38, 1.02);
    g.lineTo(0.6, 0.98);
    const glassDepth = 1.12;
    const glass = new THREE.ExtrudeGeometry(g, { depth: glassDepth, bevelEnabled: true, bevelThickness: 0.06, bevelSize: 0.05, bevelSegments: 4, curveSegments: 24 });
    glass.translate(0, 0, -glassDepth / 2);
    return { body, glass };
  }, []);
}

const CABLE_POINTS = [
  new THREE.Vector3(1.77, 0.98, -0.82),
  new THREE.Vector3(1.6, 0.45, -0.6),
  new THREE.Vector3(0.9, 0.12, -0.55),
  new THREE.Vector3(-0.3, 0.12, -0.45),
  new THREE.Vector3(-1.2, 0.45, -0.35),
  new THREE.Vector3(-1.65, 0.84, -0.2),
];

function Cable({ charging, accent, reducedMotion }: { charging: boolean; accent: string; reducedMotion: boolean }) {
  const curve = useMemo(() => new THREE.CatmullRomCurve3(CABLE_POINTS), []);
  const tube = useMemo(() => new THREE.TubeGeometry(curve, 96, 0.045, 12, false), [curve]);
  const pulses = useRef<THREE.Group>(null);
  const count = 7;

  useFrame(({ clock }) => {
    const g = pulses.current;
    if (!g) return;
    const t0 = reducedMotion ? 0 : clock.getElapsedTime() * 0.35;
    g.children.forEach((child, i) => {
      // Power flows charger -> car, i.e. along the curve from t=0 to t=1.
      const t = (i / count + t0) % 1;
      child.position.copy(curve.getPointAt(t));
    });
  });

  return (
    <group>
      <mesh geometry={tube} castShadow>
        <Clay color={RUBBER} roughness={0.45} />
      </mesh>
      {charging && (
        <group ref={pulses}>
          {Array.from({ length: count }, (_, i) => (
            <mesh key={i}>
              <sphereGeometry args={[0.065, 16, 16]} />
              <meshStandardMaterial color={accent} emissive={accent} emissiveIntensity={2.4} toneMapped={false} />
            </mesh>
          ))}
        </group>
      )}
    </group>
  );
}

function Lights() {
  return (
    <>
      <hemisphereLight args={['#ffffff', '#3b4250', 0.9]} />
      <directionalLight
        position={[-3.5, 9, 6]}
        intensity={1.6}
        castShadow
        shadow-mapSize={[2048, 2048]}
        shadow-camera-left={-6}
        shadow-camera-right={6}
        shadow-camera-top={6}
        shadow-camera-bottom={-6}
        shadow-bias={-0.0004}
        shadow-radius={6}
      />
      <Environment resolution={256} frames={1}>
        <Lightformer form="rect" intensity={2.2} position={[0, 6, 4]} scale={[10, 4, 1]} />
        <Lightformer form="rect" intensity={1.1} position={[-6, 3, 0]} rotation-y={Math.PI / 2} scale={[8, 3, 1]} />
        <Lightformer form="rect" intensity={0.8} position={[6, 2, -2]} rotation-y={-Math.PI / 2} scale={[8, 3, 1]} />
        <Lightformer form="circle" intensity={1.4} position={[0, 8, 0]} rotation-x={Math.PI / 2} scale={4} />
      </Environment>
    </>
  );
}

function Scene({ icon, accent, carPresent, charging, pins }: ChargingSceneProps) {
  const reducedMotion = usePrefersReducedMotion();
  return (
    <>
      <FitCamera />
      <Lights />
      <Plinth />
      <ContactShadows position={[0, 0.005, 0]} scale={7} blur={2.2} far={3} opacity={0.55} resolution={512} frames={reducedMotion ? 1 : Infinity} />
      <ContactShadows position={[0, -0.43, 0]} scale={9} blur={3} far={2} opacity={0.6} resolution={256} frames={1} />
      <Charger accent={accent} pins={pins} holsterCable={!carPresent} />
      <Car present={carPresent} reducedMotion={reducedMotion} />
      {carPresent && <Cable charging={charging} accent={accent} reducedMotion={reducedMotion} />}
      <StatusIcon3D kind={icon} position={[-0.75, 2.75, 0.6]} reducedMotion={reducedMotion} />
    </>
  );
}

export default function ChargingScene(props: ChargingSceneProps): JSX.Element {
  return (
    <Canvas
      orthographic
      shadows="soft"
      dpr={[1, 2]}
      gl={{ antialias: true, alpha: true }}
      camera={{ position: [8, 6.6, 8], zoom: 80, near: 0.1, far: 100 }}
      style={{ background: 'transparent' }}
    >
      <Suspense fallback={null}>
        <Scene {...props} />
      </Suspense>
    </Canvas>
  );
}
