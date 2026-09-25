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

    private func startNewEntry() {
        app.startNewWrittenEntry()
        focusEditor()
    }

    private func focusEditor() {
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)
        wait(for: [hittable], timeout: 5)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    private var canvas: XCUIElement { app.descendants(matching: .any)["mindGraphCanvas"] }

    // The page and the Edit sheet over it both show the description.
    private var bioText: XCUIElement { app.staticTexts.matching(identifier: "entityBio").firstMatch }

    private func openMind() {
        app.tabBars.buttons["Mind"].tap()
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
    }

    private func waitFor(_ format: String, _ args: CVarArg..., on element: XCUIElement, timeout: TimeInterval = 5) {
        let predicate = NSPredicate(format: format, argumentArray: args)
        wait(for: [expectation(for: predicate, evaluatedWith: element)], timeout: timeout)
    }

    // Searches from the panel and returns the row, without tapping it.
    private func search(_ text: String) -> XCUIElement {
        let field = app.textFields["mindSearchField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
        return app.buttons["mindRow-\(text)"]
    }

    // Search, tap the row, and open the page from its card.
    private func openPage(_ name: String) {
        let row = search(name)
        XCTAssertTrue(row.waitForExistence(timeout: 5), "row for \(name)")
        row.tap()
        let open = app.buttons["entityPeekOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    // Leaves the finished stub entry and returns to the journal list.
    private func finishAndLeave() {
        finishEntryAndOpenInsights()
        app.buttons["Done"].tap() // insights sheet -> editor
        goBack() // editor -> list
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // The insights sheet is a lazily rendered list; a chip below the fold isn't in the tree
    // until it's scrolled into view.
    private func scrollToElement(_ element: XCUIElement, in container: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        // Clear of the tab bar, not just hittable: the + draws a touch area a little taller than
        // the bar, so a row whose middle sits just above the bar still opened the new-entry fan.
        let barTop = app.tabBars.firstMatch.frame.minY
        while !(element.exists && element.isHittable && element.frame.maxY < barTop) && swipes < maxSwipes {
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
        XCTAssertTrue(app.descendants(matching: .any)["lifeArea-friends"].waitForExistence(timeout: 5), "the stub files the entry under friends")
    }

    // Search, the card, the page, an entry preview, a merge that refocuses the map on the winner,
    // a relaunch, and an unmerge from "Merged into this". Stub only, same reason as above.
    @MainActor
    func testMindSearchOpenMergeAndUnmerge() throws {
        finishAndLeave()
        openMind()

        // The stub's loose end is about Sarah.
        let sarahRow = search("Sarah")
        XCTAssertTrue(sarahRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["mindRowOpen-Sarah"].exists, "Sarah's row counts her open loose end")
        sarahRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["entityPeekCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["entityPeekLooseEnd"].waitForExistence(timeout: 5))
        // The card never starts a bio draft; the stub would answer one at once.
        XCTAssertFalse(app.descendants(matching: .any)["entityPeekBio"].waitForExistence(timeout: 3))
        waitFor("value ENDSWITH 'focused=Sarah'", on: canvas)

        app.buttons["entityPeekOpen"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["entityPage"].waitForExistence(timeout: 5))
        XCTAssertTrue(bioText.waitForExistence(timeout: 10), "opening the page drafts the bio")
        XCTAssertTrue(app.descendants(matching: .any)["entityLooseEnds"].waitForExistence(timeout: 5))
        let summary = app.buttons["entityEntriesSummary"]
        scrollToElement(summary, in: app.collectionViews.firstMatch)
        XCTAssertTrue(summary.label.contains("1 mentioned entry"), summary.label)
        summary.tap()
        let entryRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'entityEntryRow-'")).firstMatch
        XCTAssertTrue(entryRow.waitForExistence(timeout: 5))
        app.collectionViews.firstMatch.swipeUp()
        entryRow.tap()
        XCTAssertTrue(app.descendants(matching: .any)["entryPreview"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Met Sarah'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap() // entry preview -> Sarah's page
        goBack() // Sarah's page -> map

        openPage("Tom")
        let mergeInto = app.buttons["entityMergeInto"]
        scrollToElement(mergeInto, in: app.collectionViews.firstMatch)
        mergeInto.tap()
        let candidate = app.buttons["mergeCandidate-Sarah"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 5))
        candidate.tap()
        app.buttons["confirmMergeButton"].firstMatch.tap()
        // The route follows the merge: this is Sarah's page now, not Tom's.
        XCTAssertTrue(app.navigationBars["Sarah"].waitForExistence(timeout: 5))
        goBack() // Sarah's page -> map, focused on the winner
        waitFor("value ENDSWITH 'focused=Sarah'", on: canvas)

        // Relaunching, the merge survives. Tom is Sarah's alias now, so searching him finds her.
        app.terminate()
        app.launch()
        openMind()
        XCTAssertTrue(search("Tom").waitForExistence(timeout: 3) == false, "Tom merged away")
        let sarahAgain = app.buttons["mindRow-Sarah"]
        XCTAssertTrue(sarahAgain.waitForExistence(timeout: 5))
        sarahAgain.tap()
        // The card slides in over the panel; tapped before it lands, Open has no hit point and
        // XCTest skips the tap without failing.
        let openAgain = app.buttons["entityPeekOpen"]
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: openAgain)], timeout: 5)
        openAgain.tap()
        XCTAssertTrue(app.navigationBars["Sarah"].waitForExistence(timeout: 5))

        let mergedInRow = app.buttons["mergedInRow-Tom"]
        scrollToElement(mergedInRow, in: app.collectionViews.firstMatch)
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: mergedInRow)], timeout: 5)
        mergedInRow.tap()
        XCTAssertTrue(app.navigationBars["Tom"].waitForExistence(timeout: 5))
        let unmerge = app.buttons["entityUnmerge"]
        scrollToElement(unmerge, in: app.collectionViews.firstMatch)
        XCTAssertTrue(unmerge.exists)
        unmerge.tap()

        goBack() // Tom's page -> Sarah's page
        goBack() // Sarah's page -> map
        XCTAssertTrue(search("Tom").waitForExistence(timeout: 5), "unmerge restored Tom")
    }
}
