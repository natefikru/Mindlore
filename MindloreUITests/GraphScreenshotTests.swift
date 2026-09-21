import XCTest

// Screenshots of entity page bio states for Phase 5a review. Currently captures only the
// drafted state; other states (not enough, failed, merged) require manual verification
// or more complex stub setup.
final class GraphScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingAIReady", "-uiTestingFakeAI"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    private var editor: XCUIElement { app.textViews["entryEditor"] }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollToChip(_ identifier: String) {
        let chip = app.buttons[identifier]
        var swipes = 0
        while !chip.exists && swipes < 6 {
            app.collectionViews.firstMatch.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(chip.exists, "chip: \(identifier)")
    }

    // A8: the grouped journal list on a year of entries, for looking at by eye.
    @MainActor
    func testDemoJournalList() throws {
        app.launchArguments = ["-seedDemoJournal", "300"]
        app.launchEnvironment = [:]
        app.launch()

        let journal = app.tabBars.buttons["Journal"]
        XCTAssertTrue(journal.waitForExistence(timeout: 60))
        journal.tap()
        XCTAssertTrue(app.descendants(matching: .any)["entryRow"].firstMatch.waitForExistence(timeout: 20))
        sleep(1)
        attach("journal-grouped-top")

        app.buttons["areaFilter-work"].tap()
        sleep(1)
        attach("journal-filter-one")
        app.buttons["areaFilter-health"].tap()
        sleep(1)
        attach("journal-filter-two")
    }

    // The 300-entry demo journal on the Mind tab at rest, with the panel up, focused, and zoomed,
    // for looking at by eye. The demo seed only runs outside -uiTesting, so this launch uses the
    // demo store alone.
    @MainActor
    func testDemoJournalMind() throws {
        app.launchArguments = ["-seedDemoJournal", "300"]
        app.launchEnvironment = [:]
        app.launch()

        let mind = app.tabBars.buttons["Mind"]
        XCTAssertTrue(mind.waitForExistence(timeout: 60))
        mind.tap()

        let canvas = app.descendants(matching: .any)["mindGraphCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(canvas.graphNodeCount ?? 0, 50)
        sleep(6)
        attach("mind-rest-panel-half")

        app.buttons["areaTile-work"].tap()
        sleep(2)
        attach("mind-area-work")
        app.buttons["areaTile-work"].tap()

        let field = app.textFields["mindSearchField"]
        field.tap()
        field.typeText("Sarah")
        sleep(1)
        attach("mind-search-keyboard")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mindRow-Sarah'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["entityPeekCard"].waitForExistence(timeout: 5))
        sleep(2)
        attach("mind-focused-card")

        canvas.pinch(withScale: 2, velocity: 1)
        sleep(2)
        attach("mind-zoomed")

        // A5b: the lenses, entry dots, area regions, and a replay mid-run, zoomed back out.
        canvas.pinch(withScale: 0.4, velocity: -1)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.2)).tap()
        for (lens, name) in [("Mood around", "mind-lens-mood"), ("Recent", "mind-lens-recent")] {
            app.buttons["mindLens"].tap()
            app.buttons[lens].tap()
            sleep(2)
            attach(name)
        }
        app.buttons["mindLens"].tap()
        app.buttons["Kinds"].tap()

        app.buttons["mindFilters"].tap()
        let entries = app.switches["mindShowEntries"]
        XCTAssertTrue(entries.waitForExistence(timeout: 5))
        entries.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        sleep(6)
        attach("mind-entries")

        app.buttons["mindFilters"].tap()
        let regions = app.switches["mindGroupByArea"]
        XCTAssertTrue(regions.waitForExistence(timeout: 5))
        entries.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        regions.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        app.buttons["Done"].tap()
        sleep(8)
        attach("mind-regions")

        app.buttons["mindReplay"].tap()
        sleep(5)
        attach("mind-replay-midway")
        sleep(7)
        attach("mind-replay-done")
    }

    @MainActor
    func testDraftedBioState() throws {
        app.launch()
        app.buttons["newEntryButton"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)], timeout: 5)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        editor.typeText("Met Sarah by the river and felt calm about the move.")
        app.buttons["finishEntryButton"].tap()
        XCTAssertTrue(app.buttons["insightsReadyButton"].waitForExistence(timeout: 90))
        app.buttons["insightsReadyButton"].tap()
        XCTAssertTrue(app.staticTexts["Summary"].waitForExistence(timeout: 10))
        scrollToChip("entityChip-person-Sarah")
        app.buttons["entityChip-person-Sarah"].tap()
        XCTAssertTrue(app.staticTexts["entityBioDrafted"].waitForExistence(timeout: 10))
        attach("drafted-bio")
    }
}
