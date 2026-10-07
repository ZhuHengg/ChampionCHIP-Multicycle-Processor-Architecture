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
    <div className="rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
      <h3 className="mb-3 font-mono text-sm font-medium text-[#F8FAFC]">Session Record</h3>

      {/* Byte boxes */}
      <div className="mb-4 flex flex-wrap gap-1.5">
        {Array.from(record).map((byte, i) => (
          <div
            key={i}
            title={`byte[${i}] (${byteFieldLabel(i)})`}
            className="flex h-8 w-8 items-center justify-center rounded bg-[#272F42] font-mono text-sm text-[#F8FAFC]"
          >
            {byte.toString(16).toUpperCase().padStart(2, '0')}
          </div>
        ))}
      </div>

      {/* Decoded fields */}
      <dl className="mb-4 grid grid-cols-2 gap-x-4 gap-y-1.5 text-sm sm:grid-cols-4">
        <div>
          <dt className="text-xs text-[#94A3B8]">Energy</dt>
          <dd className="font-mono text-[#F8FAFC]">{energy}</dd>
        </div>
        <div>
          <dt className="text-xs text-[#94A3B8]">Status</dt>
          <dd className="font-mono text-[#F8FAFC]">{formatHex(status, 2)}</dd>
        </div>
        <div>
          <dt className="text-xs text-[#94A3B8]">Frames</dt>
          <dd className="font-mono text-[#F8FAFC]">{frames}</dd>
        </div>
        <div>
          <dt className="text-xs text-[#94A3B8]">CRC-16</dt>
          <dd className="font-mono text-[#F8FAFC]">{formatHex(crcField)}</dd>
        </div>
      </dl>

      {/* Status flags */}
      <div className="mb-4 flex flex-wrap gap-3">
        {FLAGS.map(({ bit, label }) => {
          const on = (status & bit) !== 0;
          return (
            <div key={bit} className="flex items-center gap-1.5 text-xs text-[#94A3B8]">
              {on ? (
                <CheckSquare size={14} color="#F2B134" aria-hidden="true" />
              ) : (
                <Square size={14} color="#475569" aria-hidden="true" />
              )}
              <span className={on ? 'text-[#F8FAFC]' : ''}>{label}</span>
            </div>
          );
        })}
      </div>

      {/* Verdict */}
      {valid ? (
        <div className="flex items-center gap-2 rounded-lg border border-[#22C55E]/30 bg-[#22C55E]/10 px-3 py-2 text-sm font-medium text-[#22C55E]">
          <Check size={16} aria-hidden="true" />
          CRC-16 verified
        </div>
      ) : (
        <div className="flex items-center gap-2 rounded-lg border border-[#FF5A5F]/30 bg-[#FF5A5F]/10 px-3 py-2 text-sm font-medium text-[#FF5A5F]">
          <X size={16} aria-hidden="true" />
          CRC-16 mismatch
        </div>
      )}
    </div>
  );
}

export default SessionRecord;
