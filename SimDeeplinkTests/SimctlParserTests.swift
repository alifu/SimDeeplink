//
//  SimctlParserTests.swift
//  SimDeeplinkTests
//

import Foundation
import Testing
@testable import SimDeeplink

struct SimctlParserTests {
    private func parse() throws -> [Simulator] {
        try SimctlParser.parse(
            devicesJSON: Data(Fixtures.simctlDevices.utf8),
            runtimesJSON: Data(Fixtures.simctlRuntimes.utf8)
        )
    }

    @Test("Chip names in parentheses stay part of the name, never the UDID")
    func keepsChipNameOutOfUdid() throws {
        let ipad = try #require(try parse().first { $0.name == "iPad Pro 13-inch (M5)" })

        #expect(ipad.udid == Fixtures.ipadPro13M5)
        #expect(ipad.type == .iPad)
    }

    @Test("Devices sharing a chip keep distinct ids")
    func distinctIds() throws {
        let ids = try parse().map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    @Test("Lists iPhones and iPads on every runtime, newest runtime first")
    func ordersNewestRuntimeFirst() throws {
        let simulators = try parse().filter { $0.type == .iPhone || $0.type == .iPad }

        #expect(simulators.first?.runtime == "iOS 26.0")
        #expect(simulators.last { $0.type == .iPhone }?.runtime == "iOS 18.4")
        #expect(simulators.filter { $0.type == .iPad }.count == 2)
    }

    @Test("Skips unavailable devices")
    func skipsUnavailable() throws {
        #expect(try !parse().contains { $0.name == "iPhone 15" })
    }

    @Test("Reads the booted state")
    func readsBootedState() throws {
        let simulators = try parse()

        #expect(simulators.first { $0.udid == Fixtures.iphone17Pro }?.isBooted == true)
        #expect(simulators.first { $0.udid == Fixtures.ipadPro13M5 }?.isBooted == false)
    }

    @Test("Classifies watch and unknown devices")
    func classifiesOtherDevices() throws {
        #expect(try parse().first { $0.name.contains("Watch") }?.type == .watch)
        #expect(SimctlParser.classify(deviceTypeIdentifier: nil, name: "Apple TV 4K") == .tv)
        #expect(SimctlParser.classify(deviceTypeIdentifier: nil, name: "Something") == .unknown)
    }

    @Test("Derives the runtime name from its identifier when the runtime list is missing")
    func fallsBackToIdentifierName() throws {
        let simulators = try SimctlParser.parse(devicesJSON: Data(Fixtures.simctlDevices.utf8))

        #expect(simulators.first { $0.udid == Fixtures.iphone17Pro }?.runtime == "iOS 26.0")
        #expect(SimctlParser.fallbackRuntimeName("com.apple.CoreSimulator.SimRuntime.iOS-18-4") == "iOS 18.4")
    }

    @Test("Throws on malformed JSON")
    func throwsOnMalformedJSON() {
        #expect(throws: (any Error).self) {
            try SimctlParser.parse(devicesJSON: Data("not json".utf8))
        }
    }
}
