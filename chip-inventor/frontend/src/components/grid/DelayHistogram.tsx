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
    <div className="flex h-full flex-col rounded-2xl border border-[var(--color-line)] bg-[var(--color-panel)] p-5">
      <h3 className="font-display text-base font-bold text-[var(--color-ink)]">The hash spreads chargers evenly</h3>
      <p className="mt-1 mb-3 text-sm text-[var(--color-mute)]">
        Restart delay for 10,000 charger IDs: about 1,250 in each of the 8 slots, no clustering.
      </p>
      <div className="min-h-[220px] flex-1">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} margin={{ top: 8, right: 8, left: 0, bottom: 0 }}>
            <defs>
              <linearGradient id="histogramGradient" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#3CCF5A" />
                <stop offset="100%" stopColor="#6EA8FF" />
              </linearGradient>
            </defs>
            <CartesianGrid stroke="#1F2B47" strokeDasharray="3 3" />
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
                backgroundColor: "#16203A",
                border: '1px solid #475569',
                borderRadius: 8,
                fontFamily: 'Fira Sans',
                fontSize: 12,
              }}
              labelStyle={{ color: '#F8FAFC' }}
              cursor={{ fill: '#1F2B47', opacity: 0.4 }}
            />
            <Bar
              dataKey="count"
              fill="url(#histogramGradient)"
              isAnimationActive={false}
              radius={[3, 3, 0, 0]}
            />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
