import XCTest

// Today against the demo journal, which is the only store with enough history to have an
// anniversary and threads still open. Dismissing a day card and acting on a thread are the parts
// worth driving through the real app: which cards appear, in what order, is decided in
// TodayComposerTests, on plain values.
//
// -resetDemoSettings clears the demo suite on launch, so a run starts from no dismissals however
// many times it has run today, and -resetDemoJournal reseeds the store dated from today, so the
// threads an earlier run marked done, or that have faded since it seeded, are open again.
final class TodayUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoJournal", "300"] + (reset ? ["-resetDemoSettings", "-resetDemoJournal"] : [])
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

    // A loose end's card opens Reflect's Loose ends, not the entry that raised it (owner, 2026-09-28).
    func testALooseEndCardOpensLooseEnds() throws {
        let app = launch(reset: true)
        XCTAssertTrue(app.otherElements["todayHeader"].waitForExistence(timeout: 20))

        // The row leads with the loose end that most needs attention.
        let thread = app.otherElements.matching(NSPredicate(format: "identifier IN %@", ["todayCard-stillOpen", "todayCard-dueToday"])).element(boundBy: 0)
        XCTAssertTrue(thread.waitForExistence(timeout: 5), "the demo journal has an open loose end")
        thread.buttons["todayCardOpen"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["reflectLooseEnds"].waitForExistence(timeout: 5), "lands on Reflect's Loose ends")
    }
}
