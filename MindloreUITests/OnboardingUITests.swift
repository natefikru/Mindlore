import XCTest

final class OnboardingUITests: XCTestCase {
    // The fast path: skip both the recording demo and the reminder, landing on an empty journal.
    func testSkippingBothScreensReachesAnEmptyJournal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-showOnboarding", "-uiTestingFakeRecorder"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["welcomeView"].waitForExistence(timeout: 10))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "onboarding-welcome"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["welcomeStart"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["onboardingRecordPage"].waitForExistence(timeout: 5))
        app.buttons["onboardingRecordSkip"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["onboardingReminderPage"].waitForExistence(timeout: 5))
        app.buttons["onboardingReminderSkip"].tap()

        XCTAssertTrue(app.buttons["journalEmptyRecord"].waitForExistence(timeout: 5))
    }

    // Trying the demo recording and stopping it early still reaches the reminder screen and the
    // journal. The reminder's own "Remind me" isn't exercised here: it asks the system for
    // notification permission for real, which needs an interruption monitor and belongs to a
    // device pass rather than the simulator.
    func testTryingTheDemoRecordingReachesTheJournal() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-showOnboarding", "-uiTestingFakeRecorder"]
        app.launchEnvironment = ["UITEST_STORE_NAME": UUID().uuidString]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["welcomeView"].waitForExistence(timeout: 10))
        app.buttons["welcomeStart"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["onboardingRecordPage"].waitForExistence(timeout: 5))
        app.buttons["onboardingRecordStart"].tap()
        // Same button, now labeled Stop: tapping it again ends the demo without waiting out the
        // full ten seconds.
        XCTAssertTrue(app.buttons["onboardingRecordStart"].waitForExistence(timeout: 5))
        app.buttons["onboardingRecordStart"].tap()
        XCTAssertTrue(app.buttons["onboardingRecordContinue"].waitForExistence(timeout: 5))
        app.buttons["onboardingRecordContinue"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["onboardingReminderPage"].waitForExistence(timeout: 5))
        app.buttons["onboardingReminderSkip"].tap()

        XCTAssertTrue(app.buttons["journalEmptyRecord"].waitForExistence(timeout: 5))
    }
}
