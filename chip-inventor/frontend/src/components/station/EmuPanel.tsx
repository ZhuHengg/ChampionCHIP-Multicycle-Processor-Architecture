// How ./emu drives the chip: the scenario's real emulator command line, the
// path each option takes (host -> FPGA top AXI-Lite register -> chip pins),
// and the lines the RTL printed when that command was played on it in
// simulation. Those lines come from data/emuPreview.json, written by
// testbench/app/export_emu_preview.py from tb_app.v's run logs; nothing here
// is computed by the model. Follows the station playback: the current
// step's options are highlighted and its lane lights up.

import { useEffect, useRef } from 'react';
import preview from '../../data/emuPreview.json';
import { SAFETY } from '../../data/constants';
import type { ChargerState } from '../../data/constants';
import { CP_NAME, flagNames, STATE_LABEL } from './stationStory';
import type { PlayStep } from './stationStory';

type Kind = 'd' | 'i' | 'o' | 't' | 'r';
type Lane = 'in' | 'tx' | 'rx' | 'out';

interface EmuOp {
  kind: Kind;
  n: number | null;
  value: number;
  text: string;
  /** Playback step this option belongs to; -1 = before the first step. */
  step: number;
  line: string;
}

interface EmuScenario {
  title: string;
  command: string;
  setup: string | null;
  stream: boolean;
  steps: string[];
  reset: string;
  ops: EmuOp[];
  result: string;
}

const DATA = preview as unknown as { source: string; generated: string; scenarios: Record<string, EmuScenario> };

const LANE_OF: Record<Kind, Lane> = { d: 'in', i: 'in', t: 'tx', r: 'rx', o: 'out' };
const LANE_COLOR: Record<Lane, string> = {
  in: 'var(--color-info)',
  tx: 'var(--color-ok)',
  rx: 'var(--color-warn)',
  out: 'var(--color-ink)',
};

// Register map from RVBL-Emulator/src/emu.c (IN_ADDR .. RX1_ADDR). -d writes
// the high byte of IN (pin direction), -i its low byte (pin levels).
const LANES: { id: Lane; reg: string; opts: string; pin: string; toChip: boolean }[] = [
  { id: 'in', reg: 'IN 0x04', opts: '-d -i', pin: 'P3–P0 GPIO in', toChip: true },
  { id: 'tx', reg: 'TX 0x0C', opts: '-t1 -t2 -t4', pin: 'rx_i UART in', toChip: true },
  { id: 'rx', reg: 'RX0/1 0x10/14', opts: '-r1 -r2 -r4', pin: 'tx_o UART out', toChip: false },
  { id: 'out', reg: 'OUT 0x08', opts: '-o', pin: 'P7–P4 GPIO out', toChip: false },
];

const OUT_PINS = [
  { bit: 4, name: 'P4', label: 'contactor', color: '#3CCF5A' },
  { bit: 5, name: 'P5', label: 'cable lock', color: '#8DB6FF' },
  { bit: 6, name: 'P6', label: 'grid hold', color: '#F2C230' },
  { bit: 7, name: 'P7', label: 'fault', color: '#FF6B6F' },
];

const hex = (v: number, digits: number) => '0x' + v.toString(16).toUpperCase().padStart(digits, '0');
const bin4 = (v: number) => (v & 0xf).toString(2).padStart(4, '0');

/** The bytes one -t option puts on rx_i, low byte first (emu.c). */
function txBytes(op: EmuOp): string {
  const out: string[] = [];
  for (let k = 0; k < (op.n ?? 1); k++) out.push(((op.value >>> (8 * k)) & 0xff).toString(16).toUpperCase().padStart(2, '0'));
  return out.join(' ');
}

