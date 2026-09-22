import XCTest

// Reflect's queue against the demo journal, which has enough loose ends and quiet names to have
// something to show without AI on (the demo suite starts with AI off, so only reused-signal cards
// appear; generated "Worth asking" cards need a key, which these tests don't set up). What a card
// says is decided in ReflectSignalsTests and ReflectSummaryStoreTests, on plain values; this drives
// the parts that only the real app can show: a tap landing on a prefilled editor, a month row
// expanding, and a dismissal surviving a relaunch.
final class ReflectUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoJournal", "300"] + (reset ? ["-resetDemoSettings"] : [])
        app.launch()
        return app
    }

    private func openReflect(_ app: XCUIApplication) {
        let weekStrip = app.descendants(matching: .any)["weekStrip"]
        XCTAssertTrue(weekStrip.waitForExistence(timeout: 20))
        weekStrip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reflectView"].waitForExistence(timeout: 5))
    }

    func testTappingACardOpensAPrefilledEntry() throws {
        let app = launch(reset: true)
        openReflect(app)

        let card = app.descendants(matching: .any).matching(identifier: "reflectQueueRow").element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 20), "a 300-entry demo journal has at least one open thread or quiet name")
        card.tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertFalse((editor.value as? String ?? "").isEmpty, "the card's prompt seeded the entry")
    }

    func testAMonthRowExpandsIntoItsWeeks() throws {
        let app = launch(reset: true)
        openReflect(app)

        let month = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'reflectMonth-'")).element(boundBy: 0)
        XCTAssertTrue(month.waitForExistence(timeout: 20), "a year-old demo journal has months before the recent stretch")
        month.tap()

        XCTAssertFalse(month.waitForExistence(timeout: 3), "the collapsed row is replaced by its weeks")
        let expandedWeek = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'reflectWeek-'")).element(boundBy: 0)
        XCTAssertTrue(expandedWeek.waitForExistence(timeout: 5))
    }

    func testADismissalOutlivesARelaunch() throws {
        var app = launch(reset: true)
        openReflect(app)

        let card = app.descendants(matching: .any).matching(identifier: "reflectQueueRow").element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        let dismissButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reflectDismiss-'"))
        XCTAssertTrue(dismissButtons.element(boundBy: 0).waitForExistence(timeout: 5))
        let identifier = dismissButtons.element(boundBy: 0).identifier
        dismissButtons.element(boundBy: 0).tap()

        XCTAssertFalse(app.buttons[identifier].waitForExistence(timeout: 2), "gone as it is dismissed")

        app.terminate()
        app = launch(reset: false)
        openReflect(app)

        XCTAssertFalse(app.buttons[identifier].waitForExistence(timeout: 5), "still dismissed after a relaunch")
    }
}
