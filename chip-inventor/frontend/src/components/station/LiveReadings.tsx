// The numbers a judge should glance at while a scenario plays: what the chip
// is doing, what it has billed, how fresh its meter data is, and which
// output pins it is driving.

import { METER_TIMEOUT_MS, STATE_COLORS } from '../../data/constants';
import { STATE_LABEL } from './stationStory';
import type { PlayStep } from './stationStory';

const PINS = [
  { bit: 4, name: 'P4', label: 'Contactor', color: '#3CCF5A' },
  { bit: 5, name: 'P5', label: 'Cable lock', color: '#6EA8FF' },
  { bit: 6, name: 'P6', label: 'Grid hold', color: '#F2B134' },
  { bit: 7, name: 'P7', label: 'Fault', color: '#FF5A5F' },
];

function Tile({ label, children, hint }: { label: string; children: React.ReactNode; hint?: string }) {
  return (
    <div className="flex min-w-0 flex-col justify-between gap-2 rounded-xl border border-[var(--color-line)] bg-[var(--color-panel)] px-4 py-3">
      <div className="text-xs font-medium text-[var(--color-mute)]">{label}</div>
      <div className="min-w-0">{children}</div>
      {hint && <div className="text-xs text-[var(--color-mute)]">{hint}</div>}
    </div>
  );
}

export default function LiveReadings({ step }: { step: PlayStep }) {
  const stateColor = STATE_COLORS[step.stateAfter];
  // Energy accumulates raw V (0.1 V) x I (0.1 A) samples, i.e. 0.01 W each.
  const powerSumW = step.energy / 100;
  const age = Math.min(step.ageMs, METER_TIMEOUT_MS);
  const agePct = (age / METER_TIMEOUT_MS) * 100;
  const ageColor = agePct >= 100 ? '#FF5A5F' : agePct > 60 ? '#F2B134' : '#3CCF5A';

  return (
    <div className="grid grid-cols-2 gap-3 lg:grid-cols-5">
      <Tile label="Charger state">
        <div className="flex items-center gap-2">
          <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ backgroundColor: stateColor, boxShadow: `0 0 10px ${stateColor}` }} />
          <span className="truncate font-display text-xl font-bold" style={{ color: stateColor }}>
            {STATE_LABEL[step.stateAfter]}
          </span>
        </div>
      </Tile>
      <Tile label="Billed power (Σ V×I)" hint="sum over verified frames">
        <div className="tabular font-display text-xl font-bold text-[var(--color-ink)]">
          {powerSumW.toLocaleString(undefined, { maximumFractionDigits: 2 })} <span className="text-sm font-medium text-[var(--color-mute)]">W</span>
        </div>
      </Tile>
      <Tile label="Frames billed" hint="saturates at 255">
        <div className="tabular font-display text-xl font-bold text-[var(--color-ink)]">{step.frames}</div>
      </Tile>
      <Tile label="Meter watchdog" hint={`trips at ${METER_TIMEOUT_MS} ms`}>
        <div className="flex items-center gap-3">
          <div className="tabular w-20 shrink-0 font-display text-xl font-bold text-[var(--color-ink)]">
            {age}
            <span className="text-sm font-medium text-[var(--color-mute)]"> ms</span>
          </div>
          <div
            className="h-1.5 flex-1 overflow-hidden rounded-full bg-white/10"
            role="progressbar"
            aria-label="Time since last valid meter frame"
            aria-valuemin={0}
            aria-valuemax={METER_TIMEOUT_MS}
            aria-valuenow={age}
          >
            <div className="h-full rounded-full transition-[width] duration-500" style={{ width: `${agePct}%`, backgroundColor: ageColor }} />
          </div>
        </div>
      </Tile>
      <div className="col-span-2 lg:col-span-1">
        <Tile label="Output pins (DATAOUT)" hint={`0x${step.pinsOut.toString(16).padStart(2, '0').toUpperCase()}${step.pinsChecked ? ' · checked by emulator' : ''}`}>
          <ul className="grid grid-cols-2 gap-x-3 gap-y-1.5">
            {PINS.map((p) => {
              const on = (step.pinsOut & (1 << p.bit)) !== 0;
              return (
                <li key={p.bit} className="flex items-center gap-2 text-xs">
                  <span
                    className="h-2.5 w-2.5 shrink-0 rounded-full transition-colors duration-300"
                    style={{ backgroundColor: on ? p.color : 'transparent', boxShadow: on ? `0 0 8px ${p.color}` : `inset 0 0 0 1.5px #475569` }}
                    aria-hidden="true"
                  />
                  <span className={on ? 'text-[var(--color-ink)]' : 'text-[var(--color-mute)]'}>
                    <span className="font-mono">{p.name}</span> {p.label}
                    <span className="sr-only">{on ? ' on' : ' off'}</span>
                  </span>
                </li>
              );
            })}
          </ul>
        </Tile>
      </div>
    </div>
  );
}
