import { Zap } from 'lucide-react';

interface EnergyGaugeProps {
  energy: number;
  frames: number;
  maxFrames: number;
}

function EnergyGauge({ energy, frames, maxFrames }: EnergyGaugeProps) {
  const pct = maxFrames > 0 ? Math.min(100, Math.max(0, (frames / maxFrames) * 100)) : 0;

  return (
    <div>
      <div className="mb-2 flex items-center gap-2">
        <Zap className="h-4 w-4 text-[#22C55E]" aria-hidden="true" />
        <span className="font-mono text-sm font-medium text-[#F8FAFC]">Energy Metered</span>
      </div>
      <div className="font-mono text-3xl font-bold tabular-nums text-[#22C55E]">
        {energy.toLocaleString()}
      </div>
      <div className="mb-3 text-xs text-[#94A3B8]">Wh (V&times;I accumulated)</div>
      <div
        className="h-2 w-full overflow-hidden rounded-full bg-[#272F42]"
        role="progressbar"
        aria-valuenow={frames}
        aria-valuemin={0}
        aria-valuemax={maxFrames}
      >
        <div
          className="h-full rounded-full bg-[#22C55E] transition-all duration-300"
          style={{ width: `${pct}%` }}
        />
      </div>
      <div className="mt-1 text-xs text-[#94A3B8]">
        {frames} frame{frames === 1 ? '' : 's'}
      </div>
    </div>
  );
}

export default EnergyGauge;
