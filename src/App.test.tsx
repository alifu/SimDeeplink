import { act, render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";

import App from "./App";
import { android, callsTo, iphone, mockBackend } from "./test/mockBackend";

const ADB = "/sdk/platform-tools/adb";

async function renderReady() {
  render(<App />);
  await screen.findByLabelText("Deeplink URL");
}

async function typeUrl(user: ReturnType<typeof userEvent.setup>, url: string) {
  await user.clear(screen.getByLabelText("Deeplink URL"));
  await user.type(screen.getByLabelText("Deeplink URL"), url);
}

afterEach(() => vi.useRealTimers());

describe("platforms", () => {
  it("shows no tabs and only Android controls when the backend offers Android alone", async () => {
    mockBackend({ platforms: ["android"] });

    await renderReady();

    expect(screen.queryByRole("tablist")).not.toBeInTheDocument();
    expect(screen.getByLabelText("ADB Executable")).toBeInTheDocument();
    expect(screen.queryByRole("tab", { name: /iOS/ })).not.toBeInTheDocument();
  });

  it("shows an iOS tab first on macOS and hides the Android-only fields there", async () => {
    mockBackend({ platforms: ["ios", "android"], devices: { ios: [iphone("iPad Pro 13-inch (M5)", "U1")] } });

    await renderReady();

    expect(screen.getByRole("tab", { name: "iOS Simulator", selected: true })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Android Emulator" })).toBeInTheDocument();
    expect(screen.queryByLabelText("ADB Executable")).not.toBeInTheDocument();
    expect(await screen.findByRole("option", { name: "iPad Pro 13-inch (M5)" })).toBeInTheDocument();
  });

  it("switches to the Android section from the tab", async () => {
    mockBackend({ platforms: ["ios", "android"] });
    const user = userEvent.setup();
    await renderReady();

    await user.click(screen.getByRole("tab", { name: "Android Emulator" }));

    expect(await screen.findByLabelText("ADB Executable")).toBeInTheDocument();
  });
});

describe("deeplink", () => {
  it("rejects a text that is not a link without calling the backend", async () => {
    const calls = mockBackend({ devices: { android: [android("Pixel 8", "emulator-5554", true)] } });
    const user = userEvent.setup();
    await renderReady();
    await screen.findByRole("option", { name: /Pixel 8/ });

    await typeUrl(user, "not a link");
    await user.click(screen.getByRole("button", { name: "Execute Deeplink" }));

    expect(screen.getByTestId("output")).toHaveTextContent("Invalid Deeplink URL");
    expect(screen.getByTestId("output")).toHaveAttribute("data-ok", "false");
    expect(callsTo(calls, "open_deeplink")).toHaveLength(0);
  });

  it("sends the link with the chosen emulator, package and adb, and shows success", async () => {
    const calls = mockBackend({
      devices: { android: [android("Pixel 8", "emulator-5554", true), android("Tablet", "avd:Tablet", false)] },
      open: { ok: true, message: "Opened myapp://a" },
    });
    const user = userEvent.setup();
    await renderReady();
    await screen.findByRole("option", { name: /Pixel 8/ });

    await typeUrl(user, "myapp://a?b=1&c=2");
    await user.type(screen.getByLabelText("Package Target"), " com.example ");
    await user.selectOptions(screen.getByLabelText("Device"), "emulator-5554");
    await user.click(screen.getByRole("button", { name: "Execute Deeplink" }));

    await waitFor(() => expect(screen.getByTestId("output")).toHaveTextContent("Opened myapp://a"));
    expect(screen.getByTestId("output")).toHaveAttribute("data-ok", "true");
    expect(callsTo(calls, "open_deeplink")[0]).toEqual({
      platform: "android",
      url: "myapp://a?b=1&c=2",
      target: "emulator-5554",
      package: "com.example",
      adbPath: ADB,
    });
  });

  it("shows a failure from the backend in red", async () => {
    mockBackend({
      devices: { android: [android("Pixel 8", "emulator-5554", true)] },
      open: { ok: false, message: "Error: Activity not started" },
    });
    const user = userEvent.setup();
    await renderReady();
    await screen.findByRole("option", { name: /Pixel 8/ });

    await typeUrl(user, "myapp://x");
    await user.click(screen.getByRole("button", { name: "Execute Deeplink" }));

    await waitFor(() => expect(screen.getByTestId("output")).toHaveTextContent("Activity not started"));
    expect(screen.getByTestId("output")).toHaveAttribute("data-ok", "false");
    expect(screen.getByTestId("output")).toHaveClass("text-danger");
  });

  it("clears the link and the message with the eraser", async () => {
    mockBackend();
    const user = userEvent.setup();
    await renderReady();
    await typeUrl(user, "bad");
    await user.click(screen.getByRole("button", { name: "Execute Deeplink" }));

    await user.click(screen.getByRole("button", { name: "Clear URL" }));

    expect(screen.getByLabelText("Deeplink URL")).toHaveValue("");
    expect(screen.getByTestId("output")).toHaveTextContent("Output appears here.");
  });
});

describe("delay", () => {
  it("counts down, then runs once", async () => {
    const calls = mockBackend({ devices: { android: [android("Pixel 8", "emulator-5554", true)] } });
    const user = userEvent.setup();
    await renderReady();
    await screen.findByRole("option", { name: /Pixel 8/ });
    await typeUrl(user, "myapp://x");
    await user.clear(screen.getByLabelText("Delay"));
    await user.type(screen.getByLabelText("Delay"), "2");

    vi.useFakeTimers({ shouldAdvanceTime: false });
    await act(async () => screen.getByRole("button", { name: "Execute Deeplink" }).click());
    expect(screen.getByTestId("output")).toHaveTextContent("Executing in 2s...");
    expect(callsTo(calls, "open_deeplink")).toHaveLength(0);

    await act(async () => vi.advanceTimersByTimeAsync(1000));
    expect(screen.getByTestId("output")).toHaveTextContent("Executing in 1s...");

    await act(async () => vi.advanceTimersByTimeAsync(1000));
    vi.useRealTimers();
    await waitFor(() => expect(callsTo(calls, "open_deeplink")).toHaveLength(1));
  });

  it("does not run when cancelled during the countdown", async () => {
    const calls = mockBackend({ devices: { android: [android("Pixel 8", "emulator-5554", true)] } });
    const user = userEvent.setup();
    await renderReady();
    await screen.findByRole("option", { name: /Pixel 8/ });
    await typeUrl(user, "myapp://x");
    await user.clear(screen.getByLabelText("Delay"));
    await user.type(screen.getByLabelText("Delay"), "1");
    vi.useFakeTimers({ shouldAdvanceTime: false });

    await act(async () => screen.getByRole("button", { name: "Execute Deeplink" }).click());
    await act(async () => screen.getByRole("button", { name: "Cancel" }).click());
    await act(async () => vi.advanceTimersByTimeAsync(5000));

    expect(callsTo(calls, "open_deeplink")).toHaveLength(0);
    expect(screen.getByRole("button", { name: "Execute Deeplink" })).toBeInTheDocument();
  });

  it("keeps the delay between 0 and 10 seconds", async () => {
    mockBackend();
    const user = userEvent.setup();
    await renderReady();

    await user.clear(screen.getByLabelText("Delay"));
    await user.type(screen.getByLabelText("Delay"), "99");

    expect(screen.getByLabelText("Delay")).toHaveValue(10);
  });
});

describe("devices", () => {
  it("starts a stopped emulator and reads the list again", async () => {
    const calls = mockBackend({ devices: { android: [android("Tablet", "avd:Tablet", false)] }, boot: { ok: true, message: "Booted Tablet" } });
    const user = userEvent.setup();
    await renderReady();
    await screen.findByRole("option", { name: /Tablet/ });
    const start = screen.getByRole("button", { name: "Start device" });
    expect(start).toBeDisabled();

    await user.selectOptions(screen.getByLabelText("Device"), "avd:Tablet");
    await user.click(start);

    await waitFor(() => expect(screen.getByTestId("output")).toHaveTextContent("Booted Tablet"));
    expect(callsTo(calls, "boot_device")[0]).toEqual({ platform: "android", id: "avd:Tablet", adbPath: ADB });
    await waitFor(() => expect(callsTo(calls, "list_devices").length).toBeGreaterThan(1));
  });

  it("does not offer to start a running emulator", async () => {
    mockBackend({ devices: { android: [android("Pixel 8", "emulator-5554", true)] } });
    const user = userEvent.setup();
    await renderReady();
    await screen.findByRole("option", { name: /Pixel 8/ });

    await user.selectOptions(screen.getByLabelText("Device"), "emulator-5554");

    expect(screen.getByRole("button", { name: "Start device" })).toBeDisabled();
  });

  it("explains a missing adb and blocks the run button", async () => {
    mockBackend({
      adbPaths: [],
      status: { android: { platform: "android", ok: false, message: "adb not found. Install the Android SDK platform-tools or set ANDROID_HOME." } },
    });

    await renderReady();

    expect(await screen.findByTestId("output")).toHaveTextContent("adb not found");
    expect(screen.getByRole("button", { name: "Execute Deeplink" })).toBeDisabled();
  });

  it("uses the adb picked in the list when reading devices", async () => {
    const calls = mockBackend({ adbPaths: [ADB, "/other/adb"] });
    const user = userEvent.setup();
    await renderReady();

    await user.selectOptions(screen.getByLabelText("ADB Executable"), "/other/adb");

    await waitFor(() => expect(callsTo(calls, "list_devices").slice(-1)[0]).toEqual({ platform: "android", adbPath: "/other/adb" }));
  });

  it("quits through the backend", async () => {
    const calls = mockBackend();
    const user = userEvent.setup();
    await renderReady();

    await user.click(screen.getByRole("button", { name: "Quit SimDeeplink" }));

    expect(callsTo(calls, "quit_app")).toHaveLength(1);
  });
});
