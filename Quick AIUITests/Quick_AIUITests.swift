//
//  Quick_AIUITests.swift
//  Quick AIUITests
//
//  Created by Camin McCluskey on 05/02/2026.
//

import XCTest

final class Quick_AIUITests: XCTestCase {
    private var defaultsSuite: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        defaultsSuite = "ui.tests.quickai.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        if let suite = defaultsSuite, let defaults = UserDefaults(suiteName: suite) {
            defaults.removePersistentDomain(forName: suite)
            defaults.synchronize()
        }
    }

    @MainActor
    func testLaunchDoesNotOpenStandardWindow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["QUICK_AI_DEFAULTS_SUITE"] = defaultsSuite
        app.launchEnvironment["QUICK_AI_KEYCHAIN_SERVICE"] = "ui.tests.quickai.keychain.\(UUID().uuidString)"
        app.launch()

        XCTAssertEqual(app.windows.count, 0)
    }

    @MainActor
    func testLaunchAllowsBackgroundLifecycle() throws {
        let app = XCUIApplication()
        app.launchEnvironment["QUICK_AI_DEFAULTS_SUITE"] = defaultsSuite
        app.launchEnvironment["QUICK_AI_KEYCHAIN_SERVICE"] = "ui.tests.quickai.keychain.\(UUID().uuidString)"
        app.launch()

        let launched = app.wait(for: .runningForeground, timeout: 5)
            || app.wait(for: .runningBackground, timeout: 1)
        XCTAssertTrue(launched)
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }
}
