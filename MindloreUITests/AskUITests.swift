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
        app.tabBars.buttons["Chat"].tap()
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
        XCTAssertTrue(app.descendants(matching: .any)["entryReadText"].waitForExistence(timeout: 10))
        XCTAssertTrue((app.descendants(matching: .any)["entryReadText"].value as? String)?.contains("river") == true)
    }

    // The cost line is gone (owner, 2026-09-19): the chat no longer tells you what it is about to
    // read. What replaces it is this, a screen that says nothing at all while you type, with the
    // receipt still one tap away under an answer.
    // The tap that dismisses the keyboard sits on the whole conversation. A citation under an
    // answer is a control inside it, and has to keep working with the keyboard up.
    @MainActor
    func testACitationOpensItsEntryWhileTheKeyboardIsUp() throws {
        writeTheRiverEntry()
        openAsk()
        ask("What did I do by the river?")
        let citation = app.buttons["askCitation-E1"]
        XCTAssertTrue(citation.waitForExistence(timeout: 30))

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        citation.tap()

        XCTAssertTrue(app.descendants(matching: .any)["entryReadText"].waitForExistence(timeout: 10), "the chip opened its entry")
    }

    // The keyboard covers the tab bar, so it has to go away without sending anything: a tap on
    // empty space, or a drag down. A suggestion's own tap must still reach the field.
    // With nothing written, a suggestion would be a question nothing can answer.
    @MainActor
    func testAnEmptyJournalOffersNoSuggestions() throws {
        app.launch()
        openAsk()
        XCTAssertTrue(app.staticTexts["askEmptyState"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["askExample"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testTheKeyboardGoesAwaySoTheTabsCanBeReached() throws {
        // Suggestions only show once there is something to ask about.
        writeTheRiverEntry()
        openAsk()
        let journalTab = app.tabBars.buttons["Journal"]

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.staticTexts["askEmptyState"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "a tap on empty space dismisses")
        XCTAssertTrue(journalTab.isHittable)

        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // From something inside the conversation, since the tab view has scroll views of its own.
        app.staticTexts["askEmptyState"].swipeDown()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5), "a drag down dismisses")

        let suggestion = app.buttons["askExample"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "a suggestion still focuses the field")
        XCTAssertFalse((field.value as? String ?? "").isEmpty, "and fills it")
        // Nothing to dismiss past this point: with an entry in the journal, the filled field is
        // also showing its search results, which the tap and the drag above already cover.
    }

    @MainActor
    func testTypingAQuestionSaysNothingAboutWhatItWouldSend() throws {
        writeTheRiverEntry()
        openAsk()

        field.tap()
        field.typeText("What did I do by the river?")

        let entryRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'askSearchEntry-'")).firstMatch
        XCTAssertTrue(entryRow.waitForExistence(timeout: 10), "the panel still searches while you type")
        XCTAssertFalse(app.staticTexts["askCost"].exists)
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
