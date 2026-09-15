import XCTest

// The page flow with generated pages in place of the camera and photo picker (-uiTestingFakePages).
final class PageOrderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-uiTestingFakePages"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
    }

    // Page rows top to bottom, by their width-based identifiers. A row's identifier is inherited by
    // its thumbnail, labels, and button, so each identifier is counted once at its topmost position.
    private func rowIDs() -> [String] {
        var top: [String: CGFloat] = [:]
        for element in app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "pageRow-")).allElementsBoundByIndex {
            top[element.identifier] = min(top[element.identifier] ?? .greatestFiniteMagnitude, element.frame.minY)
        }
        return top.sorted { $0.value < $1.value }.map(\.key)
    }

    @MainActor
    func testScanReorderRemoveAndConfirmPages() throws {
        app.launch()
        let newPhotos = app.buttons["newPhotoEntryButton"]
        XCTAssertTrue(newPhotos.waitForExistence(timeout: 5))
        newPhotos.tap()

        // The fake scan adds three pages, widths 1000, 1010, 1020.
        XCTAssertTrue(app.descendants(matching: .any)["pageRow-1000"].waitForExistence(timeout: 10))
        app.buttons["addFromPhotosButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pageRow-2310"].waitForExistence(timeout: 10))

        // Force-quit before confirming: the pages are kept and the entry says so.
        app.terminate()
        app.launch()
        let unconfirmed = app.staticTexts["Pages not confirmed"]
        XCTAssertTrue(unconfirmed.waitForExistence(timeout: 5))
        unconfirmed.tap()
        XCTAssertTrue(app.descendants(matching: .any)["pageRow-1000"].waitForExistence(timeout: 5))

        // Move the third scanned page to the top with its reorder handle.
        let third = app.buttons["Reorder Page 3"]
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        third.press(forDuration: 0.6, thenDragTo: app.buttons["Reorder Page 1"])

        // Remove the last page (one of the library pages).
        app.buttons["Remove page 5"].tap()
        let confirmRemove = app.buttons["confirmRemovePageButton"].firstMatch
        XCTAssertTrue(confirmRemove.waitForExistence(timeout: 5))
        confirmRemove.tap()

        let confirm = app.buttons["confirmPagesButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        XCTAssertEqual(confirm.label, "Save pages")
        let orderBeforeConfirm = rowIDs()
        XCTAssertEqual(orderBeforeConfirm.count, 4)
        XCTAssertEqual(orderBeforeConfirm.first, "pageRow-1020")
        confirm.tap()

        // Confirming opens the entry; the list no longer shows it as unconfirmed.
        XCTAssertTrue(app.textViews["entryEditor"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.staticTexts["Pages not confirmed"].exists)
    }

    @MainActor
    func testClosingWithNoPagesLeavesNothingBehind() throws {
        app.launch()
        app.buttons["newPhotoEntryButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["pageRow-1000"].waitForExistence(timeout: 10))

        for _ in 0..<3 {
            app.buttons["Remove page 1"].tap()
            let confirmRemove = app.buttons["confirmRemovePageButton"].firstMatch
            XCTAssertTrue(confirmRemove.waitForExistence(timeout: 5))
            confirmRemove.tap()
        }
        app.buttons["pageOrderCloseButton"].tap()

        XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5))
    }
}
