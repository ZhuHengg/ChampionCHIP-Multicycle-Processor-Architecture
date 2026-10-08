import { Cpu, ShieldCheck } from 'lucide-react';

export type NavTab = 'station' | 'grid';

interface NavbarProps {
  activeTab: NavTab;
  onTabChange: (tab: NavTab) => void;
}

const TABS: { id: NavTab; n: number; label: string; short: string }[] = [
  { id: 'station', n: 1, label: 'One charger', short: 'Charger' },
  { id: 'grid', n: 2, label: 'A thousand chargers', short: 'Fleet' },
];

function Navbar({ activeTab, onTabChange }: NavbarProps) {
  return (
    <nav className="sticky top-0 z-20 border-b border-[var(--color-line)] bg-[var(--color-page)]/85 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-[1440px] items-center justify-between gap-4 px-4 md:px-8">
        <div className="flex min-w-0 items-center gap-3">
          <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[var(--color-ok)]/15">
            <Cpu className="h-5 w-5 text-[var(--color-ok)]" aria-hidden="true" />
          </span>
          <div className="hidden min-w-0 leading-tight sm:block">
            <div className="truncate font-display text-base font-extrabold text-[var(--color-ink)]">ChampionCHIP RVBL-2</div>
            <div className="truncate text-xs text-[var(--color-mute)]">Grid-aware EV charging controller</div>
          </div>
        </div>

        <div className="flex items-center gap-1 rounded-full border border-[var(--color-line)] bg-[var(--color-panel)] p-1" role="tablist" aria-label="Demo sections">
          {TABS.map((tab) => {
            const active = tab.id === activeTab;
            return (
              <button
                key={tab.id}
                type="button"
                role="tab"
                aria-selected={active}
                onClick={() => onTabChange(tab.id)}
                className={`flex min-h-10 cursor-pointer items-center gap-2 rounded-full px-3 text-sm font-medium transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ok)] md:px-4 ${
                  active ? 'bg-white text-[#0A2A66]' : 'text-[var(--color-ink-2)] hover:text-[var(--color-ink)]'
                }`}
              >
                <span className={`font-mono text-xs ${active ? 'text-[#0A2A66]/70' : 'text-[var(--color-mute)]'}`}>{tab.n}</span>
                <span className="sm:hidden">{tab.short}</span>
                <span className="hidden sm:inline">{tab.label}</span>
              </button>
            );
          })}
        </div>

        <div className="hidden items-center gap-2 text-xs text-[var(--color-mute)] lg:flex">
          <ShieldCheck className="h-4 w-4 text-[var(--color-ok)]" aria-hidden="true" />
          Matches the firmware's golden model
        </div>
      </div>
    </nav>
  );
}

export default Navbar;
