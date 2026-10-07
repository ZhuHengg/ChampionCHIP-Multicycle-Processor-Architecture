import {
  Bar,
  CartesianGrid,
  ComposedChart,
  Line,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { F_LOW, I_MAX, V_SAG } from '../../data/constants';

export interface MeterFrame {
  v: number;
  i: number;
  f: number;
  valid: boolean;
  index: number;
}

interface MeterChartProps {
  frames: MeterFrame[];
}

interface ChartRow {
  index: number;
  voltage: number;
  current: number;
  frequency: number;
  valid: boolean;
}

const V_SAG_V = V_SAG / 10;
const F_LOW_HZ = F_LOW / 100;
const I_MAX_A = I_MAX / 10;

// Recharts' own `dot` render-prop type differs across its internal
// overloads (plain function vs. DotType), and fighting that union with
// explicit types causes a spurious overload-mismatch error. The props
// we actually need (cx, cy, payload) are duck-typed here instead.
interface InvalidDotProps {
  cx?: number;
  cy?: number;
  payload?: ChartRow;
}

function InvalidDot(props: InvalidDotProps) {
  const { cx, cy, payload } = props;
  if (cx == null || cy == null || !payload || payload.valid) {
    return null;
  }
  const s = 5;
  return (
    <g stroke="#FF5A5F" strokeWidth={2}>
      <line x1={cx - s} y1={cy - s} x2={cx + s} y2={cy + s} />
      <line x1={cx - s} y1={cy + s} x2={cx + s} y2={cy - s} />
    </g>
  );
}

function MeterChart({ frames }: MeterChartProps) {
  const data: ChartRow[] = frames.map((f) => ({
    index: f.index,
    voltage: f.v / 10,
    current: f.i / 10,
    frequency: f.f / 100,
    valid: f.valid,
  }));

  return (
    <div style={{ width: '100%', height: 200 }}>
      <ResponsiveContainer width="100%" height="100%">
        <ComposedChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
          <CartesianGrid stroke="#272F42" strokeDasharray="3 3" />
          <XAxis dataKey="index" tick={{ fill: '#94A3B8', fontSize: 11 }} stroke="#475569" />
          <YAxis
            yAxisId="left"
            tick={{ fill: '#94A3B8', fontSize: 11 }}
            stroke="#475569"
            width={36}
          />
          <YAxis
            yAxisId="right"
            orientation="right"
            tick={{ fill: '#94A3B8', fontSize: 11 }}
            stroke="#475569"
            width={36}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: '#1B2336',
              border: '1px solid #475569',
              borderRadius: 8,
              fontFamily: "'Fira Code', monospace",
              fontSize: 12,
            }}
            labelStyle={{ color: '#F8FAFC' }}
          />
          <ReferenceLine
            yAxisId="left"
            y={V_SAG_V}
            stroke="#FF5A5F"
            strokeDasharray="5 5"
            label={{ value: 'V_SAG', position: 'insideTopLeft', fill: '#FF5A5F', fontSize: 10 }}
          />
          <ReferenceLine
            yAxisId="right"
            y={F_LOW_HZ}
            stroke="#FF5A5F"
            strokeDasharray="5 5"
            label={{ value: 'F_LOW', position: 'insideBottomLeft', fill: '#FF5A5F', fontSize: 10 }}
          />
          <ReferenceLine
            yAxisId="left"
            y={I_MAX_A}
            stroke="#FF5A5F"
            strokeDasharray="5 5"
            label={{ value: 'I_MAX', position: 'insideTopRight', fill: '#FF5A5F', fontSize: 10 }}
          />
          <Bar yAxisId="left" dataKey="current" name="Current (A)" fill="#F2B134" barSize={12} />
          <Line
            yAxisId="left"
            type="monotone"
            dataKey="voltage"
            name="Voltage (V)"
            stroke="#6EA8FF"
            strokeWidth={2}
            dot={((props: InvalidDotProps) => {
              const key = `v-dot-${props.payload?.index ?? props.cx}`;
              return <InvalidDot key={key} {...props} />;
            }) as unknown as boolean}
            activeDot={{ r: 4 }}
          />
          <Line
            yAxisId="right"
            type="monotone"
            dataKey="frequency"
            name="Frequency (Hz)"
            stroke="#22C55E"
            strokeWidth={2}
            dot={((props: InvalidDotProps) => {
              const key = `f-dot-${props.payload?.index ?? props.cx}`;
              return <InvalidDot key={key} {...props} />;
            }) as unknown as boolean}
            activeDot={{ r: 4 }}
          />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  );
}

export default MeterChart;
