import XCTest

// Photo entries end to end. Generated pages stand in for the camera. With TEST_RUNNER_MINDLORE_OPENAI_KEY
// set, the app runs against real OpenAI with that key saved into this test's own Keychain; without it,
// the app's OpenAI stub answers instead.
final class PageTranscriptionUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingFakePages", "-uiTestingAIReady"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
        if let key = ProcessInfo.processInfo.environment["MINDLORE_OPENAI_KEY"], !key.isEmpty {
            app.launchEnvironment["MINDLORE_OPENAI_KEY"] = key
        } else {
            app.launchArguments.append("-uiTestingFakeAI")
        }
    }

    private var editorText: String {
        (app.textViews["entryEditor"].value as? String ?? "").lowercased()
    }

    // True when every phrase appears, in this order.
    private func textContainsInOrder(_ phrases: [String]) -> Bool {
        var remaining = editorText[...]
        for phrase in phrases {
            guard let range = remaining.range(of: phrase.lowercased()) else { return false }
            remaining = remaining[range.upperBound...]
        }
        return true
    }

    private func waitForText(_ phrases: [String], timeout: TimeInterval = 120) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if textContainsInOrder(phrases) { return true }
            _ = app.textViews["entryEditor"].waitForExistence(timeout: 2)
        }
        return false
    }

    @MainActor
    func testTranscribeReviewApproveAndRestartPages() throws {
        app.launch()
        app.buttons["newPhotoEntryButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pageRow-1000"].waitForExistence(timeout: 10))

        let confirm = app.buttons["confirmPagesButton"]
        XCTAssertEqual(confirm.label, "Transcribe 3 pages")
        confirm.tap()

        // The editor fills with each page's text in order and waits for review.
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForText(["fixture page 1", "fixture page 2", "fixture page 3"]), "got \(editorText)")
        XCTAssertTrue(app.buttons["approveTextButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Written on March 3, 2025")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["pageStrip"].exists)

        app.buttons["approveTextButton"].tap()
        XCTAssertFalse(app.buttons["approveTextButton"].waitForExistence(timeout: 2))

        // Editing pages and cancelling changes nothing.
        app.buttons["editPagesButton"].tap()
        XCTAssertTrue(app.buttons["pageOrderCloseButton"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["pageOrderCloseButton"].label, "Cancel")
        app.buttons["pageOrderCloseButton"].tap()
        XCTAssertTrue(waitForText(["fixture page 1", "fixture page 2", "fixture page 3"], timeout: 5))

        // Removing a page warns, then erases and transcribes the remaining pages again.
        app.buttons["editPagesButton"].tap()
        app.buttons["Remove page 1"].tap()
        let confirmRemove = app.buttons["confirmRemovePageButton"].firstMatch
        XCTAssertTrue(confirmRemove.waitForExistence(timeout: 5))
        confirmRemove.tap()
        app.buttons["confirmPagesButton"].tap()
        let restart = app.buttons["confirmRestartPagesButton"].firstMatch
        XCTAssertTrue(restart.waitForExistence(timeout: 5))
        restart.tap()

        XCTAssertTrue(waitForText(["fixture page 2", "fixture page 3"]), "got \(editorText)")
        XCTAssertFalse(editorText.contains("fixture page 1"))
        XCTAssertTrue(app.buttons["approveTextButton"].waitForExistence(timeout: 10))

        // Relaunch: the reviewed-but-unapproved state survives.
        app.terminate()
        app.launch()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Fixture page 2")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["approveTextButton"].waitForExistence(timeout: 5))
    }
}
