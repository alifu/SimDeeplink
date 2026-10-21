import { useEffect, useState } from "react";

import "./App.css";
import { PLATFORM_LABELS, PlatformTabs } from "./components/PlatformTabs";
import { PlatformPanel } from "./components/PlatformPanel";
import { api, errorMessage } from "./lib/api";
import type { Platform } from "./lib/types";

function App() {
  const [platforms, setPlatforms] = useState<Platform[]>([]);
  const [active, setActive] = useState<Platform | null>(null);
  const [adbPaths, setAdbPaths] = useState<string[]>([]);
  const [adbPathsReady, setAdbPathsReady] = useState(false);
  const [fatal, setFatal] = useState<string | null>(null);

  useEffect(() => {
    void (async () => {
      try {
        // macOS turns the window into a menubar panel here; other systems ignore the call.
        await api.init();
        const available = await api.platforms();
        setPlatforms(available);
        setActive(available[0] ?? null);
        setAdbPaths(await api.adbPaths());
      } catch (e) {
        setFatal(errorMessage(e));
      } finally {
        setAdbPathsReady(true);
      }
    })();
  }, []);

  return (
    <main className="flex h-full flex-col gap-2 p-3">
      <header className="flex items-center gap-2">
        <h1 className="flex-1 text-lg font-bold">
          SimDeeplink
          {platforms.length === 1 && <span className="ml-2 text-sm font-normal opacity-70">{PLATFORM_LABELS[platforms[0]]}</span>}
        </h1>
        <button
          aria-label="Quit SimDeeplink"
          className="rounded-lg bg-panel px-3 py-1 text-sm hover:bg-field"
          onClick={() => void api.quit()}
        >
          Quit
        </button>
      </header>
      <PlatformTabs platforms={platforms} active={active ?? "android"} onChange={setActive} />
      {fatal && <p role="alert" className="text-danger">{fatal}</p>}
      {active && <PlatformPanel key={active} platform={active} adbPaths={adbPaths} adbPathsReady={adbPathsReady} />}
    </main>
  );
}

export default App;
