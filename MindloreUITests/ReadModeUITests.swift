import XCTest

// Past entries open for reading; Edit switches to typing and Done returns. Stub AI, so the
// finished entry names Sarah and gets its insights (UITestingHTTPClient).
final class ReadModeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingAIReady", "-uiTestingFakeAI"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    private var editor: XCUIElement { app.textViews["entryEditor"] }
    // Read mode is the same text view made non-editable, so it is queried by identifier alone.
    private var readText: XCUIElement { app.descendants(matching: .any)["entryReadText"] }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func typeAtEnd(_ text: String) {
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)], timeout: 5)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        editor.typeText(text)
    }

    // Writes and finishes an entry, waits for its insights, and reopens it from the list.
    private func finishAndReopen() {
        app.launch()
        app.startNewWrittenEntry()
        typeAtEnd("Met Sarah by the river and felt calm about the move.")
        app.buttons["finishEntryButton"].tap()
        XCTAssertTrue(app.buttons["insightsReadyButton"].waitForExistence(timeout: 90))
        goBack()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Met Sarah'")).firstMatch.tap()
        XCTAssertTrue(readText.waitForExistence(timeout: 5))
    }

    @MainActor
    func testAFinishedEntryOpensForReadingAndEditReturnsToIt() throws {
        finishAndReopen()
        XCTAssertFalse(editor.exists)
        XCTAssertTrue(app.buttons["insightsButton"].exists)

        app.buttons["editEntryButton"].tap()
        // Edit puts the caret at the end, so typing straight away continues the entry.
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: editor)], timeout: 5)
        editor.typeText(" Later it rained.")
        app.buttons["doneEditingButton"].tap()

        XCTAssertTrue(readText.waitForExistence(timeout: 5))
        XCTAssertTrue((readText.value as? String)?.hasSuffix("Later it rained.") == true, readText.value as? String ?? "")
        XCTAssertFalse(editor.exists)

        goBack()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Later it rained.'")).firstMatch.waitForExistence(timeout: 5))
    }
}
