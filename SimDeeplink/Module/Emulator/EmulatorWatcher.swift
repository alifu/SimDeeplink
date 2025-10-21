//
//  EmulatorWatcher.swift
//  SimDeeplink
//
//  Created by Alif Phincon on 21/10/25.
//

import SwiftUI
import Combine

final class EmulatorWatcher: ObservableObject {
    
    @Published var adbPaths: [String] = []
    @Published var bootedEmulators: [Emulator] = []
    
    init () {
        adbPaths = fetchADBPaths()
    }
    
    func parseADBDevices(_ output: String) -> [Emulator] {
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
    
    func fetchADBPaths() -> [String] {
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
