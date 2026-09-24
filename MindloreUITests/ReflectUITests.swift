import XCTest

// Reflect's queue against the generated demo journal, which caches a plain summary for every
// finished week and month so there is something to show without a key, reseeded from today on
// each reset launch so those summaries reach the current week. What a summary says is decided in
// ReflectQueueGeneratorTests and ReflectSummaryStoreTests, on plain values; this drives the part
// that only the real app can show: a dismissal surviving a relaunch.
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
