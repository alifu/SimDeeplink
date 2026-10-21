//
//  AdbTests.swift
//  SimDeeplinkTests
//

import Testing
@testable import SimDeeplink

struct AdbParserTests {
    @Test("Parses devices and skips daemon notices")
    func parsesDevices() {
        let devices = AdbParser.parseDevices(Fixtures.adbDevices)

        #expect(devices.map(\.serial) == ["emulator-5554", "emulator-5556", "R58M12345XY"])
        #expect(devices.map(\.state) == ["device", "offline", "device"])
        #expect(devices.first?.model == "sdk_gphone64_arm64")
        #expect(devices[1].model == nil)
    }

    @Test("Ignores version-mismatch noise and blank output")
    func ignoresNoise() {
        let noise = "adb server version (41) doesn't match this client (40); killing...\n"

        #expect(AdbParser.parseDevices(noise).isEmpty)
        #expect(AdbParser.parseDevices("").isEmpty)
    }

    @Test("Parses AVD names and drops log lines")
    func parsesAvdNames() {
        let output = "INFO    | Storing crashdata\nPixel_8_API_35\nMedium_Phone.API-36\n\n"

        #expect(AdbParser.parseAvdNames(output) == ["Pixel_8_API_35", "Medium_Phone.API-36"])
    }

    @Test("Reads the AVD name before OK")
    func parsesEmuName() {
        #expect(AdbParser.parseAvdName(fromEmuOutput: "Pixel_8_API_35\r\nOK\r\n") == "Pixel_8_API_35")
        #expect(AdbParser.parseAvdName(fromEmuOutput: "OK\n") == nil)
    }
}

struct AdbServiceTests {
    @Test("Finds adb in ANDROID_HOME before PATH")
    func prefersAndroidHome() {
        let service = AdbService(
            runner: FakeCommandRunner(),
            environment: ["ANDROID_HOME": "/sdk", "PATH": "/usr/bin"],
            homeDirectory: "/home",
            isExecutable: { ["/sdk/platform-tools/adb", "/usr/bin/adb"].contains($0) }
        )

        #expect(service.adbPath == "/sdk/platform-tools/adb")
    }

    @Test("Falls back to the default SDK folder, then PATH")
    func fallsBack() {
        let defaultSdk = AdbService(
            runner: FakeCommandRunner(), environment: [:], homeDirectory: "/home",
            isExecutable: { $0 == "/home/Library/Android/sdk/platform-tools/adb" }
        )
        let onPath = AdbService(
            runner: FakeCommandRunner(), environment: ["PATH": "/a:/b"], homeDirectory: "/home",
            isExecutable: { $0 == "/b/adb" }
        )

        #expect(defaultSdk.adbPath == "/home/Library/Android/sdk/platform-tools/adb")
        #expect(onPath.adbPath == "/b/adb")
    }

    @Test("Explains when adb is missing and never runs anything")
    func missingAdb() {
        let runner = FakeCommandRunner()
        let service = Fixtures.adbService(runner: runner, installed: [])

        #expect(service.missingToolMessage == AdbService.missingAdbMessage)
        #expect(service.listDevices().isEmpty)
        #expect(!service.openURL("myapp://x", on: "emulator-5554").succeeded)
        #expect(runner.calls.isEmpty)
    }

    @Test("Lists running emulators first, then stopped AVDs without duplicates")
    func listsRunningThenStopped() {
        let devices = Fixtures.adbService(runner: Fixtures.standardRunner()).listDevices()

        #expect(devices.map(\.name) == ["Pixel_8_API_35", "Tablet_API_35"])
        #expect(devices.map(\.udid) == ["emulator-5554", "avd:Tablet_API_35"])
        #expect(devices.map(\.isBooted) == [true, false])
        #expect(devices.allSatisfy { $0.type == .android })
    }

    @Test("Uses the model name for physical devices and skips offline ones")
    func physicalDevice() {
        let runner = FakeCommandRunner { executable, arguments in
            executable == Fixtures.adbPath && !arguments.contains("emu")
                ? CommandResult(output: Fixtures.adbDevices, exitCode: 0)
                : CommandResult(output: "", exitCode: 1)
        }

        let devices = Fixtures.adbService(runner: runner).listDevices()

        #expect(devices.contains { $0.udid == "R58M12345XY" && $0.name == "SM G973F" })
        #expect(!devices.contains { $0.udid == "emulator-5556" })
    }

