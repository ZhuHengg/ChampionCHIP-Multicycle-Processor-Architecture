// Pin layout per spec SS7.3/7.6 STATE_OUT encoding: bits 4-7 of the output
// byte map to CONTACTOR (P4), CABLE_LOCK (P5), GRID_HOLD (P6), FAULT (P7).
// e.g. CHARGING = 0x30 (bits 4+5), GRID_HOLD = 0x60 (bits 5+6), FAULT = 0x80
// (bit 7) -- confirmed against STATE_OUT in src/data/constants.ts.

interface PinLedSpec {
  bit: number;
  label: string;
  color: string;
}

const PINS: PinLedSpec[] = [
  { bit: 0x10, label: 'P4 CONTACTOR', color: '#22C55E' },
  { bit: 0x20, label: 'P5 CABLE_LOCK', color: '#6EA8FF' },
  { bit: 0x40, label: 'P6 GRID_HOLD', color: '#F2B134' },
  { bit: 0x80, label: 'P7 FAULT', color: '#FF5A5F' },
];

interface PinLEDsProps {
  pinOutputs: number;
}

function PinLEDs({ pinOutputs }: PinLEDsProps) {
  return (
    <div className="flex flex-wrap items-center gap-4" role="list" aria-label="Output pin status">
      {PINS.map(({ bit, label, color }) => {
        const on = (pinOutputs & bit) !== 0;
        return (
          <div className="flex items-center gap-2" role="listitem" key={bit}>
            <div
              className={`h-3.5 w-3.5 rounded-full transition-all duration-300 ${
                on ? '' : 'border border-[#475569] bg-[#272F42]'
              }`}
              style={on ? { backgroundColor: color, boxShadow: `0 0 12px ${color}` } : undefined}
              aria-hidden="true"
            />
            <span className="font-mono text-xs text-[#94A3B8]">{label}</span>
          </div>
        );
      })}
    </div>
  );
}

export default PinLEDs;
