import XCTest

// The bar above the keyboard: a list item continues on Return, an empty item leaves the list, and
// the layout survives a relaunch beside the plain words.
final class FormattingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    private var editor: XCUIElement { app.textViews["entryEditor"] }

    private func startEntry() {
        app.launch()
        app.buttons["newEntryButton"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: editor)], timeout: 5)
    }

    @MainActor
    func testAListContinuesOnReturnAndEndsOnAnEmptyItem() throws {
        startEntry()
        editor.typeText("Milk")
        let bullet = app.buttons["format-bullet"]
        XCTAssertTrue(bullet.waitForExistence(timeout: 5), "the bar is above the keyboard")
        // The bar rides up with the keyboard; a tap before it has settled lands on nothing.
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: bullet)], timeout: 5)
        bullet.tap()
        XCTAssertTrue(bullet.isSelected)
        editor.typeText("\nEggs")
        XCTAssertTrue(bullet.isSelected, "Return continued the list")
        // The words hold no markers: the list is drawn, not typed.
        XCTAssertEqual(editor.value as? String, "Milk\nEggs")
        editor.typeText("\n")
        XCTAssertTrue(bullet.isSelected)
        editor.typeText("\n")
        XCTAssertFalse(bullet.isSelected, "Return on an empty item leaves the list")
        editor.typeText("Plain")
        XCTAssertEqual(editor.value as? String, "Milk\nEggs\nPlain")

        app.buttons["format-heading1"].tap()
        XCTAssertTrue(app.buttons["format-heading1"].isSelected)
        app.buttons["format-heading1"].tap()
        XCTAssertFalse(app.buttons["format-heading1"].isSelected, "the same button again makes it body")
    }

    // "@" offers names; picking one puts the plain name in the text and links it, with AI off.
    @MainActor
    func testAnAtSignLinksANameTheEntryThenShows() throws {
        startEntry()
        editor.typeText("Lunch with @May")
        let add = app.buttons["mentionAdd"]
        XCTAssertTrue(add.waitForExistence(timeout: 5), "the bar offers the typed name")
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: add)], timeout: 5)
        add.tap()
        XCTAssertEqual(editor.value as? String, "Lunch with May")
        XCTAssertTrue(app.buttons["format-bullet"].waitForExistence(timeout: 5), "the bar goes back to its buttons")
        editor.typeText(" by the #river.")
        app.buttons["finishEntryButton"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        // With AI off the entry keeps offering Done until a launch sweep spends its pass, and an
        // entry that offers Done opens for typing; a relaunch is what makes it a past entry.
        app.terminate()
        app.launch()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Lunch with May'")).firstMatch.tap()
        let readText = app.descendants(matching: .any)["entryReadText"]
        XCTAssertTrue(readText.waitForExistence(timeout: 5))
        XCTAssertTrue(readText.links["May"].waitForExistence(timeout: 5), "the picked name is linked")
        XCTAssertTrue(readText.links["#river"].exists, "the typed tag is linked as written")
    }

    @MainActor
    func testFormattingSurvivesARelaunch() throws {
        startEntry()
        editor.typeText("Call the landlord")
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: app.buttons["format-check"])], timeout: 5)
        app.buttons["format-check"].tap()
        XCTAssertTrue(app.buttons["format-check"].isSelected)
        app.buttons["finishEntryButton"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.terminate()
        app.launch()
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Call the landlord'")).firstMatch.tap()
        let readText = app.descendants(matching: .any)["entryReadText"]
        XCTAssertTrue(readText.waitForExistence(timeout: 5))
        XCTAssertEqual(readText.value as? String, "Call the landlord")
        app.buttons["editEntryButton"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: editor)], timeout: 5)
        XCTAssertTrue(app.buttons["format-check"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["format-check"].isSelected, "the checklist came back with the words")
    }
}
