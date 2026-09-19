import XCTest

// Phase B1: the Keep card after a recording, filled in by the stubbed AI, for looking at by eye.
// The speech prompt would cover it on a fresh simulator; grant it once from outside:
//   xcrun simctl privacy <udid> grant speech-recognition <bundle id>
final class KeepScreenshotTests: XCTestCase {
    @MainActor
    func testTheCardFillsInAsThePipelineLands() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingFakeRecorder", "-uiTestingAIReady", "-uiTestingFakeAI"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
        addUIInterruptionMonitor(withDescription: "speech") { alert in
            alert.buttons["Allow"].tap()
            return true
        }
        app.launch()

        app.buttons["newVoiceEntryButton"].tap()
        let finish = app.buttons["finishRecordingButton"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: finish)], timeout: 5)
        finish.tap()

        XCTAssertTrue(app.descendants(matching: .any)["keepCard"].waitForExistence(timeout: 10))
        attach(app, "keep-1-just-kept")
        // The words arrive, then the pass the card started brings what was noticed.
        XCTAssertTrue(app.staticTexts["keepWords"].waitForExistence(timeout: 20))
        attach(app, "keep-2-words")
        if app.descendants(matching: .any)["keepNoticed"].waitForExistence(timeout: 20) {
            sleep(1)
            attach(app, "keep-3-noticed")
        }

        app.buttons["keepDone"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["keepCard"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.descendants(matching: .any)["entryRow"].waitForExistence(timeout: 5), "the recording is an entry without the editor ever opening")
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
