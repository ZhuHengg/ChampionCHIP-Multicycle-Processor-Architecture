// Isometric clay diorama of one charging bay, styled after the clay-render
// references: white car, grey charger post on a rounded plinth, soft contact
// shadows and a single glossy status icon floating above the car. Pure
// presentation: every input is a prop derived from the model upstream.
//
// Lighting comes from an Environment built of local Lightformers rather than
// a drei preset, because presets download an HDR file at runtime -- a blank
// scene on an offline demo laptop.
//
// Nothing in the bay snaps between states. A Director eases a shared Motion
// record each frame and every part reads from it, so a session plays as one
// sequence: the car drives in and brakes, the cable reaches out to the port,
// power pulses fade up; on unplug the order runs in reverse and the car
// drives off. Colours, lamps and the status icon cross-fade the same way.
// Reduced motion snaps every value straight to its target.

import { Suspense, useEffect, useMemo, useRef, useState } from 'react';
import { usePrefersReducedMotion } from '../../hooks/usePrefersReducedMotion';
import type { JSX, MutableRefObject } from 'react';
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

const CAR_HOME = -0.55;
const CAR_START = -7.8;
const CAR_END = 7.2;
const ARRIVE_S = 1.3;
const LEAVE_S = 1.1;
const PLUG_S = 0.55;
const FLOW_S = 0.35;

type CarMode = 'away' | 'arriving' | 'parked' | 'leaving';

/** Eased animation state shared by every part of the bay. */
interface Motion {
  mode: CarMode;
  /** Progress through the current arriving/leaving drive, 0..1. */
  p: number;
  /** Car x position, world units. */
  x: number;
  /** Cable reach, 0 = coiled on the holster, 1 = plugged into the car. */
  cable: number;
  /** Power-pulse strength along the cable, 0..1. */
  flow: number;
}

type MotionRef = MutableRefObject<Motion>;

const easeOutCubic = (t: number) => 1 - (1 - t) ** 3;
const easeInCubic = (t: number) => t ** 3;
const easeInOut = (t: number) => (t < 0.5 ? 4 * t ** 3 : 1 - (-2 * t + 2) ** 3 / 2);

function approach(v: number, target: number, step: number) {
  return v < target ? Math.min(v + step, target) : Math.max(v - step, target);
}

function restingMotion(carPresent: boolean, charging: boolean): Motion {
  return {
    mode: carPresent ? 'parked' : 'away',
    p: 0,
    x: carPresent ? CAR_HOME : CAR_START,
    cable: carPresent ? 1 : 0,
    flow: carPresent && charging ? 1 : 0,
  };
}

/**
 * Advances the bay choreography. Arrival: drive in, then plug, then flow.
 * Departure: flow fades, cable retracts, then the car drives off. A target
 * that flips mid-drive reverses the drive in place instead of jumping.
 */
function Director({ motion, carPresent, charging, reducedMotion }: { motion: MotionRef; carPresent: boolean; charging: boolean; reducedMotion: boolean }) {
  useFrame((_, rawDelta) => {
    if (reducedMotion) {
      motion.current = restingMotion(carPresent, charging);
      return;
    }
    // Clamp so a backgrounded tab does not skip the whole sequence.
    const dt = Math.min(rawDelta, 0.05);
    const m = motion.current;
    switch (m.mode) {
      case 'away':
        if (carPresent) {
          m.mode = 'arriving';
          m.p = 0;
        }
        break;
      case 'arriving':
        m.p += ((carPresent ? 1 : -1) * dt) / ARRIVE_S;
        if (m.p >= 1) {
          m.p = 0;
          m.mode = 'parked';
        } else if (m.p <= 0) {
          m.p = 0;
          m.mode = 'away';
        }
        break;
      case 'parked':
        if (!carPresent && m.cable <= 0) {
          m.mode = 'leaving';
          m.p = 0;
        }
        break;
      case 'leaving':
        m.p += ((carPresent ? -1 : 1) * dt) / LEAVE_S;
        if (m.p >= 1) {
          m.p = 0;
          m.mode = 'away';
        } else if (m.p <= 0) {
          m.p = 0;
          m.mode = 'parked';
        }
        break;
    }
    if (m.mode === 'arriving') m.x = THREE.MathUtils.lerp(CAR_START, CAR_HOME, easeOutCubic(m.p));
    else if (m.mode === 'leaving') m.x = THREE.MathUtils.lerp(CAR_HOME, CAR_END, easeInCubic(m.p));
    else m.x = m.mode === 'parked' ? CAR_HOME : CAR_START;

    // Plug only once parked; unplug only after the power flow has faded.
    const plugged = carPresent && m.mode === 'parked';
    const cableTarget = plugged ? 1 : m.flow > 0 ? m.cable : 0;
    m.cable = approach(m.cable, cableTarget, dt / PLUG_S);
    m.flow = approach(m.flow, charging && plugged && m.cable >= 1 ? 1 : 0, dt / FLOW_S);
  });
  return null;
}

