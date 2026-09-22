import XCTest

// Reflect's queue against the generated demo journal, which caches a plain summary for every
// finished week and month so there is something to show without a key, reseeded from today on
// each reset launch so those summaries reach the current week. What a summary says is decided in
// ReflectQueueGeneratorTests and ReflectSummaryStoreTests, on plain values; this drives the parts
// that only the real app can show: a tap landing on an entry with the card's prompt as a
// placeholder (not real, saved content), a month row expanding, and a dismissal surviving a
// relaunch.
final class ReflectUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoJournal", "300"] + (reset ? ["-resetDemoSettings", "-resetDemoJournal"] : [])
        app.launch()
        return app
    }

    private func openReflect(_ app: XCUIApplication) {
        let weekStrip = app.descendants(matching: .any)["weekStrip"]
        XCTAssertTrue(weekStrip.waitForExistence(timeout: 20))
        weekStrip.tap()
        let reflectView = app.descendants(matching: .any)["reflectView"]
        XCTAssertTrue(reflectView.waitForExistence(timeout: 5))
        // A LazyVStack's rows can exist visually before XCTest's accessibility tree walker
        // exposes them: a tiny nudge forces a layout pass so later element queries actually see
        // what's already on screen.
        app.swipeUp(velocity: .slow)
        app.swipeDown(velocity: .slow)
    }

    // Generous: a week with no cached summary yet generates on this appear, and when the
    // simulator's on-device model is what answers (FoundationModelsAvailability.isAvailable can be
    // true under the Simulator), that's real inference time, not an instant failure.
    private static let generationTimeout: TimeInterval = 60

    func testTappingACardOpensAnEntryWithThePromptAsAPlaceholder() throws {
        let app = launch(reset: true)
        openReflect(app)

        let card = app.descendants(matching: .any).matching(identifier: "reflectQueueRow").element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: Self.generationTimeout), "every finished week in the demo journal has a cached summary")
        card.tap()

        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").isEmpty, "nothing is saved until the user actually types")
        XCTAssertTrue(app.descendants(matching: .any)["entryStartingTextPlaceholder"].waitForExistence(timeout: 2), "the card's prompt shows as a hint")
    }

    func testAMonthRowExpandsIntoItsWeeks() throws {
        let app = launch(reset: true)
        openReflect(app)

        let month = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'reflectMonth-'")).element(boundBy: 0)
        XCTAssertTrue(month.waitForExistence(timeout: Self.generationTimeout), "a year-old demo journal has months before the recent stretch")
        // The exact identifier of the row tapped, not a live re-query: other collapsed month rows
        // below it match the same "reflectMonth-" prefix, so re-querying `.element(boundBy: 0)`
        // after the tap can find one of those instead and wrongly look like nothing changed.
        let tappedIdentifier = month.identifier
        // The row is off the bottom of the screen (a year-old demo journal has plenty above it).
        // `.tap()` on an off-screen element auto-scrolls to it and taps immediately, and that tap
        // can land while the scroll view is still decelerating and get read as part of the
        // gesture rather than a discrete tap, so the row never toggles open. Scrolling the
        // ScrollView itself first, settling, and only then tapping (now that the element is
        // already on screen and needs no further auto-scroll) avoids that.
        let scrollView = app.scrollViews["reflectView"]
        for _ in 0..<6 where !month.isHittable {
            scrollView.swipeUp()
        }
        XCTAssertTrue(month.isHittable, "scrolled the tapped row into view")
        Thread.sleep(forTimeInterval: 1)
        // A coordinate tap, computed fresh now that the row is confirmed on screen, rather than
        // `.tap()`'s own hit-point heuristic (which can be stale immediately after a scroll).
        month.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertFalse(app.buttons[tappedIdentifier].waitForExistence(timeout: 3), "the tapped row is replaced by its weeks")
        let expandedWeek = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'reflectWeek-'")).element(boundBy: 0)
        XCTAssertTrue(expandedWeek.waitForExistence(timeout: 5))
    }

    func testADismissalOutlivesARelaunch() throws {
        var app = launch(reset: true)
        openReflect(app)

        let card = app.descendants(matching: .any).matching(identifier: "reflectQueueRow").element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: Self.generationTimeout))
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
