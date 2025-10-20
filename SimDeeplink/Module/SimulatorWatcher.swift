//
//  SimulatorWatcher.swift
//  SimDeeplink
//
//  Created by Alif on 17/10/25.
//

import SwiftUI
import Combine

final class SimulatorWatcher: ObservableObject {
    @Published var simulators: [Simulator] = []
    @Published var bootedSimulators: [Simulator] = []
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                startWatching()
            } else {
                stopWatching()
            }
        }
    }
    
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    init() {}
    
    func startWatching() {
        stopWatching()
        observeSimulatorEvents()
        refreshSimulators()
        startPolling()
    }
    
    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Fetch available simulators and publish
    func refreshSimulators() {
        DispatchQueue.global(qos: .background).async {
            let newList = self.getAvailableSimulators()
            DispatchQueue.main.async {
                let iPhones = newList.filter { $0.type == .iPhone }
                self.simulators = iPhones
            }
        }
    }
    
    func refreshBootedSimulators() {
        DispatchQueue.global(qos: .background).async {
            let newList = self.getBootedSimulators()
            DispatchQueue.main.async {
                let iPhones = newList.filter { $0.type == .iPhone }
                self.bootedSimulators = iPhones
            }
        }
    }
    
    /// Periodically re-fetch simulators
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshSimulators()
        }
    }
    
    /// Listen to boot/shutdown notifications from Simulator.app
    private func observeSimulatorEvents() {
        let center = DistributedNotificationCenter.default()
        let queue = OperationQueue.main
        
        // Boot notification
        center.addObserver(forName: NSNotification.Name("com.apple.iphonesimulator.simulator.launchd"),
                           object: nil,
                           queue: queue) { [weak self] _ in
            print("🔵 Simulator boot detected")
            self?.refreshSimulators()
        }
        
        // Shutdown notification
        center.addObserver(forName: NSNotification.Name("com.apple.iphonesimulator.simulator.shutdown"),
                           object: nil,
                           queue: queue) { [weak self] _ in
            print("🔴 Simulator shutdown detected")
            self?.refreshSimulators()
        }
    }
    
    func bootSimulator(udid: String, completion: (() -> Void)? = nil) {
        DispatchQueue.global().async {
            let _ = self.runShellCommand("xcrun simctl boot \(udid)")
            let _ = self.runShellCommand("open -a Simulator") // open the app if not opened
            // give it a moment to boot
            sleep(3)
            DispatchQueue.main.async {
                completion?()
            }
        }
    }
    
    private func runShellCommand(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        
        process.standardOutput = pipe
        process.standardError = pipe
        process.arguments = ["-c", command]
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        
        do {
            try process.run()
        } catch {
            print("Error running command: \(error.localizedDescription)")
            return nil
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
    
    private func getBootedSimulators() -> [Simulator] {
        // 1️⃣ Get runtime versions first (for full iOS version names)
        var runtimeVersions: [String: String] = [:]
        if let runtimeOutput = runShellCommand("xcrun simctl list runtimes --json"),
           let data = runtimeOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let runtimes = json["runtimes"] as? [[String: Any]] {
            for runtime in runtimes {
                if let name = runtime["name"] as? String,
                   let version = runtime["version"] as? String {
                    runtimeVersions[name] = version
                }
            }
        }
        
        // 2️⃣ Get devices in JSON for reliable parsing
        guard let output = runShellCommand("xcrun simctl list devices --json"),
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesDict = json["devices"] as? [String: [[String: Any]]] else {
            return []
        }
        
        var bootedSimulators: [Simulator] = []
        
        // 3️⃣ Iterate through all runtimes
        for (runtimeKey, devices) in devicesDict {
            // Normalize runtime label
            var runtimeName = runtimeKey
                .replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "ios", with: "iOS ")
                .capitalized
            
            // Try to replace with known version mapping (from runtimes)
            if let fullVersion = runtimeVersions[runtimeName] {
                runtimeName = "\(runtimeName) (\(fullVersion))"
            }
            
            // 4️⃣ Parse each device
            for device in devices {
                guard
                    let name = device["name"] as? String,
                    let udid = device["udid"] as? String,
                    let state = device["state"] as? String,
                    state == "Booted"
                else { continue }
                
                let lowerName = name.lowercased()
                let type: SimulatorType
                if lowerName.contains("iphone") {
                    type = .iPhone
                } else if lowerName.contains("ipad") {
                    type = .iPad
                } else if lowerName.contains("watch") {
                    type = .watch
                } else if lowerName.contains("tv") {
                    type = .tv
                } else {
                    type = .unknown
                }
                
                bootedSimulators.append(
                    Simulator(
                        name: name,
                        udid: udid,
                        runtime: runtimeName,
                        isBooted: true,
                        type: type
                    )
                )
            }
        }
        
        return bootedSimulators
    }
    
    private func getAvailableSimulators() -> [Simulator] {
        // 1️⃣ Get runtime versions first (to get iOS 18.3.1, etc.)
        var runtimeVersions: [String: String] = [:]
        if let runtimeOutput = runShellCommand("xcrun simctl list runtimes --json"),
           let data = runtimeOutput.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let runtimes = json["runtimes"] as? [[String: Any]] {
            for runtime in runtimes {
                if let name = runtime["name"] as? String,
                   let version = runtime["version"] as? String {
                    runtimeVersions[name] = version
                }
            }
        }
        
        // 2️⃣ Get available devices (your current method)
        guard let output = runShellCommand("xcrun simctl list devices available") else { return [] }
        
        var simulators: [Simulator] = []
        var currentRuntime = ""
        
        for line in output.split(separator: "\n").map(String.init) {
            // Detect runtime header line
            if line.starts(with: "--") && line.contains("--") {
                currentRuntime = line
                    .replacingOccurrences(of: "-", with: "")
                    .trimmingCharacters(in: .whitespaces)
                
                // Replace truncated iOS version with full version if found
                if let fullVersion = runtimeVersions[currentRuntime.replacingOccurrences(of: "--", with: "").trimmingCharacters(in: .whitespaces)] {
                    currentRuntime = currentRuntime.replacingOccurrences(of: #"\d+(\.\d+)?"#, with: fullVersion, options: .regularExpression)
                }
            }
            
            // Detect device line
            else if line.contains("("), line.contains(")") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                let pattern = #"(.+?) \(([\w\-]+)\)(?: \((Booted)\))?"#
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                guard let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else { continue }
                
                let name = Range(match.range(at: 1), in: trimmed).flatMap { String(trimmed[$0]) } ?? "Unknown"
                let udid = Range(match.range(at: 2), in: trimmed).flatMap { String(trimmed[$0]) } ?? ""
                let isBooted = trimmed.contains("(Booted)")
                
                let lowerName = name.lowercased()
                let type: SimulatorType
                if lowerName.contains("iphone") {
                    type = .iPhone
                } else if lowerName.contains("ipad") {
                    type = .iPad
                } else if lowerName.contains("watch") {
                    type = .watch
                } else if lowerName.contains("tv") {
                    type = .tv
                } else {
                    type = .unknown
                }
                
                simulators.append(
                    Simulator(
                        name: name,
                        udid: udid,
                        runtime: currentRuntime,
                        isBooted: isBooted,
                        type: type
                    )
                )
            }
        }
        
        return simulators
    }
    
    func runDeeplink(url: String, target: String = "booted") -> String {
        let process = Process()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["simctl", "openurl", target, url]
        
        do {
            try process.run()
        } catch {
            return "Error: \(error.localizedDescription)"
        }
        
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    deinit {
        timer?.invalidate()
    }
}
