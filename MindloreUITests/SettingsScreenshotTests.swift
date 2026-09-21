import XCTest

// Every settings screen, in light and dark, for looking at by eye. Nothing here asserts what a
// screen looks like; pull the attachments out and look:
//
//   xcrun simctl boot <udid>; xcrun simctl ui <udid> appearance dark
//   TEST_RUNNER_SETTINGS_APPEARANCE=dark xcodebuild ... -only-testing:MindloreUITests/SettingsScreenshotTests
//   xcrun xcresulttool export attachments --path <result bundle> --output-path <dir>
//
// XCUIDevice.shared.appearance does not reach the simulator (tasks/lessons.md: it produced ten
// light screenshots, five of them named "dark"), so the appearance is set from outside on a booted
// device. The variable here only names the files.
final class SettingsScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        // -uiTestingAIReady so the AI rows are live and the key reads as saved: a settings tour
        // with everything disabled shows nothing worth looking at.
        app.launchArguments = ["-uiTesting", "-uiTestingAIReady", "-uiTestingFakeAI"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    // DesignScreenshotTests keeps its own copy of this; it is private there.
    private func attach(_ name: String) {
        sleep(1)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func open(_ identifier: String) {
        let link = app.buttons[identifier]
        XCTAssertTrue(link.waitForExistence(timeout: 5), "\(identifier) should exist")
        link.tap()
    }

    @MainActor
    func testTour() throws {
        let tag = ProcessInfo.processInfo.environment["SETTINGS_APPEARANCE"] ?? "light"
        app.launch()

        let tab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30))
        tab.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        attach("\(tag)-settings-root")

        // About and, in this Debug build, the Debug section sit below the fold.
        let entries = app.descendants(matching: .any)["totalEntries"]
        for _ in 0..<4 where !(entries.exists && entries.isHittable) { app.swipeUp() }
        XCTAssertTrue(entries.exists, "About should be on the root")
        attach("\(tag)-settings-root-bottom")
        for _ in 0..<4 { app.swipeDown() }

        open("lifeAreasSettingsLink")
        attach("\(tag)-life-areas")
        back()

        open("journalVoiceSettingsLink")
        attach("\(tag)-voice")
        back()

        open("aiKeyLink")
        attach("\(tag)-key")
        back()

        open("aiFeaturesLink")
        attach("\(tag)-what-ai-does")

        open("speechSettingsLink")
        attach("\(tag)-speech")
        back()

        open("insightsSettingsLink")
        attach("\(tag)-insights")
        back()

        open("advancedAISettingsLink")
        attach("\(tag)-advanced")

        open("customInsightsLink")
        attach("\(tag)-custom-insights")
        app.buttons["addCustomPromptButton"].tap()
        XCTAssertTrue(app.textFields["customPromptNameField"].waitForExistence(timeout: 5))
        attach("\(tag)-custom-prompt-editor")
    }
}
