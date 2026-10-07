import { useMemo } from 'react';
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts';
import { delayHistogram } from '../../data/rebound';

interface HistogramRow {
  delay: number;
  count: number;
}

const N_CHARGERS = 10000;

export default function DelayHistogram() {
  const data = useMemo<HistogramRow[]>(() => {
    const hist = delayHistogram(N_CHARGERS);
    return Object.entries(hist)
      .map(([delay, count]) => ({ delay: Number(delay), count }))
      .sort((a, b) => a.delay - b.delay);
  }, []);

  return (
    <div className="flex h-full flex-col rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
      <h3 className="font-mono text-sm font-medium text-[#F8FAFC]">
        CRC-16 Hash Distribution: 10,000 Charger IDs
      </h3>
      <p className="mb-3 font-sans text-sm text-[#94A3B8]">
        Each bar ≈ 1,250 — uniform spread, no clustering
      </p>
      <div className="min-h-[220px] flex-1">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
            <defs>
              <linearGradient id="histogramGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#22C55E" />
                <stop offset="100%" stopColor="#6EA8FF" />
              </linearGradient>
            </defs>
            <CartesianGrid stroke="#272F42" strokeDasharray="3 3" />
            <XAxis
              dataKey="delay"
              stroke="#94A3B8"
              tick={{ fill: '#94A3B8', fontSize: 11, fontFamily: 'Fira Sans' }}
              label={{
                value: 'Restart delay (frames)',
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
                value: 'Count',
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
            <Bar
              dataKey="count"
              fill="url(#histogramGradient)"
              animationDuration={800}
              radius={[3, 3, 0, 0]}
            />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
