// Meter readings as three small multiples (voltage, current, frequency), each
// on its own scale with the firmware limit it is checked against. One shared
// axis would flatten 16 A next to 230 V.

import { CartesianGrid, Line, LineChart, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { F_LOW, I_MAX, V_SAG } from '../../data/constants';

export interface MeterFrame {
  v: number;
  i: number;
  f: number;
  valid: boolean;
  index: number;
}

interface Series {
  key: 'voltage' | 'current' | 'frequency';
  label: string;
  unit: string;
  color: string;
  limit: number;
  limitLabel: string;
  digits: number;
  pad: number;
}

const SERIES: Series[] = [
  { key: 'voltage', label: 'Voltage', unit: 'V', color: '#3B6FD8', limit: V_SAG / 10, limitLabel: 'sag limit', digits: 1, pad: 15 },
  { key: 'current', label: 'Current', unit: 'A', color: '#D99A06', limit: I_MAX / 10, limitLabel: 'max', digits: 1, pad: 4 },
  { key: 'frequency', label: 'Frequency', unit: 'Hz', color: '#2E9E48', limit: F_LOW / 100, limitLabel: 'low limit', digits: 2, pad: 0.3 },
];

interface Row {
  n: number;
  voltage: number | null;
  current: number | null;
  frequency: number | null;
  valid: boolean;
}

interface DotProps {
  cx?: number;
  cy?: number;
  payload?: Row;
  color: string;
}

function FrameDot({ cx, cy, payload, color }: DotProps) {
  if (cx == null || cy == null || !payload) return null;
  if (payload.valid) return <circle cx={cx} cy={cy} r={3.5} fill={color} stroke="#FFFFFF" strokeWidth={1.5} />;
  const s = 4.5;
  return (
    <g stroke="#E0484D" strokeWidth={2} aria-label="rejected frame">
      <line x1={cx - s} y1={cy - s} x2={cx + s} y2={cy + s} />
      <line x1={cx - s} y1={cy + s} x2={cx + s} y2={cy - s} />
    </g>
  );
}

function SmallChart({ data, s }: { data: Row[]; s: Series }) {
  const values = data.map((r) => r[s.key]).filter((v): v is number => v != null);
  const lo = Math.min(s.limit, ...values) - s.pad;
  const hi = Math.max(s.limit, ...values) + s.pad;
  const latest = values[values.length - 1];
  return (
    <div className="rounded-xl border border-[var(--color-line)] bg-[var(--color-panel)] p-4">
      <div className="mb-2 flex items-baseline justify-between gap-2">
        <span className="text-xs font-medium text-[var(--color-mute)]">{s.label}</span>
        <span className="tabular font-display text-lg font-bold" style={{ color: s.color }}>
          {latest != null ? latest.toFixed(s.digits) : '—'}
          <span className="ml-1 text-xs font-medium text-[var(--color-mute)]">{s.unit}</span>
        </span>
      </div>
      <div className="h-32">
        <ResponsiveContainer width="100%" height="100%">
          <LineChart data={data} margin={{ top: 6, right: 6, left: -18, bottom: 0 }}>
            <CartesianGrid stroke="#ECE8DF" vertical={false} />
            <XAxis dataKey="n" tick={{ fill: '#6E6C66', fontSize: 11 }} stroke="#ECE8DF" tickLine={false} allowDecimals={false} />
            <YAxis
              domain={[lo, hi]}
              tick={{ fill: '#6E6C66', fontSize: 11 }}
              stroke="#ECE8DF"
              tickLine={false}
              tickFormatter={(v: number) => v.toFixed(s.digits === 2 ? 1 : 0)}
              width={48}
            />
            <Tooltip
              contentStyle={{ backgroundColor: '#FFFFFF', border: '1px solid #ECE8DF', borderRadius: 8, fontSize: 12 }}
              labelStyle={{ color: '#4A4945' }}
              labelFormatter={(n) => `Frame ${n}`}
              formatter={(v) => [`${Number(v).toFixed(s.digits)} ${s.unit}`, s.label]}
            />
            <ReferenceLine
              y={s.limit}
              stroke="#E0484D"
              strokeDasharray="4 4"
              label={{ value: `${s.limitLabel} ${s.limit.toFixed(s.digits)}`, position: 'insideBottomRight', fill: '#E0484D', fontSize: 10 }}
            />
            <Line
              type="monotone"
              dataKey={s.key}
              stroke={s.color}
              strokeWidth={2}
              connectNulls
              isAnimationActive={false}
              dot={((p: Omit<DotProps, 'color'>) => <FrameDot key={`${s.key}-${p.payload?.n}`} {...p} color={s.color} />) as unknown as boolean}
            />
          </LineChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}

export default function MeterChart({ frames }: { frames: MeterFrame[] }) {
  if (frames.length === 0) {
    return (
      <div className="flex h-40 items-center justify-center rounded-xl border border-dashed border-[var(--color-line)] text-sm text-[var(--color-mute)]">
        No meter frames received yet — step forward to see readings arrive.
      </div>
    );
  }
  const data: Row[] = frames.map((f) => ({
    n: f.index + 1,
    voltage: f.v / 10,
    current: f.i / 10,
    frequency: f.f / 100,
    valid: f.valid,
  }));
  return (
    <div>
      <div className="grid grid-cols-1 gap-3 md:grid-cols-3">
        {SERIES.map((s) => (
          <SmallChart key={s.key} data={data} s={s} />
        ))}
      </div>
      <p className="mt-3 text-xs text-[var(--color-mute)]">
        Dots are frames that passed the CRC check; <span className="text-[#E0484D]">×</span> marks a rejected frame. Dashed red lines are the
        limits the firmware compares each reading against.
      </p>
    </div>
  );
}