    @Test("Opens a deeplink with a quoted URL on the chosen device")
    func openURLArguments() {
        let runner = FakeCommandRunner { _, _ in CommandResult(output: "Starting: Intent { }\nStatus: ok", exitCode: 0) }
        let url = "myapp://x?a=1&b=it's;rm -rf /"

        let result = Fixtures.adbService(runner: runner).openURL(url, on: "emulator-5554")

        #expect(result.succeeded)
        #expect(runner.calls == [[
            Fixtures.adbPath, "-s", "emulator-5554", "shell", "am", "start", "-W",
            "-a", "android.intent.action.VIEW",
            "-d", "'myapp://x?a=1&b=it'\\''s;rm -rf /'"
        ]])
    }

    @Test("Treats an unresolved intent as a failure even though am exits 0")
    func unresolvedIntent() {
        let runner = FakeCommandRunner { _, _ in
            CommandResult(output: "Error: Activity not started, unable to resolve Intent", exitCode: 0)
        }

        #expect(!Fixtures.adbService(runner: runner).openURL("myapp://x", on: "emulator-5554").succeeded)
    }

    @Test("A URL that contains the word Error is not mistaken for a failure")
    func errorWordInUrl() {
        let runner = FakeCommandRunner { _, _ in
            CommandResult(output: "Starting: Intent { dat=myapp://screen?name=ErrorPage }\nStatus: ok", exitCode: 0)
        }

        #expect(Fixtures.adbService(runner: runner).openURL("myapp://screen?name=ErrorPage", on: "emulator-5554").succeeded)
    }

    @Test("Quotes single quotes for the device shell")
    func shellQuoting() {
        #expect(AdbService.shellQuoted("plain") == "'plain'")
        #expect(AdbService.shellQuoted("a'b") == "'a'\\''b'")
    }

    @Test("Boot launches the emulator and waits for sys.boot_completed")
    func bootWaitsForCompletion() {
        var bootChecks = 0
        let runner = FakeCommandRunner { executable, arguments in
            if arguments.contains("emu") { return CommandResult(output: "Pixel_8\nOK", exitCode: 0) }
            if arguments.contains("getprop") {
                bootChecks += 1
                return CommandResult(output: bootChecks < 2 ? "0\n" : "1\n", exitCode: 0)
            }
            return CommandResult(output: "List of devices attached\nemulator-5554\tdevice\n", exitCode: 0)
        }
        // First isBooted check (before launch) must be false, so start with no emulator listed.
        var listCalls = 0
        let gated = FakeCommandRunner { executable, arguments in
            if arguments == ["devices"] {
                listCalls += 1
                return listCalls == 1 ? CommandResult(output: "List of devices attached\n", exitCode: 0) : runner.run(executable, arguments: arguments)
            }
            return runner.run(executable, arguments: arguments)
        }

        let result = Fixtures.adbService(runner: gated).boot(avdNamed: "Pixel_8", pollInterval: 0, timeout: 5)

        #expect(result.succeeded)
        #expect(gated.detachedLaunches == [[Fixtures.emulatorPath, "-avd", "Pixel_8"]])
    }

    @Test("Boot does not start a second emulator when it is already up")
    func bootAlreadyRunning() {
        let runner = FakeCommandRunner { _, arguments in
            if arguments.contains("emu") { return CommandResult(output: "Pixel_8\nOK", exitCode: 0) }
            if arguments.contains("getprop") { return CommandResult(output: "1\n", exitCode: 0) }
            return CommandResult(output: "List of devices attached\nemulator-5554\tdevice\n", exitCode: 0)
        }

        let result = Fixtures.adbService(runner: runner).boot(avdNamed: "Pixel_8", pollInterval: 0, timeout: 1)

        #expect(result.succeeded)
        #expect(runner.detachedLaunches.isEmpty)
    }

    @Test("Boot times out when the emulator never finishes booting")
    func bootTimeout() {
        let runner = FakeCommandRunner { _, _ in CommandResult(output: "List of devices attached\n", exitCode: 0) }

        let result = Fixtures.adbService(runner: runner).boot(avdNamed: "Pixel_8", pollInterval: 0, timeout: 0.05)

        #expect(!result.succeeded)
        #expect(result.output.contains("Timed out"))
    }

    @Test("Boot reports a missing emulator binary")
    func bootWithoutEmulator() {
        let service = Fixtures.adbService(runner: FakeCommandRunner(), installed: [Fixtures.adbPath])

        #expect(service.boot(avdNamed: "Pixel_8").output == AdbService.missingEmulatorMessage)
    }
}
