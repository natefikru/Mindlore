//
//  MindloreUITestsLaunchTests.swift
//  MindloreUITests
//
//  Created by Nate Fikru on 9/15/26.
//

import XCTest

final class MindloreUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }
}
