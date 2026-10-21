//
//  AdbParser.swift
//  SimDeeplink
//

import Foundation

struct AdbDevice: Equatable {
    let serial: String
    let state: String
    let model: String?
}

enum AdbParser {
    private static let knownStates: Set<String> = [
        "device", "offline", "unauthorized", "authorizing", "recovery", "sideload", "bootloader", "host", "no"
    ]
    private static let avdNamePattern = "^[A-Za-z0-9._-]+$"

    /// Parses `adb devices -l`; daemon notices and other noise are skipped.
    static func parseDevices(_ output: String) -> [AdbDevice] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, !text.hasPrefix("*"), !text.hasPrefix("List of devices") else { return nil }

            let fields = text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard fields.count >= 2, knownStates.contains(fields[1]) else { return nil }

            let model = fields.dropFirst(2)
                .first { $0.hasPrefix("model:") }
                .map { String($0.dropFirst("model:".count)) }
            return AdbDevice(serial: fields[0], state: fields[1], model: model)
        }
    }

    /// Parses `emulator -list-avds`, ignoring "INFO |" style log lines.
    static func parseAvdNames(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: avdNamePattern, options: .regularExpression) != nil }
    }

    /// Parses `adb -s <serial> emu avd name`, which prints the name and then "OK".
    static func parseAvdName(fromEmuOutput output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && $0 != "OK" }
    }
}
