// Charger FSM, laid out as a left-to-right pipeline (normal operation) above
// a "latched" row (FAULT, METER_TIMEOUT). The current state is filled and the
// transition that just happened is highlighted.

import { ChargerState, STATE_COLORS } from '../../data/constants';
import { STATE_LABEL } from './stationStory';

const { IDLE, CONNECTED, CHARGING, GRID_HOLD, FAULT, METER_TIMEOUT } = ChargerState;

const W = 764;
const H = 250;
const NW = 118;
const NH = 42;

const NODES: Record<ChargerState, { x: number; y: number }> = {
  [IDLE]: { x: 8, y: 54 },
  [CONNECTED]: { x: 218, y: 54 },
  [CHARGING]: { x: 428, y: 54 },
  [GRID_HOLD]: { x: 638, y: 54 },
  [FAULT]: { x: 343, y: 176 },
  [METER_TIMEOUT]: { x: 553, y: 176 },
};

type EdgeId = 'i-c' | 'c-ch' | 'ch-gh' | 'gh-ch' | 'ch-c' | 'c-i' | 'toF' | 'toT' | 'release';

const cx = (s: ChargerState) => NODES[s].x + NW / 2;
const top = (s: ChargerState) => NODES[s].y;
const bot = (s: ChargerState) => NODES[s].y + NH;
const mid = (s: ChargerState) => NODES[s].y + NH / 2;
const left = (s: ChargerState) => NODES[s].x;
const right = (s: ChargerState) => NODES[s].x + NW;

const EDGES: { id: EdgeId; d: string; label: string; lx: number; ly: number; dashed?: boolean }[] = [
  { id: 'i-c', d: `M${right(IDLE)},${mid(IDLE)} H${left(CONNECTED) - 4}`, label: 'plug in', lx: (right(IDLE) + left(CONNECTED)) / 2, ly: mid(IDLE) - 8 },
  { id: 'c-ch', d: `M${right(CONNECTED)},${mid(CONNECTED) - 8} H${left(CHARGING) - 4}`, label: 'CP C + healthy', lx: (right(CONNECTED) + left(CHARGING)) / 2, ly: mid(CONNECTED) - 15 },
  { id: 'ch-c', d: `M${left(CHARGING)},${mid(CHARGING) + 8} H${right(CONNECTED) + 4}`, label: 'CP B / D', lx: (right(CONNECTED) + left(CHARGING)) / 2, ly: mid(CHARGING) + 23 },
  { id: 'ch-gh', d: `M${right(CHARGING)},${mid(CHARGING) - 8} H${left(GRID_HOLD) - 4}`, label: 'grid dip', lx: (right(CHARGING) + left(GRID_HOLD)) / 2, ly: mid(CHARGING) - 15 },
  { id: 'gh-ch', d: `M${left(GRID_HOLD)},${mid(GRID_HOLD) + 8} H${right(CHARGING) + 4}`, label: 'restart slot', lx: (right(CHARGING) + left(GRID_HOLD)) / 2, ly: mid(GRID_HOLD) + 23 },
  { id: 'c-i', d: `M${cx(CONNECTED)},${top(CONNECTED)} C${cx(CONNECTED)},14 ${cx(IDLE)},14 ${cx(IDLE)},${top(IDLE) - 4}`, label: 'unplug', lx: (cx(CONNECTED) + cx(IDLE)) / 2, ly: 16 },
  { id: 'toF', d: `M${cx(CHARGING) - 30},${bot(CHARGING)} V${top(FAULT) - 4}`, label: '', lx: 0, ly: 0, dashed: true },
  { id: 'toT', d: `M${cx(GRID_HOLD) - 50},${bot(GRID_HOLD)} V140 H${cx(METER_TIMEOUT)} V${top(METER_TIMEOUT) - 4}`, label: '', lx: 0, ly: 0, dashed: true },
  { id: 'release', d: `M${left(FAULT)},${mid(FAULT)} H${cx(IDLE)} V${bot(IDLE) + 4}`, label: 'unplug + safety clear', lx: (left(FAULT) + cx(IDLE)) / 2 + 6, ly: mid(FAULT) - 8 },
];

function edgeFor(from: ChargerState, to: ChargerState): EdgeId | null {
  if (from === to) return null;
  if (to === FAULT) return 'toF';
  if (to === METER_TIMEOUT) return 'toT';
  if (to === IDLE) return from === FAULT || from === METER_TIMEOUT ? 'release' : 'c-i';
  if (from === IDLE && to === CONNECTED) return 'i-c';
  if (from === CONNECTED && to === CHARGING) return 'c-ch';
  if (to === GRID_HOLD) return 'ch-gh';
  if (from === GRID_HOLD && to === CHARGING) return 'gh-ch';
  if (to === CONNECTED) return 'ch-c';
  return null;
}

interface StateIndicatorProps {
  currentState: ChargerState;
  previousState?: ChargerState;
}

export default function StateIndicator({ currentState, previousState }: StateIndicatorProps) {
  const active = previousState !== undefined ? edgeFor(previousState, currentState) : null;
  const activeColor = STATE_COLORS[currentState];

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label={`Charger state machine, currently ${STATE_LABEL[currentState]}`}>
      <defs>
        <marker id="fsm-arrow" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
          <path d="M0,0 L8,4 L0,8 Z" fill="#B9B4A8" />
        </marker>
        <marker id="fsm-arrow-active" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
          <path d="M0,0 L8,4 L0,8 Z" fill={activeColor} />
        </marker>
      </defs>

      {/* Latched zone */}
      <rect x={322} y={160} width={370} height={84} rx={14} fill="none" stroke="#CFC9BC" strokeDasharray="5 5" />
      <text x={682} y={238} textAnchor="end" fontSize={12} fill="#6E6C66">
        latched · from any active state
      </text>

      {EDGES.map((e) => {
        const on = e.id === active;
        return (
          <g key={e.id}>
            <path
              d={e.d}
              fill="none"
              stroke={on ? activeColor : '#CFC9BC'}
              strokeWidth={on ? 2.5 : 1.4}
              strokeDasharray={e.dashed && !on ? '4 4' : undefined}
              markerEnd={on ? 'url(#fsm-arrow-active)' : 'url(#fsm-arrow)'}
              style={{ transition: 'stroke 300ms, stroke-width 300ms' }}
            />
            {e.label && (
              <text x={e.lx} y={e.ly} textAnchor="middle" fontSize={12} fill={on ? activeColor : '#6E6C66'}>
                {e.label}
              </text>
            )}
          </g>
        );
      })}

      {(Object.keys(NODES) as unknown as string[]).map((k) => {
        const s = Number(k) as ChargerState;
        const n = NODES[s];
        const current = s === currentState;
        const color = STATE_COLORS[s];
        return (
          <g key={k} style={{ transition: 'opacity 300ms' }}>
            <rect
              x={n.x}
              y={n.y}
              width={NW}
              height={NH}
              rx={10}
              fill={current ? color : '#FFFFFF'}
              stroke={color}
              strokeOpacity={current ? 1 : 0.45}
              strokeWidth={1.5}
              style={current ? { filter: `drop-shadow(0 0 10px ${color}88)` } : undefined}
            />
            <text
              x={n.x + NW / 2}
              y={n.y + NH / 2}
              textAnchor="middle"
              dominantBaseline="central"
              fontSize={15}
              fontWeight={current ? 700 : 500}
              fill={current ? '#FFFFFF' : color}
              fontFamily="Manrope, system-ui, sans-serif"
            >
              {STATE_LABEL[s]}
            </text>
          </g>
        );
      })}
    </svg>
  );
}
