// Phase 6: dispute-scenario mini demo for the Grid tab.
//
// This is a self-contained, simplified illustration of the same idea as
// station/CRCChainViz.tsx (chain of CRC-checked frames feeding a session
// record) -- NOT a byte-exact simulation. It does not import crc16()
// against real frame bytes; the three "frames" here are decorative nodes
// whose job is to make the argument legible at a glance: once a frame's
// CRC breaks, nothing chained after it can be trusted, so the record only
// reports energy up to the last good frame. Byte-exact corruption/chain
// mechanics already live in CRCChainViz + FrameInspector for the Station
// tab; duplicating that machinery here would just be a second, harder-to-
// read copy of the same proof.
//
// Energy count-down tween: simple requestAnimationFrame-driven ease, no
// animation library dependency (none is used elsewhere in grid/*).

import { useEffect, useRef, useState } from 'react';
import { ChevronDown, Check, X, RotateCcw, AlertTriangle } from 'lucide-react';

const ENERGY_BEFORE = 1_104_000; // Wh, illustrative "healthy session" figure
const ENERGY_AFTER = 368_000; // Wh, illustrative "billed up to fault" figure
const TWEEN_MS = 900;

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

/** Eases energy from `from` to `to` over TWEEN_MS, via rAF. Cancels cleanly on unmount/retrigger. */
function useEnergyTween(target: number, reducedMotion: boolean): number {
  const [value, setValue] = useState(target);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    const start = value;
    const delta = target - start;
    if (delta === 0) return;

    if (reducedMotion) {
      setValue(target);
      return;
    }

    const startTime = performance.now();
    const tick = (now: number) => {
      const t = Math.min(1, (now - startTime) / TWEEN_MS);
      const eased = 1 - (1 - t) * (1 - t); // ease-out quad
      setValue(Math.round(start + delta * eased));
      if (t < 1) {
        rafRef.current = requestAnimationFrame(tick);
      }
    };
    rafRef.current = requestAnimationFrame(tick);

    return () => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
    };
    // Intentionally re-runs only when `target` changes (plus reducedMotion),
    // not when `value` changes -- `value` is the tween's own output.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [target, reducedMotion]);

  return value;
}

interface MiniNodeProps {
  label: string;
  broken: boolean;
  isRecord?: boolean;
}

function MiniNode({ label, broken, isRecord }: MiniNodeProps) {
  const borderColor = broken ? 'rgba(255,90,95,0.6)' : 'rgba(34,197,94,0.5)';
  const bg = broken ? 'rgba(255,90,95,0.12)' : '#1B2336';

  return (
    <div
      className="flex h-[58px] w-[110px] shrink-0 flex-col items-center justify-center gap-0.5 rounded-lg border px-2 text-center transition-colors duration-300"
      style={{ borderColor, backgroundColor: bg }}
    >
      <span className="font-sans text-[10px] text-[#94A3B8]">{isRecord ? 'Record' : label}</span>
      {broken ? (
        <X size={16} color="#FF5A5F" aria-label="invalid" />
      ) : (
        <Check size={16} color="#22C55E" aria-label="valid" />
      )}
      {isRecord && broken && (
        <span className="font-mono text-[9px] font-semibold text-[#FF5A5F]">CRC_LOST</span>
      )}
    </div>
  );
}

function Arrow() {
  return (
    <svg width="28" height="12" viewBox="0 0 28 12" aria-hidden="true" className="shrink-0">
      <path d="M0 6 H20" stroke="#475569" strokeWidth="1.5" fill="none" />
      <path d="M20 2 L28 6 L20 10 Z" fill="#475569" />
    </svg>
  );
}