/** One plain-English line under each RTL output line. */
function gloss(op: EmuOp, readIndex: number): string {
  switch (op.kind) {
    case 'd':
      return `Pin direction ${hex(op.value, 2)}: P7–P4 are the chip's outputs, P3–P0 its inputs.`;
    case 'i': {
      const estop = op.value & SAFETY ? ', emergency stop pressed' : '';
      return `P3–P0 = ${bin4(op.value)}: pilot ${CP_NAME[op.value & 7]}${estop}.`;
    }
    case 't':
      return `The FPGA top sends ${txBytes(op)} into the chip's rx_i, low byte first, at 115,200 bps.`;
    case 'o': {
      const on = OUT_PINS.filter((p) => op.value & (1 << p.bit)).map((p) => p.label);
      return `P7–P4 = ${bin4(op.value >> 4)}: ${on.length ? on.join(' + ') : 'all off'}. Matches the expected value.`;
    }
    case 'r': {
      if (readIndex === 0) return `Record bytes 0–3: ENERGY = ${op.value.toLocaleString()} (Σ V×I over billed frames).`;
      if (readIndex === 1) {
        const status = op.value & 0xff;
        const label = STATE_LABEL[(status & 7) as ChargerState] ?? `code ${status & 7}`;
        const flags = flagNames(status & 0xf8);
        return `Bytes 4–5: ended in ${label}${flags.length ? ` (${flags.join(', ')})` : ''}, ${op.value >> 8} frames billed.`;
      }
      return `Bytes 6–7: CRC-16 ${hex(op.value, 4)} seals the record, computed on the chip.`;
    }
  }
}

