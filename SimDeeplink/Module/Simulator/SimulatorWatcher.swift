//
//  SimulatorWatcher.swift
//  SimDeeplink
//
//  Created by Alif on 17/10/25.
//

import SwiftUI
import Combine

final class SimulatorWatcher: ObservableObject {
    private static let pollInterval: TimeInterval = 5
    private static let bootNotification = NSNotification.Name("com.apple.iphonesimulator.simulator.launchd")
    private static let shutdownNotification = NSNotification.Name("com.apple.iphonesimulator.simulator.shutdown")

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

    private let service: SimctlService
    private let workQueue = DispatchQueue(label: "SimulatorWatcher.work", qos: .utility)
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var isRefreshing = false
    private var needsRerun = false
    private var pendingCompletions: [() -> Void] = []

    init(service: SimctlService = SimctlService()) {
        self.service = service
    }

    static func makeDefault() -> SimulatorWatcher {
        #if DEBUG
        if UITestSupport.isActive { return UITestSupport.makeSimulatorWatcher() }
        #endif
        return SimulatorWatcher()
    }

    func startWatching() {
        stopWatching()
        observeSimulatorEvents()
        refreshSimulators()
        startPolling()
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
        let center = DistributedNotificationCenter.default()
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    /// Reads iPhone and iPad simulators of every runtime. A refresh that is still running is not repeated.
    func refreshSimulators(completion: (() -> Void)? = nil) {
        if let completion { pendingCompletions.append(completion) }
        // A request that arrives mid-refresh may have been made after the list was read, so it runs once more.
        guard !isRefreshing else {
            needsRerun = true
            return
        }
        isRefreshing = true
        let completions = pendingCompletions
        pendingCompletions = []
        workQueue.async {
            let devices = self.service.listDevices()
            DispatchQueue.main.async {
                self.isRefreshing = false
                self.simulators = devices
                self.bootedSimulators = devices.filter(\.isBooted)
                completions.forEach { $0() }
                if self.needsRerun {
                    self.needsRerun = false
                    self.refreshSimulators()
                }
            }
        }
    }

    func refreshBootedSimulators() {
        refreshSimulators()
    }

    /// Re-fetch simulators periodically
    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refreshSimulators()
        }
    }

    /// Listen to boot/shutdown notifications from Simulator.app
    private func observeSimulatorEvents() {
        let center = DistributedNotificationCenter.default()
        observers = [Self.bootNotification, Self.shutdownNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshSimulators()
            }
        }
    }

    func bootSimulator(udid: String, completion: (() -> Void)? = nil) {
        workQueue.async {
            let result = self.service.boot(udid: udid)
            if !result.succeeded {
                AppLog.device.error("Boot failed: \(result.trimmedOutput, privacy: .public)")
            }
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    /// `target` is a UDID, or "booted" for whichever simulator is running.
    func runDeeplink(url: String, target: String = "booted") async -> String {
        await withCheckedContinuation { continuation in
            workQueue.async {
                let result = self.service.openURL(url, on: target)
                continuation.resume(returning: Self.message(for: result, url: url))
            }
        }
    }

    private static func message(for result: CommandResult, url: String) -> String {
        guard result.succeeded else { return "Failed to open \(url): \(result.trimmedOutput)" }
        return result.trimmedOutput.isEmpty ? "Opened \(url)" : result.trimmedOutput
    }

    deinit {
        stopWatching()
    }
}
