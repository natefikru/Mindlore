import XCTest

// The + in the tab bar: it never takes the user anywhere by itself, and a tap leaves its half circle
// open for a choice. The slide from the + onto an option isn't covered here: a synthesized
// press-and-drag passed on a Mac and failed every try on a CI runner (2026-09-25).
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
}
