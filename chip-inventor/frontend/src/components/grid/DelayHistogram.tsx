import { useMemo } from 'react';
import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { delayHistogram } from '../../data/rebound';
import { CHART } from '../../styles/chartTheme';

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
    <div className="card flex h-full flex-col p-6">
      <h3 className="font-display text-xl font-medium text-[var(--color-ink)]">The hash spreads chargers evenly</h3>
      <p className="mt-1 mb-4 text-sm text-[var(--color-mute)]">
        Restart delay for 10,000 charger IDs: about 1,250 in each of the 8 slots, no clustering.
      </p>
      <div className="min-h-[220px] flex-1">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} margin={{ top: 8, right: 8, left: -8, bottom: 12 }}>
            <CartesianGrid stroke={CHART.grid} strokeDasharray="2 6" vertical={false} />
            <XAxis
              dataKey="delay"
              axisLine={false}
              tickLine={false}
              tick={{ fill: CHART.tick, fontSize: 11 }}
              label={{ value: 'Restart delay (healthy frames)', position: 'insideBottom', offset: -8, fill: CHART.tick, fontSize: 11 }}
            />
            <YAxis axisLine={false} tickLine={false} tick={{ fill: CHART.tick, fontSize: 11 }} width={48} />
            <Tooltip contentStyle={CHART.tooltip} labelStyle={{ color: CHART.ink2 }} labelFormatter={(d) => `Delay ${d} frames`} cursor={{ fill: 'rgba(0,0,0,0.035)' }} />
            <Bar dataKey="count" name="Chargers" fill={CHART.accent} isAnimationActive={false} radius={[8, 8, 8, 8]} maxBarSize={34} />
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
