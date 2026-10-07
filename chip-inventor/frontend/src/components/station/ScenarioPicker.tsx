import type { Scenario } from '../../data/scenarios';

const CATEGORY_COLORS: Record<Scenario['category'], string> = {
  normal: '#22C55E',
  grid: '#F2B134',
  fault: '#FF5A5F',
  integrity: '#A78BFA',
};

function truncateTitle(title: string, max = 20): string {
  return title.length > max ? `${title.slice(0, max - 1)}…` : title;
}

interface ScenarioPickerProps {
  scenarios: Scenario[];
  activeId: string;
  onSelect: (id: string) => void;
}

function ScenarioPicker({ scenarios, activeId, onSelect }: ScenarioPickerProps) {
  return (
    <div className="flex gap-2 overflow-x-auto pb-1" role="tablist" aria-label="Scenario selection">
      {scenarios.map((s) => {
        const isActive = s.id === activeId;
        const color = CATEGORY_COLORS[s.category];
        return (
          <button
            key={s.id}
            type="button"
            role="tab"
            aria-selected={isActive}
            onClick={() => onSelect(s.id)}
            className={`flex shrink-0 cursor-pointer items-center gap-2 whitespace-nowrap rounded-full border px-3 py-1.5 font-mono text-xs font-medium transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] ${
              isActive
                ? 'text-[#F8FAFC]'
                : 'border-[#475569]/50 bg-[#1B2336] text-[#94A3B8] hover:border-[#94A3B8]'
            }`}
            style={
              isActive
                ? { backgroundColor: `${color}33`, borderColor: color }
                : undefined
            }
          >
            <span
              className="h-2 w-2 shrink-0 rounded-full"
              style={{ backgroundColor: color }}
              aria-hidden="true"
            />
            <span>{s.id}</span>
            <span className="font-sans font-normal">{truncateTitle(s.title)}</span>
          </button>
        );
      })}
    </div>
  );
}

export default ScenarioPicker;
