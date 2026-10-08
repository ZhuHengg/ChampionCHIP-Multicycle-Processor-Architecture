// Phase 4: interactive per-frame CRC + sequence visualization across meter
// frames (protocol v2, see data/meterProtocol.ts).
//
// Byte layout per data/meter.ts Meter.frame() / golden.py frame_body():
// byte[0] = sequence, bytes[1:3] = voltage, bytes[3:5] = current,
// bytes[5:7] = frequency, bytes[7:9] = CRC-16, little-endian
// (confirmed against data/charger.ts Charger._onFrame: `frame[7] |
// frame[8] << 8`, CRC over `frame.subarray(0, 7)`). Unlike the original
// protocol, each frame's CRC is independent (seed always 0xFFFF) -- the
// chain concept is gone. Continuity is instead checked via the sequence
// byte: Charger.lastSequence must advance by exactly 1, and a gap/replay
// is flagged or rejected (see charger.ts _onFrame).
//
// This component recomputes each frame's CRC and sequence delta
// client-side from `original`/`current` bytes so a user can flip byte 1
// bit 0 (voltage, mirrors data/meter.ts corrupt()) on any frame and watch
// validity change, without touching the Charger model.

import { useMemo } from 'react';
import { Check, X, RotateCcw } from 'lucide-react';
import { crc16 } from '../../data/crc';

export interface CRCChainFrame {
  original: Uint8Array;
  current: Uint8Array;
}

interface ChainNode {
  index: number;
  bytes: Uint8Array;
  sequence: number;
  sequenceOk: boolean;
  crcField: number;
  expectedCrc: number;
  valid: boolean;
  corrupted: boolean;
}

interface CRCChainVizProps {
  frames: CRCChainFrame[];
  corrupted: ReadonlySet<number>;
  onToggleCorrupt: (index: number) => void;
  onReset: () => void;
  selectedIndex?: number | null;
  onSelect?: (index: number) => void;
}

/** Flip bit 0 of the voltage's low byte -- mirrors data/meter.ts corrupt(). */
function flipVoltageBit0(bytes: Uint8Array): Uint8Array {
  const out = new Uint8Array(bytes);
  out[1] = out[1] ^ 1;
  return out;
}

function formatHex(value: number): string {
  return `0x${value.toString(16).toUpperCase().padStart(4, '0')}`;
}

function CRCChainViz({ frames, corrupted, onToggleCorrupt, onReset, selectedIndex, onSelect }: CRCChainVizProps) {
  const nodes = useMemo<ChainNode[]>(() => {
    let lastSequence: number | null = null;
    return frames.map((f, index) => {
      const bytes = corrupted.has(index) ? flipVoltageBit0(f.current) : f.current;
      const sequence = bytes[0];
      const crcField = bytes[7] | (bytes[8] << 8);
      const expectedCrc = crc16(bytes.subarray(0, 7));
      const valid = expectedCrc === crcField;
      // Mirrors charger.ts _onFrame: delta of 1 continues, 0 or >=128 is a
      // replay (rejected), anything else is a forward gap (flagged, not
      // rejected). Only evaluated when the frame's own CRC is valid, same
      // as the model (a corrupt frame never reaches the sequence check).
      const delta = lastSequence === null ? 1 : (sequence - lastSequence) & 0xFF;
      const sequenceOk = !valid || lastSequence === null || (delta !== 0 && delta < 128);
      if (valid) lastSequence = sequence;
      return { index, bytes, sequence, sequenceOk, crcField, expectedCrc, valid, corrupted: corrupted.has(index) };
    });
  }, [frames, corrupted]);

  if (frames.length === 0) {
    return (
      <div className="flex h-24 items-center justify-center rounded-xl border border-dashed border-[var(--color-line)] text-sm text-[var(--color-mute)]">
        This scenario sends no meter frames.
      </div>
    );
  }

  return (
    <div>
      <div className="mb-3 flex items-center justify-between gap-3">
        <p className="text-sm text-[var(--color-ink-2)]">
          Click a frame to flip one bit of its voltage. Its CRC no longer matches, and the chip rejects it.
        </p>
        <button
          type="button"
          onClick={onReset}
          disabled={corrupted.size === 0}
          className="flex min-h-9 shrink-0 cursor-pointer items-center gap-1.5 rounded-lg border border-[var(--color-line)] px-3 text-xs font-medium text-[var(--color-ink)] transition-colors duration-150 hover:bg-white/[0.05] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ok)] disabled:cursor-not-allowed disabled:opacity-40"
        >
          <RotateCcw size={14} aria-hidden="true" />
          Reset
        </button>
      </div>

      <div className="overflow-x-auto pb-2">
        <div className="flex items-center" style={{ minWidth: 'max-content' }}>
          {/* Start node: each frame's CRC is now independent (no chain
              seed), so this marks the start of the sequence-number run
              rather than a shared CRC seed. */}
          <div
            className="flex h-[55px] w-[130px] shrink-0 flex-col items-center justify-center rounded-lg border px-2 text-center"
            style={{ borderColor: 'rgba(255,255,255,0.1)', backgroundColor: '#0F1729' }}
          >
            <span className="font-sans text-[11px] text-[#94A3B8]">Start</span>
            <span className="font-mono text-sm text-[#F8FAFC]">seq --</span>
          </div>

          {nodes.map((node) => (
            <ChainEdgeAndNode
              key={node.index}
              node={node}
              isSelected={selectedIndex === node.index}
              onClickNode={() => onSelect?.(node.index)}
              onToggleCorrupt={() => onToggleCorrupt(node.index)}
            />
          ))}
        </div>
      </div>
    </div>
  );
}

