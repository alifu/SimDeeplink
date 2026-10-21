//
//  CommandRunner.swift
//  SimDeeplink
//

import Foundation
import os

enum AppLog {
    static let device = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SimDeeplink", category: "device")
}

struct CommandResult: Equatable {
    let output: String
    let exitCode: Int32

    var succeeded: Bool { exitCode == 0 }
    var trimmedOutput: String { output.trimmingCharacters(in: .whitespacesAndNewlines) }

    static func failure(_ message: String) -> CommandResult {
        CommandResult(output: message, exitCode: -1)
    }
}

/// Runs external tools without a shell, so arguments are never re-interpreted.
protocol CommandRunning {
    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult
    /// Starts a long-lived process (such as the Android emulator) and does not wait for it.
    func launchDetached(_ executable: String, arguments: [String]) -> Bool
}

extension CommandRunning {
    static var defaultTimeout: TimeInterval { 30 }

    func run(_ executable: String, arguments: [String]) -> CommandResult {
        run(executable, arguments: arguments, timeout: Self.defaultTimeout)
    }
}

struct ProcessCommandRunner: CommandRunning {
    private static let killGrace: TimeInterval = 2
    private static let drainGrace: TimeInterval = 1

    /// Collects pipe output on the reader thread while the caller waits for the process.
    private final class OutputBuffer {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        // Do not wait for end-of-file on the pipe: a daemon that the tool starts (such as the adb server)
        // inherits it and would keep the read open long after the tool itself has finished.
        let buffer = OutputBuffer()
        let reachedEnd = DispatchSemaphore(value: 0)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                reachedEnd.signal()
            } else {
                buffer.append(chunk)
            }
        }
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return .failure("Error: \(error.localizedDescription)")
        }

        var didTimeOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            didTimeOut = true
            process.terminate()
            if exited.wait(timeout: .now() + Self.killGrace) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
        }

        // Normally end-of-file arrives at once; if a leftover child holds the pipe, stop waiting.
        _ = reachedEnd.wait(timeout: .now() + Self.drainGrace)
        pipe.fileHandleForReading.readabilityHandler = nil

        let output = buffer.text
        if didTimeOut {
            return CommandResult(output: output + "\nTimed out after \(Int(timeout))s", exitCode: -1)
        }
        return CommandResult(output: output, exitCode: process.terminationStatus)
    }

    func launchDetached(_ executable: String, arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            return true
        } catch {
            AppLog.device.error("Could not launch \(executable, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
