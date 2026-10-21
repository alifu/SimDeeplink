//
//  SimDeeplinkUITests.swift
//  SimDeeplinkUITests
//
//  Created by Alif on 16/10/25.
//

import XCTest

/// Runs the real window with canned devices (`-UITest`), so no simulator or emulator is needed.
final class SimDeeplinkUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITest"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Helpers

    private var outputText: XCUIElement { app.staticTexts["outputText"] }

    private func waitForOutput(containing text: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", text, text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: outputText)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func enterDeeplink(_ text: String, field: String) {
        let deeplinkField = app.textFields[field]
        XCTAssertTrue(deeplinkField.waitForExistence(timeout: 5))
        deeplinkField.click()
        deeplinkField.typeText(text)
    }

    private func openComboBox(_ identifier: String) {
        let comboBox = app.comboBoxes[identifier]
        XCTAssertTrue(comboBox.waitForExistence(timeout: 5))
        comboBox.buttons.firstMatch.click()
    }

    /// Entries of the open combo box list are text fields inside the combo box.
    private func comboItem(_ identifier: String, containing text: String) -> XCUIElement {
        app.comboBoxes[identifier].textFields.matching(NSPredicate(format: "value CONTAINS %@", text)).firstMatch
    }

    private func enableSection(_ toggle: String) {
        let toggleSwitch = app.switches[toggle]
        XCTAssertTrue(toggleSwitch.waitForExistence(timeout: 5))
        toggleSwitch.click()
    }

    private func showAndroidTab() {
        app.tabs["Android Emulator"].click()
    }

    // MARK: - Simulator tab

    @MainActor
    func testWindowShowsBothTabs() {
        XCTAssertTrue(app.tabs["Apple Simulator"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabs["Android Emulator"].exists)
        XCTAssertTrue(app.buttons["exitButton"].exists)
    }

    @MainActor
    func testInvalidDeeplinkShowsError() {
        enterDeeplink("not a link", field: "simulatorDeeplinkField")
        app.buttons["simulatorExecuteButton"].click()

        XCTAssertTrue(waitForOutput(containing: "Invalid Deeplink URL"))
    }

    @MainActor
    func testValidDeeplinkOpensOnTheBootedSimulator() {
        enterDeeplink("myapp://home", field: "simulatorDeeplinkField")
        app.buttons["simulatorExecuteButton"].click()

        XCTAssertTrue(waitForOutput(containing: "Opened myapp://home"))
    }

    @MainActor
    func testSimulatorSectionListsIPhoneAndIPad() {
        enableSection("simulatorToggle")
        openComboBox("simulatorComboBox")

        XCTAssertTrue(comboItem("simulatorComboBox", containing: "iPhone 17 Pro").waitForExistence(timeout: 5))
        XCTAssertTrue(comboItem("simulatorComboBox", containing: "iPad Pro 13-inch (M5)").exists)
    }

    @MainActor
    func testResetClearsTheField() {
        enterDeeplink("bad url", field: "simulatorDeeplinkField")
        app.buttons["simulatorExecuteButton"].click()
        XCTAssertTrue(waitForOutput(containing: "Invalid"))

        app.buttons["simulatorResetButton"].click()

        XCTAssertEqual((app.textFields["simulatorDeeplinkField"].value as? String) ?? "", "")
    }

    // MARK: - Android tab

    @MainActor
    func testEmulatorSectionListsAvds() {
        showAndroidTab()
        enableSection("emulatorToggle")
        openComboBox("emulatorComboBox")

        XCTAssertTrue(comboItem("emulatorComboBox", containing: "Pixel_8_API_35").waitForExistence(timeout: 5))
        XCTAssertTrue(comboItem("emulatorComboBox", containing: "Pixel_Tablet_API_35").exists)
    }

    @MainActor
    func testEmulatorDeeplinkRunsOnTheOnlyRunningEmulator() {
        showAndroidTab()
        enterDeeplink("myapp://home", field: "emulatorDeeplinkField")
        app.buttons["emulatorExecuteButton"].click()

        XCTAssertTrue(waitForOutput(containing: "Starting: Intent"))
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let launched = XCUIApplication()
            launched.launchArguments = ["-UITest"]
            launched.launch()
            launched.terminate()
        }
    }
}
