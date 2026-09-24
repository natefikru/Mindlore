import XCTest

// The bar above the keyboard: layout survives a relaunch beside the plain words.
final class FormattingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    private var editor: XCUIElement { app.textViews["entryEditor"] }

    private func startEntry() {
        app.launch()
        app.startNewWrittenEntry()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: editor)], timeout: 5)
    }

    @MainActor
    func testFormattingSurvivesARelaunch() throws {
        startEntry()
        editor.typeText("Call the landlord")
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: app.buttons["format-check"])], timeout: 5)
        app.buttons["format-check"].tap()
        XCTAssertTrue(app.buttons["format-check"].isSelected)
        app.buttons["finishEntryButton"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.terminate()
        app.launch()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Call the landlord'")).firstMatch.tap()
        let readText = app.descendants(matching: .any)["entryReadText"]
        XCTAssertTrue(readText.waitForExistence(timeout: 5))
        XCTAssertEqual(readText.value as? String, "Call the landlord")
        app.buttons["editEntryButton"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: editor)], timeout: 5)
        XCTAssertTrue(app.buttons["format-check"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["format-check"].isSelected, "the checklist came back with the words")
    }
}
