import { mockIPC } from "@tauri-apps/api/mocks";
import { vi } from "vitest";

import type { Device, Outcome, Platform, ToolStatus } from "../lib/types";

export const android = (name: string, id: string, isBooted: boolean): Device => ({
  name,
  id,
  runtime: "Android",
  isBooted,
  kind: "android",
});

export const iphone = (name: string, id: string, isBooted = false): Device => ({
  name,
  id,
  runtime: "iOS 26.0",
  isBooted,
  kind: "iphone",
});

export interface Backend {
  platforms?: Platform[];
  adbPaths?: string[];
  devices?: Partial<Record<Platform, Device[]>>;
  status?: Partial<Record<Platform, ToolStatus>>;
  open?: Outcome;
  boot?: Outcome;
}

/** Fakes the Rust commands and returns a spy that records every call as `[command, args]`. */
export function mockBackend(backend: Backend = {}) {
  const calls = vi.fn<(command: string, args: unknown) => void>();
  mockIPC((command, args) => {
    calls(command, args);
    const platform = (args as { platform?: Platform } | undefined)?.platform ?? "android";
    switch (command) {
      case "platforms":
        return backend.platforms ?? ["android"];
      case "adb_paths":
        return backend.adbPaths ?? ["/sdk/platform-tools/adb"];
      case "tool_status":
        return backend.status?.[platform] ?? { platform, ok: true, message: null };
      case "list_devices":
        return backend.devices?.[platform] ?? [];
      case "boot_device":
        return backend.boot ?? { ok: true, message: "Booted" };
      case "open_deeplink":
        return backend.open ?? { ok: true, message: "Opened" };
      default:
        return undefined;
    }
  });
  return calls;
}

export const callsTo = (calls: ReturnType<typeof mockBackend>, command: string) =>
  calls.mock.calls.filter(([name]) => name === command).map(([, args]) => args as Record<string, unknown>);
