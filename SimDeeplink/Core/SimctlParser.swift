//
//  SimctlParser.swift
//  SimDeeplink
//

import Foundation

/// Parses `xcrun simctl list devices --json`. JSON keeps device names such as
/// "iPad Pro 13-inch (M5)" apart from the UDID, which the text output cannot.
enum SimctlParser {
    private struct DeviceList: Decodable {
        struct Entry: Decodable {
            let name: String
            let udid: String
            let state: String
            let isAvailable: Bool?
            let deviceTypeIdentifier: String?
        }

        let devices: [String: [Entry]]
    }

    private struct RuntimeList: Decodable {
        struct Entry: Decodable {
            let identifier: String
            let name: String
        }

        let runtimes: [Entry]
    }

    static func parse(devicesJSON: Data, runtimesJSON: Data? = nil) throws -> [Simulator] {
        let deviceList = try JSONDecoder().decode(DeviceList.self, from: devicesJSON)
        let runtimeNames = runtimeNames(from: runtimesJSON)

        // Newest runtime first.
        let runtimeIDs = deviceList.devices.keys.sorted { $0.compare($1, options: .numeric) == .orderedDescending }

        return runtimeIDs.flatMap { runtimeID -> [Simulator] in
            let runtime = runtimeNames[runtimeID] ?? fallbackRuntimeName(runtimeID)
            return (deviceList.devices[runtimeID] ?? [])
                .filter { $0.isAvailable != false }
                .map { entry in
                    Simulator(
                        name: entry.name,
                        udid: entry.udid,
                        runtime: runtime,
                        isBooted: entry.state == "Booted",
                        type: classify(deviceTypeIdentifier: entry.deviceTypeIdentifier, name: entry.name)
                    )
                }
        }
    }

    static func classify(deviceTypeIdentifier: String?, name: String) -> SimulatorType {
        let haystack = "\(deviceTypeIdentifier ?? "") \(name)".lowercased()
        if haystack.contains("iphone") { return .iPhone }
        if haystack.contains("ipad") { return .iPad }
        if haystack.contains("watch") { return .watch }
        if haystack.contains("apple-tv") || haystack.contains("apple tv") { return .tv }
        return .unknown
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-0" -> "iOS 26.0"
    static func fallbackRuntimeName(_ identifier: String) -> String {
        let last = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let parts = last.split(separator: "-").map(String.init)
        guard let platform = parts.first else { return identifier }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? platform : "\(platform) \(version)"
    }

    private static func runtimeNames(from json: Data?) -> [String: String] {
        guard let json, let list = try? JSONDecoder().decode(RuntimeList.self, from: json) else { return [:] }
        return Dictionary(list.runtimes.map { ($0.identifier, $0.name) }, uniquingKeysWith: { first, _ in first })
    }
}
