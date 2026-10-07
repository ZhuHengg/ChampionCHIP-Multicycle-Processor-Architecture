// Phase 4: byte-level view of a single meter frame.
//
// Frame layout (data/meter.ts Meter.frame): bytes[0:2]=voltage (u16 LE,
// scale /10 -> V, see scenarios.ts nominal() using 2300 for 230.0V),
// bytes[2:4]=current (u16 LE, scale /10 -> A, 160 -> 16.0A),
// bytes[4:6]=frequency (u16 LE, scale /100 -> Hz, 5000 -> 50.00Hz),
// bytes[6:8]=CRC-16 (u16 LE, bytesToU16LE, charger.ts `bytesToU16LE(frame, 6)`).

import { Check, X } from 'lucide-react';
import { crc16 } from '../../data/crc';
import { bytesToU16LE } from '../../data/binutil';

interface FrameInspectorProps {
  frame: Uint8Array;
  seed: number;
  index: number;
  onFlipByte?: (byteIndex: number) => void;
}

function formatHex(value: number, width = 4): string {
  return `0x${value.toString(16).toUpperCase().padStart(width, '0')}`;
}

const FIELD_BYTES: Array<{ label: string; range: [number, number] }> = [
  { label: 'Voltage', range: [0, 2] },
  { label: 'Current', range: [2, 4] },
  { label: 'Frequency', range: [4, 6] },
  { label: 'CRC', range: [6, 8] },
];

function byteFieldLabel(byteIndex: number): string {
  const field = FIELD_BYTES.find(({ range }) => byteIndex >= range[0] && byteIndex < range[1]);
  return field ? field.label : '';
}

function FrameInspector({ frame, seed, index, onFlipByte }: FrameInspectorProps) {
  const crcField = bytesToU16LE(frame, 6);
  const expectedCrc = crc16(frame.subarray(0, 6), seed);
  const valid = expectedCrc === crcField;

  const voltageRaw = bytesToU16LE(frame, 0);
  const currentRaw = bytesToU16LE(frame, 2);
  const frequencyRaw = bytesToU16LE(frame, 4);

  return (
    <div>
      <h4 className="mb-2 font-mono text-sm font-medium text-[#F8FAFC]">
        Frame {index + 1} — byte inspector
      </h4>

      {/* Byte boxes */}
      <div className="mb-4 flex flex-wrap gap-1.5">
        {Array.from(frame).map((byte, i) => {
          const isCorruptCandidate = i === 0;
          return (
            <button
              key={i}
              type="button"
              onClick={() => onFlipByte?.(i)}
              disabled={!onFlipByte}
              title={`byte[${i}] (${byteFieldLabel(i)})${isCorruptCandidate ? ' — click to flip bit 0' : ''}`}
              className={`flex h-8 w-8 cursor-pointer items-center justify-center rounded font-mono text-sm transition-colors duration-150 bg-[#272F42] hover:bg-[#334155] disabled:cursor-default ${
                isCorruptCandidate ? 'ring-1 ring-[#475569]' : ''
              }`}
            >
              {byte.toString(16).toUpperCase().padStart(2, '0')}
            </button>
          );
        })}
      </div>

      {/* Decoded fields */}
      <dl className="mb-3 grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm sm:grid-cols-4">
        <div>
          <dt className="text-xs text-[#94A3B8]">Voltage</dt>
          <dd className="font-mono text-[#F8FAFC]">
            {voltageRaw} → {(voltageRaw / 10).toFixed(1)} V
          </dd>
        </div>
        <div>
          <dt className="text-xs text-[#94A3B8]">Current</dt>
          <dd className="font-mono text-[#F8FAFC]">
            {currentRaw} → {(currentRaw / 10).toFixed(1)} A
          </dd>
        </div>
        <div>
          <dt className="text-xs text-[#94A3B8]">Frequency</dt>
          <dd className="font-mono text-[#F8FAFC]">
            {frequencyRaw} → {(frequencyRaw / 100).toFixed(2)} Hz
          </dd>
        </div>
        <div>
          <dt className="text-xs text-[#94A3B8]">CRC</dt>
          <dd className="font-mono text-[#F8FAFC]">{formatHex(crcField)}</dd>
        </div>
      </dl>

      {/* Seed / expected / verdict */}
      <div className="flex flex-wrap items-center gap-3 text-xs">
        <span className="text-[#94A3B8]">
          Seed <span className="font-mono text-[#F8FAFC]">{formatHex(seed)}</span>
        </span>
        <span className="text-[#94A3B8]">
          Expected <span className="font-mono text-[#F8FAFC]">{formatHex(expectedCrc)}</span>
        </span>
        {valid ? (
          <span className="flex items-center gap-1 rounded bg-[#22C55E]/10 px-2 py-1 font-medium text-[#22C55E]">
            <Check size={14} aria-hidden="true" /> match
          </span>
        ) : (
          <span className="flex items-center gap-1 rounded bg-[#FF5A5F]/10 px-2 py-1 font-medium text-[#FF5A5F]">
            <X size={14} aria-hidden="true" /> mismatch
          </span>
        )}
      </div>
    </div>
  );
}

export default FrameInspector;
