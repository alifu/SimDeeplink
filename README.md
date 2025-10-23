<p align="center">
  <img src="./doc/main-icon.png" alt="icon" width="128"/>
</p>

# SimDeeplink (Menu Bar)


[![Swift Version](https://img.shields.io/badge/Swift-5.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS-blue.svg)](https://developer.apple.com/macos)
[![Xcode](https://img.shields.io/badge/Xcode-15+-blue.svg)](https://developer.apple.com/xcode/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)
[![Version](https://img.shields.io/badge/Version-0.0.6-yellow.svg)](https://github.com/alifu/SimDeeplink/releases)
[![Homebrew Tap](https://img.shields.io/badge/Homebrew-alifu%2Ftap-blue.svg)](https://github.com/alifu/homebrew-tap)



SimDeeplink (Deeplink Runner) is a desktop utility designed to make testing and running app deeplinks in Simulator effortless. Unlike other solutions, there’s no need to drag and drop URLs onto Simulator—you simply paste and run! The app lives comfortably in your macOS menu bar, allowing quick access at any time.

|Apple Simulator|Android Emulator|
|:---:|:---:|
|<img src="./doc/preview-app-simulator.png" alt="preview" width="500"/>|<img src="./doc/preview-app-emulator.png" alt="preview" width="500"/>|


## ✨ Features

- **Paste and Run Deeplinks Instantly:** Just paste your deeplink and run it in Simulator—no drag-and-drop required.
- **Delay:** Add delay to wait for the simulator to be ready to watch.
- **Specific Simulator Target:** Choose your right target for running deeplink.
- **Menu Bar Access:** Launch and use the app from your menu bar on any Mac desktop, for maximum convenience.
- **Simulator Booting:** The app can automatically boot the Simulator if it’s not running, so you can execute deeplinks immediately.

## 🧭 Install

With [Homebrew](https://brew.sh) (no Xcode needed; this installs the prebuilt app):

```bash
brew install --cask alifu/tap/simdeeplink
```

Open it from Launchpad, Spotlight or `open -a SimDeeplink`; the icon appears in the menu bar.

### Update and uninstall

```bash
brew update && brew upgrade --cask simdeeplink
brew uninstall --cask simdeeplink          # add --zap to also remove its settings
```

Or download `SimDeeplink.zip` from the [latest release](https://github.com/alifu/SimDeeplink/releases/latest), unzip it and
drag `SimDeeplink.app` into `/Applications`. To update that way, quit the app and replace it with the new one; to remove
it, quit it and move it to the Trash.

### "SimDeeplink can't be opened" warning

SimDeeplink isn't notarized by Apple (that needs a paid developer account), so macOS blocks it the first time you open
it. You only have to allow it once:

1. Open SimDeeplink. macOS shows a warning that it couldn't verify the app; click **Done**.
2. Open **System Settings › Privacy & Security** and scroll down to the **Security** section.
3. Next to "SimDeeplink was blocked to protect your Mac", click **Open Anyway**, then confirm with your password or
   Touch ID and click **Open Anyway** again.

Or, from the Terminal, remove the quarantine flag instead:

```bash
xattr -dr com.apple.quarantine /Applications/SimDeeplink.app
```

### Requirements

macOS 14 or later. iOS simulators need Xcode (or the Command Line Tools); Android needs the Android SDK
platform-tools (`adb`) and, to start an emulator from the app, the `emulator` package.

### Build from source

Only needed to work on SimDeeplink itself (see [Getting Started](#-getting-started)).

Maintainers: see [RELEASING.md](RELEASING.md).

## 💡 Why Use This?
- Eliminate repetitive drag-and-drop steps for deeplink testing.
- Stay focused—access the tool instantly from your menu bar.
- Works with any desktop setup.
- Streamlines the developer workflow, especially for QA and app review scenarios.

## 🧪 Roadmap

| Status | Feature |
|:-------:|-----|
|✅|**Running Deeplink:** Just paste the deeplink and GO!|
|✅|**Simulator Section:** Choose and boot the XCode Simulator without XCode (We can disabled this feature if no needed)|
|✅|**Add Timer for Deeplink Execution:** Allow users to specify a delay before running a deeplink, making it easier to wait for the simulator to be ready.|
|✅|**Distribute via Homebrew:** Publish the app through Homebrew for easy installation. Currently, run the project from source as described above.|
|✅|**Android Emulator Support:** Enable deeplink runs in Android Emulator for cross-platform testing.|
|✅|**MacOS App:** Build for MacOS (Using Swift, SwiftUI).|
|🚧|**Windows App:** Build for Windows (Using Tauri -- Rust and React).|
|🔄|**Linux App:** Build for Linux (Using Tauri -- Rust and React).|

## ⚙️ Contributing
Contributions and feedback are welcome! Please open an issue or submit a pull request with ideas or improvements.

### 🚀 Getting Started

#### Prerequisites
- Xcode 15 or later  
- MacOS 14.0+ target  
- Swift 5.9+

#### Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/alifu/SimDeeplink.git
   cd SimDeeplink
   ```
2. Open the project:

   ```bash
   open SimDeeplink.xcodeproj
   ```
3. Select the appropriate target and scheme (usually 'SimDeeplink' or similar).
4. Build and run (⌘R). The app should appear in your menu bar.

### 🧪 Running the tests

```bash
# unit tests (Swift Testing, no simulator needed)
xcodebuild -project SimDeeplink.xcodeproj -scheme SimDeeplink -destination 'platform=macOS' -only-testing:SimDeeplinkTests test

# UI tests (run the real window with canned devices, `-UITest`)
xcodebuild -project SimDeeplink.xcodeproj -scheme SimDeeplink -destination 'platform=macOS' test
```

Maintainers: see [`RELEASING.md`](./RELEASING.md) for how a release and the Homebrew cask are published.

## 🪪 License
MIT License. See [`LICENSE`](./LICENSE) for details.

---

> _Built with passion and love ❤️  
> — [@alifu](https://github.com/alifu)