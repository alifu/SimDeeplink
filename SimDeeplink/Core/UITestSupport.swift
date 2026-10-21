//
//  UITestSupport.swift
//  SimDeeplink
//

#if DEBUG
import Foundation

/// Lets UI tests run the real window against canned devices instead of real simulators.
enum UITestSupport {
    static let launchArgument = "-UITest"

    static var isActive: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    static func makeSimulatorWatcher() -> SimulatorWatcher {
        SimulatorWatcher(service: SimctlService(runner: UITestCommandRunner()))
    }

    static func makeEmulatorWatcher() -> EmulatorWatcher {
        EmulatorWatcher(makeService: { _ in
            AdbService(preferredAdbPath: "/uitest/adb", runner: UITestCommandRunner(), environment: [:], homeDirectory: "/uitest", isExecutable: { _ in true })
        })
    }
}

struct UITestCommandRunner: CommandRunning {
    private static let devicesJSON = """
    {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[
      {"name":"iPhone 17 Pro","udid":"23F0A11F-0DD8-4766-853D-987DE9852BAC","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"},
      {"name":"iPad Pro 13-inch (M5)","udid":"A412E5A6-62A9-478C-9935-0E1B97399786","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-8GB"}]}}
    """
    private static let runtimesJSON = """
    {"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-0","name":"iOS 26.0"}]}
    """

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
        let output: String
        if executable.hasSuffix("adb") {
            if arguments.contains("emu") {
                output = "Pixel_8_API_35\nOK\n"
            } else if arguments.contains("shell") {
                output = "Starting: Intent { act=android.intent.action.VIEW }\n"
            } else {
                output = "List of devices attached\nemulator-5554\tdevice product:sdk model:Pixel_8 device:emu\n"
            }
        } else if executable.hasSuffix("emulator") {
            output = "Pixel_8_API_35\nPixel_Tablet_API_35\n"
        } else if arguments.contains("runtimes") {
            output = Self.runtimesJSON
        } else if arguments.contains("devices") {
            output = Self.devicesJSON
        } else {
            output = ""
        }
        return CommandResult(output: output, exitCode: 0)
    }

    func launchDetached(_ executable: String, arguments: [String]) -> Bool { true }
}
#endif
