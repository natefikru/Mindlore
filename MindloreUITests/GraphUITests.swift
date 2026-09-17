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

    private var canvas: XCUIElement { app.descendants(matching: .any)["mindGraphCanvas"] }

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
        XCTAssertTrue(app.descendants(matching: .any)["lifeArea-friends"].waitForExistence(timeout: 5), "the stub files the entry under friends")
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
    // The stub's entry puts Sarah, Tom, and the river tag on the map, all with one mention, which a
    // young journal shows by default. Focus by tapping, drag and pinch, clear, and filter.
    @MainActor
    func testMindFocusesATappedNodeAndKeepsResponding() throws {
        finishAndLeave()
        openMind()
        waitFor("value BEGINSWITH 'nodes=3 '", on: canvas)

        // With nothing focused, the layout sits in the middle of what the panel leaves uncovered.
        let focus = canvas.tapUntilGraphFocuses(from: CGVector(dx: 0.5, dy: 0.35))
        XCTAssertNotNil(focus, "no tap landed on a node or edge: \(String(describing: canvas.value))")
        XCTAssertTrue(app.descendants(matching: .any)["entityPeekCard"].waitForExistence(timeout: 5))
        let panel = app.descendants(matching: .any)["mindSearchPanel"]
        XCTAssertEqual(panel.value as? String, "stop=peek")

        sleep(1)
        let center = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        center.press(forDuration: 0.05, thenDragTo: center.withOffset(CGVector(dx: 60, dy: 40)))
        canvas.pinch(withScale: 1.8, velocity: 1)
        canvas.pinch(withScale: 0.3, velocity: -1)
        XCTAssertEqual(canvas.graphFocus, focus)

        // Zoomed out, a tap at the left edge above the card is clear of every node and edge.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.2)).tap()
        waitFor("value ENDSWITH 'focused=none'", on: canvas)
        XCTAssertFalse(app.descendants(matching: .any)["entityPeekCard"].waitForExistence(timeout: 2))

        // Switching people off drops Sarah and Tom without replacing the canvas.
        app.buttons["mindFilters"].tap()
        let people = app.switches["mindKind-person"]
        XCTAssertTrue(people.waitForExistence(timeout: 5))
        people.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        waitFor("value BEGINSWITH 'nodes=1 '", on: canvas)
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
        XCTAssertTrue(app.staticTexts["entityBioDrafted"].waitForExistence(timeout: 10), "opening the page drafts the bio")
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
        app.buttons["entityPeekOpen"].tap()
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

    // The review card: a suggestion appears when two names look alike, "Not the same" dismisses
    // it, and both stay.
    @MainActor
    func testReviewCardNotTheSameRemovesThePair() throws {
        finishAndLeave()
        openMind()
        openPage("Tom")

        // Renaming Tom to "Sara" makes him look like Sarah, so a suggestion appears.
        app.buttons["entityRename"].tap()
        let renameField = app.textFields["entityRenameField"]
        XCTAssertTrue(renameField.waitForExistence(timeout: 5))
        renameField.doubleTap()
        renameField.typeText("Sara")
        app.buttons["entityRenameSave"].tap()
        goBack() // Sara's page -> map

        // Choosing Tom cleared the search and lowered the panel; focusing the field raises it.
        app.textFields["mindSearchField"].tap()
        let notTheSame = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reviewNotSame-'")).firstMatch
        XCTAssertTrue(notTheSame.waitForExistence(timeout: 5), "Sara and Sarah look alike enough to ask")
        notTheSame.tap()

        let stillAsked = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'reviewNotSame-'")).firstMatch
        XCTAssertFalse(stillAsked.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["mindRow-Sara"].exists)
        XCTAssertTrue(app.buttons["mindRow-Sarah"].exists)
    }

    // An area tile brings its entities forward; a second tap clears it. The stub files the entry
    // under Friends.
    @MainActor
    func testAreaTileHighlightsItsEntities() throws {
        finishAndLeave()
        openMind()
        waitFor("value BEGINSWITH 'nodes=3 '", on: canvas)
        XCTAssertTrue((canvas.value as? String)?.contains("highlighted=0") == true)

        let friends = app.buttons["areaTile-friends"]
        XCTAssertTrue(friends.waitForExistence(timeout: 5))
        friends.tap()
        waitFor("value CONTAINS 'highlighted=3'", on: canvas)
        friends.tap()
        waitFor("value CONTAINS 'highlighted=0'", on: canvas)
    }

    // Lenses recolour without touching the node set; the entry dot and area grouping come from
    // the filters; a tap on the dot opens the entry for reading on Journal.
    @MainActor
    func testMindLensesEntriesAndRegions() throws {
        finishAndLeave()
        openMind()
        waitFor("value BEGINSWITH 'nodes=3 '", on: canvas)

        app.buttons["mindLens"].tap()
        app.buttons["Mood around"].tap()
        waitFor("value CONTAINS 'lens=mood'", on: canvas)
        XCTAssertTrue(app.descendants(matching: .any)["mindLensLegend"].waitForExistence(timeout: 5))
        app.buttons["mindLens"].tap()
        app.buttons["Recent"].tap()
        waitFor("value CONTAINS 'lens=recency'", on: canvas)
        app.buttons["mindLens"].tap()
        app.buttons["Kinds"].tap()
        waitFor("value CONTAINS 'lens=kind'", on: canvas)
        XCTAssertFalse(app.descendants(matching: .any)["mindLensLegend"].exists)

        app.buttons["mindFilters"].tap()
        for id in ["mindShowEntries", "mindGroupByArea"] {
            let toggle = app.switches[id]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        app.buttons["Done"].tap()
        waitFor("value BEGINSWITH 'nodes=3 ' AND value CONTAINS 'entries=1'", on: canvas)

        // Lowered, the panel covers as little of the map as it can; the canvas reports the dot's
        // spot once the regrouped layout settles.
        let panel = app.descendants(matching: .any)["mindSearchPanel"]
        let grabber = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        grabber.press(forDuration: 0.1, thenDragTo: grabber.withOffset(CGVector(dx: 0, dy: 500)))
        waitFor("value == 'stop=peek'", on: panel)
        waitFor("value CONTAINS 'entryDot='", on: canvas, timeout: 20)
        let value = try XCTUnwrap(canvas.value as? String)
        let token = try XCTUnwrap(value.split(separator: " ").first { $0.hasPrefix("entryDot=") })
        let parts = token.dropFirst("entryDot=".count).split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(parts.count, 2)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: parts[0], dy: parts[1])).tap()
        XCTAssertTrue(app.staticTexts["entryReadText"].waitForExistence(timeout: 5), "the dot opened its entry for reading")
    }

    // Replay runs to the end on its own and hands back the same map.
    @MainActor
    func testMindReplayRunsAndEnds() throws {
        finishAndLeave()
        openMind()
        waitFor("value BEGINSWITH 'nodes=3 '", on: canvas)
        let play = app.buttons["mindReplay"]
        waitFor("isEnabled == true", on: play)
        play.tap()
        waitFor("value CONTAINS 'replay=on'", on: canvas)
        XCTAssertTrue(app.buttons["mindReplayStop"].exists)
        waitFor("value CONTAINS 'replay=off'", on: canvas, timeout: 20)
        waitFor("value BEGINSWITH 'nodes=3 '", on: canvas)
        XCTAssertTrue(play.exists)
    }

    // From an entry's read view: the name's card, its page, then Show in Mind. Mind opens focused
    // on Sarah, and Journal still has the entry open.
    @MainActor
    func testShowInMindFromTheEditor() throws {
        finishAndLeave()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Met Sarah'")).firstMatch.tap()
        let readText = app.staticTexts["entryReadText"]
        let sarah = readText.links["Sarah"]
        XCTAssertTrue(sarah.waitForExistence(timeout: 10))
        sarah.tap()
        let open = app.buttons["entityPeekOpen"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let showInMind = app.buttons["entityShowInMind"]
        XCTAssertTrue(app.descendants(matching: .any)["entityPage"].waitForExistence(timeout: 5))
        scrollToElement(showInMind, in: app.collectionViews.firstMatch)
        showInMind.tap()

        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        waitFor("value ENDSWITH 'focused=Sarah'", on: canvas)
        XCTAssertTrue(app.tabBars.buttons["Mind"].isSelected)

        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(readText.waitForExistence(timeout: 5), "the entry is still open on Journal")
    }
}
