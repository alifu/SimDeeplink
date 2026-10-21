//
//  SimulatorTests.swift
//  SimDeeplinkTests
//

import Testing
@testable import SimDeeplink

struct SimulatorTests {
    @Test("Id is the udid, so it is stable between refreshes")
    func stableId() {
        let first = Simulator(name: "iPad", udid: "U1", runtime: "iOS 26.0", isBooted: false, type: .iPad)
        let second = Simulator(name: "iPad", udid: "U1", runtime: "iOS 26.0", isBooted: false, type: .iPad)

        #expect(first.id == second.id)
        #expect(first == second)
    }

    @Test("Title shows runtime and boot state")
    func title() {
        let booted = Simulator(name: "iPhone 17", udid: "U", runtime: "iOS 26.0", isBooted: true, type: .iPhone)
        let stopped = Simulator(name: "iPhone 17", udid: "U", runtime: "iOS 26.0", isBooted: false, type: .iPhone)

        #expect(booted.displayTitle == "iPhone 17 — iOS 26.0 🟢 Booted")
        #expect(stopped.displayTitle == "iPhone 17 — iOS 26.0 ⚪️")
    }

    @Test("Android devices belong to the Android platform, everything else to iOS")
    func platform() {
        func make(_ type: SimulatorType) -> Simulator {
            Simulator(name: "n", udid: "u", runtime: "r", isBooted: false, type: type)
        }

        #expect(make(.android).platform == .android)
        #expect(make(.iPad).platform == .ios)
        #expect(make(.iPhone).platform == .ios)
    }
}
