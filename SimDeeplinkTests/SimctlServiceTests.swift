//
//  SimctlServiceTests.swift
//  SimDeeplinkTests
//

import Testing
@testable import SimDeeplink

struct SimctlServiceTests {
    @Test("Lists iPhones and iPads but not watches")
    func listsPhonesAndTablets() {
        let service = SimctlService(runner: Fixtures.standardRunner())

        let types = Set(service.listDevices().map(\.type))

        #expect(types == [.iPhone, .iPad])
    }

    @Test("Returns an empty list when simctl fails")
    func emptyOnFailure() {
        let service = SimctlService(runner: FakeCommandRunner { _, _ in CommandResult(output: "boom", exitCode: 1) })

        #expect(service.listDevices().isEmpty)
    }

    @Test("Returns an empty list when simctl prints something unreadable")
    func emptyOnGarbage() {
        let service = SimctlService(runner: FakeCommandRunner { _, _ in CommandResult(output: "garbage", exitCode: 0) })

        #expect(service.listDevices().isEmpty)
    }

    @Test("Boot waits for the device after starting it and opens Simulator on that device")
    func bootSequence() {
        let runner = FakeCommandRunner()

        let result = SimctlService(runner: runner).boot(udid: "UDID-1")

        #expect(result.succeeded)
        #expect(runner.calls[0] == ["/usr/bin/xcrun", "simctl", "boot", "UDID-1"])
        #expect(runner.calls[1] == ["/usr/bin/open", "-a", "Simulator", "--args", "-CurrentDeviceUDID", "UDID-1"])
        #expect(runner.calls[2] == ["/usr/bin/xcrun", "simctl", "bootstatus", "UDID-1"])
    }

    @Test("Booting an already booted device is not an error")
    func alreadyBooted() {
        let runner = FakeCommandRunner { _, arguments in
            arguments.contains("boot")
                ? CommandResult(output: "Unable to boot device in current state: Booted", exitCode: 149)
                : CommandResult(output: "", exitCode: 0)
        }

        #expect(SimctlService(runner: runner).boot(udid: "UDID-1").succeeded)
    }

    @Test("Boot reports a real failure and stops")
    func bootFailure() {
        let runner = FakeCommandRunner { _, _ in CommandResult(output: "Invalid device", exitCode: 164) }

        let result = SimctlService(runner: runner).boot(udid: "nope")

        #expect(!result.succeeded)
        #expect(runner.calls.count == 1)
    }

    @Test("Opens the URL on the given target as one argument, without a shell")
    func openURLArguments() {
        let runner = FakeCommandRunner()
        let url = "myapp://x?a=1&b=$(whoami);ls"

        _ = SimctlService(runner: runner).openURL(url, on: "UDID-1")

        #expect(runner.calls == [["/usr/bin/xcrun", "simctl", "openurl", "UDID-1", url]])
    }
}
