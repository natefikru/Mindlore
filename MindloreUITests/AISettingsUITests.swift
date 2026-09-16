import XCTest

// Drives the AI settings screen against the app's stubbed OpenAI (-uiTestingFakeAI). Settings and
// Keychain are isolated per test by UITEST_STORE_NAME, so nothing leaks into other tests.
final class AISettingsUITests: XCTestCase {
    private var app: XCUIApplication!
    private let validKey = "sk-uitest-valid"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingFakeAI"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    @MainActor
    func testKeySetupConnectionAndRemoval() throws {
        app.launch()
        openAISettings()

        let toggle = app.switches["aiEnabledToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")

        // A key the provider rejects is saved but reported as invalid.
        enterKey("sk-wrong")
        XCTAssertTrue(app.staticTexts["OpenAI didn't accept your API key. Check it in Settings."].waitForExistence(timeout: 5))

        app.buttons["Replace key"].tap()
        enterKey(validKey)
        XCTAssertTrue(app.staticTexts["Connected. 2 models available."].waitForExistence(timeout: 5))

        // Relaunch with the same store: AI stays on and the key stays saved.
        app.terminate()
        app.launch()
        openAISettings()
        XCTAssertTrue(app.switches["aiEnabledToggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["aiEnabledToggle"].value as? String, "1")
        // The labeled row reads as one element, "API key, Saved".
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Saved")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        app.buttons["Test connection"].tap()
        XCTAssertTrue(app.staticTexts["Connected. 2 models available."].waitForExistence(timeout: 5))

        app.buttons["Remove key"].tap()
        XCTAssertTrue(app.secureTextFields["openAIKeyField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Test connection"].exists)
    }

    private func openAISettings() {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let link = app.buttons["aiSettingsLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
    }

    private func enterKey(_ key: String) {
        let field = app.secureTextFields["openAIKeyField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(key)
        app.buttons["Save key"].tap()
    }
}
