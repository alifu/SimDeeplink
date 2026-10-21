import { invoke } from "@tauri-apps/api/core";

import type { Device, Outcome, Platform, ToolStatus } from "./types";

/** One typed wrapper per Rust command (`src-tauri/src/api/commands.rs`). */
export const api = {
  init: () => invoke<void>("init"),
  platforms: () => invoke<Platform[]>("platforms"),
  toolStatus: (platform: Platform, adbPath?: string) => invoke<ToolStatus>("tool_status", { platform, adbPath }),
  adbPaths: () => invoke<string[]>("adb_paths"),
  listDevices: (platform: Platform, adbPath?: string) => invoke<Device[]>("list_devices", { platform, adbPath }),
  bootDevice: (platform: Platform, id: string, adbPath?: string) =>
    invoke<Outcome>("boot_device", { platform, id, adbPath }),
  openDeeplink: (args: { platform: Platform; url: string; target?: string; pkg?: string; adbPath?: string }) =>
    invoke<Outcome>("open_deeplink", {
      platform: args.platform,
      url: args.url,
      target: args.target,
      package: args.pkg,
      adbPath: args.adbPath,
    }),
  quit: () => invoke<void>("quit_app"),
};

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