function Diagram({ active, pinsOut }: { active: Partial<Record<Lane, string>>; pinsOut: number }) {
  const laneY = [104, 144, 184, 224];
  const box = { stroke: 'var(--color-line-strong)', fill: '#FFFFFF' };
  const arrow = (x1: number, x2: number, y: number, toChip: boolean, color: string, on: boolean) => {
    const tip = toChip ? x2 : x1;
    const back = toChip ? -8 : 8;
    return (
      <g style={{ stroke: color, fill: color }}>
        <line x1={x1} y1={y} x2={x2} y2={y} strokeWidth={on ? 2.5 : 1.5} />
        <polygon points={`${tip},${y} ${tip + back},${y - 4.5} ${tip + back},${y + 4.5}`} strokeWidth={0} />
      </g>
    );
  };

  return (
    <svg viewBox="0 0 760 280" className="w-full min-w-[600px]" role="img" aria-label="./emu writes and reads FPGA top registers, each wired to a group of the chip's pins">
      <text x={195} y={30} textAnchor="middle" fontSize={11} style={{ fill: 'var(--color-mute)' }}>
        PCIe · AXI-Lite
      </text>
      <text x={535} y={30} textAnchor="middle" fontSize={11} style={{ fill: 'var(--color-mute)' }}>
        chip pins
      </text>

      {/* ./emu */}
      <rect x={1} y={40} width={138} height={228} rx={14} style={box} />
      <text x={70} y={68} textAnchor="middle" fontSize={15} fontWeight={600} className="font-mono" style={{ fill: 'var(--color-ink)' }}>
        ./emu
      </text>
      <text x={70} y={86} textAnchor="middle" fontSize={11} style={{ fill: 'var(--color-mute)' }}>
        organisers' host tool
      </text>
      <text x={70} y={254} textAnchor="middle" fontSize={11} style={{ fill: 'var(--color-mute)' }}>
        AWS F2 host
      </text>

      {/* FPGA top */}
      <rect x={250} y={40} width={230} height={228} rx={14} style={box} />
      <text x={365} y={68} textAnchor="middle" fontSize={15} fontWeight={600} style={{ fill: 'var(--color-ink)' }}>
        FPGA top
      </text>
      <text x={365} y={86} textAnchor="middle" fontSize={11} style={{ fill: 'var(--color-mute)' }}>
        AXI-Lite registers
      </text>

      {/* RVBL-2 */}
      <rect x={590} y={40} width={168} height={228} rx={14} style={{ stroke: 'var(--color-ok)', fill: '#F3FBF4', strokeWidth: 1.5 }} />
      <text x={674} y={68} textAnchor="middle" fontSize={15} fontWeight={600} style={{ fill: 'var(--color-ink)' }}>
        RVBL-2 chip
      </text>
      <text x={674} y={86} textAnchor="middle" fontSize={11} style={{ fill: 'var(--color-mute)' }}>
        EV charger firmware
      </text>

      {LANES.map((lane, k) => {
        const y = laneY[k];
        const value = active[lane.id];
        const on = value !== undefined;
        const color = on ? LANE_COLOR[lane.id] : 'var(--color-line-strong)';
        const text = on ? LANE_COLOR[lane.id] : 'var(--color-ink-2)';
        return (
          <g key={lane.id}>
            {arrow(142, 246, y, lane.toChip, color, on)}
            {arrow(482, 586, y, lane.toChip, color, on)}
            {on && (
              <>
                <text x={194} y={y - 8} textAnchor="middle" fontSize={11} fontWeight={600} className="font-mono" style={{ fill: color }}>
                  {value}
                </text>
                <text x={534} y={y - 8} textAnchor="middle" fontSize={11} fontWeight={600} className="font-mono" style={{ fill: color }}>
                  {value}
                </text>
              </>
            )}
            <text x={264} y={y + 4} fontSize={12} fontWeight={on ? 700 : 500} className="font-mono" style={{ fill: text }}>
              {lane.reg}
            </text>
            <text x={466} y={y + 4} textAnchor="end" fontSize={11} className="font-mono" style={{ fill: 'var(--color-mute)' }}>
              {lane.opts}
            </text>
            <text x={604} y={y + 4} fontSize={12} fontWeight={on ? 700 : 500} className="font-mono" style={{ fill: text }}>
              {lane.pin}
            </text>
          </g>
        );
      })}

      {/* Output pins as the chip last drove them */}
      {OUT_PINS.map((p, k) => {
        const lit = (pinsOut & (1 << p.bit)) !== 0;
        const x = 612 + k * 38;
        return (
          <g key={p.bit}>
            <circle cx={x} cy={248} r={5} style={{ fill: lit ? p.color : 'transparent', stroke: lit ? p.color : 'var(--color-line-strong)', strokeWidth: 1.5 }} />
            <text x={x + 9} y={252} fontSize={10} className="font-mono" style={{ fill: 'var(--color-mute)' }}>
              {p.name}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

interface EmuPanelProps {
  scenarioId: string;
  steps: PlayStep[];
  index: number;
  onJump: (index: number) => void;
  className?: string;
}

export default function EmuPanel({ scenarioId, steps, index, onJump, className = '' }: EmuPanelProps) {
  const emu = DATA.scenarios[scenarioId];
  const logRef = useRef<HTMLDivElement>(null);

  // Follow the newest line, scrolling inside the log only.
  useEffect(() => {
    const el = logRef.current;
    if (el) el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' });
  }, [index, scenarioId]);

  // The export tags options with playback steps; refuse to show them against
  // a playback whose steps no longer line up.
  const aligned = !!emu && emu.steps.length === steps.length && emu.steps.every((k, i) => k === steps[i].kind);

  const shown = aligned ? emu.ops.filter((op) => op.step <= index) : [];
  const current = shown.filter((op) => op.step === index);
  const active: Partial<Record<Lane, string>> = {};
  for (const op of current) active[LANE_OF[op.kind]] = op.kind === 't' ? txBytes(op) : hex(op.value, (op.n ?? 1) * 2);
  const lastOut = [...shown].reverse().find((op) => op.kind === 'o');
  const checks = current.filter((op) => op.kind === 'o' || op.kind === 'r').length;
  let reads = 0;
  const readIndex = new Map<EmuOp, number>();
  if (aligned) for (const op of emu.ops) if (op.kind === 'r') readIndex.set(op, reads++);

  return (
    <section aria-labelledby="emu-label" className={`card min-w-0 p-6 ${className}`}>
      <p className="text-xs font-medium tracking-[0.14em] text-[var(--color-mute)] uppercase">Application logic · the emulator link</p>
      <h2 id="emu-label" className="mt-2 font-display text-2xl font-medium text-[var(--color-ink)] md:text-3xl">
        How <span className="font-mono">./emu</span> drives the chip
      </h2>


      <details className="mt-2 text-sm text-[var(--color-ink-2)]">
        <summary className="cursor-pointer">How the emulator connection works</summary>
      <p className="mt-3 max-w-3xl leading-relaxed text-[var(--color-ink-2)]">
        The organisers' emulator talks to the FPGA top over PCIe and AXI-Lite. Each option writes or reads one register, and each register is one group
        of the chip's pins. One command line is one charging session. The log below shows <strong className="text-[var(--color-ink)]">the chip's own answers</strong>
        : every line printed when this exact command was played on the RTL in simulation.
      </p>
      </details>

      {!emu ? (
        <p className="mt-6 rounded-2xl border border-dashed border-[var(--color-line-strong)] p-5 text-sm text-[var(--color-mute)]">
          {scenarioId} has no <span className="font-mono">./emu</span> command line. It waits 4 seconds with no meter data, and <span className="font-mono">./emu</span> has
          no option that waits. The watchdog is checked on the RTL by <span className="font-mono">testbench/app/run_watchdog_tests.py</span> instead.
        </p>
      ) : !aligned ? (
        <p className="mt-6 rounded-2xl border border-dashed border-[var(--color-bad)] p-5 text-sm text-[var(--color-bad)]">
          The emulator export for {scenarioId} no longer lines up with this scenario's steps. Re-run{' '}
          <span className="font-mono">export_emu_preview.py --run</span>.
        </p>
      ) : (
        <>
          {emu.setup && (
            <p className="mt-5 text-sm text-[var(--color-ink-2)]">
              Run first: <span className="font-mono text-[var(--color-ink)]">{emu.setup}</span>. ./emu keeps the input pins across its reset, so {scenarioId} boots with
              them already set.
            </p>
          )}
          {emu.stream && (
            <p className="mt-5 text-sm text-[var(--color-ink-2)]">
              Stress case: in this simulation the UART bytes arrive back to back, with no gap between bytes or frames.
            </p>
          )}


          <div className="mt-6 grid grid-cols-1 gap-6">
            <div>
              <div className="overflow-x-auto">
                <Diagram active={active} pinsOut={lastOut?.value ?? 0} />
              </div>
              <p className="mt-4 text-sm leading-relaxed text-[var(--color-ink-2)]" aria-live="polite">
                <span className="font-medium text-[var(--color-ink)]">
                  Step {index + 1} · {steps[index].title}
                </span>
                {current.length > 0 && (
                  <>
                    {' '}· <span className="font-mono">{current.map((op) => op.text).join(' ')}</span>
                    {checks > 0 && ` · ${checks === 1 ? 'the read' : `all ${checks} reads`} matched on the RTL`}
                  </>
                )}
              </p>
            </div>

            <div
              ref={logRef}
              className="h-[320px] overflow-y-auto rounded-2xl border border-[var(--color-line)] bg-[var(--color-panel-2)] p-4 font-mono text-[12px] leading-relaxed"
              aria-label="RTL simulation output"
            >
              <p className="text-[var(--color-ink-2)]">
                <span className="text-[var(--color-ok)]">[ok]</span> {emu.reset.replace('[ok] ', '')}
              </p>
              {shown.map((op, k) => {
                const isCurrent = op.step === index;
                return (
                  <div key={k} className={`fade-rise mt-2 ${isCurrent ? '' : 'opacity-60'}`}>
                    <p className={isCurrent ? 'font-semibold text-[var(--color-ink)]' : 'text-[var(--color-ink-2)]'}>
                      <span className="text-[var(--color-ok)]">[ok]</span> {op.line.replace('[ok] ', '')}
                    </p>
                    <p className="pl-4 font-sans text-[12.5px] text-[var(--color-mute)]">{gloss(op, readIndex.get(op) ?? 0)}</p>
                  </div>
                );
              })}
            </div>
          </div>

          {/* The command line, one button per option */}
          <div className="mt-5 rounded-2xl border border-[var(--color-line)] bg-[var(--color-panel-2)] px-4 py-3 font-mono text-[13px] leading-7">
            <span className="mr-2 text-[var(--color-ink)]">./emu</span>
            {emu.ops.map((op, k) => {
              const isCurrent = op.step === index;
              const future = op.step > index;
              return (
                <button
                  key={k}
                  type="button"
                  disabled={op.step < 0}
                  onClick={() => onJump(op.step)}
                  aria-current={isCurrent ? 'step' : undefined}
                  className={`mr-1.5 rounded-md px-1.5 whitespace-nowrap transition-[background-color,opacity] duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)] enabled:cursor-pointer ${
                    isCurrent ? 'bg-[var(--color-accent-soft)] font-semibold shadow-[inset_0_0_0_1.5px_var(--color-accent)]' : future ? 'opacity-35 enabled:hover:opacity-70' : 'enabled:hover:bg-white'
                  }`}
                  style={{ color: LANE_COLOR[LANE_OF[op.kind]] }}
                >
                  {op.text}
                </button>
              );
            })}
          </div>


          <p className="mt-5 text-xs text-[var(--color-mute)]">
            {DATA.source}, exported {DATA.generated}. All {Object.keys(DATA.scenarios).length} command lines pass. This is
            simulation: on the AWS F2 each register access takes 50 ms, here the gaps are shortened.
          </p>
        </>
      )}
    </section>
  );
}
