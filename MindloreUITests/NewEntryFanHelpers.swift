import XCTest

// Every way to start an entry goes through the tab bar's + and its fan (owner, 2026-09-24): the
// Journal toolbar no longer has its own buttons. A tap on the + tab lands on the drawn + above it,
// which opens the fan and leaves it open for the option's tap.
extension XCUIApplication {
    func openNewEntryFan(file: StaticString = #filePath, line: UInt = #line) {
        let plus = tabBars.buttons["New"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10), file: file, line: line)
        plus.tap()
    }

    func chooseFromNewEntryFan(_ option: String, file: StaticString = #filePath, line: UInt = #line) {
        openNewEntryFan(file: file, line: line)
        let button = buttons["newEntryFan-\(option)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        button.tap()
    }

    func startNewWrittenEntry(file: StaticString = #filePath, line: UInt = #line) {
        chooseFromNewEntryFan("write", file: file, line: line)
    }

    // Record in the fan starts recording at once: choosing it was the decision.
    func startNewRecording(file: StaticString = #filePath, line: UInt = #line) {
        chooseFromNewEntryFan("record", file: file, line: line)
    }

    func startNewPages(file: StaticString = #filePath, line: UInt = #line) {
        chooseFromNewEntryFan("pages", file: file, line: line)
    }

    // Settings is a sheet from Journal's gear.
    func openSettingsSheet(file: StaticString = #filePath, line: UInt = #line) {
        let journal = tabBars.buttons["Journal"]
        if journal.exists, !journal.isSelected { journal.tap() }
        let gear = buttons["settingsButton"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5), file: file, line: line)
        gear.tap()
    }
}
