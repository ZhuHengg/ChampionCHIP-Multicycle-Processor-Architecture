import { useEffect, useState } from 'react';
import Navbar from './components/Navbar';
import type { NavTab } from './components/Navbar';
import StationView from './components/station/StationView';
import GridView from './components/grid/GridView';

function App() {
  const [activeTab, setActiveTab] = useState<NavTab>('station');
  const [visible, setVisible] = useState(true);

  // Simple 150ms opacity cross-fade on tab switch instead of an instant
  // swap: fade out, swap content, fade back in.
  useEffect(() => {
    setVisible(false);
    const id = setTimeout(() => setVisible(true), 0);
    return () => clearTimeout(id);
  }, [activeTab]);

  return (
    <div className="flex min-h-screen flex-col">
      <Navbar activeTab={activeTab} onTabChange={setActiveTab} />
      <main
        className="flex-1 px-4 py-6 transition-opacity duration-150 md:px-8"
        style={{ opacity: visible ? 1 : 0 }}
      >
        {activeTab === 'station' ? <StationView /> : <GridView />}
      </main>
      <footer className="py-6 text-center text-xs text-[#94A3B8]">
        Every value on this page comes from the chip&apos;s own firmware, verified against the
        Python golden model. The visualization reads bytes — it makes no decisions.
      </footer>
    </div>
  );
}

export default App;
