import XCTest

// Drives the AI settings screens against the app's stubbed OpenAI (-uiTestingFakeAI). Settings and
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
        openSettings()

        let toggle = app.switches["aiEnabledToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")

        // Turning AI on asks first, naming OpenAI; Not now leaves it off.
        toggle.switches.firstMatch.tap()
        let consent = app.alerts["Send your journal to OpenAI?"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.buttons["Not now"].firstMatch.tap()
        XCTAssertTrue(consent.waitForNonExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")

        // Saving a key with AI off asks too, and Allow is what turns it on.
        openKey()
        XCTAssertTrue(app.links["getOpenAIKeyLink"].exists || app.buttons["getOpenAIKeyLink"].exists)

        // A key the provider rejects is saved but reported as invalid.
        enterKey("sk-wrong")
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        consent.buttons["Allow"].firstMatch.tap()
        XCTAssertTrue(consent.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["OpenAI didn't accept your API key. Check it in Settings."].waitForExistence(timeout: 5))

        app.buttons["Replace key"].tap()
        enterKey(validKey)
        XCTAssertTrue(app.staticTexts["Connected. 2 models available."].waitForExistence(timeout: 5))

        // Relaunch with the same store: AI stays on and the key stays saved.
        app.terminate()
        app.launch()
        openSettings()
        XCTAssertTrue(app.switches["aiEnabledToggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["aiEnabledToggle"].value as? String, "1")
        // The AI screen's own row reports the key without opening it.
        let keyLink = app.buttons["aiKeyLink"]
        XCTAssertTrue(keyLink.waitForExistence(timeout: 5))
        XCTAssertTrue(keyLink.label.contains("Saved"))

        openKey()
        // The labeled row reads as one element, "API key, Saved".
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Saved")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        app.buttons["Test connection"].tap()
        XCTAssertTrue(app.staticTexts["Connected. 2 models available."].waitForExistence(timeout: 5))

        app.buttons["Remove key"].tap()
        XCTAssertTrue(app.secureTextFields["openAIKeyField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Test connection"].exists)

        // Undo keeps the key; letting the window pass removes it.
        app.buttons["undoButton"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        app.buttons["Remove key"].tap()
        XCTAssertTrue(app.otherElements["undoPill"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.secureTextFields["openAIKeyField"].exists)
        XCTAssertFalse(app.buttons["Test connection"].exists)
    }

    // Scoped to the tab bar on purpose: app.buttons["Settings"] also matches the tab item, so an
    // unscoped tap cannot tell a tab from a toolbar gear. See SettingsTabUITests. Then into AI,
    // which is its own screen under the root.
    private func openSettings() {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let ai = app.buttons["aiSettingsLink"]
        XCTAssertTrue(ai.waitForExistence(timeout: 5))
        ai.tap()
    }

    private func openKey() {
        let link = app.buttons["aiKeyLink"]
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
