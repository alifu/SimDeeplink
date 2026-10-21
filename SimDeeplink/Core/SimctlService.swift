//
//  SimctlService.swift
//  SimDeeplink
//

import Foundation

struct SimctlService {
    private static let xcrun = "/usr/bin/xcrun"
    private static let bootTimeout: TimeInterval = 120
    private static let alreadyBootedMessage = "current state: Booted"

    private let runner: CommandRunning

    init(runner: CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    /// iPhone and iPad simulators of every installed runtime.
    func listDevices() -> [Simulator] {
        let devices = runner.run(Self.xcrun, arguments: ["simctl", "list", "devices", "available", "--json"])
        guard devices.succeeded else {
            AppLog.device.error("simctl list devices failed: \(devices.trimmedOutput, privacy: .public)")
            return []
        }

        let runtimes = runner.run(Self.xcrun, arguments: ["simctl", "list", "runtimes", "--json"])
        let runtimesJSON = runtimes.succeeded ? Data(runtimes.output.utf8) : nil

        do {
            return try SimctlParser.parse(devicesJSON: Data(devices.output.utf8), runtimesJSON: runtimesJSON)
                .filter { $0.type == .iPhone || $0.type == .iPad }
        } catch {
            AppLog.device.error("Could not read simctl output: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func boot(udid: String) -> CommandResult {
        let boot = runner.run(Self.xcrun, arguments: ["simctl", "boot", udid])
        if !boot.succeeded && !boot.output.contains(Self.alreadyBootedMessage) {
            return boot
        }

        let open = runner.run("/usr/bin/open", arguments: ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid])
        if !open.succeeded {
            AppLog.device.error("Could not open Simulator.app: \(open.trimmedOutput, privacy: .public)")
        }
        return runner.run(Self.xcrun, arguments: ["simctl", "bootstatus", udid], timeout: Self.bootTimeout)
    }

    /// `target` is a UDID, or "booted" for whichever simulator is running.
    func openURL(_ url: String, on target: String) -> CommandResult {
        runner.run(Self.xcrun, arguments: ["simctl", "openurl", target, url])
    }
}