/** Material whose colour eases toward `color` instead of jumping to it. */
function FadingMaterial({
  color,
  emissiveIntensity,
  base,
  roughness = 0.4,
  reducedMotion,
}: {
  color: string;
  emissiveIntensity: number;
  /** Fixed base colour; when omitted the base follows `color` too. */
  base?: string;
  roughness?: number;
  reducedMotion: boolean;
}) {
  const mat = useRef<THREE.MeshStandardMaterial>(null);
  const target = useRef(new THREE.Color());
  // Initial values only: later changes go through the lerp, not the props.
  const [initial] = useState(color);
  useFrame((_, delta) => {
    const m = mat.current;
    if (!m) return;
    const t = target.current.set(color);
    const k = reducedMotion ? 1 : 1 - Math.exp(-5 * delta);
    m.emissive.lerp(t, k);
    if (!base) m.color.lerp(t, k);
  });
  return (
    <meshStandardMaterial
      ref={mat}
      color={base ?? initial}
      emissive={initial}
      emissiveIntensity={emissiveIntensity}
      roughness={roughness}
      toneMapped={base !== undefined}
    />
  );
}

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

/** One DATAOUT pin lamp; brightness and colour ease between off and on. */
function PinLamp({ on, color, position, reducedMotion }: { on: boolean; color: string; position: [number, number, number]; reducedMotion: boolean }) {
  const mat = useRef<THREE.MeshStandardMaterial>(null);
  const level = useRef(on ? 1 : 0);
  const offColor = useMemo(() => new THREE.Color('#2A2D33'), []);
  const onColor = useMemo(() => new THREE.Color(color), [color]);
  // Initial values only, so a re-render never snaps what the frame loop eases.
  const [initialOn] = useState(on);
  useFrame((_, delta) => {
    const m = mat.current;
    if (!m) return;
    level.current = reducedMotion ? (on ? 1 : 0) : THREE.MathUtils.damp(level.current, on ? 1 : 0, 9, delta);
    m.color.lerpColors(offColor, onColor, level.current);
    m.emissiveIntensity = 2.2 * level.current;
  });
  return (
    <mesh position={position}>
      <sphereGeometry args={[0.035, 16, 16]} />
      <meshStandardMaterial ref={mat} color={initialOn ? color : '#2A2D33'} emissive={color} emissiveIntensity={initialOn ? 2.2 : 0} toneMapped={false} />
    </mesh>
  );
}

