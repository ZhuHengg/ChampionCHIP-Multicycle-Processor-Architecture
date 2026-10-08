import type { Scenario } from '../../data/scenarios';
import { GROUP_ORDER, GROUP_TONE, SCENARIO_META, TONE_COLOR } from './stationStory';

interface ScenarioPickerProps {
  scenarios: Scenario[];
  activeId: string;
  onSelect: (id: string) => void;
}

function ScenarioPicker({ scenarios, activeId, onSelect }: ScenarioPickerProps) {
  return (
    <>
      {/* Phones: a compact native select instead of 13 stacked buttons. */}
      <label className="block md:hidden">
        <span className="sr-only">Scenario</span>
        <select
          value={activeId}
          onChange={(e) => onSelect(e.target.value)}
          className="min-h-12 w-full cursor-pointer rounded-xl border border-[var(--color-line)] bg-[var(--color-panel)] px-3 text-base text-[var(--color-ink)] focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ok)]"
        >
          {GROUP_ORDER.map((group) => (
            <optgroup key={group} label={group}>
              {scenarios
                .filter((s) => SCENARIO_META[s.id]?.group === group)
                .map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.id} · {SCENARIO_META[s.id]?.name ?? s.title}
                  </option>
                ))}
            </optgroup>
          ))}
        </select>
      </label>
      <ScenarioList scenarios={scenarios} activeId={activeId} onSelect={onSelect} />
    </>
  );
}

function ScenarioList({ scenarios, activeId, onSelect }: ScenarioPickerProps) {
  return (
    <div className="hidden grid-cols-2 gap-x-6 gap-y-5 md:grid lg:grid-cols-4 xl:grid-cols-1">
      {GROUP_ORDER.map((group) => {
        const color = TONE_COLOR[GROUP_TONE[group]];
        const items = scenarios.filter((s) => SCENARIO_META[s.id]?.group === group);
        return (
          <div key={group} role="group" aria-label={group}>
            <div className="mb-2 flex items-center gap-2">
              <span className="h-2 w-2 rounded-full" style={{ backgroundColor: color }} aria-hidden="true" />
              <span className="text-xs font-semibold uppercase tracking-[0.12em] text-[var(--color-mute)]">{group}</span>
            </div>
            <div className="flex flex-col gap-1">
              {items.map((s) => {
                const active = s.id === activeId;
                return (
                  <button
                    key={s.id}
                    type="button"
                    aria-pressed={active}
                    onClick={() => onSelect(s.id)}
                    className={`group flex min-h-11 cursor-pointer items-center gap-3 rounded-lg border px-3 py-2 text-left transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ok)] ${
                      active
                        ? 'border-transparent text-[var(--color-ink)]'
                        : 'border-transparent text-[var(--color-ink-2)] hover:bg-white/[0.04] hover:text-[var(--color-ink)]'
                    }`}
                    style={active ? { backgroundColor: `${color}1F`, boxShadow: `inset 0 0 0 1px ${color}66` } : undefined}
                  >
                    <span
                      className="w-9 shrink-0 font-mono text-xs font-medium"
                      style={{ color: active ? color : 'var(--color-mute)' }}
                    >
                      {s.id}
                    </span>
                    <span className="text-sm font-medium leading-snug">{SCENARIO_META[s.id]?.name ?? s.title}</span>
                  </button>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}

export default ScenarioPicker;