function ChainEdgeAndNode({
  node,
  isSelected,
  onClickNode,
  onToggleCorrupt,
}: {
  node: ChainNode;
  isSelected: boolean;
  onClickNode: () => void;
  onToggleCorrupt: () => void;
}) {
  const borderColor = node.valid ? 'rgba(34,197,94,0.5)' : 'rgba(255,90,95,0.5)';
  const bg = node.valid ? '#0F1729' : 'rgba(255,90,95,0.1)';

  return (
    <div className="flex shrink-0 items-center">
      {/* Arrow with this frame's sequence byte */}
      <div className="flex w-12 flex-col items-center justify-center">
        <span className="mb-0.5 whitespace-nowrap font-mono text-[10px] text-[#94A3B8]">
          seq {node.sequence}
        </span>
        <svg width="40" height="12" viewBox="0 0 40 12" aria-hidden="true">
          <path d="M0 6 H32" stroke="#475569" strokeWidth="1.5" fill="none" />
          <path d="M32 2 L40 6 L32 10 Z" fill="#475569" />
        </svg>
      </div>

      {/* Frame node: click toggles corruption (spec); selecting for inspection
          is a separate affordance (the small index badge) so the two
          interactions -- corrupt vs inspect -- don't collide on one click. */}
      <button
        type="button"
        onClick={onToggleCorrupt}
        className={`relative flex h-[55px] w-[130px] cursor-pointer flex-col items-center justify-center rounded-lg border px-2 text-center transition-colors duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] ${
          isSelected ? 'ring-2 ring-[#6EA8FF]' : ''
        }`}
        style={{ borderColor, backgroundColor: bg }}
        title="Click to toggle voltage bit-0 corruption"
      >
        <span
          role="button"
          tabIndex={0}
          onClick={(e) => {
            e.stopPropagation();
            onClickNode();
          }}
          onKeyDown={(e) => {
            if (e.key === 'Enter' || e.key === ' ') {
              e.stopPropagation();
              onClickNode();
            }
          }}
          className="cursor-pointer font-sans text-[11px] text-[#94A3B8] underline decoration-dotted underline-offset-2 hover:text-[#F8FAFC]"
          title="Inspect this frame"
        >
          Frame {node.index + 1}
        </span>
        <span className="font-mono text-sm text-[#F8FAFC]">{formatHex(node.crcField)}</span>
        {node.valid ? (
          node.sequenceOk ? (
            <Check size={14} color="#22C55E" aria-label="valid" />
          ) : (
            <X size={14} color="#F2B134" aria-label="sequence gap or replay" />
          )
        ) : (
          <X size={14} color="#FF5A5F" aria-label="invalid" />
        )}
        {node.corrupted && (
          <svg
            className="pointer-events-none absolute inset-0"
            width="130"
            height="55"
            viewBox="0 0 130 55"
            aria-hidden="true"
          >
            <line x1="6" y1="49" x2="124" y2="6" stroke="#FF5A5F" strokeWidth="2" />
          </svg>
        )}
      </button>
    </div>
  );
}

export default CRCChainViz;
