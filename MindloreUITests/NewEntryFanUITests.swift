import XCTest

// The + in the tab bar: it never takes the user anywhere by itself, a tap leaves its half circle
// open for a choice, and a slide from the + onto an option starts it on release.
final class NewEntryFanUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingFakeRecorder"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    func testTapOpensTheFanAndTheTabStaysPut() {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Mind"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Mind"].tap()
        app.openNewEntryFan()
        for option in ["write", "record"] {
            XCTAssertTrue(app.buttons["newEntryFan-\(option)"].waitForExistence(timeout: 5), option)
        }
        XCTAssertTrue(app.tabBars.buttons["Mind"].isSelected, "the + is never the selected tab")
        app.buttons["newEntryFanBackdrop"].tap()
        XCTAssertTrue(app.buttons["newEntryFan-write"].waitForNonExistence(timeout: 5))

        app.chooseFromNewEntryFan("write")
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Journal"].isSelected)
    }

    func testSlidingFromThePlusOntoRecordStartsRecording() {
        app.launch()
        let plus = app.tabBars.buttons["New"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        // Record sits straight above the +, the arc's radius plus its lift away.
        let start = plus.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -140)))
        XCTAssertTrue(app.buttons["finishRecordingButton"].waitForExistence(timeout: 10), "the recorder is up and recording")
    }
}
