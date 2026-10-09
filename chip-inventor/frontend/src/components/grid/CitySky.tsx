// Clay sky behind the town: a sun with turning rays and a soft halo, puffy
// clouds drifting on the wind, a few birds, and stars for the blackout.
//
// The sky is pinned to the view, not the world: each frame its root sits far
// behind the town along the camera axis, faces the camera, and is scaled to
// the visible height. So clouds keep their screen size and place while the
// camera glides into a close-up, the way a painted backdrop would.

import { useMemo, useRef } from 'react';
import { useFrame, useThree } from '@react-three/fiber';
import * as THREE from 'three';
import type { Mood } from '../SceneBackdrop';

/** Cloud cluster: [x, y, radius] puffs in cluster units, plus a flat base. */
const PUFFS: [number, number, number][] = [
  [0, 0.05, 0.5],
  [0.48, -0.06, 0.38],
  [-0.46, -0.08, 0.34],
  [0.2, 0.32, 0.36],
  [-0.2, 0.26, 0.3],
  [0.78, -0.14, 0.24],
];

/**
 * Cloud placement in viewport units: x in widths (-0.5..0.5), y in heights
 * (-0.5..0.5), size as a fraction of the viewport height. The bottom-left
 * corner stays clear for the caption.
 */
const CLOUDS = [
  { x: -0.4, y: 0.36, s: 0.085, speed: 0.006 },
  { x: -0.18, y: 0.44, s: 0.05, speed: 0.009 },
  { x: 0.2, y: 0.4, s: 0.06, speed: 0.007 },
  { x: -0.44, y: 0.04, s: 0.06, speed: 0.005 },
  { x: 0.43, y: -0.06, s: 0.075, speed: 0.006 },
  { x: 0.38, y: -0.36, s: 0.055, speed: 0.008 },
  { x: 0.05, y: 0.47, s: 0.04, speed: 0.01 },
];

const SUN = { x: 0.36, y: 0.33, r: 0.055 };

const BIRDS = [
  { y: 0.25, phase: 0, s: 0.011 },
  { y: 0.28, phase: 0.035, s: 0.009 },
  { y: 0.22, phase: 0.05, s: 0.01 },
  { y: 0.27, phase: 0.08, s: 0.008 },
];

const SKY_DEPTH = 50;

const TINT: Record<Mood, { cloud: string; sun: string; halo: string; glow: number }> = {
  calm: { cloud: '#FFFFFF', sun: '#FFC93D', halo: '#FFE08A', glow: 0.9 },
  alert: { cloud: '#F6E6E1', sun: '#FFAA45', halo: '#FFB38A', glow: 0.75 },
  night: { cloud: '#6A7090', sun: '#E6EBF7', halo: '#9FB2E6', glow: 0.35 },
};

function haloTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d')!;
  const grad = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  grad.addColorStop(0, 'rgba(255,255,255,0.9)');
  grad.addColorStop(0.35, 'rgba(255,255,255,0.35)');
  grad.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 128, 128);
  return new THREE.CanvasTexture(c);
}

function Cloud() {
  return (
    <group>
      {PUFFS.map(([x, y, r], i) => (
        <mesh key={i} position={[x, y, 0]}>
          <sphereGeometry args={[r, 24, 18]} />
          <meshStandardMaterial name="cloud" color="#FFFFFF" roughness={0.95} emissive="#FFFFFF" emissiveIntensity={0.18} />
        </mesh>
      ))}
      {/* Flat underside, as clay clouds are modelled */}
      <mesh position={[0.1, -0.16, 0]} scale={[1.25, 0.32, 0.6]}>
        <sphereGeometry args={[0.7, 24, 12]} />
        <meshStandardMaterial name="cloud" color="#FFFFFF" roughness={0.95} emissive="#FFFFFF" emissiveIntensity={0.18} />
      </mesh>
    </group>
  );
}

