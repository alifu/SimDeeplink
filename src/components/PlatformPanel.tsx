import { useEffect, useState } from "react";

import { useDeeplinkRun, MAX_DELAY_SECONDS } from "../hooks/useDeeplinkRun";
import { useDevices } from "../hooks/useDevices";
import { api, errorMessage } from "../lib/api";
import type { Outcome, Platform } from "../lib/types";
import { DeviceSelect } from "./DeviceSelect";
import { buttonClass, Field, inputClass } from "./Field";
import { OutputPanel } from "./OutputPanel";

interface Props {
  platform: Platform;
  /** adb installs found at startup; only Android uses them. */
  adbPaths: string[];
  adbPathsReady: boolean;
}

export function PlatformPanel({ platform, adbPaths, adbPathsReady }: Props) {
  const isAndroid = platform === "android";
  const [url, setUrl] = useState("");
  const [pkg, setPkg] = useState("");
  const [delay, setDelay] = useState(0);
  const [deviceId, setDeviceId] = useState("");
  const [chosenAdb, setChosenAdb] = useState("");
  const [bootOutcome, setBootOutcome] = useState<Outcome | null>(null);
  const [booting, setBooting] = useState(false);

  // The first adb found is the default until the user picks another.
  const adbPath = isAndroid ? chosenAdb || adbPaths[0] || undefined : undefined;
  const { devices, status, loading, error, refresh } = useDevices(platform, adbPath, !isAndroid || adbPathsReady);
  const run = useDeeplinkRun();

  const selected = devices.find((d) => d.id === deviceId);
  // A device that disappeared from the list can no longer be the target.
  useEffect(() => {
    if (deviceId && !selected && !loading) setDeviceId("");
  }, [deviceId, selected, loading]);

  const toolsOk = status?.ok ?? false;
  const shown = run.outcome ?? bootOutcome ?? (status && !status.ok ? { ok: false, message: status.message ?? "" } : null);
  const shownOrError = error ? { ok: false, message: error } : shown;

  const boot = async () => {
    if (!selected) return;
    setBooting(true);
    setBootOutcome({ ok: true, message: `Starting ${selected.name}...` });
    try {
      setBootOutcome(await api.bootDevice(platform, selected.id, adbPath));
    } catch (e) {
      setBootOutcome({ ok: false, message: errorMessage(e) });
    } finally {
      setBooting(false);
      await refresh();
    }
  };

  const execute = () => {
    setBootOutcome(null);
    void run.start({ platform, url, target: deviceId || undefined, pkg, adbPath, delaySeconds: delay });
  };

  return (
    <section className="flex min-h-0 flex-1 flex-col gap-2" aria-label={`${platform} controls`}>
      <div className="flex flex-col gap-2 rounded-xl bg-panel p-3">
        <div className="flex gap-2">
          <input
            aria-label="Deeplink URL"
            value={url}
            placeholder="Enter Deeplink URL"
            onChange={(e) => setUrl(e.target.value)}
            className={inputClass}
          />
          <button
            aria-label="Clear URL"
            className={buttonClass}
            onClick={() => {
              setUrl("");
              run.reset();
            }}
          >
            ⌫
          </button>
        </div>

        {isAndroid && (
          <Field label="ADB Executable">
            <select
              aria-label="ADB Executable"
              value={adbPath ?? ""}
              onChange={(e) => setChosenAdb(e.target.value)}
              className={inputClass}
            >
              {adbPaths.length === 0 && <option value="">{adbPathsReady ? "adb not found" : "Looking..."}</option>}
              {adbPaths.map((path) => (
                <option key={path} value={path}>
                  {path}
                </option>
              ))}
            </select>
          </Field>
        )}

        {isAndroid && (
          <Field label="Package Target (optional)">
            <input
              aria-label="Package Target"
              value={pkg}
              placeholder="com.example.app"
              onChange={(e) => setPkg(e.target.value)}
              className={inputClass}
            />
          </Field>
        )}

        <Field label={isAndroid ? "Emulator Target" : "Simulator Target"}>
          <DeviceSelect devices={devices} value={deviceId} onChange={setDeviceId} disabled={!toolsOk} />
          <button
            aria-label="Start device"
            className={buttonClass}
            disabled={!selected || selected.isBooted || booting}
            onClick={boot}
          >
            {booting ? "Starting..." : "Start"}
          </button>
          <button aria-label="Refresh devices" className={buttonClass} disabled={loading} onClick={() => void refresh()}>
            ↻
          </button>
        </Field>

        <div className="flex items-center gap-2 text-sm">
          <label className="flex items-center gap-2">
            <span className="w-40 shrink-0">Delay (seconds)</span>
            <input
              aria-label="Delay"
              type="number"
              min={0}
              max={MAX_DELAY_SECONDS}
              value={delay}
              onChange={(e) => setDelay(Math.min(Math.max(Number(e.target.value) || 0, 0), MAX_DELAY_SECONDS))}
              className="w-16 rounded-lg bg-surface p-1.5 text-center"
            />
          </label>
          <span className="flex-1" />
          {run.running ? (
            <button className={buttonClass} onClick={run.cancel}>
              Cancel
            </button>
          ) : (
            <button
              className={`${buttonClass} bg-field font-semibold`}
              disabled={!toolsOk}
              onClick={execute}
            >
              Execute Deeplink
            </button>
          )}
        </div>
      </div>
      <OutputPanel outcome={shownOrError} />
    </section>
  );
}
