import XCTest

final class TitleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    @MainActor
    func testATitleWithoutTextKeepsTheEntry() throws {
        app.launch()
        let newEntry = app.buttons["newEntryButton"]
        XCTAssertTrue(newEntry.waitForExistence(timeout: 5))
        newEntry.tap()

        let titleField = app.textFields["entryTitleField"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: titleField)], timeout: 5)
        titleField.tap()
        titleField.typeText("Groceries for Sunday")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.terminate()
        app.launch()

        XCTAssertTrue(app.staticTexts["Groceries for Sunday"].waitForExistence(timeout: 5))
    }
}
