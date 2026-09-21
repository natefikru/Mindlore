import XCTest

// Opens the 3D spike over the demo journal and photographs it. The spike has no other way to be
// looked at, and a four-node journal once drew what read as an empty page, so the readout it
// asserts on is the one that said how many nodes were really there.
//
// SPIKE_SEED sets the journal size (default 300); the demo store is only seeded when empty, so
// uninstall the app between sizes.
final class Spike3DScreenshotTests: XCTestCase {
    @MainActor
    func testOpenTheSpike() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seedDemoJournal", ProcessInfo.processInfo.environment["SPIKE_SEED"] ?? "300"]
        app.launch()

        XCTAssertTrue(app.buttons["settingsButton"].waitForExistence(timeout: 60))
        app.buttons["settingsButton"].tap()

        let link = app.buttons["spike3DLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 10), "the Debug row is there")
        link.tap()

        // The layout settles before the scene appears; the readout says how it went.
        sleep(12)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "spike"
        shot.lifetime = .keepAlways
        add(shot)

        let readout = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'nodes'")).firstMatch
        XCTAssertTrue(readout.exists, "the readout should say how many nodes were built")
        print("SPIKE-READOUT: \(readout.label)")
    }
}
