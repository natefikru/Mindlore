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
