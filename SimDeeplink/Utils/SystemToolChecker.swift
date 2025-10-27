//
//  SystemToolChecker.swift
//  SimDeeplink
//
//  Created by Alif on 24/10/25.
//

import Foundation
import Combine

/// A service to detect if required developer tools (xcrun, adb, etc.) exist on macOS.
@MainActor
final class SystemToolChecker: ObservableObject {
    @Published var isXcrunAvailable: Bool = false
    @Published var isAdbAvailable: Bool = false
    @Published var xcrunPath: String? = nil
    @Published var adbPath: String? = nil
    
    /// Check tools asynchronously
    func checkTools() {
        Task.detached {
            let xcrun = await Self.findCommandPath("xcrun")
            let adb = await Self.findCommandPath("adb")
            
            await MainActor.run {
                self.xcrunPath = xcrun
                self.adbPath = adb
                self.isXcrunAvailable = xcrun != nil
                self.isAdbAvailable = adb != nil
            }
        }
    }
    
    /// Check if a command-line tool exists and return its full path
    private static func findCommandPath(_ command: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        // Add common SDK paths manually for GUI apps
        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/Users/\(NSUserName())/Library/Android/sdk/platform-tools",
            "/Users/\(NSUserName())/Library/Android/sdk/tools"
        ]
        let defaultPath = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + [defaultPath]).joined(separator: ":")
        process.environment = env
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let path = output, !path.isEmpty, process.terminationStatus == 0 else {
            return nil
        }
        return path
    }
}
