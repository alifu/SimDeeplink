import type { Outcome } from "../lib/types";

export function OutputPanel({ outcome }: { outcome: Outcome | null }) {
  const tone = outcome === null ? "text-ink/60" : outcome.ok ? "text-good" : "text-danger";
  return (
    <output
      data-testid="output"
      data-ok={outcome?.ok ?? ""}
      aria-live="polite"
      className={`block min-h-16 flex-1 overflow-auto whitespace-pre-wrap rounded-lg bg-field p-2 text-sm ${tone}`}
    >
      {outcome?.message ?? "Output appears here."}
    </output>
  );
}
