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
            app.scrollViews["insightsSheet"].swipeUp()
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

    // The story journal on the Mind tab: the map per window, a replay, a focus, the drawer, Tidy
    // up, the card, the entity page, and its Edit sheet, for looking at by eye. Run it once in
    // light and once in dark.
    @MainActor
    func testDemoJournalMind() throws {
        app.launchArguments = ["-seedStoryJournal", "-resetStoryJournal"]
        app.launchEnvironment = [:]
        app.launch()

        let mind = app.tabBars.buttons["Mind"]
        XCTAssertTrue(mind.waitForExistence(timeout: 90))
        mind.tap()

        let canvas = app.descendants(matching: .any)["mindGraphCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 30))
        XCTAssertGreaterThan(canvas.graphNodeCount ?? 0, 20)
        sleep(5)
        attach("mind-drawer-half")

        let grabber = app.descendants(matching: .any)["mindPanelGrabber"]
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        for window in ["month", "quarter", "year", "all"] {
            app.buttons["mindWindow-\(window)"].tap()
            sleep(5)
            attach("mind-window-\(window)")
        }
        app.buttons["mindWindow-quarter"].tap()
        app.buttons["mindReplay"].tap()
        sleep(5)
        attach("mind-replay-midway")
        sleep(7)

        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        sleep(1)
        attach("mind-drawer-full")
        app.buttons["mindKindChip-people"].tap()
        sleep(1)
        attach("mind-drawer-people")
        app.buttons["mindKindChip-all"].tap()
        let tidyUp = app.buttons["mindTidyUp"]
        var swipes = 0
        while !tidyUp.isHittable && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        tidyUp.tap()
        sleep(2)
        attach("mind-tidy-up")
        app.buttons["tidyUpDone"].tap()

        let field = app.textFields["mindSearchField"]
        field.tap()
        field.typeText("Maya")
        let row = app.buttons["mindRow-Maya"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["entityPeekCard"].waitForExistence(timeout: 5))
        sleep(3)
        attach("mind-focused-card")

        app.buttons["entityPeekOpen"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["entityPage"].waitForExistence(timeout: 5))
        sleep(2)
        attach("entity-page-top")
        app.collectionViews.firstMatch.swipeUp()
        sleep(1)
        attach("entity-page-middle")
        app.collectionViews.firstMatch.swipeUp()
        app.collectionViews.firstMatch.swipeUp()
        sleep(1)
        attach("entity-page-bottom")
        app.buttons["entityEdit"].tap()
        sleep(1)
        attach("entity-edit")
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
        sleep(1)
        attach("insights-sheet")
        app.scrollViews["insightsSheet"].swipeUp()
        sleep(1)
        attach("insights-sheet-lower")
        scrollToChip("entityChip-person-Sarah")
        app.buttons["entityChip-person-Sarah"].tap()
        XCTAssertTrue(app.staticTexts["entityBio"].waitForExistence(timeout: 10))
        attach("entity-page")
        app.buttons["entityEdit"].tap()
        XCTAssertTrue(app.staticTexts["entityBioDrafted"].waitForExistence(timeout: 5))
        attach("drafted-bio")
    }
}
