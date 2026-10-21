export type Platform = "ios" | "android";

export interface Device {
  name: string;
  id: string;
  runtime: string;
  isBooted: boolean;
  kind: "iphone" | "ipad" | "watch" | "tv" | "android" | "unknown";
}

/** What an action reports; `ok: false` is shown in red. */
export interface Outcome {
  ok: boolean;
  message: string;
}

export interface ToolStatus {
  platform: Platform;
  ok: boolean;
  message: string | null;
}
