import { useMemo } from 'react';
import { Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { rebound } from '../../data/rebound';
import { CHART } from '../../styles/chartTheme';

interface Row {
  frame: number;
  allAtOnce: number;
  crcHashed: number;
}

interface ReboundChartProps {
  /** Frame (since grid recovery) to highlight, or undefined. */
  highlightFrame?: number;
  nChargers: number;
}

export default function ReboundChart({ highlightFrame, nChargers }: ReboundChartProps) {
  const data = useMemo<Row[]>(() => {
    const { sync, stag } = rebound(nChargers);
    return sync.map((v, i) => ({ frame: i, allAtOnce: v, crcHashed: stag[i] ?? 0 }));
  }, [nChargers]);

  return (
    <div className="card flex h-full flex-col p-6">
      <h3 className="font-display text-xl font-medium text-[var(--color-ink)]">Load coming back, frame by frame</h3>
      <p className="mt-1 text-sm text-[var(--color-mute)]">MW reconnecting per meter frame after the grid recovers</p>
      <div className="mt-4 flex flex-wrap gap-x-5 gap-y-2 text-xs text-[var(--color-ink-2)]">
        <span className="flex items-center gap-2">
          <span className="h-2.5 w-5 rounded-full bg-[var(--color-dark)]" aria-hidden="true" /> Fixed delay: everyone at once
        </span>
        <span className="flex items-center gap-2">
          <span className="h-2.5 w-5 rounded-full bg-[var(--color-accent)]" aria-hidden="true" /> RVBL-2: CRC-hashed delay
        </span>
      </div>
      <div className="mt-3 min-h-[260px] flex-1">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} margin={{ top: 12, right: 4, left: -12, bottom: 4 }} barGap={3}>
            <CartesianGrid stroke={CHART.grid} strokeDasharray="2 6" vertical={false} />
            <XAxis dataKey="frame" tick={{ fill: CHART.tick, fontSize: 11 }} axisLine={false} tickLine={false} />
            <YAxis tick={{ fill: CHART.tick, fontSize: 11 }} axisLine={false} tickLine={false} unit=" MW" width={64} />
            <Tooltip
              contentStyle={CHART.tooltip}
              labelStyle={{ color: CHART.ink2 }}
              labelFormatter={(f) => `Frame ${f} after recovery`}
              formatter={(v, name) => [`${Number(v).toFixed(3)} MW`, name === 'allAtOnce' ? 'Fixed delay' : 'CRC-hashed']}
              cursor={{ fill: 'rgba(0,0,0,0.035)' }}
            />
            <Bar dataKey="allAtOnce" fill={CHART.dark} radius={[6, 6, 6, 6]} maxBarSize={18} isAnimationActive={false} />
            <Bar dataKey="crcHashed" radius={[6, 6, 6, 6]} maxBarSize={18} isAnimationActive={false}>
              {data.map((row) => (
                <Cell
                  key={row.frame}
                  fill={CHART.accent}
                  fillOpacity={highlightFrame === undefined || row.frame <= highlightFrame ? 1 : 0.3}
                  stroke={row.frame === highlightFrame ? CHART.dark : undefined}
                  strokeWidth={row.frame === highlightFrame ? 1.5 : 0}
                />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}
