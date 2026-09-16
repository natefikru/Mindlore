import XCTest

// Entering an entity's page from a chip, seeing its AI-drafted bio, editing it, and opening a
// tag's page. Stub only: real OpenAI names people however it likes, so nothing here can assert
// a name (tasks/todo.md, Phase 5a).
final class GraphUITests: XCTestCase {
    private var app: XCUIApplication!
    private var storeName: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        storeName = UUID().uuidString
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingAIReady", "-uiTestingFakeAI"]
        app.launchEnvironment = ["UITEST_STORE_NAME": storeName]
    }

    private var editor: XCUIElement { app.textViews["entryEditor"] }

    private func waitForRunButton(_ label: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "label == %@", label)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app.buttons["runInsightsButton"])], timeout: timeout) == .completed
    }

    private func startNewEntry() {
        let newEntry = app.buttons["newEntryButton"]
        XCTAssertTrue(newEntry.waitForExistence(timeout: 5))
        newEntry.tap()
        focusEditor()
    }

    private func focusEditor() {
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)
        wait(for: [hittable], timeout: 5)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // The insights sheet is a lazily rendered list; a chip below the fold isn't in the tree
    // until it's scrolled into view.
    private func scrollToElement(_ element: XCUIElement, in container: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            container.swipeUp()
            swipes += 1
        }
    }

    // The stub's fixed insights payload names Sarah and tags "river" (UITestingHTTPClient).
    private func finishEntryAndOpenInsights() {
        app.launch()
        startNewEntry()
        editor.typeText("Met Sarah by the river and felt calm about the move.")
        app.buttons["finishEntryButton"].tap()
        let ready = app.buttons["insightsReadyButton"]
        XCTAssertTrue(ready.waitForExistence(timeout: 90))
        ready.tap()
        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testOpenAPersonSeeTheDraftedBioEditItAndOpenATag() throws {
        finishEntryAndOpenInsights()

        let sarahChip = app.buttons["entityChip-person-Sarah"]
        scrollToElement(sarahChip, in: app.collectionViews.firstMatch)
        XCTAssertTrue(sarahChip.exists)
        sarahChip.tap()

        let page = app.descendants(matching: .any)["entityPage"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        let drafted = app.staticTexts["entityBioDrafted"]
        if !drafted.waitForExistence(timeout: 10) {
            FileManager.default.createFile(atPath: "/tmp/graphui-dump2.txt", contents: Data(app.debugDescription.utf8))
        }
        XCTAssertTrue(drafted.exists, "the stub answers the entity_bio request directly")

        // Editing the bio clears the AI mark.
        let editButton = app.buttons["entityBioEdit"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()
        let field = app.textFields["entityBioField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(" (edited)")
        app.buttons["entityBioSave"].tap()
        XCTAssertFalse(app.staticTexts["entityBioDrafted"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["entityBio"].label.contains("(edited)"))

        // Adding another name.
        app.buttons["entityAddAlias"].tap()
        let aliasAlert = app.alerts.firstMatch
        XCTAssertTrue(aliasAlert.waitForExistence(timeout: 5))
        aliasAlert.textFields.firstMatch.typeText("Sar")
        aliasAlert.buttons["Add"].tap()
        XCTAssertTrue(app.staticTexts["Sar"].waitForExistence(timeout: 5))

        goBack() // entity page -> insights sheet
        let tagChip = app.buttons["entityChip-tag-river"]
        scrollToElement(tagChip, in: app.collectionViews.firstMatch)
        XCTAssertTrue(tagChip.exists)
        tagChip.tap()
        XCTAssertTrue(app.descendants(matching: .any)["entityPage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["river"].waitForExistence(timeout: 5))

        goBack() // tag page -> insights sheet
        app.buttons["Done"].tap() // insights sheet -> editor

        // Relaunching, the edited bio survives.
        app.terminate()
        app.launch()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Met Sarah'")).firstMatch.tap()
        app.buttons["insightsButton"].tap()
        let sarahChipAgain = app.buttons["entityChip-person-Sarah"]
        scrollToElement(sarahChipAgain, in: app.collectionViews.firstMatch)
        sarahChipAgain.tap()
        XCTAssertTrue(app.staticTexts["entityBio"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["entityBio"].label.contains("(edited)"))
        XCTAssertFalse(app.staticTexts["entityBioDrafted"].exists)
    }
}
