import XCTest

// Saving has no Save button, so these prove text is on disk after the ways an entry can end:
// a force-quit mid-sentence, leaving the app, and editing later. Each app launch costs about ten
// seconds, so the checks are grouped into two runs rather than one per behavior.
final class ContinuousSaveUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    @MainActor
    func testTextSurvivesForceQuitLeavingTheAppAndLaterEdits() throws {
        app.launch()
        startNewEntry()
        editor.typeText("Walked to the river this morning.")

        // Killed while still typing, with no save step taken.
        sleep(2)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Walked to the river this morning."].waitForExistence(timeout: 5))

        // Editing an existing entry, then leaving the app, saves immediately.
        app.staticTexts["Walked to the river this morning."].tap()
        focusEditor()
        editor.typeText(" The light was strange.")
        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launch()

        XCTAssertTrue(app.staticTexts["Walked to the river this morning. The light was strange."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEntriesWithNothingInThemDoNotStickAround() throws {
        app.launch()

        // Opening a new entry and leaving without typing.
        startNewEntry()
        goBack()
        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))

        // Clearing an entry's text deletes it, and it stays deleted.
        startNewEntry()
        editor.typeText("oops")
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        goBack()
        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))

        // Swipe to delete, also across a relaunch.
        startNewEntry()
        editor.typeText("Delete me")
        goBack()
        let row = app.staticTexts["Delete me"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))
    }

    private var editor: XCUIElement {
        app.textViews["entryEditor"]
    }

    private func startNewEntry() {
        let newEntry = app.buttons["newEntryButton"]
        XCTAssertTrue(newEntry.waitForExistence(timeout: 5))
        newEntry.tap()
        focusEditor()
    }

    // Taps sent during the navigation push animation are dropped, so wait until the editor is hittable first.
    private func focusEditor() {
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)
        wait(for: [hittable], timeout: 5)
        editor.tap()
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }
}
