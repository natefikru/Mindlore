import XCTest

// The editor's close rules run when an entry leaves Journal's path, not when its view disappears.
final class JournalNavigationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    private var editor: XCUIElement { app.textViews["entryEditor"] }

    private func startNewEntry() {
        app.launch()
        app.buttons["newEntryButton"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)], timeout: 5)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    private func goBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    // Entry rows, not cells: the list is sectioned by date, and a section header is a cell too.
    private var rows: XCUIElementQuery {
        app.cells.containing(.any, identifier: "entryRow")
    }

    // Clearing a new entry deletes it as the editor slides away, which must not crash or flash.
    @MainActor
    func testClearingANewEntryAndGoingBackLeavesNothing() throws {
        startNewEntry()
        editor.typeText("Gone")
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        goBack()

        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))
    }

    // Switching tabs with an entry open keeps it open, and its text keeps saving into the same entry.
    @MainActor
    func testSwitchingTabsKeepsTheEntryOpen() throws {
        startNewEntry()
        editor.typeText("Before the switch.")

        app.tabBars.buttons["Ask"].tap()
        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        editor.typeText(" After it.")
        goBack()

        XCTAssertTrue(app.staticTexts["Before the switch. After it."].waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
    }

    // A back swipe the user abandons leaves the entry open.
    @MainActor
    func testACancelledBackSwipeKeepsTheEntryOpen() throws {
        startNewEntry()
        editor.typeText("Swiped")

        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        // Slow, a short way, and held before release, so the pop springs back instead of finishing.
        edge.press(
            forDuration: 0.2,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)),
            withVelocity: .slow,
            thenHoldForDuration: 0.5
        )
        if !editor.waitForExistence(timeout: 5) {
            FileManager.default.createFile(atPath: "/tmp/mindlore-swipe-dump.txt", contents: Data(app.debugDescription.utf8))
        }
        XCTAssertTrue(editor.exists, "the swipe was abandoned, so the entry is still open")
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: editor)], timeout: 5)

        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        editor.typeText(" but stayed.")
        goBack()

        if !app.staticTexts["Swiped but stayed."].waitForExistence(timeout: 5) {
            FileManager.default.createFile(atPath: "/tmp/mindlore-swipe-dump.txt", contents: Data(app.debugDescription.utf8))
        }
        XCTAssertTrue(app.staticTexts["Swiped but stayed."].exists)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(app.staticTexts["Draft"].exists)
    }
}
