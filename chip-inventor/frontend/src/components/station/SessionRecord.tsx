// Phase 4: 8-byte session record display.
//
// Layout per data/charger.ts recordBytes(): bytes[0:4]=energy (u32 LE),
// byte[4]=status (state | flags), byte[5]=frames count, bytes[6:8]=CRC-16
// over bytes[0:6] (u16 LE). Status flag bits from data/constants.ts:
// F_ESTOP=0x08, F_CP_ERROR=0x10, F_OVERCURRENT=0x20, F_CRC_LOST=0x40,
// F_GRID_HOLD=0x80.

import { Check, X, Square, CheckSquare } from 'lucide-react';
import { crc16 } from '../../data/crc';
import { bytesToU16LE, bytesToU32LE } from '../../data/binutil';
import {
  F_CP_ERROR,
  F_CRC_LOST,
  F_ESTOP,
  F_GRID_HOLD,
  F_OVERCURRENT,
} from '../../data/constants';

interface SessionRecordProps {
  record: Uint8Array;
}

function formatHex(value: number, width = 4): string {
  return `0x${value.toString(16).toUpperCase().padStart(width, '0')}`;
}

const FLAGS: Array<{ bit: number; label: string }> = [
  { bit: F_ESTOP, label: 'E-Stop' },
  { bit: F_CP_ERROR, label: 'CP Error' },
  { bit: F_OVERCURRENT, label: 'Over-current' },
  { bit: F_CRC_LOST, label: 'CRC Lost' },
  { bit: F_GRID_HOLD, label: 'Grid Hold' },
];

function byteFieldLabel(byteIndex: number): string {
  if (byteIndex < 4) return 'Energy';
  if (byteIndex === 4) return 'Status';
  if (byteIndex === 5) return 'Frames';
  return 'CRC';
}

function SessionRecord({ record }: SessionRecordProps) {
  const energy = bytesToU32LE(record, 0);
  const status = record[4] ?? 0;
  const frames = record[5] ?? 0;
  const crcField = bytesToU16LE(record, 6);
  const expectedCrc = crc16(record.subarray(0, 6));
  const valid = expectedCrc === crcField;

  return (
    <div className="rounded-xl border border-[#ECE8DF] bg-[var(--color-panel-2)] p-4">
      <h3 className="mb-3 font-mono text-sm font-medium text-[#1E1E1E]">Session Record</h3>

      {/* Byte boxes */}
      <div className="mb-4 flex flex-wrap gap-1.5">
        {Array.from(record).map((byte, i) => (
          <div
            key={i}
            title={`byte[${i}] (${byteFieldLabel(i)})`}
            className="flex h-8 w-8 items-center justify-center rounded bg-[#ECE8DF] font-mono text-sm text-[#1E1E1E]"
          >
            {byte.toString(16).toUpperCase().padStart(2, '0')}
          </div>
        ))}
      </div>

      {/* Decoded fields */}
      <dl className="mb-4 grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm sm:grid-cols-4">
        <div>
          <dt className="text-xs text-[#6E6C66]">Energy</dt>
          <dd className="font-mono text-[#1E1E1E]">{energy}</dd>
        </div>
        <div>
          <dt className="text-xs text-[#6E6C66]">Status</dt>
          <dd className="font-mono text-[#1E1E1E]">{formatHex(status, 2)}</dd>
        </div>
        <div>
          <dt className="text-xs text-[#6E6C66]">Frames</dt>
          <dd className="font-mono text-[#1E1E1E]">{frames}</dd>
        </div>
        <div>
          <dt className="text-xs text-[#6E6C66]">CRC-16</dt>
          <dd className="font-mono text-[#1E1E1E]">{formatHex(crcField)}</dd>
        </div>
      </dl>

      {/* Status flags */}
      <div className="mb-4 flex flex-wrap gap-3">
        {FLAGS.map(({ bit, label }) => {
          const on = (status & bit) !== 0;
          return (
            <div key={bit} className="flex items-center gap-1.5 text-xs text-[#6E6C66]">
              {on ? (
                <CheckSquare size={14} color="#D99A06" aria-hidden="true" />
              ) : (
                <Square size={14} color="#B9B4A8" aria-hidden="true" />
              )}
              <span className={on ? 'text-[#1E1E1E]' : ''}>{label}</span>
            </div>
          );
        })}
      </div>

      {/* Verdict */}
      {valid ? (
        <div className="flex items-center gap-2 rounded-lg border border-[#2E9E48]/30 bg-[#2E9E48]/10 px-3 py-2 text-sm font-medium text-[#2E9E48]">
          <Check size={16} aria-hidden="true" />
          CRC-16 verified
        </div>
      ) : (
        <div className="flex items-center gap-2 rounded-lg border border-[#E0484D]/30 bg-[#E0484D]/10 px-3 py-2 text-sm font-medium text-[#E0484D]">
          <X size={16} aria-hidden="true" />
          CRC-16 mismatch
        </div>
      )}
    </div>
  );
}

export default SessionRecord;
