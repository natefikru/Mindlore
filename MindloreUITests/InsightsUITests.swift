import XCTest

// Writing an entry, finishing it, reading its insights, and running them again after an edit.
// Runs against real OpenAI when TEST_RUNNER_MINDLORE_OPENAI_KEY is set, else the app's stub.
final class InsightsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingAIReady"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
        if let key = ProcessInfo.processInfo.environment["MINDLORE_OPENAI_KEY"], !key.isEmpty {
            app.launchEnvironment["MINDLORE_OPENAI_KEY"] = key
        } else {
            app.launchArguments.append("-uiTestingFakeAI")
        }
    }

    private var editor: XCUIElement { app.textViews["entryEditor"] }

    // The button's label is the state, so waiting on it is waiting for the screen to catch up.
    private func waitForRunButton(_ label: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app.buttons["runInsightsButton"])], timeout: timeout) == .completed
    }

    private func typeEntry(_ text: String) {
        app.buttons["newEntryButton"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)], timeout: 5)
        editor.tap()
        editor.typeText(text)
    }

    @MainActor
    func testFinishReadInsightsEditRerunAndDelete() throws {
        app.launch()
        typeEntry("Met Sarah by the river and felt calm about the move. I still need to call the landlord.")

        // Done finishes the draft and starts insights; the editor says when they're ready.
        app.buttons["finishEntryButton"].tap()
        let ready = app.buttons["insightsReadyButton"]
        XCTAssertTrue(ready.waitForExistence(timeout: 90))
        ready.tap()

        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Moods"].exists)
        XCTAssertTrue(waitForRunButton("Generate again"))

        // Calling the landlord is a loose end; marking it done sticks.
        let open = app.descendants(matching: .any)["looseEnd-open"].firstMatch
        var swipes = 0
        while !open.exists && swipes < 6 {
            app.scrollViews["insightsSheet"].swipeUp()
            swipes += 1
        }
        XCTAssertTrue(open.exists, "the entry left a loose end")
        app.buttons["looseEndMenu"].firstMatch.tap()
        app.buttons["Mark done"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["looseEnd-resolved"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()

        // Editing the entry makes the insights out of date.
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" We also talked about the garden.")
        app.buttons["insightsButton"].tap()
        let explanation = app.staticTexts["insightsExplanation"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertEqual(explanation.label, "Your entry changed since these insights.")
        XCTAssertTrue(waitForRunButton("Update insights"))

        app.buttons["runInsightsButton"].tap()
        let updated = NSPredicate(format: "exists == false")
        wait(for: [XCTNSPredicateExpectation(predicate: updated, object: app.staticTexts["insightsExplanation"])], timeout: 90)
        XCTAssertTrue(waitForRunButton("Generate again", timeout: 90))

        // Delete insights: the entry stays, the insights don't.
        app.buttons["insightsMenuButton"].tap()
        app.buttons["Delete insights"].tap()
        app.buttons["confirmDeleteInsightsButton"].firstMatch.tap()
        // Deleting inside the sheet doesn't start a run on its own; that's still the user's call.
        XCTAssertTrue(waitForRunButton("Generate insights"), "got \(app.buttons["runInsightsButton"].label)")
        app.buttons["Done"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        // With no insights, the entry's Insights button generates them without a second tap.
        app.buttons["insightsButton"].tap()
        XCTAssertTrue(waitForRunButton("Generate again", timeout: 90), "got \(app.buttons["runInsightsButton"].label)")
        XCTAssertTrue(app.staticTexts["Summary"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
    }
}
