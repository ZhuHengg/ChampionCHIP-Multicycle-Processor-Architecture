import { useMemo } from 'react';
import {
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { rebound } from '../../data/rebound';
import { HOLD_BASE } from '../../data/constants';

interface ReboundChartRow {
  frame: number;
  allAtOnce: number;
  crcHashed: number;
}

interface ReboundChartProps {
  /** Optional stagger sub-frame (0-7) to highlight the matching bar. */
  highlightFrame?: number;
}

export default function ReboundChart({ highlightFrame }: ReboundChartProps) {
  const data = useMemo<ReboundChartRow[]>(() => {
    const { sync, stag } = rebound();
    return sync.map((v, i) => ({
      frame: i,
      allAtOnce: v,
      crcHashed: stag[i] ?? 0,
    }));
  }, []);

  const highlightAbsFrame =
    highlightFrame !== undefined ? HOLD_BASE + highlightFrame : undefined;

  return (
    <div className="flex h-full flex-col rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
      <h3 className="mb-3 font-mono text-sm font-medium text-[#F8FAFC]">
        Load Restored per Frame (MW)
      </h3>
      <div className="min-h-[260px] flex-1">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
            <CartesianGrid stroke="#272F42" strokeDasharray="3 3" />
            <XAxis
              dataKey="frame"
              stroke="#94A3B8"
              tick={{ fill: '#94A3B8', fontSize: 11, fontFamily: 'Fira Sans' }}
              label={{
                value: 'Frames since grid recovered',
                position: 'insideBottom',
                offset: -2,
                fill: '#94A3B8',
                fontSize: 11,
              }}
            />
            <YAxis
              stroke="#94A3B8"
              tick={{ fill: '#94A3B8', fontSize: 11, fontFamily: 'Fira Sans' }}
              label={{
                value: 'MW',
                angle: -90,
                position: 'insideLeft',
                fill: '#94A3B8',
                fontSize: 11,
              }}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: '#1B2336',
                border: '1px solid #475569',
                borderRadius: 8,
                fontFamily: 'Fira Sans',
                fontSize: 12,
              }}
              labelStyle={{ color: '#F8FAFC' }}
              cursor={{ fill: '#272F42', opacity: 0.4 }}
            />
            <Legend wrapperStyle={{ fontSize: 12, fontFamily: 'Fira Sans', color: '#94A3B8' }} />
            <Bar
              dataKey="allAtOnce"
              name="All at once"
              fill="#FF5A5F"
              animationDuration={800}
              radius={[3, 3, 0, 0]}
            />
            <Bar
              dataKey="crcHashed"
              name="CRC-hashed"
              fill="#22C55E"
              animationDuration={800}
              radius={[3, 3, 0, 0]}
            >
              {data.map((row) => (
                <Cell
                  key={row.frame}
                  fill={row.frame === highlightAbsFrame ? '#6EA8FF' : '#22C55E'}
                />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
