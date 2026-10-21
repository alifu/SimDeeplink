//
//  TestSupport.swift
//  SimDeeplinkTests
//

import Foundation
@testable import SimDeeplink

/// Scripted stand-in for the shell: records every call and answers from `handler`.
final class FakeCommandRunner: CommandRunning {
    typealias Handler = (_ executable: String, _ arguments: [String]) -> CommandResult

    private let handler: Handler
    private(set) var calls: [[String]] = []
    private(set) var detachedLaunches: [[String]] = []
    var launchSucceeds = true

    init(handler: @escaping Handler = { _, _ in CommandResult(output: "", exitCode: 0) }) {
        self.handler = handler
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
        calls.append([executable] + arguments)
        return handler(executable, arguments)
    }

    func launchDetached(_ executable: String, arguments: [String]) -> Bool {
        detachedLaunches.append([executable] + arguments)
        return launchSucceeds
    }
}

enum Fixtures {
    static let ipadPro13M5 = "A412E5A6-62A9-478C-9935-0E1B97399786"
    static let ipadAir11M3 = "F4B2F269-8F69-4F7F-B2B4-CEF01C8B2D09"
    static let iphone17Pro = "23F0A11F-0DD8-4766-853D-987DE9852BAC"
    static let iphone16Pro = "B0B059B3-19CB-4C5C-B677-3A9866037257"

    /// Shaped like `xcrun simctl list devices available --json` on Xcode 26.
    static let simctlDevices = """
    {"devices":{
      "com.apple.CoreSimulator.SimRuntime.iOS-18-4":[
        {"name":"iPhone 16 Pro","udid":"\(iphone16Pro)","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"}],
      "com.apple.CoreSimulator.SimRuntime.iOS-26-0":[
        {"name":"iPhone 17 Pro","udid":"\(iphone17Pro)","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"},
        {"name":"iPad Pro 13-inch (M5)","udid":"\(ipadPro13M5)","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-8GB"},
        {"name":"iPad Air 11-inch (M3)","udid":"\(ipadAir11M3)","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3-8GB"}],
      "com.apple.CoreSimulator.SimRuntime.iOS-17-0":[
        {"name":"iPhone 15","udid":"11111111-2222-3333-4444-555555555555","state":"Shutdown","isAvailable":false,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-15"}],
      "com.apple.CoreSimulator.SimRuntime.watchOS-26-0":[
        {"name":"Apple Watch Series 11 (46mm)","udid":"66666666-7777-8888-9999-000000000000","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm"}]
    }}
    """

    static let simctlRuntimes = """
    {"runtimes":[
      {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-0","name":"iOS 26.0"},
      {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-4","name":"iOS 18.4"}]}
    """

    static let adbDevices = """
    * daemon not running; starting now at tcp:5037
    * daemon started successfully
    List of devices attached
    emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1
    emulator-5556          offline
    R58M12345XY            device usb:1-1 product:beyond1 model:SM_G973F device:beyond1 transport_id:3
    """

    static let sdkRoot = "/sdk"
    static let adbPath = "/sdk/platform-tools/adb"
    static let emulatorPath = "/sdk/emulator/emulator"

    static func adbService(runner: CommandRunning, installed: Set<String> = [adbPath, emulatorPath]) -> AdbService {
        AdbService(runner: runner, environment: ["ANDROID_HOME": sdkRoot], homeDirectory: "/home", isExecutable: { installed.contains($0) })
    }

    /// Answers like a machine with one iOS runtime, one running emulator and one stopped AVD.
    static func standardRunner() -> FakeCommandRunner {
        FakeCommandRunner { executable, arguments in
            switch (executable, arguments) {
            case (_, let args) where args.contains("runtimes"):
                return CommandResult(output: simctlRuntimes, exitCode: 0)
            case (_, let args) where args.starts(with: ["simctl", "list", "devices"]):
                return CommandResult(output: simctlDevices, exitCode: 0)
            case (adbPath, let args) where args.contains("emu"):
                return CommandResult(output: "Pixel_8_API_35\nOK\n", exitCode: 0)
            case (adbPath, _):
                return CommandResult(output: "List of devices attached\nemulator-5554\tdevice model:Pixel_8\n", exitCode: 0)
            case (emulatorPath, _):
                return CommandResult(output: "Pixel_8_API_35\nTablet_API_35\n", exitCode: 0)
            default:
                return CommandResult(output: "", exitCode: 0)
            }
        }
    }
}
