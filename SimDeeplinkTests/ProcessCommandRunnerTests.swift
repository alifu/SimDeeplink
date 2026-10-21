//
//  ProcessCommandRunnerTests.swift
//  SimDeeplinkTests
//

import Foundation
import Testing
@testable import SimDeeplink

struct ProcessCommandRunnerTests {
    private let runner = ProcessCommandRunner()

    @Test("Captures output and exit code")
    func capturesOutput() {
        let result = runner.run("/bin/echo", arguments: ["hello", "world"])

        #expect(result.succeeded)
        #expect(result.trimmedOutput == "hello world")
    }

    @Test("Does not interpret shell syntax in arguments")
    func noShellInterpretation() {
        let result = runner.run("/bin/echo", arguments: ["$(whoami);ls", "a&b"])

        #expect(result.trimmedOutput == "$(whoami);ls a&b")
    }

    @Test("Reports a non-zero exit code")
    func nonZeroExit() {
        let result = runner.run("/usr/bin/false", arguments: [])

        #expect(!result.succeeded)
        #expect(result.exitCode == 1)
    }

    @Test("Fails cleanly when the executable does not exist")
    func missingExecutable() {
        let result = runner.run("/definitely/not/here", arguments: [])

        #expect(!result.succeeded)
        #expect(result.output.hasPrefix("Error:"))
    }

    @Test("Stops a command that runs past the timeout")
    func timesOut() {
        let result = runner.run("/bin/sleep", arguments: ["10"], timeout: 0.3)

        #expect(!result.succeeded)
        #expect(result.output.contains("Timed out"))
    }

    @Test("Reads output larger than the pipe buffer without hanging")
    func largeOutput() {
        let result = runner.run("/usr/bin/yes", arguments: ["x"], timeout: 1)

        #expect(result.output.count > 10_000)
    }

    @Test("Does not wait for a child that keeps the pipe open after the tool exits")
    func leftoverChildHoldsPipe() {
        let started = Date()

        let result = runner.run("/bin/sh", arguments: ["-c", "echo started; (sleep 5 &) ; exit 0"], timeout: 10)

        #expect(result.succeeded)
        #expect(result.trimmedOutput == "started")
        #expect(Date().timeIntervalSince(started) < 4)
    }

    @Test("A crash is not reported as a timeout")
    func crashIsNotTimeout() {
        let result = runner.run("/bin/sh", arguments: ["-c", "kill -SEGV $$"], timeout: 5)

        #expect(!result.succeeded)
        #expect(!result.output.contains("Timed out"))
    }

    @Test("Detached launch reports whether the process started")
    func detachedLaunch() {
        #expect(runner.launchDetached("/usr/bin/true", arguments: []))
        #expect(!runner.launchDetached("/definitely/not/here", arguments: []))
    }

    @Test("Real simctl returns only valid UDIDs", .enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun")))
    func realSimctl() {
        let devices = SimctlService().listDevices()
        let uuidPattern = "^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$"

        #expect(devices.allSatisfy { $0.udid.range(of: uuidPattern, options: .regularExpression) != nil })
    }
}
