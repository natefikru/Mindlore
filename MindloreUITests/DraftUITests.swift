import XCTest

final class DraftUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    @MainActor
    func testWriteLeaveComeBackAndFinish() throws {
        app.launch()
        app.buttons["newEntryButton"].tap()
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)], timeout: 5)
        editor.tap()
        editor.typeText("Started this on the train")

        // Leaving keeps it as a draft, across a relaunch.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Draft"].waitForExistence(timeout: 5))

        app.staticTexts["Started this on the train"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)], timeout: 5)
        // Past the end of the line, so the caret lands after the draft rather than at the activation
        // point, which sits at the start of the text.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        editor.typeText(" and finished at home.")

        let done = app.buttons["finishEntryButton"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertFalse(done.waitForExistence(timeout: 2))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Started this on the train and finished at home."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Draft"].exists)
    }
}
