import type { Platform } from "../lib/types";

export const PLATFORM_LABELS: Record<Platform, string> = {
  ios: "iOS Simulator",
  android: "Android Emulator",
};

interface Props {
  platforms: Platform[];
  active: Platform;
  onChange: (platform: Platform) => void;
}

/** Hidden when there is only one platform, as on Windows and Linux. */
export function PlatformTabs({ platforms, active, onChange }: Props) {
  if (platforms.length < 2) return null;
  return (
    <div role="tablist" aria-label="Platform" className="flex gap-2">
      {platforms.map((platform) => (
        <button
          key={platform}
          role="tab"
          aria-selected={platform === active}
          onClick={() => onChange(platform)}
          className={`rounded-lg px-3 py-1 text-sm ${platform === active ? "bg-panel font-semibold" : "bg-field/50 hover:bg-field"}`}
        >
          {PLATFORM_LABELS[platform]}
        </button>
      ))}
    </div>
  );
}
