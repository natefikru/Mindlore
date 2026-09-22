import XCTest

final class WelcomeUITests: XCTestCase {
    func testStartClosesTheWelcomeOntoAnEmptyJournal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-showWelcome"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["welcomeView"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "welcome"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["welcomeStart"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["welcomeView"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["journalEmptyRecord"].waitForExistence(timeout: 5))
    }
}
