# SimDeeplink (Tauri)

The cross-platform SimDeeplink: Rust backend, React + Tailwind window. It runs on macOS, Windows and Linux.

- **macOS:** menu bar popup with the iOS Simulator and Android Emulator sections.
- **Windows and Linux:** system tray popup with the Android Emulator section only (there is no iOS Simulator there).

Install instructions for users are in the [main README](../README.md#-install).

## Layout

| Path | What it is |
|---|---|
| `src/` | React UI: `components/`, `hooks/` (device list, delayed run), `lib/` (typed `invoke` wrappers, link check) |
| `src-tauri/src/device/` | Device layer without any Tauri types: `adb`, `simctl` (macOS only), command runner with timeout, parsers |
| `src-tauri/src/api/` | The commands the window calls (`platforms`, `tool_status`, `adb_paths`, `list_devices`, `boot_device`, `open_deeplink`, `quit_app`) |
| `src-tauri/src/platform/` | Per-OS window code: `macos/` (menu bar panel), `desktop.rs` (tray, positioning, single instance, no-tray fallback) |

## Develop

Needs Node 22, a current stable Rust, and on Linux:
`sudo apt install libwebkit2gtk-4.1-dev libayatana-appindicator3-dev librsvg2-dev libgtk-3-dev libssl-dev patchelf`.

```bash
npm ci
npm run tauri dev       # run the app
npm test                # UI tests (Vitest, with the Rust commands faked)
cd src-tauri && cargo test    # device layer and commands (fake command runner, no adb or Xcode needed)
```

Real-device checks are ignored by default: `cargo test -- --ignored` runs them against the `adb` on your machine.

## Build the installers

```bash
npx tauri build --bundles nsis,msi                          # Windows
npx tauri build --bundles deb,rpm                           # Linux (needs the `rpm` package for the .rpm)
npx tauri build --target universal-apple-darwin --bundles app   # macOS
```

CI builds all of them and installs the Linux packages in Debian, Ubuntu and Fedora containers; see
[`RELEASING.md`](../RELEASING.md).
