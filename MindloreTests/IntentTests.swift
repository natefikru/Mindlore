import Foundation
import Testing
@testable import Mindlore

// What an App Intent can make the app do, and the handoff that lets one arrive before RootView
// exists. The intents themselves only call IntentRequests.request, so everything that can go wrong
// is here; whether Siri and the Action button reach perform() at all is the device's to show.
@MainActor
struct IntentTests {
    private final class Log {
        var opened: [UUID] = []
        var closed: [UUID] = []
    }

    private func router(_ log: Log = Log()) -> AppRouter {
        AppRouter(opened: { log.opened.append($0) }, closed: { log.closed.append($0) })
    }

    // MARK: - The handoff

    @Test func aRequestIsTakenExactlyOnce() {
        let requests = IntentRequests(diagnostics: .disabled)
        requests.request(.newEntry)

        #expect(requests.take() == .newEntry)
        #expect(requests.take() == nil, "a view that appears twice acts once")
    }

    // A cold launch: the request lands before anything could take it, and is still there when
    // RootView finally appears.
    @Test func aRequestWaitsForWhoeverTakesIt() {
        let requests = IntentRequests(diagnostics: .disabled)
        requests.request(.record)
        // Nothing takes it yet.
        #expect(requests.pending == .record)
        #expect(requests.take() == .record)
    }

    @Test func askingTwiceForTheSameThingCountsTwice() {
        let requests = IntentRequests(diagnostics: .disabled)
        requests.request(.newEntry)
        let first = requests.token
        _ = requests.take()
        requests.request(.newEntry)
        #expect(requests.token == first + 1, "the change is what RootView watches")
    }

    // MARK: - Record

    @Test func recordStartsARecording() throws {
        let harness = try RecordingSessionHarness()

        let outcome = IntentHandler.handle(.record, recording: harness.session, router: router())

        #expect(outcome == .recording)
        #expect(harness.session.status != .idle)
        #expect(harness.session.isExpanded)
        #expect(harness.recorders.count == 1)
    }

    // Starting a second would be a silent no-op; the recorder coming back is the honest answer.
    @Test func recordWhileRecordingBringsTheRecorderBack() async throws {
        let harness = try RecordingSessionHarness()
        await harness.beginAndWait()
        harness.session.minimize()
        #expect(!harness.session.isExpanded)

        let outcome = IntentHandler.handle(.record, recording: harness.session, router: router())

        #expect(outcome == .recorderShown)
        #expect(harness.session.isExpanded)
        #expect(harness.recorders.count == 1, "no second recording")
    }

    // MARK: - New entry

    @Test func newEntryOpensANewEntryInJournal() throws {
        let log = Log()
        let router = router(log)
        router.tab = .mind

        IntentHandler.handle(.newEntry, recording: try RecordingSessionHarness().session, router: router)

        #expect(router.tab == .journal)
        #expect(router.journalPath.count == 1)
        #expect(router.journalPath.first?.isNew == true)
        #expect(log.opened.count == 1)
    }

    // Like showEntry: it replaces, so an open entry closes rather than sitting underneath.
    @Test func newEntryReplacesAnOpenEntry() {
        let log = Log()
        let router = router(log)
        let open = UUID()
        router.journalPath = [JournalRoute(entryID: open)]

        router.showNewEntry()

        #expect(log.closed == [open])
        #expect(router.journalPath.count == 1)
        #expect(router.journalPath.first?.entryID != open)
    }

    @Test func newEntryWaitsBehindTheRecorder() {
        let router = router()
        router.setCover("recorder", open: true)

        router.showNewEntry()
        #expect(router.journalPath.isEmpty, "a full-screen cover can't be closed from outside")

        router.setCover("recorder", open: false)
        #expect(router.journalPath.first?.isNew == true)
    }

    // MARK: - Ask

    @Test func askOpensAskWithTheQuestionForTheFieldToTake() throws {
        let router = router()

        IntentHandler.handle(.ask("How was the move?"), recording: try RecordingSessionHarness().session, router: router)

        #expect(router.tab == .ask)
        #expect(router.consumeAskField()?.question == "How was the move?")
        #expect(router.consumeAskField() == nil, "taken once")
    }

    @Test func askWithNoQuestionStillOpensAsk() {
        let router = router()
        router.showAsk(question: nil)

        #expect(router.tab == .ask)
        let request = router.consumeAskField()
        #expect(request != nil)
        #expect(request?.question == nil)
    }

    @Test func askWaitsBehindTheRecorder() {
        let router = router()
        router.setCover("recorder", open: true)

        router.showAsk(question: "anything")
        #expect(router.tab == .journal)
        #expect(router.askFieldRequest == nil)

        router.setCover("recorder", open: false)
        #expect(router.tab == .ask)
        #expect(router.consumeAskField()?.question == "anything")
    }

    @Test func askingTwiceGivesTwoRequests() {
        let router = router()
        router.showAsk(question: "same")
        let first = router.consumeAskField()
        router.showAsk(question: "same")
        let second = router.consumeAskField()
        #expect(first != second, "the token tells them apart")
    }

    // MARK: - Privacy

    @Test func theLogSaysWhichIntentAndNeverWhatWasAsked() throws {
        let sentinel = DiagnosticsPrivacyTests.sentinel
        let file = URL.temporaryDirectory.appending(path: "intents-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let requests = IntentRequests(diagnostics: DiagnosticsLog(fileURL: file))

        requests.request(.ask(sentinel))
        requests.request(.ask(nil))
        requests.request(.record)
        requests.request(.newEntry)

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("intent.invoked"))
        #expect(written.contains("\"ask\""))
        #expect(written.contains("hasQuestion"))
        #expect(!written.contains(sentinel))
    }
}
