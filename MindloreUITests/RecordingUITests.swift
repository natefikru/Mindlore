import XCTest

// Recording from Journal's microphone, minimized into the tab bar's accessory, with the fake recorder standing in for the microphone.
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
        // Record in the + fan starts at once: choosing it was the decision.
        app.startNewRecording()
        let finish = app.buttons["finishRecordingButton"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: finish)], timeout: 5)

        app.buttons["minimizeRecordingButton"].tap()
        XCTAssertFalse(finish.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["recordingAccessory"].waitForExistence(timeout: 5))
    }

    // The Record control in Control Center opens mindlore://record, which starts a recording the way
    // Siri's Start Recording does. Leaving the app shows it as a Live Activity; the attachment is
    // where its look is checked, since the Dynamic Island isn't in the app's element tree.
    @MainActor
    func testTheRecordLinkStartsARecordingThatShowsOutsideTheApp() throws {
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))

        XCUIDevice.shared.system.open(URL(string: "mindlore://record")!)
        let finish = app.buttons["finishRecordingButton"]
        // Some runs deliver the link straight away, others ask first.
        if !finish.waitForExistence(timeout: 3) {
            XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Open"].tap()
        }
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "the link opened a recording")

        XCUIDevice.shared.press(.home)
        sleep(2)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "live-activity"
        shot.lifetime = .keepAlways
        add(shot)

        app.activate()
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "still recording after leaving the app")
        finish.tap()
        XCTAssertTrue(app.descendants(matching: .any)["keepCard"].waitForExistence(timeout: 10))
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

        // Pause and resume from the bar itself, not only from its long-press menu.
        let pause = app.buttons["accessoryPauseButton"]
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        XCTAssertEqual(pause.label, "Pause")
        pause.tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 5))
        app.buttons["accessoryPauseButton"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))

        let finish = app.buttons["accessoryFinishButton"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        // Finishing ends in the Keep card, wherever the user is, and the recording is already an entry.
        XCTAssertTrue(app.descendants(matching: .any)["keepCard"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Kept"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "keep-card"
        shot.lifetime = .keepAlways
        add(shot)

        // The card leads to the new entry, on the Journal tab.
        app.buttons["keepOpenEntry"].tap()
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["keepCard"].exists)
        XCTAssertTrue(app.tabBars.buttons["Journal"].isSelected)
        // The accessory is only there while a recording runs.
        XCTAssertFalse(app.buttons["recordingAccessory"].exists)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.descendants(matching: .any)["entryRow"].waitForExistence(timeout: 5))
        // Recordings share one folder across UI test stores, so a run that died mid-recording would
        // surface here as a recovered second entry. Entry rows, not cells: the list is sectioned
        // by date, and a section header is a cell too.
        XCTAssertEqual(app.cells.containing(.any, identifier: "entryRow").count, 1)
    }
}
