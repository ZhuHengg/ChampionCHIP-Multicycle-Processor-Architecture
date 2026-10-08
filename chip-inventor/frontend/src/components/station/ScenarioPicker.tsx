// Scenario library as an accordion: one group open at a time, starting with
// the group of the scenario on screen.

import { useState } from 'react';
import { ChevronDown } from 'lucide-react';
import type { Scenario } from '../../data/scenarios';
import { GROUP_ORDER, SCENARIO_META } from './stationStory';
import type { ScenarioGroup } from './stationStory';

const GROUP_BLURB: Record<ScenarioGroup, string> = {
  Everyday: 'Normal plug-in, charge, unplug',
  'Grid support': 'Backing off when the grid dips',
  'Data integrity': 'Bad, replayed or missing meter data',
  Safety: 'Watchdog, e-stop, limits, pilot errors',
};

interface ScenarioPickerProps {
  scenarios: Scenario[];
  activeId: string;
  onSelect: (id: string) => void;
}

export default function ScenarioPicker({ scenarios, activeId, onSelect }: ScenarioPickerProps) {
  const activeGroup = SCENARIO_META[activeId]?.group ?? 'Everyday';
  const [open, setOpen] = useState<ScenarioGroup | null>(activeGroup);

  return (
    <div className="card flex h-full flex-col px-6 pt-6 pb-3">
      <div className="flex items-baseline justify-between">
        <h2 className="font-display text-xl font-medium text-[var(--color-ink)]">Scenarios</h2>
        <span className="tabular text-sm text-[var(--color-mute)]">{scenarios.length}</span>
      </div>
      <div className="mt-2 flex flex-col">
        {GROUP_ORDER.map((group) => {
          const items = scenarios.filter((s) => SCENARIO_META[s.id]?.group === group);
          const isOpen = open === group;
          const panelId = `group-${group.replace(/\s+/g, '-')}`;
          return (
            <div key={group} className="border-b border-dashed border-[var(--color-line-strong)] last:border-b-0">
              <button
                type="button"
                aria-expanded={isOpen}
                aria-controls={panelId}
                onClick={() => setOpen(isOpen ? null : group)}
                className="flex min-h-14 w-full cursor-pointer items-center justify-between gap-3 text-left focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)]"
              >
                <span>
                  <span className="block text-[15px] font-medium text-[var(--color-ink)]">
                    {group}
                    {group === activeGroup && !isOpen && <span className="ml-2 inline-block h-1.5 w-1.5 rounded-full bg-[var(--color-accent)] align-middle" />}
                  </span>
                  <span className="block text-xs text-[var(--color-mute)]">{GROUP_BLURB[group]}</span>
                </span>
                <ChevronDown size={18} className={`shrink-0 text-[var(--color-ink-2)] transition-transform duration-200 ${isOpen ? 'rotate-180' : ''}`} aria-hidden="true" />
              </button>
              {isOpen && (
                <ul id={panelId} className="flex flex-col gap-1 pb-3">
                  {items.map((s) => {
                    const active = s.id === activeId;
                    return (
                      <li key={s.id}>
                        <button
                          type="button"
                          aria-pressed={active}
                          onClick={() => onSelect(s.id)}
                          className={`flex min-h-11 w-full cursor-pointer items-center gap-3 rounded-full px-4 text-left text-sm transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)] ${
                            active ? 'bg-[var(--color-dark)] text-white' : 'text-[var(--color-ink-2)] hover:bg-white'
                          }`}
                        >
                          <span className={`w-8 shrink-0 font-mono text-xs ${active ? 'text-[var(--color-accent)]' : 'text-[var(--color-mute)]'}`}>{s.id}</span>
                          <span className="truncate font-medium">{SCENARIO_META[s.id]?.name ?? s.title}</span>
                        </button>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
