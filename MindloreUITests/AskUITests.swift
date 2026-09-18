import XCTest

// The Ask tab against the app's stubbed OpenAI: search as you type, an answer with a citation,
// and conversations that survive a relaunch. The stub answers a journal_ask request with the
// first handle the request actually carried, so the chip points at a real entry.
final class AskUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storeName = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        storeName = UUID().uuidString
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingAIReady", "-uiTestingFakeAI"]
        app.launchEnvironment = ["UITEST_STORE_NAME": storeName]
    }

    private var field: XCUIElement { app.textFields["askField"] }

    // One finished entry with its insights, so the journal has an entry, a tag, and Sarah in it.
    private func writeTheRiverEntry() {
        app.launch()
        app.buttons["newEntryButton"].tap()
        let editor = app.textViews["entryEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)], timeout: 5)
        editor.tap()
        editor.typeText("Met Sarah by the river and felt calm about the move.")
        app.buttons["finishEntryButton"].tap()
        XCTAssertTrue(app.buttons["insightsReadyButton"].waitForExistence(timeout: 90))
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func openAsk() {
        app.tabBars.buttons["Ask"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
    }

    private func ask(_ question: String) {
        field.tap()
        field.typeText(question)
        app.buttons["askSend"].tap()
    }

    @MainActor
    func testAskSearchesAsYouType() throws {
        writeTheRiverEntry()
        openAsk()

        field.tap()
        field.typeText("river")

        let tag = app.buttons["askSearchTag-river"]
        XCTAssertTrue(tag.waitForExistence(timeout: 10), "the entry's tag shows as a row")
        let entryRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'askSearchEntry-'")).firstMatch
        XCTAssertTrue(entryRow.waitForExistence(timeout: 5))

        entryRow.tap()

        // Journal opens the entry for reading, since it is finished.
        XCTAssertTrue(app.staticTexts["entryReadText"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["entryReadText"].label.contains("river"))
    }

    // The cost line is the one place the app tells you what asking will send, and it is built from
    // a conditional string. Built as a String rather than Text it rendered its own inflection markup
    // on screen, and every unit test passed while it did.
    @MainActor
    func testTheCostLineReadsLikeASentence() throws {
        writeTheRiverEntry()
        openAsk()

        field.tap()
        field.typeText("What did I do by the river?")

        let cost = app.staticTexts["askCost"]
        XCTAssertTrue(cost.waitForExistence(timeout: 10))
        XCTAssertFalse(cost.label.contains("inflect"), "the line is showing its own markup: \(cost.label)")
        XCTAssertFalse(cost.label.contains("^["), "the line is showing its own markup: \(cost.label)")
        XCTAssertTrue(cost.label.contains("1 entry"), cost.label)
    }

    @MainActor
    func testAskAnswersWithACitationAndKeepsHistory() throws {
        writeTheRiverEntry()
        openAsk()

        ask("What did I do by the river?")

        let answer = app.staticTexts["askAnswer"]
        XCTAssertTrue(answer.waitForExistence(timeout: 30))
        XCTAssertEqual(answer.label, "You walked by the river with Sarah.")
        XCTAssertTrue(app.buttons["askCitation-E1"].waitForExistence(timeout: 5))

        // What was sent: one entry, and the count says so.
        app.buttons["askWhatWasSent"].firstMatch.tap()
        let entries = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Entries' AND label CONTAINS '1'")).firstMatch
        XCTAssertTrue(entries.waitForExistence(timeout: 5))
        app.buttons["Done"].firstMatch.tap()

        // A new conversation starts empty.
        app.buttons["askNewConversation"].tap()
        XCTAssertTrue(app.staticTexts["askEmptyState"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["askAnswer"].exists)

        // History reopens the first one, and it can be carried on.
        app.buttons["askHistory"].tap()
        let row = app.buttons["askHistoryRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["askAnswer"].waitForExistence(timeout: 5))

        ask("And who was with me?")
        let answers = app.staticTexts.matching(identifier: "askAnswer")
        XCTAssertTrue(NSPredicate(format: "count == 2").evaluate(with: answers) ||
                      XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: answers)], timeout: 30) == .completed)

        // The conversation survives a relaunch, and swiping deletes it.
        app.terminate()
        app.launch()
        openAsk()
        app.buttons["askHistory"].tap()
        let saved = app.buttons["askHistoryRow"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["askHistoryRow"].firstMatch)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
    }
}
