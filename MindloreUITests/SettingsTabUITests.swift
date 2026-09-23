import XCTest

// Settings is a tab, not a gear on Journal. This class exists because the two AI settings classes
// cannot tell the difference: both reach settings through `app.buttons["Settings"]`, which matches
// the tab item just as happily as it matched the toolbar button, so both kept passing unchanged
// when the tab landed. Everything here is scoped to `tabBars`, or to the gear's absence.
final class SettingsTabUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
        app.launch()
    }

    func testSettingsIsATabAndTheJournalGearIsGone() {
        let tab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Settings should be a tab bar item")

        // The gear was a toolbar button on Journal. It has no identifier anywhere now.
        XCTAssertFalse(app.buttons["settingsButton"].exists, "The Journal gear should be gone")

        tab.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(tab.isSelected)
    }

    // The point of the tab over the gear: settings is reachable from wherever you noticed you
    // needed it, not only from Journal.
    func testSettingsIsReachableFromEveryTab() {
        for origin in ["Mind", "Chat", "Journal"] {
            let tab = app.tabBars.buttons[origin]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "\(origin) tab should exist")
            tab.tap()

            app.tabBars.buttons["Settings"].tap()
            XCTAssertTrue(
                app.navigationBars["Settings"].waitForExistence(timeout: 5),
                "Settings should open from \(origin)"
            )
        }
    }

    // Where the journal is kept is the first thing Settings says (owner, 2026-09-23). A UI test
    // store never mirrors, so it reads as staying on this iPhone.
    func testICloudIsTheFirstSection() {
        app.tabBars.buttons["Settings"].tap()
        let sync = app.descendants(matching: .any)["syncStatusRow"]
        XCTAssertTrue(sync.waitForExistence(timeout: 5))
        XCTAssertTrue(sync.label.contains("Off"), sync.label)
        XCTAssertTrue(app.staticTexts["This journal stays on this iPhone."].exists)

        let lifeAreas = app.buttons["lifeAreasSettingsLink"]
        XCTAssertTrue(lifeAreas.waitForExistence(timeout: 5))
        XCTAssertLessThan(sync.frame.minY, lifeAreas.frame.minY)
    }
}
