# Releasing SimDeeplink

A release is a Git tag. Pushing `vX.Y.Z` runs `.github/workflows/release.yml`. It checks the version, builds the Tauri
app on all three systems (`package-desktop.yml`), installs the Linux packages in containers, and only then publishes one
GitHub release with:

| File | What it is |
|---|---|
| `SimDeeplink.zip` | `stage/SimDeeplink.app` (universal, ad-hoc signed), `LICENSE`, `README.txt` (Gatekeeper note). The name never changes, so `.../releases/latest/download/SimDeeplink.zip` always works |
| `SimDeeplink.zip.sha256` | its checksum |
| `simdeeplink.rb` | the Homebrew cask for this version (`Scripts/release/make-cask.sh`) |
| `SimDeeplink_X.Y.Z_x64-setup.exe`, `SimDeeplink_X.Y.Z_x64_en-US.msi`, `SHA256SUMS-windows.txt` | Windows installers (not code-signed) |
| `SimDeeplink_X.Y.Z_amd64.deb`, `SimDeeplink-X.Y.Z-1.x86_64.rpm`, `SHA256SUMS-linux.txt` | Debian/Ubuntu and Fedora packages (package name `sim-deeplink`) |

The `.deb` is installed and removed on Debian 12 and Ubuntu 22.04/24.04, the `.rpm` on Fedora 40/41; a missing library
fails the release before anything is published.

## Steps

1. Merge to `main` and wait for CI to pass.
2. Set the new number in `src-tauri/tauri.conf.json`, `src-tauri/Cargo.toml` and `package.json`, run `npm install` and
   `cargo check` (so `package-lock.json` and `Cargo.lock` follow), then check:
   `sh Scripts/release/check-version.sh 0.2.0`
3. Commit (`chore: release 0.2.0`), then tag and push:
   ```bash
   git tag v0.2.0
   git push origin main v0.2.0
   ```
4. The Release workflow fails at once if the tag and those versions differ.
5. Homebrew tap:
   - with a `TAP_TOKEN` repository secret (a token that can push to `alifu/homebrew-tap`) the workflow commits
     `Casks/simdeeplink.rb` itself;
   - without it, copy `simdeeplink.rb` from the release to `Casks/simdeeplink.rb` in `alifu/homebrew-tap` and push.
6. macOS smoke test:
   ```bash
   brew update && brew upgrade --cask simdeeplink     # or: brew install --cask alifu/tap/simdeeplink
   ```
   Launch it, check the menu bar icon, run a deeplink on an iPad simulator and an Android emulator.
   `brew uninstall --cask --zap simdeeplink` removes it again.
7. Windows and Linux (on a real machine; CI cannot see a tray): install the file from the release, then check that the
   tray icon shows, a click opens the window and a click elsewhere hides it, `adb` is found and an emulator is listed, a
   deeplink containing `&` arrives intact, a second launch focuses the first, and Quit works.

## Local dry run (macOS)

```bash
sh Scripts/release/check-version.sh
npx tauri build --target universal-apple-darwin --bundles app
app=src-tauri/target/universal-apple-darwin/release/bundle/macos/SimDeeplink.app
lipo -archs "$app/Contents/MacOS/simdeeplink"     # x86_64 arm64
codesign -dv "$app"                               # Signature=adhoc, Identifier=com.alifu.SimDeeplink
sh Scripts/release/make-cask.sh 0.2.0 "$(printf 'a%.0s' $(seq 64))" | ruby -c
```

## Notes

- Nothing is notarized or code-signed (no paid accounts), so the first launch needs "Open Anyway" on macOS and
  "Run anyway" on Windows; see the README.
- Versions are plain `X.Y.Z` numbers; `check-version.sh` and `make-cask.sh` reject anything else (no `-rc` tags).
- The app is not sandboxed: it runs `xcrun simctl` and `adb`.
- The Swift app (up to 0.0.6) lives on the `legacy` branch; it has its own `release.yml` there for hotfixes.
