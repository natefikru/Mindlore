import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct ReviewPromptTests {
    let installed = Date(timeIntervalSince1970: 1_000_000)
    var later: Date { installed.addingTimeInterval(4 * 86_400) }

    @Test func aFullLifeReadingAsksOnceTheAppHasBeenAroundLongEnough() {
        #expect(ReviewPrompt.shouldAsk(.lifeReading, finishedEntries: 0, installedAt: installed, lastAskedVersion: nil, version: "1.0", now: later))
    }

    @Test func neverInTheFirstDays() {
        let early = installed.addingTimeInterval(2 * 86_400)
        #expect(!ReviewPrompt.shouldAsk(.lifeReading, finishedEntries: 50, installedAt: installed, lastAskedVersion: nil, version: "1.0", now: early))
        #expect(!ReviewPrompt.shouldAsk(.lifeReading, finishedEntries: 50, installedAt: nil, lastAskedVersion: nil, version: "1.0", now: later))
    }

    @Test func aFinishedEntryAsksFromTheTenth() {
        #expect(!ReviewPrompt.shouldAsk(.entryFinished, finishedEntries: 9, installedAt: installed, lastAskedVersion: nil, version: "1.0", now: later))
        #expect(ReviewPrompt.shouldAsk(.entryFinished, finishedEntries: 10, installedAt: installed, lastAskedVersion: nil, version: "1.0", now: later))
    }

    @Test func neverTwiceForOneVersion() {
        #expect(!ReviewPrompt.shouldAsk(.lifeReading, finishedEntries: 0, installedAt: installed, lastAskedVersion: "1.0", version: "1.0", now: later))
        #expect(ReviewPrompt.shouldAsk(.lifeReading, finishedEntries: 0, installedAt: installed, lastAskedVersion: "1.0", version: "1.1", now: later))
    }
}

@MainActor
struct ReviewPrompterTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }

    @Test func asksOnceAndRemembersTheVersion() {
        let clock = Clock()
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store, diagnostics: .disabled, now: { clock.now })
        settings.recordAutomationStartIfNeeded()
        clock.now = clock.now.addingTimeInterval(4 * 86_400)
        let prompter = ReviewPrompter(settings: settings, version: "1.0", now: { clock.now }, diagnostics: .disabled)
        var shown = 0
        prompter.request = { shown += 1 }

        #expect(prompter.moment(.lifeReading))
        #expect(!prompter.moment(.lifeReading))
        #expect(shown == 1)
        // The version survives a relaunch.
        let reopened = SettingsStore(store: store, diagnostics: .disabled)
        #expect(reopened.reviewRequestedVersion == "1.0")
    }

    @Test func editorCloseReportsOnlyAFinishedEntry() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, now: { Date(timeIntervalSince1970: 1_000) })
        settings.recordAutomationStartIfNeeded()
        let presence = EditorPresence()
        let aiPass = AIPassTrigger(settings: settings, presence: presence, titleUsable: { false }, insightsUsable: { false }, diagnostics: .disabled)
        let lifecycle = EditorLifecycle(context: context, saver: EntrySaver(context: context, diagnostics: .disabled), presence: presence, aiPass: aiPass, keepAudio: { true }, diagnostics: .disabled)
        var finished = 0
        lifecycle.onEntryFinished = { finished += 1 }

        let draft = Entry(text: "half a thought")
        draft.isDraft = true
        let done = Entry(text: "a whole day")
        context.insert(draft)
        context.insert(done)

        lifecycle.closed(draft.id)
        lifecycle.closedForDeletion(done.id)
        #expect(finished == 0)
        lifecycle.closed(done.id)
        #expect(finished == 1)
    }
}
