import XCTest

// Screenshots of the Ask tab for looking at by eye: the empty state, the field with results, a
// search that finds nothing, and an answer with its citations. Nothing is asserted about how it
// looks; these exist so a person can see the screen without holding the phone.
final class AskScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private var field: XCUIElement { app.textFields["askField"] }

    // The 300-entry demo journal, which has real names, tags, and entries to search.
    @MainActor
    func testDemoJournalAsk() throws {
        app.launchArguments = ["-seedDemoJournal", "300"]
        app.launch()

        let ask = app.tabBars.buttons["Ask"]
        XCTAssertTrue(ask.waitForExistence(timeout: 60))
        ask.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        sleep(1)
        attach("ask-empty")

        field.tap()
        field.typeText("river")
        sleep(2)
        attach("ask-search-results")

        field.typeText("zzzq")
        sleep(2)
        attach("ask-search-nothing-found")
    }

    @MainActor
    func testAnswerWithCitations() throws {
        app.launchArguments = ["-uiTesting", "-uiTestingAIReady", "-uiTestingFakeAI"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
        app.launch()

        app.buttons["newEntryButton"].tap()
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Met Sarah by the river and felt calm about the move.")
        app.buttons["finishEntryButton"].tap()
        XCTAssertTrue(app.buttons["insightsReadyButton"].waitForExistence(timeout: 90))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.tabBars.buttons["Ask"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("What did I do by the river?")
        sleep(1)
        attach("ask-typed-question")
        app.buttons["askSend"].tap()
        XCTAssertTrue(app.staticTexts["askAnswer"].waitForExistence(timeout: 30))
        sleep(1)
        attach("ask-answer")

        app.buttons["askWhatWasSent"].firstMatch.tap()
        sleep(1)
        attach("ask-what-was-sent")
        app.buttons["Done"].firstMatch.tap()

        app.buttons["askHistory"].tap()
        sleep(1)
        attach("ask-history")
    }
}