function Charger({ accent, pins, motion, reducedMotion }: { accent: string; pins: number; motion: MotionRef; reducedMotion: boolean }) {
  const coil = useRef<THREE.Mesh>(null);
  useFrame(() => {
    // The coiled cable on the holster shrinks away as the cable reaches out.
    const c = coil.current;
    if (!c) return;
    const k = 1 - easeInOut(Math.min(motion.current.cable * 1.6, 1));
    c.scale.setScalar(Math.max(k, 0.001));
    c.visible = k > 0.01;
  });
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
        <FadingMaterial color={accent} emissiveIntensity={1.6} reducedMotion={reducedMotion} />
      </mesh>
      {/* Screen */}
      <RoundedBox args={[0.5, 0.34, 0.03]} radius={0.02} smoothness={3} position={[0, 1.72, 0.35]}>
        <FadingMaterial color={accent} base="#0C1018" emissiveIntensity={0.35} roughness={0.2} reducedMotion={reducedMotion} />
      </RoundedBox>
      {/* P4-P7 output lamps */}
      {PIN_LAMPS.map((l, i) => (
        <PinLamp
          key={l.bit}
          on={(pins & (1 << l.bit)) !== 0}
          color={l.color}
          position={[-0.18 + i * 0.12, 1.4, 0.35]}
          reducedMotion={reducedMotion}
        />
      ))}
      {/* Holster */}
      <RoundedBox args={[0.22, 0.34, 0.14]} radius={0.05} smoothness={4} position={[0.22, 0.98, 0.36]} castShadow>
        <Clay color={CLAY_DARK} />
      </RoundedBox>
      <mesh ref={coil} position={[0.22, 0.62, 0.42]} castShadow>
        <torusGeometry args={[0.2, 0.035, 12, 32, Math.PI * 1.6]} />
        <Clay color={RUBBER} roughness={0.5} />
      </mesh>
    </group>
  );
}

function Wheel({ position }: { position: [number, number, number] }) {
  const outward = position[2] > 0 ? 1 : -1;
  return (
    <group position={position}>
      {/* Spun by Car as it rolls; the name is how Car finds it. */}
      <group name="wheel-spin">
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
    </group>
  );
}

const WHEEL_R = 0.33;

