import XCTest

// Done and Let it go on a thread card take it off Today's row at once. Run against the story
// journal, whose row always opens on an open thread. The row used to wait for an unrelated redraw,
// because the save it relied on moves a counter SwiftUI doesn't observe.
final class TodayThreadActionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedStoryJournal", "-resetStoryJournal", "-resetDemoSettings"]
        app.launch()
        return app
    }

    private func total(_ app: XCUIApplication) -> Int {
        Int(app.staticTexts["todayRowPosition"].label.components(separatedBy: " of ").last ?? "") ?? 0
    }

    private func hittable(_ id: String, in app: XCUIApplication) -> XCUIElement? {
        app.buttons.matching(identifier: id).allElementsBoundByIndex.first { $0.isHittable }
    }

    func testDoneAndLetGoTakeTheCardOffTheRow() throws {
        let app = launch()
        XCTAssertTrue(app.staticTexts["todayRowPosition"].waitForExistence(timeout: 60))

        for action in ["threadDone", "threadLetGo"] {
            XCTAssertTrue(app.buttons[action].firstMatch.waitForExistence(timeout: 10))
            // The row keeps its place, so page back to the start, then along to a thread card.
            let row = app.descendants(matching: .any)["todayRow"]
            for _ in 0..<3 where hittable(action, in: app) == nil { row.swipeRight() }
            for _ in 0..<8 where hittable(action, in: app) == nil { row.swipeLeft() }
            let before = total(app)
            let button = try XCTUnwrap(hittable(action, in: app), "the story journal has an open thread")
            button.tap()
            let shorter = NSPredicate { _, _ in self.total(app) == before - 1 }
            XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: shorter, object: nil)], timeout: 3), .completed, "\(action) took the card off the row")
        }
    }
}
