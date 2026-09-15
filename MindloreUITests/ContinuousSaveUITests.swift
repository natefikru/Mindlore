import XCTest

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
    func testTypedTextSurvivesTheAppBeingKilledWhileStillEditing() throws {
        app.launch()
        startNewEntry()
        editor.typeText("Walked to the river this morning.")

        sleep(2)
        app.terminate()
        app.launch()

        XCTAssertTrue(app.staticTexts["Walked to the river this morning."].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLeavingTheAppSavesImmediately() throws {
        app.launch()
        startNewEntry()
        editor.typeText("Saved on the way out")

        XCUIDevice.shared.press(.home)
        app.terminate()
        app.launch()

        XCTAssertTrue(app.staticTexts["Saved on the way out"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testEditingAnExistingEntryIsSaved() throws {
        app.launch()
        startNewEntry()
        editor.typeText("First draft")
        goBack()

        app.staticTexts["First draft"].tap()
        focusEditor()
        editor.typeText(" and more")
        goBack()

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["First draft and more"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testOpeningANewEntryWithoutTypingLeavesNothingBehind() throws {
        app.launch()
        startNewEntry()
        goBack()

        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testClearingAllTextDeletesTheEntry() throws {
        app.launch()
        startNewEntry()
        editor.typeText("oops")
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        goBack()

        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSwipeDeleteStaysDeletedAfterRelaunch() throws {
        app.launch()
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
