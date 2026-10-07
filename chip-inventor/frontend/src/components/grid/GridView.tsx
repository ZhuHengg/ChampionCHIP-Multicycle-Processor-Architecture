import { useCallback, useMemo, useState } from 'react';
import { Activity, TrendingDown, Zap } from 'lucide-react';
import { rebound } from '../../data/rebound';
import CityScene from './CityScene';
import ReboundChart from './ReboundChart';
import DelayHistogram from './DelayHistogram';
import GridTimeline, { type Phase } from './GridTimeline';
import DisputePanel from './DisputePanel';

const N_CHARGERS = 1000;

interface StatTileProps {
  value: string;
  label: string;
  icon: React.ComponentType<{ size?: number; className?: string }>;
}

function StatTile({ value, label, icon: Icon }: StatTileProps) {
  return (
    <div className="relative rounded-xl border border-white/10 bg-[#1B2336]/80 p-4 backdrop-blur-sm">
      <Icon size={28} className="absolute top-4 right-4 text-[#22C55E] opacity-50" />
      <div className="font-mono text-3xl text-[#22C55E]">{value}</div>
      <div className="mt-1 font-sans text-sm text-[#94A3B8]">{label}</div>
    </div>
  );
}

export default function GridView() {
  const [phase, setPhase] = useState<Phase>('normal');
  const [staggerFrame, setStaggerFrame] = useState(0);

  const handlePhaseChange = useCallback((nextPhase: Phase, nextStaggerFrame: number) => {
    setPhase(nextPhase);
    setStaggerFrame(nextStaggerFrame);
  }, []);

  const { peakSync, peakStag, reduction } = useMemo(() => {
    const { sync, stag } = rebound(N_CHARGERS);
    const sync0 = Math.max(...sync);
    const stag0 = Math.max(...stag);
    return {
      peakSync: sync0,
      peakStag: stag0,
      reduction: sync0 / stag0,
    };
  }, []);

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <StatTile value={N_CHARGERS.toLocaleString()} label="chargers" icon={Zap} />
        <StatTile value={`${reduction.toFixed(2)}×`} label="reduction" icon={TrendingDown} />
        <StatTile value={`${peakStag.toFixed(2)} MW`} label="peak load" icon={Activity} />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <div className="h-[400px]">
          <CityScene phase={phase} staggerFrame={staggerFrame} />
        </div>
        <ReboundChart highlightFrame={phase === 'stagger' ? staggerFrame : undefined} />
      </div>

      <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <GridTimeline onPhaseChange={handlePhaseChange} />
        <DelayHistogram />
      </div>

      {/* Dispute panel (Phase 6) */}
      <DisputePanel />

      {/* peakSync retained for reference / potential future tooltip use */}
      <span className="sr-only">Peak synchronised load: {peakSync.toFixed(2)} MW</span>
    </div>
  );
}
