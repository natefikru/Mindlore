import XCTest

// Reflect's Life side against the generated demo journal, which carries a year of insights with
// areas and moods: the tab opens on Life, the bubbles are there, and a bubble opens its area.
final class LifeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReflectOpensOnLifeAndABubbleOpensItsArea() {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoJournal", "300", "-resetDemoSettings", "-resetDemoJournal"]
        app.launch()
        let reflect = app.tabBars.buttons["Reflect"]
        XCTAssertTrue(reflect.waitForExistence(timeout: 60))
        reflect.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lifeView"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["lifeHeadline"].waitForExistence(timeout: 10))
        let bubble = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'lifeBubble-'")).firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 10))
        bubble.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lifeAreaView"].waitForExistence(timeout: 10))
    }
}
