// Phase 4: interactive CRC chain visualization across meter frames.
//
// Byte layout per data/meter.ts Meter.frame(): [v_lo, v_hi, i_lo, i_hi,
// f_lo, f_hi, crc_lo, crc_hi] -- i.e. bytes[0:6] are the payload and
// bytes[6:8] are the frame's own CRC-16, little-endian (bytesToU16LE),
// NOT big-endian -- confirmed against data/binutil.ts bytesToU16LE and
// data/charger.ts Charger._onFrame (`bytesToU16LE(frame, 6)`). Each
// frame's CRC is seeded by the previous frame's CRC value (chain seed
// starts at 0xFFFF), matching Meter.chain / Charger.seed.
//
// This component recomputes the chain client-side from `original`/
// `current` bytes so a user can flip byte 0 bit 0 on any frame and watch
// validity cascade downstream, without touching the Charger model.

import { useMemo, useState } from 'react';
import { Check, X, RotateCcw } from 'lucide-react';
import { crc16 } from '../../data/crc';
import { bytesToU16LE } from '../../data/binutil';

export interface CRCChainFrame {
  original: Uint8Array;
  current: Uint8Array;
}

interface ChainNode {
  index: number;
  bytes: Uint8Array;
  seedIn: number;
  crcField: number;
  expectedCrc: number;
  valid: boolean;
  corrupted: boolean;
}

interface CRCChainVizProps {
  frames: CRCChainFrame[];
  onCorrupt?: (index: number) => void;
  selectedIndex?: number | null;
  onSelect?: (index: number) => void;
}

const SEED = 0xFFFF;

/** Flip bit 0 of byte 0 -- mirrors data/meter.ts corrupt(). */
function flipByte0Bit0(bytes: Uint8Array): Uint8Array {
  const out = new Uint8Array(bytes);
  out[0] = out[0] ^ 1;
  return out;
}

function formatHex(value: number): string {
  return `0x${value.toString(16).toUpperCase().padStart(4, '0')}`;
}

function CRCChainViz({ frames, onCorrupt, selectedIndex, onSelect }: CRCChainVizProps) {
  const [corrupted, setCorrupted] = useState<Set<number>>(new Set());

  const nodes = useMemo<ChainNode[]>(() => {
    let seed = SEED;
    return frames.map((f, index) => {
      const bytes = corrupted.has(index) ? flipByte0Bit0(f.current) : f.current;
      const crcField = bytesToU16LE(bytes, 6);
      const expectedCrc = crc16(bytes.subarray(0, 6), seed);
      const valid = expectedCrc === crcField;
      const seedIn = seed;
      seed = crcField; // chain always advances, valid or not (charger.ts rule 1)
      return { index, bytes, seedIn, crcField, expectedCrc, valid, corrupted: corrupted.has(index) };
    });
  }, [frames, corrupted]);

  const toggleCorrupt = (index: number) => {
    setCorrupted((prev) => {
      const next = new Set(prev);
      if (next.has(index)) {
        next.delete(index);
      } else {
        next.add(index);
      }
      return next;
    });
    onCorrupt?.(index);
  };

  const resetAll = () => setCorrupted(new Set());

  if (frames.length === 0) {
    return (
      <div className="text-sm text-[#94A3B8]">No meter frames in this scenario yet.</div>
    );
  }

  return (
    <div>
      <div className="mb-3 flex items-center justify-between">
        <h3 className="font-mono text-sm font-medium text-[#F8FAFC]">CRC Chain</h3>
        <button
          type="button"
          onClick={resetAll}
          disabled={corrupted.size === 0}
          className="flex cursor-pointer items-center gap-1.5 rounded-lg border border-[var(--color-border)]/40 bg-[var(--color-card)]/70 px-3 py-1 text-xs font-medium text-[var(--color-foreground)] transition-colors duration-150 hover:border-[var(--color-accent)] disabled:cursor-not-allowed disabled:opacity-40"
        >
          <RotateCcw size={14} aria-hidden="true" />
          Reset All
        </button>
      </div>

      <div className="overflow-x-auto pb-2">
        <div className="flex items-center" style={{ minWidth: 'max-content' }}>
          {/* Seed node */}
          <div
            className="flex h-[55px] w-[130px] shrink-0 flex-col items-center justify-center rounded-lg border px-2 text-center"
            style={{ borderColor: 'rgba(255,255,255,0.1)', backgroundColor: '#1B2336' }}
          >
            <span className="font-sans text-[11px] text-[#94A3B8]">Seed</span>
            <span className="font-mono text-sm text-[#F8FAFC]">0xFFFF</span>
          </div>

          {nodes.map((node) => (
            <ChainEdgeAndNode
              key={node.index}
              node={node}
              isSelected={selectedIndex === node.index}
              onClickNode={() => onSelect?.(node.index)}
              onToggleCorrupt={() => toggleCorrupt(node.index)}
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
  const bg = node.valid ? '#1B2336' : 'rgba(255,90,95,0.1)';

  return (
    <div className="flex shrink-0 items-center">
      {/* Arrow with seed label */}
      <div className="flex w-12 flex-col items-center justify-center">
        <span className="mb-0.5 whitespace-nowrap font-mono text-[10px] text-[#94A3B8]">
          {formatHex(node.seedIn)}
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
        title="Click to toggle byte-0 bit-0 corruption"
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
          <Check size={14} color="#22C55E" aria-label="valid" />
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
