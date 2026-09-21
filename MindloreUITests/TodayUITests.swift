import XCTest

// Today against the demo journal, which is the only store with enough history to have an
// anniversary and a thread that has been open for months. The dismissal is the part worth driving
// through the real app: which card is chosen is decided in TodayComposerTests, on plain values.
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

        let cards = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'todayCard-'"))
        let before = cards.count
        XCTAssertGreaterThan(before, 0, "the demo journal has something to say")

        let first = cards.element(boundBy: 0)
        let identifier = first.identifier
        let kind = identifier.replacingOccurrences(of: "todayCard-", with: "")
        app.buttons["todayDismiss-\(kind)"].tap()

        XCTAssertFalse(app.otherElements[identifier].waitForExistence(timeout: 2), "gone as it is tapped")

        // Relaunching without the reset keeps whatever the last run dismissed.
        app.terminate()
        app = launch(reset: false)

        XCTAssertTrue(app.otherElements["todayHeader"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.otherElements[identifier].exists, "still dismissed after a relaunch")
    }

    func testTappingTheWeekStripOpensReflect() throws {
        let app = launch(reset: true)

        let weekStrip = app.descendants(matching: .any)["weekStrip"]
        XCTAssertTrue(weekStrip.waitForExistence(timeout: 20))
        weekStrip.tap()

        XCTAssertTrue(app.descendants(matching: .any)["reflectView"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["reflectView"].waitForExistence(timeout: 2), "Done closes Reflect")
    }
}
