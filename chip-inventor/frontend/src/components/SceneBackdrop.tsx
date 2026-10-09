// Layered, see-through backdrop for the 3D dioramas. Replaces the flat,
// fully opaque navy/charcoal fills: a frosted card that lets the warm page
// show through, a sky gradient per mood, a soft sun/alarm glow, a faint
// blueprint dot grid that fades at the edges, and a pool of light under the
// diorama so the plinth sits on something. Moods cross-fade (700 ms).
//
//   calm  -- pale sky into paper: normal running.
//   alert -- dusty-rose dusk with a warm alarm glow: grid stress.
//   night -- deep twilight: the blackout moment only, where the lit windows
//            and red crosses need a dark field to read.

export type Mood = 'calm' | 'alert' | 'night';

interface Layer {
  mood: Mood;
  background: string;
}

const SKY: Layer[] = [
  {
    mood: 'calm',
    background: [
      'radial-gradient(38% 46% at 84% 6%, rgba(250, 226, 150, 0.55) 0%, rgba(250, 226, 150, 0) 70%)',
      'linear-gradient(180deg, rgba(196, 214, 236, 0.78) 0%, rgba(222, 231, 240, 0.55) 46%, rgba(246, 240, 228, 0.2) 100%)',
    ].join(', '),
  },
  {
    mood: 'alert',
    background: [
      'radial-gradient(46% 42% at 24% 0%, rgba(255, 112, 96, 0.26) 0%, rgba(255, 112, 96, 0) 70%)',
      'radial-gradient(34% 40% at 88% 10%, rgba(248, 196, 120, 0.35) 0%, rgba(248, 196, 120, 0) 70%)',
      'linear-gradient(180deg, rgba(236, 204, 196, 0.8) 0%, rgba(240, 221, 210, 0.55) 50%, rgba(246, 238, 228, 0.2) 100%)',
    ].join(', '),
  },
  {
    mood: 'night',
    background: [
      'radial-gradient(40% 40% at 80% 4%, rgba(150, 168, 230, 0.28) 0%, rgba(150, 168, 230, 0) 70%)',
      'linear-gradient(180deg, rgba(36, 44, 70, 0.94) 0%, rgba(62, 64, 92, 0.88) 55%, rgba(104, 96, 112, 0.78) 100%)',
    ].join(', '),
  },
];

const FADE = 'absolute inset-0 transition-opacity duration-700 ease-out';

/** Text classes that read on each mood, and a glass panel to set them on. */
export const MOOD_TEXT: Record<Mood, { title: string; sub: string; panel: string }> = {
  calm: { title: 'text-[var(--color-ink)]', sub: 'text-[var(--color-ink-2)]', panel: 'bg-white/60 ring-white/80' },
  alert: { title: 'text-[var(--color-ink)]', sub: 'text-[var(--color-ink-2)]', panel: 'bg-white/60 ring-white/80' },
  night: { title: 'text-white', sub: 'text-white/70', panel: 'bg-[#14161A]/55 ring-white/10' },
};

export default function SceneBackdrop({ mood }: { mood: Mood }) {
  const dark = mood === 'night';
  return (
    <div className="pointer-events-none absolute inset-0" aria-hidden="true">
      {/* Frosted base: translucent, so the page's warm wash shows through */}
      <div className="absolute inset-0 bg-white/30 backdrop-blur-md" />

      {SKY.map((l) => (
        <div key={l.mood} className={FADE} style={{ background: l.background, opacity: mood === l.mood ? 1 : 0 }} />
      ))}

      {/* Blueprint dot grid, strongest behind the diorama, gone at the edges */}
      {[false, true].map((light) => (
        <div
          key={String(light)}
          className={FADE}
          style={{
            backgroundImage: `radial-gradient(${light ? 'rgba(255,255,255,0.16)' : 'rgba(40,48,70,0.13)'} 1px, transparent 1.6px)`,
            backgroundSize: '22px 22px',
            maskImage: 'radial-gradient(72% 62% at 50% 42%, #000 0%, transparent 100%)',
            WebkitMaskImage: 'radial-gradient(72% 62% at 50% 42%, #000 0%, transparent 100%)',
            opacity: light === dark ? 1 : 0,
          }}
        />
      ))}

      {/* Pool of light the plinth rests in */}
      <div
        className={FADE}
        style={{ background: 'radial-gradient(46% 20% at 50% 70%, rgba(255,255,255,0.6) 0%, rgba(255,255,255,0) 72%)', opacity: dark ? 0 : 1 }}
      />
      <div
        className={FADE}
        style={{ background: 'radial-gradient(46% 20% at 50% 70%, rgba(140,160,230,0.22) 0%, rgba(140,160,230,0) 72%)', opacity: dark ? 1 : 0 }}
      />

      {/* Bottom wash keeps the caption legible over the scene */}
      <div className={FADE} style={{ background: 'linear-gradient(to top, rgba(248,245,238,0.85) 0%, rgba(248,245,238,0) 26%)', opacity: dark ? 0 : 1 }} />
      <div className={FADE} style={{ background: 'linear-gradient(to top, rgba(22,24,38,0.7) 0%, rgba(22,24,38,0) 26%)', opacity: dark ? 1 : 0 }} />

      {/* Hairline inner edge, like the frosted cards elsewhere on the page */}
      <div className="absolute inset-0 rounded-[inherit] ring-1 ring-white/70 ring-inset" />
    </div>
  );
}
