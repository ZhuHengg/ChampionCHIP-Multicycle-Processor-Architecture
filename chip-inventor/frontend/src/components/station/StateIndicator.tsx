import { ChargerState, STATE_COLORS, STATE_NAMES } from '../../data/constants';

interface StateIndicatorProps {
  currentState: ChargerState;
  previousState?: ChargerState;
}

interface NodeLayout {
  state: ChargerState;
  x: number;
  y: number;
}

const WIDTH = 300;
const HEIGHT = 250;
const NODE_W = 100;
const NODE_H = 36;

// Vertical flow: IDLE -> CONNECTED -> CHARGING -> {GRID_HOLD, FAULT}, with a
// return arrow from the branches back to IDLE.
const NODES: NodeLayout[] = [
  { state: ChargerState.IDLE, x: WIDTH / 2 - NODE_W / 2, y: 6 },
  { state: ChargerState.CONNECTED, x: WIDTH / 2 - NODE_W / 2, y: 76 },
  { state: ChargerState.CHARGING, x: WIDTH / 2 - NODE_W / 2, y: 146 },
  { state: ChargerState.GRID_HOLD, x: 4, y: 208 },
  { state: ChargerState.FAULT, x: WIDTH - NODE_W - 4, y: 208 },
];

function nodeCenter(n: NodeLayout) {
  return { cx: n.x + NODE_W / 2, cy: n.y + NODE_H / 2 };
}

function findNode(state: ChargerState): NodeLayout {
  return NODES.find((n) => n.state === state)!;
}

// Static edges of the FSM, drawn dim unless they match the active transition.
const EDGES: [ChargerState, ChargerState][] = [
  [ChargerState.IDLE, ChargerState.CONNECTED],
  [ChargerState.CONNECTED, ChargerState.CHARGING],
  [ChargerState.CHARGING, ChargerState.GRID_HOLD],
  [ChargerState.CHARGING, ChargerState.FAULT],
  [ChargerState.GRID_HOLD, ChargerState.FAULT],
  [ChargerState.GRID_HOLD, ChargerState.CHARGING],
  [ChargerState.FAULT, ChargerState.IDLE],
  [ChargerState.CONNECTED, ChargerState.IDLE],
];

function edgePath(from: ChargerState, to: ChargerState): string {
  const a = nodeCenter(findNode(from));
  const b = nodeCenter(findNode(to));

  // Return-to-IDLE arrows curve out to the side so they don't overlap the
  // straight-line forward edges.
  if (to === ChargerState.IDLE && from !== ChargerState.CONNECTED) {
    const side = from === ChargerState.FAULT ? WIDTH - 8 : 8;
    return `M ${a.cx},${a.cy - NODE_H / 2} C ${side},${a.cy} ${side},${b.cy} ${b.cx - (from === ChargerState.FAULT ? 30 : -30)},${b.cy}`;
  }
  return `M ${a.cx},${a.cy} L ${b.cx},${b.cy}`;
}

function StateIndicator({ currentState, previousState }: StateIndicatorProps) {
  const isActiveEdge = (from: ChargerState, to: ChargerState) =>
    previousState !== undefined && previousState === from && currentState === to;

  return (
    <svg
      viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
      width="100%"
      height={HEIGHT}
      role="img"
      aria-label={`Charger state machine, currently ${STATE_NAMES[currentState]}`}
      style={{ maxWidth: WIDTH }}
    >
      <style>
        {`
          @keyframes scp-pulse {
            0%, 100% { opacity: 0.55; }
            50% { opacity: 1; }
          }
          .scp-active-edge {
            animation: scp-pulse 1.4s ease-in-out infinite;
          }
          @media (prefers-reduced-motion: reduce) {
            .scp-active-edge { animation: none; opacity: 1; }
          }
        `}
      </style>
      <defs>
        <marker id="scp-arrow-dim" markerWidth="8" markerHeight="8" refX="6" refY="3" orient="auto">
          <path d="M0,0 L6,3 L0,6 Z" fill="#475569" />
        </marker>
        {NODES.map((n) => (
          <marker
            key={`arrow-${n.state}`}
            id={`scp-arrow-${n.state}`}
            markerWidth="8"
            markerHeight="8"
            refX="6"
            refY="3"
            orient="auto"
          >
            <path d="M0,0 L6,3 L0,6 Z" fill={STATE_COLORS[n.state]} />
          </marker>
        ))}
        <filter id="scp-glow" x="-60%" y="-60%" width="220%" height="220%">
          <feGaussianBlur stdDeviation="4" result="blur" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>

      {/* Edges */}
      {EDGES.map(([from, to]) => {
        const active = isActiveEdge(from, to);
        const key = `${from}-${to}`;
        return (
          <path
            key={key}
            d={edgePath(from, to)}
            fill="none"
            stroke={active ? STATE_COLORS[to] : '#475569'}
            strokeWidth={active ? 2 : 1}
            className={active ? 'scp-active-edge' : undefined}
            markerEnd={active ? `url(#scp-arrow-${to})` : 'url(#scp-arrow-dim)'}
          />
        );
      })}

      {/* Nodes */}
      {NODES.map((n) => {
        const isCurrent = n.state === currentState;
        const color = STATE_COLORS[n.state];
        const { cx, cy } = nodeCenter(n);
        return (
          <g
            key={n.state}
            transform={isCurrent ? `translate(${cx} ${cy}) scale(1.05) translate(${-cx} ${-cy})` : undefined}
          >
            <rect
              x={n.x}
              y={n.y}
              width={NODE_W}
              height={NODE_H}
              rx={8}
              fill={isCurrent ? color : 'transparent'}
              stroke={isCurrent ? 'none' : color}
              strokeOpacity={isCurrent ? 1 : 0.4}
              strokeWidth={1.5}
              filter={isCurrent ? 'url(#scp-glow)' : undefined}
            />
            <text
              x={cx}
              y={cy}
              textAnchor="middle"
              dominantBaseline="central"
              fontFamily="'Fira Code', monospace"
              fontSize={11}
              fill={isCurrent ? '#0F172A' : color}
              fontWeight={isCurrent ? 700 : 500}
            >
              {STATE_NAMES[n.state]}
            </text>
          </g>
        );
      })}
    </svg>
  );
}

export default StateIndicator;
