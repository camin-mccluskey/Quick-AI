//
//  Quick_AIUITestsLaunchTests.swift
//  Quick AIUITests
//
//  Created by Camin McCluskey on 05/02/2026.
//

import XCTest

final class Quick_AIUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["QUICK_AI_DEFAULTS_SUITE"] = "ui.tests.quickai.launch.\(UUID().uuidString)"
        app.launchEnvironment["QUICK_AI_KEYCHAIN_SERVICE"] = "ui.tests.quickai.keychain.\(UUID().uuidString)"
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
