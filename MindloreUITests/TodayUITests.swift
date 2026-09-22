import XCTest

// Today against the demo journal, which is the only store with enough history to have an
// anniversary and threads still open. Dismissing a day card and acting on a thread are the parts
// worth driving through the real app: which cards appear, in what order, is decided in
// TodayComposerTests, on plain values.
//
// -resetDemoSettings clears the demo suite on launch, so a run starts from no dismissals however
// many times it has run today.
final class TodayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoJournal", "300"] + (reset ? ["-resetDemoSettings"] : [])
        app.launch()
        return app
    }

    func testTodayShowsCardsAndADismissalOutlivesALaunch() throws {
        var app = launch(reset: true)

        let header = app.otherElements["todayHeader"]
        XCTAssertTrue(header.waitForExistence(timeout: 20), "the journal opens onto Today")
        XCTAssertTrue(app.descendants(matching: .any)["weekStrip"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["todayRow"].exists, "the demo journal has something to say")

        // Only a day card has "not today"; the first one leads the row.
        let dismiss = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'todayDismiss-'")).element(boundBy: 0)
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        let kind = dismiss.identifier.replacingOccurrences(of: "todayDismiss-", with: "")
        let identifier = "todayCard-\(kind)"
        dismiss.tap()

        XCTAssertFalse(app.otherElements[identifier].waitForExistence(timeout: 2), "gone as it is tapped")

        // Relaunching without the reset keeps whatever the last run dismissed.
        app.terminate()
        app = launch(reset: false)

        XCTAssertTrue(app.otherElements["todayHeader"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.otherElements[identifier].exists, "still dismissed after a relaunch")
    }

    // Swipe along the row to a thread, mark it done, and the row is one card shorter.
    func testMarkingAThreadDoneTakesItOffTheRow() throws {
        let app = launch(reset: true)
        let row = app.descendants(matching: .any)["todayRow"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        let position = app.staticTexts["todayRowPosition"]
        XCTAssertTrue(position.waitForExistence(timeout: 5))
        let total = { Int(position.label.components(separatedBy: " of ").last ?? "") ?? 0 }
        let before = total()

        let done = app.buttons.matching(identifier: "threadDone")
        for _ in 0..<8 where !(done.allElementsBoundByIndex.contains { $0.isHittable }) {
            row.swipeLeft()
        }
        let button = try XCTUnwrap(done.allElementsBoundByIndex.first { $0.isHittable }, "the demo journal has an open thread")
        button.tap()

        let shorter = NSPredicate { _, _ in total() == before - 1 }
        wait(for: [XCTNSPredicateExpectation(predicate: shorter, object: nil)], timeout: 5)
    }

    func testTappingTheWeekStripOpensReflect() throws {
        let app = launch(reset: true)

        let weekStrip = app.descendants(matching: .any)["weekStrip"]
        XCTAssertTrue(weekStrip.waitForExistence(timeout: 20))
        weekStrip.tap()

        XCTAssertTrue(app.descendants(matching: .any)["reflectView"].waitForExistence(timeout: 5))
        // The sheet's own Done, not a thread card's Done button behind it.
        app.navigationBars.buttons["Done"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["reflectView"].waitForExistence(timeout: 2), "Done closes Reflect")
    }
}
