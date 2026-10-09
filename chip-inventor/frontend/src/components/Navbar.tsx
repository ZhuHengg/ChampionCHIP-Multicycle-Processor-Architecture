import GripperLogo from './GripperLogo';

export type NavTab = 'station' | 'grid';

interface NavbarProps {
  activeTab: NavTab;
  onTabChange: (tab: NavTab) => void;
}

const TABS: { id: NavTab; label: string; short: string }[] = [
  { id: 'station', label: 'One charger', short: 'Charger' },
  { id: 'grid', label: 'A thousand chargers', short: 'Fleet' },
];

function Navbar({ activeTab, onTabChange }: NavbarProps) {
  return (
    <nav className="mx-auto flex w-full max-w-[1440px] items-center justify-between gap-3 px-4 pt-5 md:px-8 md:pt-7">
      <span className="flex min-w-0 items-center gap-2 font-display text-xl font-medium tracking-tight text-[var(--color-ink)] md:text-2xl">
        <GripperLogo className="h-6 w-6 shrink-0 md:h-7 md:w-7" />
        Gripper
      </span>

      <div className="flex items-center gap-1 rounded-full bg-white/60 p-1 backdrop-blur-sm" role="tablist" aria-label="Demo sections">
        {TABS.map((tab) => {
          const active = tab.id === activeTab;
          return (
            <button
              key={tab.id}
              type="button"
              role="tab"
              aria-selected={active}
              onClick={() => onTabChange(tab.id)}
              className={`min-h-11 cursor-pointer rounded-full px-4 text-sm font-medium transition-colors duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-ink)] md:px-5 ${
                active ? 'bg-[var(--color-dark)] text-white' : 'text-[var(--color-ink-2)] hover:text-[var(--color-ink)]'
              }`}
            >
              <span className="sm:hidden">{tab.short}</span>
              <span className="hidden sm:inline">{tab.label}</span>
            </button>
          );
        })}
      </div>
    </nav>
  );
}

export default Navbar;
