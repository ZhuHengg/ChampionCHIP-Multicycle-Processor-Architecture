import { useMemo } from 'react';
import { Bar, BarChart, CartesianGrid, Cell, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts';
import { rebound } from '../../data/rebound';

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
    <div className="flex h-full flex-col rounded-2xl border border-[var(--color-line)] bg-[var(--color-panel)] p-5">
      <h3 className="font-display text-base font-bold text-[var(--color-ink)]">Load that comes back in each frame</h3>
      <p className="mt-1 text-sm text-[var(--color-mute)]">MW reconnecting per meter frame after the grid recovers</p>
      <div className="mt-3 flex flex-wrap gap-4 text-xs text-[var(--color-ink-2)]">
        <span className="flex items-center gap-2">
          <span className="h-2.5 w-2.5 rounded-sm bg-[#FF5A5F]" aria-hidden="true" /> Fixed delay: everyone at once
        </span>
        <span className="flex items-center gap-2">
          <span className="h-2.5 w-2.5 rounded-sm bg-[#3CCF5A]" aria-hidden="true" /> RVBL-2: CRC-hashed delay
        </span>
      </div>
      <div className="mt-2 min-h-[260px] flex-1">
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={data} margin={{ top: 12, right: 4, left: -12, bottom: 4 }} barGap={2}>
            <CartesianGrid stroke="#1F2B47" vertical={false} />
            <XAxis dataKey="frame" tick={{ fill: '#94A3B8', fontSize: 11 }} stroke="#1F2B47" tickLine={false} />
            <YAxis tick={{ fill: '#94A3B8', fontSize: 11 }} stroke="#1F2B47" tickLine={false} unit=" MW" width={64} />
            <Tooltip
              contentStyle={{ backgroundColor: '#16203A', border: '1px solid #1F2B47', borderRadius: 8, fontSize: 12 }}
              labelStyle={{ color: '#CBD5E1' }}
              labelFormatter={(f) => `Frame ${f} after recovery`}
              formatter={(v, name) => [`${Number(v).toFixed(3)} MW`, name === 'allAtOnce' ? 'Fixed delay' : 'CRC-hashed']}
              cursor={{ fill: 'rgba(255,255,255,0.04)' }}
            />
            <Bar dataKey="allAtOnce" fill="#FF5A5F" fillOpacity={0.85} radius={[4, 4, 0, 0]} isAnimationActive={false} />
            <Bar dataKey="crcHashed" radius={[4, 4, 0, 0]} isAnimationActive={false}>
              {data.map((row) => (
                <Cell
                  key={row.frame}
                  fill="#3CCF5A"
                  fillOpacity={highlightFrame === undefined || row.frame <= highlightFrame ? 1 : 0.3}
                  stroke={row.frame === highlightFrame ? '#FFFFFF' : undefined}
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
