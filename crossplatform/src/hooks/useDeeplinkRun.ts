import { useCallback, useEffect, useRef, useState } from "react";

import { api, errorMessage } from "../lib/api";
import { isLink } from "../lib/isLink";
import type { Outcome, Platform } from "../lib/types";

export const MAX_DELAY_SECONDS = 10;

export interface RunRequest {
  platform: Platform;
  url: string;
  target?: string;
  pkg?: string;
  adbPath?: string;
  delaySeconds: number;
}

/** Runs a deeplink after an optional cancelable countdown and keeps the message the user sees. */
export function useDeeplinkRun() {
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const [running, setRunning] = useState(false);
  // Bumped by every start and cancel; a run that sees a newer number stops.
  const generation = useRef(0);
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  const stopTimer = useCallback(() => clearTimeout(timer.current), []);
  useEffect(() => () => stopTimer(), [stopTimer]);

  const cancel = useCallback(() => {
    generation.current++;
    stopTimer();
    setRunning(false);
    setOutcome(null);
  }, [stopTimer]);

  const reset = useCallback(() => setOutcome(null), []);

  const start = useCallback(
    async (request: RunRequest) => {
      const mine = ++generation.current;
      stopTimer();
      const url = request.url.trim();
      if (!isLink(url)) {
        setRunning(false);
        setOutcome({ ok: false, message: "Invalid Deeplink URL" });
        return;
      }

      setRunning(true);
      const wait = (ms: number) => new Promise<void>((resolve) => (timer.current = setTimeout(resolve, ms)));
      const seconds = Math.min(Math.max(Math.floor(request.delaySeconds) || 0, 0), MAX_DELAY_SECONDS);
      for (let left = seconds; left >= 1; left--) {
        setOutcome({ ok: true, message: `Executing in ${left}s...` });
        await wait(1000);
        if (mine !== generation.current) return;
      }

      setOutcome({ ok: true, message: "Running deeplink..." });
      try {
        const result = await api.openDeeplink({ ...request, url, pkg: request.pkg?.trim() || undefined });
        if (mine === generation.current) setOutcome(result);
      } catch (e) {
        if (mine === generation.current) setOutcome({ ok: false, message: errorMessage(e) });
      } finally {
        if (mine === generation.current) setRunning(false);
      }
    },
    [stopTimer],
  );

  return { outcome, running, start, cancel, reset };
}
