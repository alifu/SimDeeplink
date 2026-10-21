import type { ReactNode } from "react";

/** A label beside its control, with the control filling the row. */
export function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="flex items-center gap-2 text-sm">
      <span className="w-40 shrink-0">{label}</span>
      {children}
    </label>
  );
}

export const inputClass = "min-w-0 flex-1 rounded-lg bg-surface p-1.5 text-sm placeholder:text-ink/40";
export const buttonClass =
  "rounded-lg bg-surface px-3 py-1.5 text-sm hover:bg-field disabled:cursor-not-allowed disabled:opacity-40";
