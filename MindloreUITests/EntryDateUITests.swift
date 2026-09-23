import XCTest

final class EntryDateUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    @MainActor
    func testBackdatingAnEntrySurvivesRelaunch() throws {
        app.launch()
        let newEntry = app.buttons["newEntryButton"]
        XCTAssertTrue(newEntry.waitForExistence(timeout: 5))
        newEntry.tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)], timeout: 5)
        editor.tap()
        editor.typeText("Written last month")

        app.buttons["entryMoreButton"].tap()
        let dateButton = app.buttons["entryDateButton"]
        XCTAssertTrue(dateButton.waitForExistence(timeout: 5))
        dateButton.tap()

        let previousMonth = app.buttons["Previous Month"]
        XCTAssertTrue(previousMonth.waitForExistence(timeout: 5))
        previousMonth.tap()
        // Day buttons in the graphical picker are labeled like "Friday, August 1".
        let firstOfMonth = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*[A-Za-z] 1$")).firstMatch
        XCTAssertTrue(firstOfMonth.waitForExistence(timeout: 5))
        firstOfMonth.tap()
        app.buttons["entryDateDoneButton"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.terminate()
        app.launch()

        XCTAssertTrue(app.staticTexts["Written last month"].waitForExistence(timeout: 5))
        // The day it was added is not shown: the day it belongs to is the only date the row carries.
        let added = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Added ")).firstMatch
        XCTAssertFalse(added.waitForExistence(timeout: 2))
    }
}
