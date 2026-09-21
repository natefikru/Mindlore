import XCTest

// The AI settings screens: change things, relaunch, and confirm they stuck. Runs against real OpenAI
// when TEST_RUNNER_MINDLORE_OPENAI_KEY is set (so the model pickers show the real list), else the stub.
final class AIConfigurationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingAIReady"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
        if let key = ProcessInfo.processInfo.environment["MINDLORE_OPENAI_KEY"], !key.isEmpty {
            app.launchEnvironment["MINDLORE_OPENAI_KEY"] = key
        } else {
            app.launchArguments.append("-uiTestingFakeAI")
        }
    }

    // Scoped to the tab bar: app.buttons["Settings"] matches the tab item too, so an unscoped tap
    // cannot tell a tab from the old toolbar gear. See SettingsTabUITests.
    private func openAIFeatures() {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let link = app.buttons["aiFeaturesLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
    }

    private func openAdvanced() {
        let link = app.buttons["advancedAISettingsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
    }

    // Form rows below the fold aren't hittable until scrolled into view.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, swipes: Int = 6) -> Bool {
        for _ in 0..<swipes {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func back() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    func testChangingAISettingsSticksAcrossRelaunch() throws {
        app.launch()
        openAIFeatures()

        // Speech: switch to on-device transcription.
        let speechLink = app.buttons["speechSettingsLink"]
        XCTAssertTrue(speechLink.waitForExistence(timeout: 5))
        XCTAssertTrue(speechLink.label.contains("OpenAI"))
        speechLink.tap()
        let enginePicker = app.segmentedControls["speechEnginePicker"]
        XCTAssertTrue(enginePicker.waitForExistence(timeout: 5))
        // All three tiers are offered by name. The simulator can't run live speech, so under UI
        // tests the default is OpenAI; the Live default is covered in SettingsStoreTests.
        XCTAssertEqual(enginePicker.buttons.count, 3)
        XCTAssertTrue(enginePicker.buttons["Live"].exists)
        XCTAssertTrue(enginePicker.buttons["OpenAI"].isSelected)
        enginePicker.buttons["This iPhone"].tap()
        back()

        // Insights: only when I ask, no moods, and a custom prompt.
        let insightsLink = app.buttons["insightsSettingsLink"]
        XCTAssertTrue(insightsLink.waitForExistence(timeout: 5))
        insightsLink.tap()
        app.segmentedControls["insightsTriggerPicker"].buttons["Only when I ask"].tap()
        let moods = app.switches["insightMoodsToggle"]
        XCTAssertTrue(moods.waitForExistence(timeout: 5))
        moods.switches.firstMatch.tap()
        XCTAssertEqual(moods.value as? String, "0")

        back()

        // Advanced: the model fields, and the custom prompts that used to sit under Insights.
        openAdvanced()
        XCTAssertTrue(app.descendants(matching: .any)["speechModelPicker"].exists || app.textFields["speechModelField"].exists)
        XCTAssertTrue(scrollTo(app.buttons["customInsightsLink"]))
        app.buttons["customInsightsLink"].tap()
        app.buttons["addCustomPromptButton"].tap()
        let name = app.textFields["customPromptNameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Gratitude")
        let instructions = app.textViews["customPromptInstructionsField"]
        let instructionsField = instructions.exists ? instructions : app.textFields["customPromptInstructionsField"]
        instructionsField.tap()
        instructionsField.typeText("What is the writer grateful for?")
        app.buttons["saveCustomPromptButton"].tap()
        XCTAssertTrue(app.staticTexts["Gratitude"].waitForExistence(timeout: 5))
        back()
        back()

        app.terminate()
        app.launch()
        openAIFeatures()

        XCTAssertTrue(app.buttons["speechSettingsLink"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["speechSettingsLink"].label.contains("This iPhone"))
        XCTAssertTrue(app.buttons["insightsSettingsLink"].label.contains("When I ask"))

        app.buttons["insightsSettingsLink"].tap()
        XCTAssertTrue(app.switches["insightMoodsToggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["insightMoodsToggle"].value as? String, "0")
        XCTAssertEqual(app.switches["insightSummaryToggle"].value as? String, "1")
        back()

        openAdvanced()
        XCTAssertTrue(scrollTo(app.buttons["customInsightsLink"]))
        XCTAssertTrue(app.buttons["customInsightsLink"].label.contains("1"))
        app.buttons["customInsightsLink"].tap()
        XCTAssertTrue(app.staticTexts["Gratitude"].waitForExistence(timeout: 5))
    }
}