export default function DisputePanel() {
  const [expanded, setExpanded] = useState(false);
  const [corrupted, setCorrupted] = useState(false);
  const reducedMotion = usePrefersReducedMotion();
  const energy = useEnergyTween(corrupted ? ENERGY_AFTER : ENERGY_BEFORE, reducedMotion);

  const handleCorrupt = () => setCorrupted(true);
  const handleReset = () => setCorrupted(false);

  return (
    <div className="rounded-xl border border-white/10 bg-[#1B2336]/80 backdrop-blur-sm">
      <button
        type="button"
        onClick={() => setExpanded((e) => !e)}
        aria-expanded={expanded}
        aria-controls="dispute-panel-content"
        className="flex w-full cursor-pointer items-center justify-between gap-2 rounded-xl px-4 py-4 text-left transition-colors duration-150 hover:bg-white/5 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A]"
      >
        <span className="font-mono text-sm font-medium text-[#F8FAFC]">
          What if someone disputes a charge?
        </span>
        <ChevronDown
          size={18}
          className={`shrink-0 text-[#94A3B8] transition-transform duration-300 ${expanded ? 'rotate-180' : ''}`}
          aria-hidden="true"
        />
      </button>

      <div
        id="dispute-panel-content"
        className="overflow-hidden transition-[max-height] duration-300 ease-in-out"
        style={{ maxHeight: expanded ? 480 : 0 }}
      >
        <div className="border-t border-white/10 px-4 py-4">
          {/* Mini CRC chain */}
          <div className="mb-4 overflow-x-auto pb-1">
            <div className="flex items-center" style={{ minWidth: 'max-content' }}>
              <MiniNode label="Frame 1" broken={false} />
              <Arrow />
              <MiniNode label="Frame 2" broken={corrupted} />
              <Arrow />
              <MiniNode label="Frame 3" broken={corrupted} />
              <Arrow />
              <MiniNode label="Record" broken={corrupted} isRecord />
            </div>
          </div>

          {/* Energy display */}
          <div className="mb-4 flex flex-wrap items-center gap-4 rounded-lg border border-white/10 bg-[#272F42]/60 px-4 py-3">
            <div>
              <div className="text-xs text-[#94A3B8]">Energy billed</div>
              <div className="font-mono text-2xl font-bold tabular-nums text-[#22C55E]">
                {energy.toLocaleString()} <span className="text-sm font-normal text-[#94A3B8]">Wh</span>
              </div>
            </div>
            {corrupted && (
              <div className="flex items-center gap-1.5 rounded-lg border border-[#FF5A5F]/40 bg-[#FF5A5F]/10 px-2.5 py-1.5 text-xs font-medium text-[#FF5A5F]">
                <AlertTriangle size={14} aria-hidden="true" />
                CRC_LOST
              </div>
            )}
          </div>

          {/* Status text */}
          <p className="mb-4 font-mono text-sm text-[#F8FAFC]">
            {corrupted
              ? 'Status: meter link broken at Frame 2 — billing stopped, session closed at last verified reading.'
              : 'Status: all frames verified — session billing nominal.'}
          </p>

          {/* Controls */}
          <div className="mb-4 flex flex-wrap items-center gap-3">
            <button
              type="button"
              onClick={handleCorrupt}
              disabled={corrupted}
              className="cursor-pointer rounded-lg border border-[#FF5A5F]/50 bg-[#FF5A5F]/20 px-4 py-1.5 text-sm font-medium text-[#FF5A5F] transition-colors duration-150 hover:bg-[#FF5A5F]/30 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A] disabled:cursor-not-allowed disabled:opacity-40"
            >
              Corrupt Frame 2
            </button>
            <button
              type="button"
              onClick={handleReset}
              disabled={!corrupted}
              aria-label="Reset dispute demo"
              className="flex cursor-pointer items-center gap-1.5 rounded-lg border border-[var(--color-border)]/40 bg-[var(--color-card)]/70 px-4 py-1.5 text-sm font-medium text-[var(--color-foreground)] transition-colors duration-150 hover:border-[var(--color-accent)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A] disabled:cursor-not-allowed disabled:opacity-40"
            >
              <RotateCcw size={14} aria-hidden="true" />
              Reset
            </button>
          </div>

          {/* Explanation */}
          <p className="text-sm text-[#94A3B8]">
            The chip stopped billing the instant the meter link broke. The session record proves
            exactly how much energy was delivered before the fault. No human override. No network
            required.
          </p>
        </div>
      </div>
    </div>
  );
}
