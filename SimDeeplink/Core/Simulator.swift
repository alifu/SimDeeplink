//
//  Simulator.swift
//  SimDeeplink
//

import Foundation

enum SimulatorType: String, CaseIterable {
    case iPhone
    case iPad
    case watch
    case tv
    case android
    case unknown
}

enum DevicePlatform: String, CaseIterable, Identifiable {
    case ios = "iOS"
    case android = "Android"

    var id: String { rawValue }
}

struct Simulator: Identifiable, Equatable {
    let name: String
    let udid: String
    let runtime: String
    let isBooted: Bool
    let type: SimulatorType

    /// Stable across refreshes, so a selection survives the list being re-read.
    var id: String { udid }

    var platform: DevicePlatform { type == .android ? .android : .ios }

    var displayTitle: String {
        let bootStatus = isBooted ? "🟢 Booted" : "⚪️"
        return "\(name) — \(runtime) \(bootStatus)"
    }
}