export default function CitySky({ mood, reducedMotion }: { mood: Mood; reducedMotion: boolean }) {
  const { camera, size } = useThree();
  const root = useRef<THREE.Group>(null);
  const clouds = useRef<(THREE.Group | null)[]>([]);
  const sun = useRef<THREE.Group>(null);
  const sunMat = useRef<THREE.MeshStandardMaterial>(null);
  const rays = useRef<THREE.Group>(null);
  const haloMat = useRef<THREE.MeshBasicMaterial>(null);
  const birds = useRef<(THREE.Group | null)[]>([]);
  const starsMat = useRef<THREE.PointsMaterial>(null);
  const starField = useRef<THREE.Group>(null);
  const halo = useMemo(() => haloTexture(), []);
  const fwd = useMemo(() => new THREE.Vector3(), []);
  const tint = useMemo(() => ({ cloud: new THREE.Color('#FFFFFF'), sun: new THREE.Color('#FFC93D'), halo: new THREE.Color('#FFE08A'), glow: 0.9, night: 0 }), []);
  const goal = useMemo(() => new THREE.Color(), []);
  const cloudMats = useRef<THREE.MeshStandardMaterial[]>([]);

  const stars = useMemo(() => {
    const n = 60;
    const pos = new Float32Array(n * 3);
    let a = 7;
    const rand = () => ((a = (a * 16807) % 2147483647) / 2147483647);
    for (let i = 0; i < n; i++) {
      pos[i * 3] = rand() - 0.5;
      pos[i * 3 + 1] = 0.05 + rand() * 0.45;
      pos[i * 3 + 2] = -0.5;
    }
    return pos;
  }, []);

  useFrame(({ clock }, delta) => {
    const g = root.current;
    if (!g) return;
    const cam = camera as THREE.OrthographicCamera;
    const H = size.height / cam.zoom;
    const aspect = size.width / size.height;
    camera.getWorldDirection(fwd);
    g.position.copy(camera.position).addScaledVector(fwd, SKY_DEPTH);
    g.quaternion.copy(camera.quaternion);
    g.scale.setScalar(H);

    if (cloudMats.current.length === 0) {
      g.traverse((o) => {
        const m = (o as THREE.Mesh).material as THREE.MeshStandardMaterial | undefined;
        if (m && m.name === 'cloud') cloudMats.current.push(m);
      });
    }

    const t = reducedMotion ? 0 : clock.getElapsedTime();
    const k = reducedMotion ? 1 : 1 - Math.exp(-2.5 * delta);
    const want = TINT[mood];
    tint.cloud.lerp(goal.set(want.cloud), k);
    tint.sun.lerp(goal.set(want.sun), k);
    tint.halo.lerp(goal.set(want.halo), k);
    tint.glow = THREE.MathUtils.lerp(tint.glow, want.glow, k);
    tint.night = THREE.MathUtils.lerp(tint.night, mood === 'night' ? 1 : 0, k);
    cloudMats.current.forEach((m) => {
      m.color.copy(tint.cloud);
      m.emissive.copy(tint.cloud);
      m.emissiveIntensity = 0.18 * (1 - tint.night * 0.7);
    });

    // Clouds drift right on the wind and wrap round past the edges.
    CLOUDS.forEach((c, i) => {
      const o = clouds.current[i];
      if (!o) return;
      const span = 1.3;
      let fx = c.x + t * c.speed;
      fx = ((((fx + span / 2) % span) + span) % span) - span / 2;
      o.position.set(fx * aspect, c.y + Math.sin(t * 0.4 + i) * 0.006, 0);
      o.scale.setScalar(c.s);
    });

    if (sun.current) {
      sun.current.position.set(SUN.x * aspect, SUN.y - tint.night * 0.04, 0);
      sun.current.scale.setScalar(SUN.r);
    }
    if (sunMat.current) {
      sunMat.current.color.copy(tint.sun);
      sunMat.current.emissive.copy(tint.sun);
      sunMat.current.emissiveIntensity = tint.glow;
    }
    if (rays.current) {
      rays.current.rotation.z = -t * 0.12;
      rays.current.scale.setScalar(Math.max(0.001, 1 - tint.night));
    }
    if (haloMat.current) {
      haloMat.current.color.copy(tint.halo);
      haloMat.current.opacity = 0.55 + Math.sin(t * 0.8) * 0.05;
    }
    starField.current?.scale.set(aspect, 1, 1);
    if (starsMat.current) {
      starsMat.current.opacity = tint.night * 0.85;
      starsMat.current.visible = tint.night > 0.02;
    }

    // Birds glide across the top, flapping; they roost during the blackout.
    birds.current.forEach((b, i) => {
      if (!b) return;
      const bd = BIRDS[i];
      const span = 1.5;
      const fx = ((t * 0.018 + bd.phase) % span) - span / 2;
      b.position.set(fx * aspect, bd.y + Math.sin(t * 0.9 + i) * 0.01, 0.2);
      b.scale.setScalar(bd.s * (1 - tint.night));
      b.visible = !reducedMotion && tint.night < 0.95;
      const flap = Math.sin(t * 7 + i * 1.3) * 0.5;
      const [l, r] = b.children as THREE.Object3D[];
      if (l && r) {
        // Wings hinge at the body; tips up makes the classic shallow V.
        l.rotation.z = -(0.35 + flap);
        r.rotation.z = 0.35 + flap;
      }
    });
  });

  return (
    <group ref={root}>
      <group ref={starField}>
        <points frustumCulled={false}>
          <bufferGeometry>
            <bufferAttribute attach="attributes-position" args={[stars, 3]} />
          </bufferGeometry>
          <pointsMaterial ref={starsMat} color="#FFFFFF" size={2.2} sizeAttenuation={false} transparent opacity={0} depthWrite={false} />
        </points>
      </group>

      <group ref={sun}>
        <mesh position={[0, 0, -0.2]}>
          <planeGeometry args={[7, 7]} />
          <meshBasicMaterial ref={haloMat} map={halo} color="#FFE08A" transparent depthWrite={false} opacity={0.55} toneMapped={false} />
        </mesh>
        <mesh>
          <sphereGeometry args={[1, 32, 24]} />
          <meshStandardMaterial ref={sunMat} color="#FFC93D" emissive="#FFC93D" emissiveIntensity={0.9} roughness={0.4} toneMapped={false} />
        </mesh>
        <group ref={rays}>
          {Array.from({ length: 10 }, (_, i) => {
            const a = (i / 10) * Math.PI * 2;
            return (
              <mesh key={i} position={[Math.cos(a) * 1.55, Math.sin(a) * 1.55, 0]} rotation={[0, 0, a + Math.PI / 2]}>
                <capsuleGeometry args={[0.12, 0.38, 4, 10]} />
                <meshStandardMaterial color="#FFD45E" emissive="#FFC93D" emissiveIntensity={0.7} roughness={0.4} toneMapped={false} />
              </mesh>
            );
          })}
        </group>
      </group>

      {CLOUDS.map((_, i) => (
        <group key={i} ref={(o) => void (clouds.current[i] = o)}>
          <Cloud />
        </group>
      ))}

      {BIRDS.map((_, i) => (
        <group key={i} ref={(o) => void (birds.current[i] = o)}>
          {[-1, 1].map((side) => (
            <group key={side}>
              <mesh position={[side * 0.55, 0, 0]}>
                <boxGeometry args={[1.1, 0.16, 0.16]} />
                <meshStandardMaterial color="#3A3F48" roughness={0.7} />
              </mesh>
            </group>
          ))}
        </group>
      ))}
    </group>
  );
}
