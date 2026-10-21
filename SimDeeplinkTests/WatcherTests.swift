//
//  WatcherTests.swift
//  SimDeeplinkTests
//

import Foundation
import Testing
@testable import SimDeeplink

struct SimulatorWatcherTests {
    @Test("Refresh lists iPhones and iPads, with the booted ones also in the target list")
    func refreshPublishesDevices() async {
        let watcher = SimulatorWatcher(service: SimctlService(runner: Fixtures.standardRunner()))

        await withCheckedContinuation { continuation in
            watcher.refreshSimulators { continuation.resume() }
        }

        #expect(Set(watcher.simulators.map(\.type)) == [.iPhone, .iPad])
        #expect(watcher.bootedSimulators.map(\.udid) == [Fixtures.iphone17Pro])
    }

    @Test("A deeplink goes to the chosen simulator")
    func deeplinkTarget() async {
        let runner = FakeCommandRunner { _, _ in CommandResult(output: "", exitCode: 0) }
        let watcher = SimulatorWatcher(service: SimctlService(runner: runner))

        let message = await watcher.runDeeplink(url: "myapp://x", target: Fixtures.ipadPro13M5)

        #expect(runner.calls == [["/usr/bin/xcrun", "simctl", "openurl", Fixtures.ipadPro13M5, "myapp://x"]])
        #expect(message == "Opened myapp://x")
    }

    @Test("A failed deeplink says why")
    func deeplinkFailure() async {
        let runner = FakeCommandRunner { _, _ in CommandResult(output: "Invalid device: x", exitCode: 164) }
        let watcher = SimulatorWatcher(service: SimctlService(runner: runner))

        let message = await watcher.runDeeplink(url: "myapp://x", target: "x")

        #expect(message.contains("Failed to open"))
        #expect(message.contains("Invalid device: x"))
    }
}

struct EmulatorWatcherTests {
    private func makeWatcher(_ runner: FakeCommandRunner) -> EmulatorWatcher {
        EmulatorWatcher(makeService: { _ in Fixtures.adbService(runner: runner) })
    }

    @Test("Without a target the only running emulator is used")
    func singleRunningEmulator() async {
        let runner = Fixtures.standardRunner()
        let message = await makeWatcher(runner).runDeeplink(url: "myapp://x", adbPath: "")

        #expect(runner.calls.contains { $0.contains("-s") && $0.contains("emulator-5554") && $0.contains("start") })
        #expect(!message.hasPrefix("Failed"))
    }

    @Test("Without a target and without a running emulator the user is told so")
    func noRunningEmulator() async {
        let runner = FakeCommandRunner { _, _ in CommandResult(output: "List of devices attached\n", exitCode: 0) }

        let message = await makeWatcher(runner).runDeeplink(url: "myapp://x", adbPath: "")

        #expect(message == EmulatorWatcher.noEmulatorMessage)
    }

    @Test("Several running emulators need an explicit target")
    func severalRunningEmulators() async {
        let runner = FakeCommandRunner { executable, arguments in
            if arguments.contains("emu") { return CommandResult(output: "A\nOK\n", exitCode: 0) }
            return CommandResult(
                output: "List of devices attached\nemulator-5554 device\nemulator-5556 device\n",
                exitCode: 0
            )
        }

        let message = await makeWatcher(runner).runDeeplink(url: "myapp://x", adbPath: "")

        #expect(message == EmulatorWatcher.severalEmulatorsMessage)
    }

    @Test("The package target is passed on")
    func packageTarget() async {
        let runner = Fixtures.standardRunner()
        _ = await makeWatcher(runner).runDeeplink(url: "myapp://x", adbPath: "", packageTarget: "com.example", emulatorTarget: "emulator-5554")

        #expect(runner.calls.contains { $0.suffix(2) == ["-p", "'com.example'"] })
    }

    @Test("A missing adb is explained")
    func missingAdb() async {
        let watcher = EmulatorWatcher(makeService: { _ in Fixtures.adbService(runner: FakeCommandRunner(), installed: []) })

        let message = await watcher.runDeeplink(url: "myapp://x", adbPath: "")

        #expect(message == AdbService.missingAdbMessage)
    }
}

struct EmulatorModelTests {
    @Test("A running emulator keeps its serial, a stopped AVD has none")
    func mapsFromAndroidDevices() {
        let running = Emulator(Simulator(name: "Pixel", udid: "emulator-5554", runtime: "Android", isBooted: true, type: .android))
        let stopped = Emulator(Simulator(name: "Tablet", udid: "avd:Tablet", runtime: "Android", isBooted: false, type: .android))

        #expect(running.serial == "emulator-5554")
        #expect(running.isOnline)
        #expect(running.id == "emulator-5554")
        #expect(stopped.serial.isEmpty)
        #expect(!stopped.isOnline)
        #expect(stopped.id == "avd:Tablet")
    }

    @Test("The title shows state and, when running, the serial")
    func title() {
        #expect(Emulator(name: "Pixel", serial: "emulator-5554", isOnline: true).title == "🟢 Pixel (emulator-5554)")
        #expect(Emulator(name: "Tablet", serial: "", isOnline: false).title == "⚪️ Tablet")
    }
}

struct AdbServicePickerTests {
    @Test("Lists every adb once, in lookup order")
    func adbPaths() {
        let service = AdbService(
            runner: FakeCommandRunner(),
            environment: ["ANDROID_HOME": "/sdk", "PATH": "/sdk/platform-tools:/usr/local/bin"],
            homeDirectory: "/home",
            isExecutable: { ["/sdk/platform-tools/adb", "/usr/local/bin/adb"].contains($0) }
        )

        #expect(service.adbPaths == ["/sdk/platform-tools/adb", "/usr/local/bin/adb"])
    }

    @Test("A chosen adb wins over the lookup")
    func preferredAdb() {
        let service = AdbService(preferredAdbPath: "/custom/adb", runner: FakeCommandRunner(), environment: [:], homeDirectory: "/h", isExecutable: { _ in true })

        #expect(service.adbPath == "/custom/adb")
    }
}

struct RefreshCoalescingTests {
    @Test("A refresh asked for mid-refresh still completes, after a second read")
    func requestDuringRefreshIsNotDropped() async {
        let runner = Fixtures.standardRunner()
        let watcher = SimulatorWatcher(service: SimctlService(runner: runner))

        await withCheckedContinuation { continuation in
            watcher.refreshSimulators {}
            watcher.refreshSimulators { continuation.resume() }
        }

        #expect(!watcher.simulators.isEmpty)
        let listCalls = runner.calls.filter { $0.contains("devices") }.count
        #expect(listCalls == 2)
    }
}
