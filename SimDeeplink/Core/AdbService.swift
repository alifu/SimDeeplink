//
//  AdbService.swift
//  SimDeeplink
//

import Foundation

struct AdbService {
    static let avdPrefix = "avd:"
    static let missingAdbMessage = "adb not found. Install the Android SDK platform-tools or set ANDROID_HOME."
    static let missingEmulatorMessage = "Android emulator not found. Install it with the Android SDK or set ANDROID_HOME."

    private static let androidRuntime = "Android"
    private static let fallbackSearchPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    private let runner: CommandRunning
    private let environment: [String: String]
    private let homeDirectory: String
    private let isExecutable: (String) -> Bool
    private let preferredAdbPath: String?

    init(
        preferredAdbPath: String? = nil,
        runner: CommandRunning = ProcessCommandRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        isExecutable: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.runner = runner
        self.environment = environment
        self.homeDirectory = homeDirectory
        self.isExecutable = isExecutable
        self.preferredAdbPath = preferredAdbPath.flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Tool lookup

    /// A GUI app does not inherit the shell PATH, so the SDK folders are checked first.
    var adbPath: String? { preferredAdbPath ?? locate("adb", in: "platform-tools") }
    var emulatorPath: String? { locate("emulator", in: "emulator") }

    var missingToolMessage: String? { adbPath == nil ? Self.missingAdbMessage : nil }

    /// Every adb found, in lookup order, so the user can pick one when several SDKs are installed.
    var adbPaths: [String] {
        var seen = Set<String>()
        return candidates("adb", in: "platform-tools").filter(isExecutable).filter { seen.insert($0).inserted }
    }

    private func locate(_ tool: String, in sdkSubfolder: String) -> String? {
        candidates(tool, in: sdkSubfolder).first(where: isExecutable)
    }

    private func candidates(_ tool: String, in sdkSubfolder: String) -> [String] {
        let sdkRoots = [environment["ANDROID_HOME"], environment["ANDROID_SDK_ROOT"], "\(homeDirectory)/Library/Android/sdk"]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let pathFolders = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + Self.fallbackSearchPaths

        return sdkRoots.map { "\($0)/\(sdkSubfolder)/\(tool)" } + pathFolders.map { "\($0)/\(tool)" }
    }

    // MARK: - Devices

    /// Running devices first, then the emulators that are installed but not started.
    func listDevices() -> [Simulator] {
        guard let adb = adbPath else { return [] }

        let result = runner.run(adb, arguments: ["devices", "-l"])
        guard result.succeeded else {
            AppLog.device.error("adb devices failed: \(result.trimmedOutput, privacy: .public)")
            return []
        }

        let running = AdbParser.parseDevices(result.output)
            .filter { $0.state == "device" }
            .map { device in (device: device, avdName: avdName(of: device.serial, adb: adb)) }

        let runningSimulators = running.map { entry in
            Simulator(
                name: entry.avdName ?? entry.device.model?.replacingOccurrences(of: "_", with: " ") ?? entry.device.serial,
                udid: entry.device.serial,
                runtime: Self.androidRuntime,
                isBooted: true,
                type: .android
            )
        }

        let runningAvdNames = Set(running.compactMap(\.avdName))
        let stoppedSimulators = installedAvdNames()
            .filter { !runningAvdNames.contains($0) }
            .map { Simulator(name: $0, udid: Self.avdPrefix + $0, runtime: Self.androidRuntime, isBooted: false, type: .android) }

        return runningSimulators + stoppedSimulators
    }

    private func installedAvdNames() -> [String] {
        guard let emulator = emulatorPath else { return [] }
        let result = runner.run(emulator, arguments: ["-list-avds"])
        return result.succeeded ? AdbParser.parseAvdNames(result.output) : []
    }

    private func avdName(of serial: String, adb: String) -> String? {
        guard serial.hasPrefix("emulator-") else { return nil }
        let console = runner.run(adb, arguments: ["-s", serial, "emu", "avd", "name"])
        if console.succeeded, let name = AdbParser.parseAvdName(fromEmuOutput: console.output) { return name }

        // The emulator console can be unreachable; the system property gives the same name, so a running AVD is
        // never listed a second time as stopped.
        let property = runner.run(adb, arguments: ["-s", serial, "shell", "getprop", "ro.boot.qemu.avd_name"])
        let name = property.trimmedOutput
        return property.succeeded && name.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil ? name : nil
    }

    // MARK: - Actions

    /// `package` limits the intent to one app (`am start -p`).
    func openURL(_ url: String, on serial: String, package: String? = nil) -> CommandResult {
        guard let adb = adbPath else { return .failure(Self.missingAdbMessage) }

        // `adb shell` joins its arguments and hands them to the device shell, so the URL must be quoted.
        let arguments = [
            "-s", serial, "shell", "am", "start", "-W",
            "-a", "android.intent.action.VIEW",
            "-d", Self.shellQuoted(url)
        ] + (package.map { ["-p", Self.shellQuoted($0)] } ?? [])
        let result = runner.run(adb, arguments: arguments)

        // `am start` exits 0 even when no app handles the URL. Only a line that starts with "Error" counts,
        // because the output echoes the URL, which may itself contain that word.
        if result.succeeded && result.output.range(of: "(?m)^Error", options: .regularExpression) != nil {
            return CommandResult(output: result.output, exitCode: 1)
        }
        return result
    }

    func boot(avdNamed name: String, pollInterval: TimeInterval = 2, timeout: TimeInterval = 120) -> CommandResult {
        guard let adb = adbPath else { return .failure(Self.missingAdbMessage) }
        guard let emulator = emulatorPath else { return .failure(Self.missingEmulatorMessage) }

        if isBooted(avdNamed: name, adb: adb) {
            return CommandResult(output: "\(name) is already running", exitCode: 0)
        }
        guard runner.launchDetached(emulator, arguments: ["-avd", name]) else {
            return .failure("Could not start emulator \(name)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isBooted(avdNamed: name, adb: adb) {
                return CommandResult(output: "Booted \(name)", exitCode: 0)
            }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return .failure("Timed out waiting for \(name) to boot")
    }

    private func isBooted(avdNamed name: String, adb: String) -> Bool {
        let devices = AdbParser.parseDevices(runner.run(adb, arguments: ["devices"]).output)
            .filter { $0.state == "device" && $0.serial.hasPrefix("emulator-") }

        return devices.contains { device in
            guard avdName(of: device.serial, adb: adb) == name else { return false }
            let boot = runner.run(adb, arguments: ["-s", device.serial, "shell", "getprop", "sys.boot_completed"])
            return boot.trimmedOutput == "1"
        }
    }

    /// Wraps the text in single quotes for a POSIX shell.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
