import { useEffect, useState } from 'react';
import Navbar from './components/Navbar';
import type { NavTab } from './components/Navbar';
import StationView from './components/station/StationView';
import GridView from './components/grid/GridView';
import { SCENARIOS } from './data/scenarios';

// Deep links: #/station/S12 opens a scenario and plays it; #/station/S12/3
// opens it paused at step 3 (1-based); #/grid opens the fleet view.
interface Route {
  tab: NavTab;
  scenario: string;
  step?: number;
}

function parseHash(hash: string): Route {
  const [tab, id, step] = hash.replace(/^#\/?/, '').split('/');
  if (tab === 'grid') return { tab: 'grid', scenario: 'S1' };
  const scenario = SCENARIOS.some((s) => s.id === id) ? id : 'S1';
  const n = Number(step);
  return { tab: 'station', scenario, step: Number.isInteger(n) && n > 0 ? n - 1 : undefined };
}

function App() {
  const [route, setRoute] = useState<Route>(() => parseHash(window.location.hash));

  useEffect(() => {
    const onHash = () => setRoute(parseHash(window.location.hash));
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  const go = (next: Route) => {
    window.history.replaceState(null, '', next.tab === 'grid' ? '#/grid' : `#/station/${next.scenario}`);
    setRoute(next);
    window.scrollTo({ top: 0 });
  };

  return (
    <div className="flex min-h-screen flex-col">
      <Navbar activeTab={route.tab} onTabChange={(tab) => go({ tab, scenario: route.scenario })} />
      <main className="mx-auto w-full max-w-[1440px] flex-1 px-4 py-8 md:px-8 md:py-12">
        {route.tab === 'station' ? (
          <StationView
            key={`${route.scenario}/${route.step ?? ''}`}
            initialScenarioId={route.scenario}
            initialStep={route.step}
            onScenarioChange={(id) => window.history.replaceState(null, '', `#/station/${id}`)}
          />
        ) : (
          <GridView onOpenStation={(id) => go({ tab: 'station', scenario: id })} />
        )}
      </main>
      <footer className="mx-auto max-w-3xl px-4 pb-10 text-center text-xs leading-relaxed text-[var(--color-mute)]">
        Values are produced by a TypeScript port of the RVBL-2 firmware's Python golden model (testbench/app/golden.py), which the RTL is verified
        against. The page only displays them.
      </footer>
    </div>
  );
}

export default App;
