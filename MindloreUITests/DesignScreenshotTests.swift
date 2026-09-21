import XCTest

// Phase B: the app's skin on the 300-entry demo journal, in light and dark, for looking at by eye.
// Nothing here asserts what a screen looks like; pull the attachments out with
// `xcrun xcresulttool export attachments` and look.
//
// `XCUIDevice.shared.appearance` does not reach the simulator, so the appearance is set outside:
//   xcrun simctl ui <udid> appearance dark
//   TEST_RUNNER_DESIGN_APPEARANCE=dark xcodebuild ... -only-testing:MindloreUITests/DesignScreenshotTests
// The variable only names the screenshots.
final class DesignScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // The demo seed only runs outside -uiTesting, so this launch uses the demo store alone.
        app.launchArguments = ["-seedDemoJournal", "300"]
    }

    private func attach(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testTour() throws {
        let tag = ProcessInfo.processInfo.environment["DESIGN_APPEARANCE"] ?? "light"
        app.launch()

        let journal = app.tabBars.buttons["Journal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 60))
        journal.tap()
        let row = app.descendants(matching: .any)["entryRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        attach("\(tag)-journal")

        XCTAssertTrue(app.otherElements["todayHeader"].exists, "Today sits above the rows")
        attach("\(tag)-today")

        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["entryReadText"].waitForExistence(timeout: 10))
        attach("\(tag)-read-mode")
        if app.buttons["insightsButton"].exists {
            app.buttons["insightsButton"].tap()
            attach("\(tag)-insights-sheet")
            app.swipeDown(velocity: .fast)
        }
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["Mind"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mindGraphCanvas"].waitForExistence(timeout: 10))
        sleep(5)
        attach("\(tag)-mind")

        app.tabBars.buttons["Ask"].tap()
        attach("\(tag)-ask")
    }
}
