import Foundation
import SwiftData
import Testing
@testable import Mindlore

// The Keep card: what it says the app noticed, the pass a kept recording gets, and what it logs.
@MainActor
struct KeepTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    private func entry(_ text: String = "Walked with Maya") throws -> Entry {
        let entry = Entry(text: text)
        context.insert(entry)
        try context.save()
        return entry
    }

    private func entity(_ name: String, _ kind: EntityKind = .person) throws -> Entity {
        let entity = Entity(name: name, key: name.lowercased(), kind: kind)
        context.insert(entity)
        try context.save()
        return entity
    }

    @discardableResult
    private func link(_ entry: Entry, _ entity: Entity) throws -> EntityLink {
        let link = EntityLink(surface: entity.name, kind: entity.kind)
        context.insert(link)
        link.attach(to: entry, entity: entity)
        try context.save()
        return link
    }

    private func snapshot(_ entry: Entry) -> KeepSnapshot {
        KeepSnapshot.make(entryID: entry.id, links: GraphIndexer(diagnostics: .disabled).allLinks(in: context), in: context)
    }

    // MARK: - What was noticed

    @Test func aNameOnlyThisEntryMentionsIsNewAndOneMentionedBeforeIsNot() throws {
        let (earlier, kept) = (try entry("Earlier"), try entry())
        let (maya, sam) = (try entity("Maya"), try entity("Sam"))
        try link(earlier, maya)
        try link(kept, maya)
        try link(kept, sam)

        let noticed = snapshot(kept).noticed
        #expect(noticed.map(\.name) == ["Sam", "Maya"], "new names come first")
        #expect(noticed.map(\.isNew) == [true, false])
        #expect(snapshot(kept).newCount == 1)
        #expect(snapshot(kept).namesOnTheMap == 2)
    }

    // The map reads journal entries only: a name only a note carries isn't on it, and a note's
    // card offers no way there.
    @Test func theMapLineCountsJournalEntriesAndANoteHasNone() throws {
        let (list, kept) = (try entry("Call Sam"), try entry())
        list.kind = .note
        try context.save()
        let (maya, sam) = (try entity("Maya"), try entity("Sam"))
        try link(list, sam)
        try link(kept, maya)

        #expect(snapshot(kept).entryOnMap)
        #expect(snapshot(kept).namesOnTheMap == 1, "Sam is only in a note")
        #expect(!snapshot(list).entryOnMap)
        #expect(!snapshot(list).noticed.isEmpty, "the card still says what it noticed")
    }

    @Test func aMergedNameShowsAsItsWinnerAndCountsTheWinnersHistory() throws {
        let (earlier, kept) = (try entry("Earlier"), try entry())
        let (winner, loser) = (try entity("Maya Chen"), try entity("Maya"))
        loser.mergedIntoID = winner.id
        try link(earlier, winner)
        try link(kept, loser)

        let result = snapshot(kept)
        #expect(result.noticed.map(\.name) == ["Maya Chen"])
        #expect(result.noticed.first?.id == winner.id)
        #expect(result.noticed.first?.isNew == false, "the winner was already in the journal")
        #expect(result.namesOnTheMap == 1, "a merged loser is not a second name")
    }

    @Test func aMergeCycleDoesNotHang() throws {
        let kept = try entry()
        let (a, b) = (try entity("A"), try entity("B"))
        a.mergedIntoID = b.id
        b.mergedIntoID = a.id
        try link(kept, a)
        #expect(snapshot(kept).noticed.count == 1)
    }

    @Test func hiddenNamesTagsAndOtherAreNeverNoticed() throws {
        let kept = try entry()
        let hidden = try entity("Hidden")
        hidden.hidden = true
        try link(kept, hidden)
        try link(kept, try entity("running", .tag))
        try link(kept, try entity("thing", .other))
        try link(kept, try entity("Lisbon", .place))

        #expect(snapshot(kept).noticed.map(\.name) == ["Lisbon"])
        #expect(snapshot(kept).namesOnTheMap == 1)
    }

    @Test func twoLinksToOneNameAreOneRowAndTheListIsCapped() throws {
        let kept = try entry()
        let maya = try entity("Maya")
        try link(kept, maya)
        try link(kept, maya)
        #expect(snapshot(kept).noticed.count == 1)

        for index in 0..<10 { try link(kept, try entity("Person \(index)")) }
        #expect(snapshot(kept).noticed.count == KeepSnapshot.noticedLimit)
    }

    @Test func aLooseEndThisEntryClosedIsShownAndOneAnotherEntryClosedIsNot() throws {
        let (earlier, kept, other) = (try entry("Earlier"), try entry(), try entry("Other"))
        let mine = LooseEnd(text: "call the landlord", sourceEntryID: earlier.id, sourceEntryDate: day)
        let theirs = LooseEnd(text: "book the dentist", sourceEntryID: earlier.id, sourceEntryDate: day)
        let stillOpen = LooseEnd(text: "renew the passport", sourceEntryID: earlier.id, sourceEntryDate: day)
        let opened = LooseEnd(text: "hear back from Sam", sourceEntryID: kept.id, sourceEntryDate: day)
        [mine, theirs, stillOpen, opened].forEach(context.insert)
        mine.setStatus(.resolved, at: day.addingTimeInterval(86_400), resolvedBy: kept.id)
        theirs.setStatus(.resolved, at: day.addingTimeInterval(86_400), resolvedBy: other.id)
        try context.save()

        let result = snapshot(kept)
        #expect(result.closed.map(\.text) == ["call the landlord"])
        #expect(result.closed.first?.openSince == day)
        #expect(result.opened == ["hear back from Sam"])
    }

    @Test func aLooseEndReopenedByHandIsNoLongerClosed() throws {
        let (earlier, kept) = (try entry("Earlier"), try entry())
        let looseEnd = LooseEnd(text: "call the landlord", sourceEntryID: earlier.id, sourceEntryDate: day)
        context.insert(looseEnd)
        looseEnd.setStatus(.resolved, at: day, resolvedBy: kept.id)
        looseEnd.setByUser(.open)
        try context.save()
        #expect(snapshot(kept).closed.isEmpty)
    }

    @Test func anEntryWithNothingNoticedIsEmptyNotBroken() throws {
        #expect(snapshot(try entry()) == KeepSnapshot.empty)
    }

    // MARK: - The pass

    private func trigger(started: Date = Date(timeIntervalSince1970: 1_000), insights: Bool = true) -> (AIPassTrigger, EditorPresence) {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, now: { started })
        settings.recordAutomationStartIfNeeded()
        let presence = EditorPresence()
        return (AIPassTrigger(settings: settings, presence: presence, titleUsable: { true }, insightsUsable: { insights }, diagnostics: .disabled), presence)
    }

    private func recording(text: String, awaitingText: Bool) throws -> Entry {
        let entry = Entry(source: .voice, text: text, awaitingText: awaitingText)
        context.insert(entry)
        try context.save()
        return entry
    }

    @Test func aLiveTranscribedRecordingGetsItsPassWhenItIsKept() throws {
        let (pass, _) = trigger()
        var queuesRan = 0
        pass.onFlagged = { queuesRan += 1 }
        let kept = try recording(text: "Spoke for a minute", awaitingText: false)

        pass.recordingKept(kept, in: context)
        #expect(kept.automaticAIPassUsed)
        #expect(kept.insightsPending && kept.titlePending)
        #expect(queuesRan == 1)
    }

    @Test func theEditorClosingAfterwardsDoesNotPayForASecondPass() throws {
        let (pass, _) = trigger()
        var queuesRan = 0
        pass.onFlagged = { queuesRan += 1 }
        let kept = try recording(text: "Spoke for a minute", awaitingText: false)
        pass.recordingKept(kept, in: context)
        kept.insightsPending = false
        kept.titlePending = false

        #expect(pass.fire(for: kept, at: .editorClosed) == false)
        #expect(pass.fire(for: kept, at: .textReady) == false)
        pass.recordingKept(kept, in: context)
        #expect(!kept.insightsPending && queuesRan == 1)
    }

    @Test func aRecordingStillWaitingForItsTextIsLeftForTextReady() throws {
        let (pass, _) = trigger()
        var queuesRan = 0
        pass.onFlagged = { queuesRan += 1 }
        let kept = try recording(text: "", awaitingText: true)

        pass.recordingKept(kept, in: context)
        #expect(!kept.automaticAIPassUsed && queuesRan == 0)

        // The cloud transcript lands under the card. Nothing has the entry open, so it fires.
        kept.text = "Arrived late"
        kept.awaitingText = false
        #expect(pass.fire(for: kept, at: .textReady))
    }

    @Test func aRecordingMadeBeforeAutomationStartedIsNeverSent() throws {
        let (pass, _) = trigger(started: .distantFuture)
        let kept = try recording(text: "Old habits", awaitingText: false)
        pass.recordingKept(kept, in: context)
        #expect(!kept.automaticAIPassUsed)
    }

    // MARK: - Words and logs

    @Test func theMeasureReadsLikeAPersonWroteIt() {
        #expect(KeepCopy.measure(duration: 92, words: 214) == "1 min 32 sec · 214 words")
        #expect(KeepCopy.measure(duration: 41.6, words: 1) == "42 sec · 1 word")
        #expect(KeepCopy.measure(duration: nil, words: 0) == "")
        #expect(KeepCopy.measure(duration: 12, words: 0) == "12 sec", "text still on its way")
        #expect(KeepCopy.wordCount("  two\nwords ") == 2)
        #expect(KeepCopy.map(names: 84, new: 3) == "84 names on your mind map, 3 new")
        #expect(KeepCopy.map(names: 1, new: 0) == "1 name on your mind map")
    }

    @Test func nothingTheCardLogsCarriesAWordTheUserSaid() throws {
        let sentinel = DiagnosticsPrivacyTests.sentinel
        let kept = try entry("Spoken \(sentinel)")
        kept.title = "Title \(sentinel)"
        try link(kept, try entity("Name \(sentinel)"))
        let looseEnd = LooseEnd(text: "Thread \(sentinel)", sourceEntryID: kept.id, sourceEntryDate: day)
        context.insert(looseEnd)
        looseEnd.setStatus(.resolved, at: day, resolvedBy: kept.id)
        try context.save()
        let result = snapshot(kept)
        #expect(result.noticed.count == 1 && result.closed.count == 1, "the sentinel is really in what the card holds")

        let file = URL.temporaryDirectory.appending(path: "keep-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let log = DiagnosticsLog(fileURL: file)
        log.record("keep.shown", KeepCopy.shownFields(entryID: kept.id, entry: kept))
        log.record("keep.dismissed", KeepCopy.dismissedFields(entryID: kept.id, entry: kept, snapshot: result, seconds: 4.2, openedEntry: true))
        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("keep.dismissed"))
        #expect(!written.contains(sentinel))
    }
}
