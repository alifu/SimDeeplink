import type { Device } from "../lib/types";

interface Props {
  devices: Device[];
  value: string;
  onChange: (id: string) => void;
  disabled?: boolean;
}

/** Devices grouped by runtime (iOS 26.0, Android...), running ones marked. */
export function DeviceSelect({ devices, value, onChange, disabled }: Props) {
  const groups = new Map<string, Device[]>();
  for (const device of devices) groups.set(device.runtime, [...(groups.get(device.runtime) ?? []), device]);
  return (
    <select
      aria-label="Device"
      value={value}
      disabled={disabled}
      onChange={(e) => onChange(e.target.value)}
      className="min-w-0 flex-1 rounded-lg bg-surface p-1.5 text-sm"
    >
      <option value="">{devices.length === 0 ? "No devices found" : "Any running device"}</option>
      {[...groups].map(([runtime, list]) => (
        <optgroup key={runtime} label={runtime}>
          {list.map((device) => (
            <option key={device.id} value={device.id}>
              {device.isBooted ? "● " : ""}
              {device.name}
            </option>
          ))}
        </optgroup>
      ))}
    </select>
  );
}
