import XCTest

// Recording from the tab bar's accessory, with the fake recorder standing in for the microphone.
// Real capture, locking, and interruptions are device steps (tasks/smoke-test.md).
final class RecordingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingFakeRecorder"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    private func startAndMinimize() {
        app.launch()
        let record = app.buttons["newVoiceEntryButton"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        let finish = app.buttons["finishRecordingButton"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: finish)], timeout: 5)

        app.buttons["minimizeRecordingButton"].tap()
        XCTAssertFalse(finish.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["recordingAccessory"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordMinimizeSwitchTabsAndFinishFromTheAccessory() throws {
        startAndMinimize()

        app.tabBars.buttons["Mind"].tap()
        XCTAssertTrue(app.buttons["recordingAccessory"].exists, "the recording follows the user across tabs")

        // Expanding and minimizing again keeps the same recording.
        app.buttons["recordingAccessory"].tap()
        XCTAssertTrue(app.buttons["finishRecordingButton"].waitForExistence(timeout: 5))
        app.buttons["minimizeRecordingButton"].tap()

        let finish = app.buttons["accessoryFinishButton"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        // Finishing lands on the new entry, on the Journal tab.
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Journal"].isSelected)
        XCTAssertTrue(app.buttons["newVoiceEntryButton"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["entryRow"].waitForExistence(timeout: 5))
        // Recordings share one folder across UI test stores, so a run that died mid-recording would
        // surface here as a recovered second entry.
        XCTAssertEqual(app.cells.count, 1)
    }

    @MainActor
    func testDiscardFromTheMinimizedRecorder() throws {
        startAndMinimize()

        app.buttons["recordingAccessory"].press(forDuration: 1.0)
        let discardItem = app.buttons["Discard Recording"]
        XCTAssertTrue(discardItem.waitForExistence(timeout: 5))
        discardItem.tap()
        let confirm = app.buttons["confirmDiscardRecordingButton"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()

        XCTAssertTrue(app.buttons["newVoiceEntryButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))
    }
}
