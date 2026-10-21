# Releasing SimDeeplink

A release is a Git tag. Pushing `vX.Y.Z` runs `.github/workflows/release.yml`, which tests the app, builds it
(universal, ad-hoc signed, not sandboxed), and publishes a GitHub release with:

| File | What it is |
|---|---|
| `SimDeeplink.zip` | `stage/SimDeeplink.app`, `LICENSE`, `README.txt` (Gatekeeper note). The name never changes, so `.../releases/latest/download/SimDeeplink.zip` always works |
| `SimDeeplink.zip.sha256` | its checksum |
| `simdeeplink.rb` | the Homebrew cask for this version (`Scripts/release/make-cask.sh`) |

## Desktop installers (Windows, Linux)

The same tag also runs `.github/workflows/release-desktop.yml`. It builds the Tauri app (`crossplatform/`), waits for the
release above to exist and attaches:

| File | What it is |
|---|---|
| `SimDeeplink_X.Y.Z_x64-setup.exe`, `SimDeeplink_X.Y.Z_x64_en-US.msi`, `SHA256SUMS-windows.txt` | Windows installers (not code-signed) |
| `SimDeeplink_X.Y.Z_amd64.deb`, `SimDeeplink-X.Y.Z-1.x86_64.rpm`, `SHA256SUMS-linux.txt` | Debian/Ubuntu and Fedora packages (package name `sim-deeplink`) |

Before it publishes, CI (`package-desktop.yml`) installs the `.deb` on Debian 12 and Ubuntu 22.04/24.04 and the `.rpm` on
Fedora 40/41, checks the binary has no missing libraries, and removes the package again. The macOS Tauri app is built and
checked there too, but is not published until it replaces the Swift app.

## Steps

1. Merge to `main` and wait for CI to pass.
2. Set the new number in every `MARKETING_VERSION` of `SimDeeplink.xcodeproj` (app, tests and UI tests share it) **and** in
   `crossplatform/src-tauri/tauri.conf.json`, `crossplatform/src-tauri/Cargo.toml` and `crossplatform/package.json`, then check:
   `sh Scripts/release/check-version.sh 0.2.0`
3. Commit (`chore: release 0.2.0`), then tag and push:
   ```bash
   git tag v0.2.0
   git push origin main v0.2.0
   ```
4. Both release workflows fail at once if the tag and any of those versions differ.
5. Homebrew tap:
   - with a `TAP_TOKEN` repository secret (a token that can push to `alifu/homebrew-tap`) the workflow commits
     `Casks/simdeeplink.rb` itself;
   - without it, copy `simdeeplink.rb` from the release to `Casks/simdeeplink.rb` in `alifu/homebrew-tap` and push.
6. Smoke test:
   ```bash
   brew update && brew install --cask alifu/tap/simdeeplink   # or: brew upgrade --cask simdeeplink
   ```
   Launch it, check the menu bar icon, run a deeplink on an iPad simulator and an Android emulator.
   `brew uninstall --cask --zap simdeeplink` removes it again.
7. Windows and Linux (on a real machine, once per release; CI cannot see a tray): install the file from the release, then
   check that the tray icon shows, a click opens the window and a click elsewhere hides it, `adb` is found and an emulator
   is listed, a deeplink containing `&` arrives intact, a second launch focuses the first, and Quit works.

## Local dry run

```bash
sh Scripts/release/check-version.sh
xcodebuild -project SimDeeplink.xcodeproj -scheme SimDeeplink -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- ONLY_ACTIVE_ARCH=NO build
lipo -archs build/Build/Products/Release/SimDeeplink.app/Contents/MacOS/SimDeeplink    # x86_64 arm64
codesign -d --entitlements - build/Build/Products/Release/SimDeeplink.app              # no app-sandbox
sh Scripts/release/make-cask.sh 0.2.0 "$(printf 'a%.0s' $(seq 64))" | ruby -c
```

## Notes

- The app is not notarized (no paid developer account), so the first launch needs "Open Anyway"; see the README.
- Versions are plain `X.Y.Z` numbers; `check-version.sh` and `make-cask.sh` reject anything else (no `-rc` tags).
- The app must stay un-sandboxed: it runs `xcrun simctl` and `adb`. CI fails if the Release build contains the
  `app-sandbox` entitlement.
