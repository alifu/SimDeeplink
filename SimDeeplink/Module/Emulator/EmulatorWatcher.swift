//
//  EmulatorWatcher.swift
//  SimDeeplink
//
//  Created by Alif on 21/10/25.
//

import SwiftUI
import Combine

final class EmulatorWatcher: ObservableObject {
    
    @Published var adbPaths: [String] = []
    @Published var emulators: [Emulator] = []
    @Published var bootedEmulators: [Emulator] = []
    
    init () {
        DispatchQueue.global().async {
            let result = self.fetchADBPaths()
            DispatchQueue.main.async {
                self.adbPaths = result
            }
        }
    }
    
    func fetchOfflineEmulators() {
        let data = self.getOfflineAndroidAVDs()
        emulators = data.map { $0.toEmulator() }
    }
    
    private func parseADBDevices(_ output: String) -> [Emulator] {
        let lines = output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.contains("List of devices") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        return lines.compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard let serial = parts.first else { return nil }
            let isOnline = line.contains("device")
            let name = line.contains("model:")
            ? (line.components(separatedBy: "model:").last?
                .components(separatedBy: " ").first ?? serial)
            : serial
            return Emulator(name: name, serial: serial, isOnline: isOnline)
        }
    }
    
    private func fetchADBPaths() -> [String] {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        
        // Manually inject your full PATH including Android SDK tools
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = [
            "/Users/\(NSUserName())/Library/Android/sdk/platform-tools",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            env["PATH"] ?? ""
        ].joined(separator: ":")
        process.environment = env
        
        process.arguments = ["which", "-a", "adb"]
        
        do {
            try process.run()
        } catch {
            return []
        }
        
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        return output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
    
    private func runShell(_ command: String) -> String {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        
        let envPath = [
            "/Users/\(NSUserName())/Library/Android/sdk/platform-tools",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin"
        ].joined(separator: ":")
        
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = envPath
        process.environment = env
        
        do { try process.run() } catch {
            print("Error running command: \(error.localizedDescription)")
            return ""
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func getBootedEmulator(adbPath: String) {
        let devicesOutput = runShell("\(adbPath) devices -l")
        let lines = devicesOutput.split(separator: "\n").map(String.init)
        var emulators: [Emulator] = []
        
        for line in lines {
            if line.contains("emulator-") && line.contains("device") {
                let serial = line.split(separator: " ").first ?? ""
                let model = line.components(separatedBy: "model:").last?
                    .components(separatedBy: " ").first ?? "Unknown"
                
                // Get AVD name from emulator
                let rawName = runShell("\(adbPath) -s \(serial) emu avd name")
                let avdName = rawName
                    .replacingOccurrences(of: "\r", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "OK", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                emulators.append(
                    Emulator(
                        name: avdName.isEmpty ? model : avdName,
                        serial: String(serial),
                        isOnline: true
                    )
                )
            }
        }
        
        DispatchQueue.main.async {
            self.bootedEmulators = emulators
        }
    }

    private func getOfflineAndroidAVDs() -> [OfflineEmulator] {
        guard let avdManager = findAVDManagerPath() else { return [] }
        let output = shell([avdManager, "list", "avd"])

        var emulators: [OfflineEmulator] = []

        var currentName: String?
        var device: String?
        var path: String?
        var basedOn: String?
        var tagAbi: String?
        var skin: String?
        var sdcard: String?
        var snapshot: String?

        func appendCurrent() {
            if let name = currentName {
                let api = makeApiDescription(basedOn: basedOn, tagAbi: tagAbi)
                let emulator = OfflineEmulator(
                    name: name,
                    device: device ?? "Unknown",
                    path: path ?? "",
                    apiLevel: api,
                    skin: skin ?? "",
                    sdcard: sdcard ?? "",
                    snapshot: snapshot ?? ""
                )
                emulators.append(emulator)
            }
        }

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.starts(with: "Name: ") {
                currentName = trimmed.replacingOccurrences(of: "Name: ", with: "")
            } else if trimmed.starts(with: "Device:") {
                device = trimmed.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.starts(with: "Path:") {
                path = trimmed.replacingOccurrences(of: "Path:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.starts(with: "Based on:") {
                basedOn = trimmed.replacingOccurrences(of: "Based on:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.starts(with: "Tag/ABI:") {
                tagAbi = trimmed.replacingOccurrences(of: "Tag/ABI:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.starts(with: "Skin:") {
                skin = trimmed.replacingOccurrences(of: "Skin:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.starts(with: "Sdcard:") {
                sdcard = trimmed.replacingOccurrences(of: "Sdcard:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.starts(with: "Snapshot:") {
                snapshot = trimmed.replacingOccurrences(of: "Snapshot:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.starts(with: "---------") || trimmed.isEmpty {
                appendCurrent()
                currentName = nil
                device = nil
                path = nil
                basedOn = nil
                tagAbi = nil
                skin = nil
                sdcard = nil
                snapshot = nil
            }
        }

        // Append the last AVD block if it wasn't followed by a separator
        appendCurrent()
        return emulators
    }

    private func makeApiDescription(basedOn: String?, tagAbi: String?) -> String {
        var desc = ""
        if let based = basedOn {
            desc += based
        }
        if let tag = tagAbi {
            if !desc.isEmpty { desc += " " }
            desc += "(\(tag))"
        }
        return desc.isEmpty ? "Unknown" : desc
    }
    
    private func shell(_ args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", args.joined(separator: " ")]
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private func findAVDManagerPath() -> String? {
        let sdkPaths = [
            ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"],
            "\(NSHomeDirectory())/Library/Android/sdk",
            "\(NSHomeDirectory())/Android/Sdk"
        ].compactMap { $0 }
        
        for base in sdkPaths {
            let path = "\(base)/cmdline-tools/latest/bin/avdmanager"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
            if let dirs = try? FileManager.default.contentsOfDirectory(atPath: "\(base)/cmdline-tools") {
                for dir in dirs where dir != "latest" {
                    let candidate = "\(base)/cmdline-tools/\(dir)/bin/avdmanager"
                    if FileManager.default.isExecutableFile(atPath: candidate) {
                        return candidate
                    }
                }
            }
        }
        return nil
    }
    
    private func findEmulatorPath() -> String? {
        // Check environment variables first (Android Studio usually sets this)
        if let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] {
            let path = "\(androidHome)/emulator/emulator"
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        if let sdkRoot = ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"] {
            let path = "\(sdkRoot)/emulator/emulator"
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Common fallback locations
        let fallbackPaths = [
            "\(NSHomeDirectory())/Library/Android/sdk/emulator/emulator", // macOS default
            "/Users/\(NSUserName())/Library/Android/sdk/emulator/emulator",
            "/usr/local/share/android-sdk/emulator/emulator",
            "/opt/android-sdk/emulator/emulator"
        ]

        for path in fallbackPaths where FileManager.default.fileExists(atPath: path) {
            return path
        }

        return nil
    }

    
    func bootEmulator(avdName: String) -> String {
        // find emulator binary
        guard let emulatorPath = findEmulatorPath() else { return "Emulator not found" }

        // run emulator detached
        let process = Process()
        process.executableURL = URL(fileURLWithPath: emulatorPath)
        process.arguments = ["-avd", avdName]

        do {
            try process.run()
            return "Booting \(avdName)..."
        } catch {
            return "Failed to boot: \(error.localizedDescription)"
        }
    }

    
    func runDeeplink(url: String, adbPath: String, packageTarget: String? = nil, emulatorTarget: String? = nil) -> String {
        let process = Process()
        let pipe = Pipe()
        
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: adbPath)
        
        // Build adb command
        var args: [String] = [
            "shell", "am", "start",
            "-a", "android.intent.action.VIEW",
            "-d", url
        ]
        
        if let emulatorTarget {
            args.insert("-s", at: 0)
            args.insert(emulatorTarget, at: 1)
        }
        
        // If you want to target specific package (optional)
        if let packageTarget {
            args.append(packageTarget)
        }
        
        process.arguments = args
        
        do {
            try process.run()
        } catch {
            return "Error: \(error.localizedDescription)"
        }
        
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