function Car({ motion }: { motion: MotionRef }) {
  const group = useRef<THREE.Group>(null);
  const body = useRef<THREE.Group>(null);
  const parts = useRef<{ wheels: THREE.Object3D[]; materials: THREE.Material[] }>({ wheels: [], materials: [] });
  const kin = useRef({ x: motion.current.x, v: 0, a: 0 });

  useEffect(() => {
    const g = group.current;
    if (!g) return;
    const wheels: THREE.Object3D[] = [];
    const materials = new Set<THREE.Material>();
    g.traverse((o) => {
      if (o.name === 'wheel-spin') wheels.push(o);
      const mat = (o as THREE.Mesh).material;
      if (mat) (Array.isArray(mat) ? mat : [mat]).forEach((m) => materials.add(m));
    });
    parts.current = { wheels, materials: [...materials] };
  }, []);

  useFrame((_, delta) => {
    const g = group.current;
    if (!g) return;
    const x = motion.current.x;
    const k = kin.current;
    let dx = x - k.x;
    k.x = x;
    // A jump of metres in one frame is the off-screen reset, not driving.
    if (Math.abs(dx) > 2) {
      dx = 0;
      k.v = 0;
      k.a = 0;
    }
    g.position.x = x;
    parts.current.wheels.forEach((w) => (w.rotation.z -= dx / WHEEL_R));

    // Suspension: the nose dips under braking and lifts when pulling away.
    if (delta > 0) {
      const v = THREE.MathUtils.damp(k.v, dx / delta, 10, delta);
      k.a = THREE.MathUtils.damp(k.a, (v - k.v) / delta, 6, delta);
      k.v = v;
    }
    if (body.current) body.current.rotation.z = THREE.MathUtils.clamp(k.a * 0.0016, -0.05, 0.05);

    // Fade in and out at the plinth edge so the car never pops.
    const opacity = 1 - THREE.MathUtils.smoothstep(Math.abs(x), 2.6, 5.4);
    g.visible = opacity > 0.01;
    parts.current.materials.forEach((m) => {
      const transparent = opacity < 0.999;
      if (m.transparent !== transparent) {
        m.transparent = transparent;
        m.needsUpdate = true;
      }
      m.opacity = opacity;
    });
  });

  const { body: bodyGeo, glass } = useCarGeometry();

  return (
    <group ref={group} position={[motion.current.x, 0, 0.6]}>
      <group ref={body}>
      <mesh geometry={bodyGeo} castShadow receiveShadow>
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
      </group>
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

const TUBE_SEGMENTS = 96;
const TUBE_RADIAL = 12;
const PULSE_COUNT = 7;

/** Reaches from the holster to the car port as motion.cable goes 0 -> 1. */
function Cable({ motion, accent, reducedMotion }: { motion: MotionRef; accent: string; reducedMotion: boolean }) {
  const curve = useMemo(() => new THREE.CatmullRomCurve3(CABLE_POINTS), []);
  const tube = useMemo(() => new THREE.TubeGeometry(curve, TUBE_SEGMENTS, 0.045, TUBE_RADIAL, false), [curve]);
  const root = useRef<THREE.Group>(null);
  const plug = useRef<THREE.Group>(null);
  const pulses = useRef<THREE.Group>(null);
  const tip = useMemo(() => new THREE.Vector3(), []);
  const tangent = useMemo(() => new THREE.Vector3(), []);
  const up = useMemo(() => new THREE.Vector3(0, 1, 0), []);

  useFrame(({ clock }) => {
    const { cable, flow } = motion.current;
    const reach = easeInOut(cable);
    if (root.current) root.current.visible = reach > 0.005;
    // TubeGeometry indices run segment by segment, so a draw range grows the
    // tube along its length. 6 indices per quad, TUBE_RADIAL quads per ring.
    tube.setDrawRange(0, Math.round(reach * TUBE_SEGMENTS) * TUBE_RADIAL * 6);

    const p = plug.current;
    if (p) {
      curve.getPointAt(reach, tip);
      curve.getTangentAt(reach, tangent);
      p.position.copy(tip);
      p.quaternion.setFromUnitVectors(up, tangent);
    }

    const g = pulses.current;
    if (!g) return;
    g.visible = flow > 0.01;
    const t0 = reducedMotion ? 0 : clock.getElapsedTime() * 0.35;
    const size = easeInOut(flow);
    g.children.forEach((child, i) => {
      // Power flows charger -> car, i.e. along the curve from t=0 to t=1.
      const t = (i / PULSE_COUNT + t0) % 1;
      child.position.copy(curve.getPointAt(t));
      child.scale.setScalar(Math.max(size, 0.001));
    });
  });

  return (
    <group ref={root}>
      <mesh geometry={tube} castShadow>
        <Clay color={RUBBER} roughness={0.45} />
      </mesh>
      {/* Connector head riding the tip of the cable */}
      <group ref={plug}>
        <mesh castShadow>
          <cylinderGeometry args={[0.075, 0.065, 0.2, 24]} />
          <Clay color={CLAY_DARK} roughness={0.5} />
        </mesh>
      </group>
      <group ref={pulses}>
        {Array.from({ length: PULSE_COUNT }, (_, i) => (
          <mesh key={i}>
            <sphereGeometry args={[0.065, 16, 16]} />
            <FadingMaterial color={accent} emissiveIntensity={2.4} reducedMotion={reducedMotion} />
          </mesh>
        ))}
      </group>
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
  // First paint starts from an empty bay, so a session opening with a car
  // attached still shows it driving in.
  const motion = useRef<Motion>(restingMotion(false, false));
  return (
    <>
      <FitCamera />
      <Lights />
      <Director motion={motion} carPresent={carPresent} charging={charging} reducedMotion={reducedMotion} />
      <Plinth />
      <ContactShadows position={[0, 0.005, 0]} scale={7} blur={2.2} far={3} opacity={0.55} resolution={512} frames={reducedMotion ? 1 : Infinity} />
      <ContactShadows position={[0, -0.43, 0]} scale={9} blur={3} far={2} opacity={0.6} resolution={256} frames={1} />
      <Charger accent={accent} pins={pins} motion={motion} reducedMotion={reducedMotion} />
      <Car motion={motion} />
      <Cable motion={motion} accent={accent} reducedMotion={reducedMotion} />
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
