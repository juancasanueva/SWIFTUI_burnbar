//
//  burnbarUITests.swift
//  burnbarUITests
//

import XCTest

/// A menu bar app has no window to inspect; this only checks it launches and stays running.
final class burnbarUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunches() throws {
        let app = XCUIApplication()
        // Keep the launched app offline: no Keychain read, no network, no transcript scan.
        app.launchEnvironment["BURNBAR_INERT"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10) || app.state == .runningBackground)
    }
}
