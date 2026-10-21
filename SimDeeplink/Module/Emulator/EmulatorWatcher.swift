//
//  EmulatorWatcher.swift
//  SimDeeplink
//
//  Created by Alif on 21/10/25.
//

import SwiftUI
import Combine

final class EmulatorWatcher: ObservableObject {
    static let noEmulatorMessage = "No running emulator. Start one first."
    static let severalEmulatorsMessage = "Several emulators are running. Pick an Emulator Target."

    @Published var adbPaths: [String] = []
    @Published var emulators: [Emulator] = []
    @Published var bootedEmulators: [Emulator] = []

    /// The adb chosen in the picker; empty means the first one found.
    var selectedAdbPath: String = ""

    private let makeService: (String) -> AdbService
    private let workQueue = DispatchQueue(label: "EmulatorWatcher.work", qos: .utility)
    private let bootQueue = DispatchQueue(label: "EmulatorWatcher.boot", qos: .utility)

    init(makeService: @escaping (String) -> AdbService = { AdbService(preferredAdbPath: $0) }) {
        self.makeService = makeService
        workQueue.async {
            let paths = makeService("").adbPaths
            DispatchQueue.main.async {
                self.adbPaths = paths
            }
        }
    }

    static func makeDefault() -> EmulatorWatcher {
        #if DEBUG
        if UITestSupport.isActive { return UITestSupport.makeEmulatorWatcher() }
        #endif
        return EmulatorWatcher()
    }

    /// Every Android Virtual Device: running ones first, then the ones that are only installed.
    func fetchOfflineEmulators() {
        let service = makeService(selectedAdbPath)
        workQueue.async {
            let devices = service.listDevices().map(Emulator.init)
            DispatchQueue.main.async {
                self.emulators = devices
            }
        }
    }

    func getBootedEmulator(adbPath: String) {
        let service = makeService(adbPath)
        workQueue.async {
            let running = service.listDevices().filter(\.isBooted).map(Emulator.init)
            DispatchQueue.main.async {
                self.bootedEmulators = running
            }
        }
    }

    /// Starts the AVD and waits until Android has finished booting.
    func bootEmulator(avdName: String) async -> String {
        let service = makeService(selectedAdbPath)
        return await withCheckedContinuation { continuation in
            bootQueue.async {
                let result = service.boot(avdNamed: avdName)
                continuation.resume(returning: result.trimmedOutput)
            }
        }
    }

    func runDeeplink(url: String, adbPath: String, packageTarget: String? = nil, emulatorTarget: String? = nil) async -> String {
        let service = makeService(adbPath)
        return await withCheckedContinuation { continuation in
            workQueue.async {
                continuation.resume(returning: Self.open(url, service: service, packageTarget: packageTarget, serial: emulatorTarget))
            }
        }
    }

    private static func open(_ url: String, service: AdbService, packageTarget: String?, serial: String?) -> String {
        if let message = service.missingToolMessage { return message }

        let target: String
        if let serial {
            target = serial
        } else {
            let running = service.listDevices().filter(\.isBooted)
            guard let only = running.first else { return noEmulatorMessage }
            guard running.count == 1 else { return severalEmulatorsMessage }
            target = only.udid
        }

        let result = service.openURL(url, on: target, package: packageTarget)
        guard result.succeeded else { return "Failed to open \(url): \(result.trimmedOutput)" }
        return result.trimmedOutput.isEmpty ? "Opened \(url)" : result.trimmedOutput
    }
}
