import { useCallback, useEffect, useRef, useState } from "react";

import { api, errorMessage } from "../lib/api";
import type { Device, Platform, ToolStatus } from "../lib/types";

export interface DevicesState {
  devices: Device[];
  status: ToolStatus | null;
  loading: boolean;
  error: string | null;
  refresh: () => Promise<void>;
}

/** Devices of one platform, read again whenever `adbPath` changes or `refresh` is called. */
export function useDevices(platform: Platform, adbPath: string | undefined, ready: boolean): DevicesState {
  const [devices, setDevices] = useState<Device[]>([]);
  const [status, setStatus] = useState<ToolStatus | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Only the latest request may write, so a slow earlier answer cannot overwrite a newer one.
  const latest = useRef(0);

  const refresh = useCallback(async () => {
    const request = ++latest.current;
    setLoading(true);
    try {
      const nextStatus = await api.toolStatus(platform, adbPath);
      const nextDevices = nextStatus.ok ? await api.listDevices(platform, adbPath) : [];
      if (request !== latest.current) return;
      setStatus(nextStatus);
      setDevices(nextDevices);
      setError(null);
    } catch (e) {
      if (request !== latest.current) return;
      setError(errorMessage(e));
    } finally {
      if (request === latest.current) setLoading(false);
    }
  }, [platform, adbPath]);

  useEffect(() => {
    if (ready) void refresh();
  }, [ready, refresh]);

  return { devices, status, loading, error, refresh };
}
