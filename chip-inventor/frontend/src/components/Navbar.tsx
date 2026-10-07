import { Cpu } from 'lucide-react';

export type NavTab = 'station' | 'grid';

interface NavbarProps {
  activeTab: NavTab;
  onTabChange: (tab: NavTab) => void;
}

const TABS: { id: NavTab; label: string }[] = [
  { id: 'station', label: 'Station' },
  { id: 'grid', label: 'Grid' },
];

function Navbar({ activeTab, onTabChange }: NavbarProps) {
  return (
    <nav className="sticky top-0 z-20 border-b border-[#475569]/30 bg-[#0F172A]">
      <div className="mx-auto flex h-16 max-w-7xl items-center justify-between gap-4 px-4 md:px-8">
        <div className="flex min-w-0 items-center gap-3">
          <Cpu className="h-7 w-7 shrink-0 text-[#22C55E]" aria-hidden="true" />
          <div className="min-w-0 leading-tight">
            <div className="truncate font-mono text-lg font-bold text-[#F8FAFC]">
              ChampionCHIP
            </div>
            <div className="truncate text-sm text-[#94A3B8]">RVBL-2 EV Controller</div>
          </div>
        </div>

        <div className="flex items-center gap-1 md:gap-2" role="tablist" aria-label="Main sections">
          {TABS.map((tab) => {
            const isActive = tab.id === activeTab;
            return (
              <button
                key={tab.id}
                type="button"
                role="tab"
                aria-selected={isActive}
                onClick={() => onTabChange(tab.id)}
                className={`cursor-pointer border-b-2 px-3 py-5 font-mono text-sm font-medium transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[#22C55E] focus-visible:ring-offset-2 focus-visible:ring-offset-[#0F172A] md:px-4 ${
                  isActive
                    ? 'border-[#22C55E] text-[#22C55E]'
                    : 'border-transparent text-[#94A3B8] hover:text-[#F8FAFC]'
                }`}
              >
                {tab.label}
              </button>
            );
          })}
        </div>
      </div>
    </nav>
  );
}

export default Navbar;
