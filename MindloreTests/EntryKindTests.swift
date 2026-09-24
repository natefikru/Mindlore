import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import Mindlore

// Journal, note, or creative: what each kind keeps from an insights run, how the user's pick and
// the model's verdict meet, and what the list row makes of the entry (owner, 2026-09-23).
@MainActor
struct EntryKindTests {
    static let noteResponse = InsightsHarness.fullResponse.replacingOccurrences(of: #"{"summary""#, with: #"{"entryKind":"note","summary""#)

    @Test func theTwoFlagsReadAndWriteAsOneKind() {
        let entry = Entry(text: "x")
        #expect(entry.kind == .journal)
        entry.kind = .note
        #expect(entry.isNote && !entry.isCreative)
        entry.kind = .creative
        #expect(entry.isCreative && !entry.isNote, "never both")
        entry.kind = .journal
        #expect(!entry.isCreative && !entry.isNote)

        entry.setKindByUser(.note)
        #expect(entry.kind == .note && entry.creativeSetByUser)
        entry.setCreativeByUser(true)
        #expect(entry.kind == .creative)
    }

    @Test func eachKindKeepsWhatItShould() {
        #expect(EntryKind.journal.keepsMoods && EntryKind.journal.keepsMentions && EntryKind.journal.keepsLooseEnds && EntryKind.journal.keepsAreas)
        #expect(!EntryKind.note.keepsMoods, "a list carries no feeling worth charting")
        #expect(EntryKind.note.keepsMentions && EntryKind.note.keepsLooseEnds && EntryKind.note.keepsAreas, "a plan names people and leaves things open")
        #expect(!EntryKind.creative.keepsMoods && !EntryKind.creative.keepsMentions && !EntryKind.creative.keepsLooseEnds && !EntryKind.creative.keepsAreas)
        #expect(EntryKind.journal.keepsMore(than: .note) && EntryKind.journal.keepsMore(than: .creative) && EntryKind.note.keepsMore(than: .creative))
        #expect(!EntryKind.note.keepsMore(than: .journal) && !EntryKind.creative.keepsMore(than: .note) && !EntryKind.journal.keepsMore(than: .journal))
        #expect(EntryKind.allCases.map(\.promptValue) == ["life", "note", "creative"])
        #expect(EntryKind.fromPromptValue("note") == .note && EntryKind.fromPromptValue("creative") == .creative)
        #expect(EntryKind.fromPromptValue("life") == .journal && EntryKind.fromPromptValue(nil) == .journal && EntryKind.fromPromptValue("poem") == .journal)
    }

    @Test func restrictingAResultDropsOnlyWhatTheKindNeverKeeps() throws {
        let plan = InsightsPromptBuilder.plan(text: "x", source: .typed, sections: InsightSections(), vocabulary: .empty, model: "m")
        var note = try InsightsPromptBuilder.parse(Self.noteResponse, plan: plan)
        #expect(note.kind == .note)
        note.restrict(to: .note)
        #expect(note.primaryMood == nil && note.secondaryMoods.isEmpty)
        #expect(note.mentions.map(\.name) == ["Sarah"] && note.looseEnds.new.map(\.text) == ["Call Sarah"] && note.areas == [.health])

        var poem = try InsightsPromptBuilder.parse(InsightsHarness.fullResponse, plan: plan)
        poem.restrict(to: .creative)
        #expect(poem.mentions.isEmpty && poem.looseEnds.isEmpty && poem.areas.isEmpty && poem.primaryMood == nil)
        #expect(poem.tags == ["nature"] && poem.summary == "A river walk.", "a theme is not a claim about a life")
    }

    // A note is read like life, minus its mood: its names are kept (for search, entity pages, and
    // Ask; the map reads journal entries only) and its loose ends stay open, so "buy a gift for Sarah" on a list is still something a later entry can settle.
    @Test func aNoteKeepsItsNamesAndLooseEndsAndCarriesNoMood() async throws {
        let harness = try InsightsHarness()
        harness.useGraph = true
        let entry = try harness.entry("Things to do: call Sarah about the lease")
        entry.entryDate = .now
        harness.generator.results = [.success(Self.noteResponse)]

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.kind == .note && !entry.creativeSetByUser)
        let insights = try #require(entry.insights)
        #expect(insights.primaryMood == nil && insights.secondaryMoods.isEmpty)
        #expect(insights.mentions.map(\.name) == ["Sarah"])
        #expect(insights.areas == [.health])
        #expect(try harness.context.fetch(FetchDescriptor<EntityLink>()).contains { $0.kindRaw == EntityKind.person.rawValue })
        #expect(LooseEnd.all(in: harness.context).filter(\.isOpen).map(\.text) == ["Call Sarah"])
    }

    @Test func theOnDeviceModelNeverFilesANote() {
        #expect(CreativeSignals.decideKind(modelSays: .note, text: "milk, eggs, bread", onDevice: true, focused: nil) == .journal)
        #expect(CreativeSignals.decideKind(modelSays: .note, text: "milk, eggs, bread", onDevice: false, focused: nil) == .note)
        #expect(CreativeSignals.decideKind(modelSays: .creative, text: "a long line of prose that goes on and on and on and on and on and on and on and on", onDevice: true, focused: true) == .journal, "prose is never creative on device")
        #expect(CreativeSignals.decideKind(modelSays: .creative, text: "x", onDevice: false, focused: nil) == .creative)
        #expect(CreativeSignals.decideKind(modelSays: .journal, text: "x", onDevice: false, focused: nil) == .journal)
    }

    @Test func markingANoteByHandDropsTheMoodAndKeepsTheRest() async throws {
        let harness = try InsightsHarness()
        harness.useGraph = true
        let entry = try harness.entry("Sarah by the river")
        entry.entryDate = .now
        harness.generator.results = [.success(InsightsHarness.fullResponse)]
        await harness.coordinator.processQueue(context: harness.context)
        #expect(entry.insights?.primaryMood == .calm)

        GraphServices(diagnostics: .disabled).setKind(.note, on: entry, in: harness.context)

        #expect(entry.kind == .note && entry.creativeSetByUser)
        #expect(entry.insights?.primaryMood == nil)
        #expect(entry.insights?.areas == [.health])
        #expect(entry.insights?.mentions.map(\.name) == ["Sarah"])
        #expect(LooseEnd.all(in: harness.context).first { $0.text == "Call Sarah" }?.isOpen == true)
        #expect(try harness.context.fetch(FetchDescriptor<EntityLink>()).contains { $0.kindRaw == EntityKind.person.rawValue })
    }

    @Test func theUsersKindIsNeverOverriddenByARun() async throws {
        let harness = try InsightsHarness()
        let entry = try harness.entry("milk, eggs, a call to Sarah")
        entry.setKindByUser(.journal)
        harness.generator.results = [.success(Self.noteResponse)]

        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.kind == .journal)
        #expect(entry.insights?.primaryMood == .calm, "read as life, as the user said")
    }

    @Test func askAndReflectSayItIsANote() {
        let block = AskContextBuilder.block(handle: "E1", date: .now, title: "Groceries", text: "milk", note: true)
        #expect(block.contains(AskContextBuilder.noteMarker))
        #expect(!block.contains(AskContextBuilder.creativeMarker))
        #expect(AskContextBuilder.noteMarker.count <= AskContextBuilder.creativeMarker.count, "the character estimate is sized on the creative marker")
        let both = AskContextBuilder.block(handle: "E1", date: .now, title: "t", text: "x", creative: true, note: true)
        #expect(both.contains(AskContextBuilder.creativeMarker) && !both.contains(AskContextBuilder.noteMarker))

        let list = ReflectFidelity.WeekEntry(id: UUID(), date: .now, title: "Groceries", text: "milk", isNote: true)
        #expect(ReflectFidelity.weekPrompt([list]).contains(AskContextBuilder.noteMarker))
        let day = ReflectFidelity.WeekEntry(id: list.id, date: list.date, title: list.title, text: list.text)
        #expect(ReflectSummaryStore.fingerprint([list]) != ReflectSummaryStore.fingerprint([day]), "flipping it rewrites a running week")
    }

    // The row's two lines of the entry's own words, without the line the title already shows.
    @Test func thePreviewLeavesOutTheLineTheTitleCameFrom() {
        #expect(Entry.preview(text: "Walked to the river.\nThe light was strange.", title: "") == "The light was strange.")
        #expect(Entry.preview(text: "Walked to the river.\nThe light was strange.", title: "A walk") == "Walked to the river. The light was strange.")
        #expect(Entry.preview(text: "Walked to the river.", title: "") == nil, "nothing beyond the derived title")
        let long = String(repeating: "word ", count: 30).trimmingCharacters(in: .whitespaces)
        #expect(Entry.preview(text: long, title: "") == long, "a first line too long to be the whole title is previewed")
        #expect(Entry.preview(text: "  \n\n", title: "") == nil)
        #expect(Entry.preview(text: String(repeating: "a", count: 400), title: "t")?.count == 240)
        let entry = Entry(text: "First line.\nSecond line.")
        #expect(entry.previewText == "Second line.")
    }
}

@MainActor
struct InsightSectionsTests {
    private let text = "Morning at the office with Dana went long. Then I called my sister about the wedding. Tonight I plan the trip to Lisbon."

    private func plan(_ sections: InsightSections = InsightSections(), budget: InsightsPromptBuilder.Budget = .cloud) -> InsightsRequestPlan {
        InsightsPromptBuilder.plan(text: text, source: .typed, sections: sections, vocabulary: .empty, model: "m", budget: budget)
    }

    private func properties(_ plan: InsightsRequestPlan) throws -> [String: Any] {
        guard case .object(let properties, _, _) = try #require(plan.request.schema) else { return [:] }
        return Dictionary(uniqueKeysWithValues: properties.map { ($0.name, $0.schema as Any) })
    }

    @Test func sectionsAreAskedForWithTheFieldsTheyRefineAndNeverOnDevice() throws {
        #expect(plan().asksForSections)
        #expect(try properties(plan())["sections"] != nil)
        #expect(plan().request.system.contains("An entry about one thing has no parts"))
        var none = InsightSections()
        none.tags = false
        none.mentions = false
        none.lifeAreas = false
        #expect(!plan(none).asksForSections)
        #expect(!plan(budget: .onDevice).asksForSections, "the small model has no room for them")
        #expect(try properties(plan(budget: .onDevice))["sections"] == nil)
    }

    @Test func partsAreGroundedCappedAndFoldedIntoTheTags() throws {
        let response = """
        {"summary":"A full day.","primaryMood":"calm","secondaryMoods":[],"lifeAreas":["work"],"tags":["office"],
         "mentions":[{"name":"Dana","kind":"person"}],"looseEnds":[],
         "sections":[
           {"topic":"Work with Dana","startsWith":"Morning at the office","summary":"A long morning.","lifeAreas":["work","work","planet"],"tags":["Office","meetings","work"],"names":["Dana"]},
           {"topic":"Sister's wedding","startsWith":"Then I called my sister","summary":null,"lifeAreas":["family"],"tags":["wedding"],"names":["my sister"]},
           {"topic":"","startsWith":"x","tags":["dropped"]},
           {"topic":"Lisbon trip","startsWith":"not in the entry","lifeAreas":["play"],"tags":["travel","lisbon","packing","flights","hotels","extra"],"names":[]}
         ]}
        """
        let result = try InsightsPromptBuilder.parse(response, plan: plan())

        #expect(result.sections.map(\.topic) == ["Work with Dana", "Sister's wedding", "Lisbon trip"], "a part with no topic is dropped")
        #expect(result.sections[0].offset == 0)
        let sisterStart = text.range(of: "Then I called").map { text.distance(from: text.startIndex, to: $0.lowerBound) }
        #expect(result.sections[1].offset == sisterStart)
        #expect(result.sections[2].offset == nil, "opening words not in the entry still count, unplaced")
        #expect(result.sections[0].areasRaw == ["work"], "duplicates and unknown areas go")
        #expect(result.sections[0].tags == ["office", "meetings"], "an area's name is not a tag")
        #expect(result.sections[2].tags.count == InsightsPromptBuilder.maxSectionTags)
        #expect(result.sections[0].summary == "A long morning." && result.sections[1].summary == nil)
        #expect(result.tags == ["office", "meetings", "wedding", "travel", "lisbon", "packing", "flights", "hotels"], "the entry's own first, then its parts, under the entry's cap")
    }

    @Test func partsArePlacedInOrderAndCappedAtSix() throws {
        let items = (1...8).map { #"{"topic":"Part \#($0)","startsWith":"Morning at the office"}"# }.joined(separator: ",")
        let result = try InsightsPromptBuilder.parse(#"{"sections":[\#(items)]}"#, plan: plan())
        #expect(result.sections.count == InsightsPromptBuilder.maxSections)
        #expect(result.sections[0].offset == 0)
        #expect(result.sections[1].offset == nil, "the same opening can't start a later part")
    }

    @Test func partsAreStoredWithTheInsightsAndDroppedForCreativeWork() async throws {
        let harness = try InsightsHarness()
        let entry = try harness.entry(text)
        let withParts = InsightsHarness.fullResponse.replacingOccurrences(of: #"{"summary""#, with: #"{"sections":[{"topic":"Work","startsWith":"Morning at the office","tags":["office"]},{"topic":"Family","startsWith":"Then I called"}],"summary""#)
        harness.generator.results = [.success(withParts)]
        await harness.coordinator.processQueue(context: harness.context)
        let stored = try #require(entry.insights?.sections)
        #expect(stored.map(\.topic) == ["Work", "Family"])
        #expect(stored[1].offset != nil)
        #expect(entry.insights?.tags == ["nature", "office"])

        let poem = try harness.entry("moon on the water")
        harness.generator.results = [.success(withParts.replacingOccurrences(of: #"{"sections""#, with: #"{"entryKind":"creative","sections""#))]
        await harness.coordinator.processQueue(context: harness.context)
        #expect(poem.isCreative && poem.insights?.sections.isEmpty == true)
    }

    @Test func aPhotoEntrysWrittenDateFromInsightsIsAppliedWithoutAsking() async throws {
        let harness = try InsightsHarness()
        let page = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .photo, text: "March 3, 2025. Dear diary.")
        page.pagesConfirmed = true
        page.insightsPending = true
        harness.context.insert(page)
        try harness.context.save()
        harness.generator.results = [.success(InsightsHarness.fullResponse)]

        await harness.coordinator.processQueue(context: harness.context)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let march3 = try #require(EntryDates.parseDay("2025-03-03", calendar: utc))
        #expect(EntryDates.isSameDay(page.entryDate, march3, calendar: utc))
        #expect(page.entryDateIsDayOnly && page.suggestedEntryDate == nil)

        // A day already picked, by the user or an earlier pass, is never moved by a rerun: a
        // different reading is only offered.
        let picked = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .photo, text: "March 3, 2025. Dear diary.")
        picked.pagesConfirmed = true
        picked.setEntryDay(Date(timeIntervalSince1970: 1_000_000_000), calendar: utc)
        picked.insightsPending = true
        harness.context.insert(picked)
        try harness.context.save()
        let pickedDay = picked.entryDate
        harness.generator.results = [.success(InsightsHarness.fullResponse)]
        await harness.coordinator.processQueue(context: harness.context)
        #expect(picked.entryDate == pickedDay)
        #expect(picked.suggestedEntryDate.map { EntryDates.isSameDay($0, march3, calendar: utc) } == true)

        // A typed entry still only gets the offer, unless the setting says otherwise.
        let typed = try harness.entry("March 3, 2025. Dear diary.")
        harness.generator.results = [.success(InsightsHarness.fullResponse)]
        await harness.coordinator.processQueue(context: harness.context)
        #expect(typed.suggestedEntryDate != nil && !typed.entryDateIsDayOnly)
    }
}

// The three events the new code writes from unit-testable places, driven with a real log and
// the sentinel as the entry's text and the recorder's prompt (docs/privacy-coverage.md).
@MainActor
struct EntryKindDiagnosticsPrivacyTests {
    @Test func kindTitleAndReadyRecorderNeverLogTheUsersWords() async throws {
        let sentinel = DiagnosticsPrivacyTests.sentinel
        let file = DiagnosticsFile()
        let log = DiagnosticsLog(fileURL: file.url)

        let harness = try InsightsHarness()
        let entry = try harness.entry("Groceries for \(sentinel)")
        GraphServices(diagnostics: log).setKind(.note, on: entry, in: harness.context)

        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, now: { Date(timeIntervalSince1970: 1_000) })
        let trigger = AIPassTrigger(settings: settings, presence: EditorPresence(), titleUsable: { true }, insightsUsable: { true }, diagnostics: log)
        #expect(trigger.requestTitle(for: entry))

        let recording = try RecordingSessionHarness(diagnostics: log)
        recording.recordOnOpen = false
        recording.prompts = ["call \(sentinel)"]
        recording.session.begin()

        let contents = file.contents()
        #expect(contents.contains("entry.kindSet"))
        #expect(contents.contains("title.requested"))
        #expect(contents.contains("recording.ready"))
        #expect(!contents.contains(sentinel))
    }
}

@MainActor
struct ApprovedTitleTests {
    private func trigger(titles: Bool = true) -> AIPassTrigger {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled, now: { Date(timeIntervalSince1970: 1_000) })
        settings.recordAutomationStartIfNeeded()
        return AIPassTrigger(settings: settings, presence: EditorPresence(), titleUsable: { titles }, insightsUsable: { true }, diagnostics: .disabled)
    }

    // Generate insights from the sheet spends the pass while the pages are still in review, which
    // used to leave a photo entry titled by its first line, often the date at the top of the page.
    @Test func approvingPageTextAsksForATitleEvenAfterThePassWasSpent() {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .photo, text: "March 3, 2025\nDear diary.")
        entry.pagesConfirmed = true
        entry.automaticAIPassUsed = true
        entry.approveText()

        #expect(!trigger().fire(for: entry, at: .approved), "the pass is spent")
        #expect(trigger().requestTitle(for: entry))
        #expect(entry.titlePending)
        #expect(!trigger().requestTitle(for: entry), "already pending")
    }

    @Test func aTitleTheUserTypedIsLeftAlone() {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .photo, text: "Dear diary.")
        entry.userDidEditTitle("My own title")
        #expect(!trigger().requestTitle(for: entry))
        entry.applyGeneratedTitle("x")
        #expect(!entry.titleWasGenerated, "a user's title never gives way")

        let generated = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: .photo, text: "Dear diary.")
        generated.applyGeneratedTitle("Old title")
        #expect(trigger().requestTitle(for: generated), "a generated one is replaced after a re-review")
        #expect(!trigger(titles: false).requestTitle(for: Entry(text: "x")))
        #expect(!trigger().requestTitle(for: Entry(text: "  ")))
    }
}

@MainActor
struct ReadyRecorderTests {
    @Test func theRecorderOpensReadyAndWaitsForItsButton() async throws {
        let harness = try RecordingSessionHarness()
        harness.recordOnOpen = false
        harness.prompts = ["call the landlord"]

        harness.session.begin()
        #expect(harness.session.status == .ready)
        #expect(harness.session.isExpanded)
        #expect(!harness.session.showsAccessory, "nothing is being recorded yet")
        #expect(harness.recorders.isEmpty, "no recorder until the tap")
        #expect(harness.session.prompt == "call the landlord", "the loose end is up while it waits")
        #expect(!harness.session.isRecording)

        harness.session.startRecording()
        #expect(harness.session.status == .starting)
        await harness.session.startTask?.value
        #expect(harness.session.status == .active)
        #expect(harness.session.showsAccessory)
        #expect(harness.recorders.count == 1 && harness.recorders[0].state == .recording)

        harness.session.startRecording()
        #expect(harness.recorders.count == 1, "only from ready")
    }

    @Test func closingAReadyRecorderPutsItAway() throws {
        let harness = try RecordingSessionHarness()
        harness.recordOnOpen = false
        harness.session.begin()
        harness.session.close()
        #expect(harness.session.status == .idle && !harness.session.isExpanded && harness.session.prompt == nil)
        #expect(harness.recorders.isEmpty)
    }

    // New Written Entry and Ask put the recorder away; a waiting one has nothing to keep and no
    // accessory to come back through, so it closes rather than hiding with Record disabled.
    @Test func puttingAWaitingRecorderAwayClosesIt() throws {
        let harness = try RecordingSessionHarness()
        harness.recordOnOpen = false
        harness.session.begin()
        harness.session.minimize()
        #expect(harness.session.status == .idle && !harness.session.isExpanded)
    }

    @Test func siriStartsAWaitingRecorder() async throws {
        let harness = try RecordingSessionHarness()
        harness.recordOnOpen = false
        harness.session.begin()
        let router = AppRouter(opened: { _ in }, closed: { _ in })
        #expect(IntentHandler.handle(.record, recording: harness.session, router: router) == .recording)
        await harness.session.startTask?.value
        #expect(harness.session.status == .active)
    }

    @Test func siriStartsAtOnceWhateverTheSettingSays() async throws {
        let harness = try RecordingSessionHarness()
        harness.recordOnOpen = false
        harness.session.begin(startsNow: true)
        #expect(harness.session.status == .starting)
        await harness.session.startTask?.value
        #expect(harness.session.status == .active)
    }

    @Test func theSettingIsOffByDefaultAndTheFontIsSerif() {
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store, diagnostics: .disabled)
        #expect(!settings.recordOnOpen)
        #expect(settings.journalFont == .serif)
        settings.recordOnOpen = true
        settings.journalFont = .rounded
        #expect(store.values[SettingsStore.Key.recordOnOpen] as? Bool == true)
        #expect(store.values[SettingsStore.Key.journalFont] as? String == "rounded")
        let again = SettingsStore(store: store, diagnostics: .disabled)
        #expect(again.recordOnOpen && again.journalFont == .rounded)
        #expect(JournalFont.allCases.map(\.design) == [.serif, .default, .rounded, .monospaced])
        #expect(JournalFont.allCases.map(\.uiDesign) == [.serif, .default, .rounded, .monospaced])
    }
}

// Two names in one entry connect on the map only when they share a part (owner, 2026-09-23).
@MainActor
struct PartAwareGraphTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func namesInDifferentPartsOfOneEntryDoNotConnect() {
        let entry = UUID()
        let dana = UUID(), office = UUID(), maya = UUID(), wedding = UUID(), unplaced = UUID()
        let edges = EntityGraph.build(links: [
            .init(entryID: entry, entityID: dana, entryDate: now, parts: [0]),
            .init(entryID: entry, entityID: office, entryDate: now, parts: [0]),
            .init(entryID: entry, entityID: maya, entryDate: now, parts: [1]),
            .init(entryID: entry, entityID: wedding, entryDate: now, parts: [1, 2]),
            .init(entryID: entry, entityID: unplaced, entryDate: now, parts: []),
        ], asOf: now)
        let pairs = Set(edges.map { Set([$0.a, $0.b]) })
        #expect(pairs.contains([dana, office]) && pairs.contains([maya, wedding]))
        #expect(!pairs.contains([dana, maya]) && !pairs.contains([office, wedding]), "different parts")
        #expect(!edges.contains { $0.a == unplaced || $0.b == unplaced }, "a name placed in no part connects to nothing from this entry")
        #expect(edges.count == 2)

        // An entry with no parts at all connects everything, as it always did.
        let old = UUID()
        let whole = EntityGraph.build(links: [dana, maya, unplaced].map { .init(entryID: old, entityID: $0, entryDate: now) }, asOf: now)
        #expect(whole.count == 3)
    }

    @Test func aNameArrivingTwiceTakesEveryPartItsLinksCarry() {
        let entry = UUID()
        let a = UUID(), b = UUID(), c = UUID()
        let spread = EntityGraph.build(links: [
            .init(entryID: entry, entityID: a, entryDate: now, parts: [0]),
            .init(entryID: entry, entityID: a, entryDate: now, parts: [1]),
            .init(entryID: entry, entityID: b, entryDate: now, parts: [1]),
            .init(entryID: entry, entityID: c, entryDate: now, parts: [2]),
        ], asOf: now)
        #expect(Set(spread.map { Set([$0.a, $0.b]) }) == [[a, b]])
        let halfPlaced = EntityGraph.build(links: [
            .init(entryID: entry, entityID: a, entryDate: now, parts: []),
            .init(entryID: entry, entityID: a, entryDate: now, parts: [2]),
            .init(entryID: entry, entityID: c, entryDate: now, parts: [2]),
        ], asOf: now)
        #expect(halfPlaced.count == 1, "one placed link is enough to connect within its part")
    }

    @Test func partsArePlacedByTheModelsListsAndByWhereTheNameIsWritten() {
        let text = "Morning at the office with Dana. Then I called Maya about the wedding."
        let sections = [
            EntrySection(topic: "Work", tags: ["office"], names: ["Dana"], offset: 0),
            EntrySection(topic: "Family", tags: ["wedding"], names: [], offset: text.distance(from: text.startIndex, to: text.range(of: "Then")!.lowerBound)),
        ]
        let context = EntryParts.Context(sections: sections, text: text)
        #expect(context.parts(surfaces: ["Dana"], isTag: false) == [0])
        #expect(context.parts(surfaces: ["maya"], isTag: false) == [1], "found in the text, though the model didn't list her")
        #expect(context.parts(surfaces: ["wedding"], isTag: true) == [1])
        #expect(context.parts(surfaces: ["Lisbon"], isTag: false) == [], "in no part: connects to nothing from this entry")
        #expect(context.parts(surfaces: ["office"], isTag: true) == [0], "a tag only by the lists")

        let edited = EntryParts.Context(sections: sections, text: nil)
        #expect(edited.parts(surfaces: ["Maya"], isTag: false) == [], "offsets are not trusted once the text changed")
        #expect(edited.parts(surfaces: ["Dana"], isTag: false) == [0])
        #expect(EntryParts.Context(sections: [sections[0]], text: text).parts(surfaces: ["Dana"], isTag: false) == nil, "one part is the whole entry")
    }

    @Test func theMapStopsJoiningNamesFromDifferentPartsOfAnEntry() async throws {
        let harness = try InsightsHarness()
        harness.useGraph = true
        let text = "Morning at the office with Dana went long. Then I called Maya about the wedding."
        let entry = try harness.entry(text)
        entry.entryDate = .now
        let response = #"{"summary":"A day.","primaryMood":"calm","secondaryMoods":[],"lifeAreas":["work"],"tags":[],"mentions":[{"name":"Dana","kind":"person"},{"name":"Maya","kind":"person"},{"name":"Priya","kind":"person"}],"looseEnds":[],"sections":[{"topic":"Work","startsWith":"Morning at the office","names":["Dana"]},{"topic":"Family","startsWith":"Then I called Maya","names":["Maya"]}]}"#
        harness.generator.results = [.success(response)]
        await harness.coordinator.processQueue(context: harness.context)
        #expect(entry.insights?.sections.count == 2)

        let graph = GraphServices(diagnostics: .disabled)
        let split = MindMap.graph(graph.mapSnapshot(in: harness.context), kinds: nil, minimumLinkCount: 1, asOf: .now)
        #expect(split.nodes.count == 3, "Priya, in no part, is still on the map")
        #expect(split.edges.isEmpty, "Dana and Maya were written about apart, and Priya connects to neither")
        let dana = try #require(try harness.context.fetch(FetchDescriptor<Entity>()).first { $0.name == "Dana" })
        #expect(graph.mentionedWith(of: dana.id, in: harness.context).isEmpty, "a person's page reads the same rule")

        // Without parts, the same two names share the entry, as they always did.
        entry.insights?.sections = []
        let wholeGraph = GraphServices(diagnostics: .disabled)
        let whole = MindMap.graph(wholeGraph.mapSnapshot(in: harness.context), kinds: nil, minimumLinkCount: 1, asOf: .now)
        #expect(whole.edges.count == 3)
        #expect(Set(wholeGraph.mentionedWith(of: dana.id, in: harness.context).map(\.name)) == ["Maya", "Priya"])
    }
}

// The placement rules the review of the part-aware map asked to pin down.
@MainActor
struct PartPlacementTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func theOpeningWordsBelongToTheOpeningPart() {
        let text = "Coffee with Dana first. Later at the office with Maya."
        let later = text.distance(from: text.startIndex, to: text.range(of: "Later")!.lowerBound)
        // The opening part's first words weren't found: the text before the next part is its.
        let unplacedOpening = EntryParts.Context(sections: [
            EntrySection(topic: "Coffee", offset: nil),
            EntrySection(topic: "Work", offset: later),
        ], text: text)
        #expect(unplacedOpening.parts(surfaces: ["Dana"], isTag: false) == [0])
        #expect(unplacedOpening.parts(surfaces: ["Maya"], isTag: false) == [1])
        // The first part was found a few words in: the words before it are still its.
        let lateStart = EntryParts.Context(sections: [
            EntrySection(topic: "Coffee", offset: 7),
            EntrySection(topic: "Work", offset: later),
        ], text: text)
        #expect(lateStart.parts(surfaces: ["Coffee"], isTag: false) == [0])
    }

    @Test func everyFormOfANameIsLookedForAtOnce() {
        let text = "Lunch with Liz. Then a walk alone past Elizabeth's old flat."
        let walk = text.distance(from: text.startIndex, to: text.range(of: "Then")!.lowerBound)
        let context = EntryParts.Context(sections: [
            EntrySection(topic: "Lunch", offset: 0),
            EntrySection(topic: "Walk", offset: walk),
        ], text: text)
        #expect(context.parts(surfaces: ["Elizabeth", "Liz"], isTag: false) == [0, 1], "an alias counts like the name")
        #expect(context.parts(surfaces: ["Eliza"], isTag: false) == [], "whole words only")
    }

    @Test func aPartsNamesAreKeptAsWrittenAndAsGrounded() throws {
        let text = "Coffee with Sarah this morning. Then groceries."
        let json: [String: Any] = ["sections": [
            ["topic": "Coffee", "startsWith": "Coffee with Sarah", "names": ["Sarah Kim"]],
            ["topic": "Errands", "startsWith": "Then groceries"],
        ]]
        let sections = InsightsPromptBuilder.parseSections(in: json, text: text, areaNames: [])
        #expect(sections[0].names == ["Sarah Kim", "Sarah"])
        // So the link, whose surface is the grounded "Sarah", is placed even with no text to search.
        #expect(EntryParts.Context(sections: sections, text: nil).parts(surfaces: ["Sarah"], isTag: false) == [0])
    }

    // Cleanup drops fillers, so the cleaned text is shorter and offsets taken from the original
    // would land late in it. The original is what names are looked for in.
    @Test func afterACleanupNamesArePlacedInTheOriginalText() async throws {
        let harness = try InsightsHarness()
        harness.useGraph = true
        harness.autoApply = true
        let original = "um so like um like um the morning was long at work with Dana. Then Maya called."
        let entry = try harness.entry(original, source: .voice)
        entry.entryDate = .now
        let then = original.distance(from: original.startIndex, to: original.range(of: "Then")!.lowerBound)
        let response = #"{"summary":"A day.","primaryMood":"calm","secondaryMoods":[],"lifeAreas":["work"],"tags":[],"mentions":[{"name":"Dana","kind":"person"},{"name":"Maya","kind":"person"}],"looseEnds":[],"cleanedText":"The morning was long at work with Dana. Then Maya called.","sections":[{"topic":"Work","startsWith":"um so like um","names":[]},{"topic":"Call","startsWith":"Then Maya called","names":[]}]}"#
        harness.generator.results = [.success(response)]
        await harness.coordinator.processQueue(context: harness.context)

        #expect(entry.text == "The morning was long at work with Dana. Then Maya called.", "the cleanup was applied")
        #expect(entry.insights?.sections[1].offset == then)
        let insights = try #require(entry.insights)
        #expect(GraphServices.analyzedText(of: entry, insights: insights) == original)
        let map = MindMap.graph(GraphServices(diagnostics: .disabled).mapSnapshot(in: harness.context), kinds: nil, minimumLinkCount: 1, asOf: .now)
        #expect(map.nodes.count == 2)
        #expect(map.edges.isEmpty, "Dana is in the first part and Maya in the second, read in the text the offsets came from")

        // Any other edit leaves nothing to search, and unlisted names are placed nowhere.
        entry.text += " Later, tea."
        #expect(GraphServices.analyzedText(of: entry, insights: insights) == nil)
    }

    @Test func aPairApartInOneEntryAndTogetherInAnotherWeighsOnlyTheSecond() {
        let dana = UUID(), maya = UUID()
        let split = UUID(), plain = UUID()
        let edges = EntityGraph.build(links: [
            .init(entryID: split, entityID: dana, entryDate: now, parts: [0]),
            .init(entryID: split, entityID: maya, entryDate: now, parts: [1]),
            .init(entryID: plain, entityID: dana, entryDate: now),
            .init(entryID: plain, entityID: maya, entryDate: now),
        ], asOf: now)
        #expect(edges.count == 1)
        #expect(abs(edges[0].weight - 1.0) < 0.0001, "only the entry that joined them counts")
    }
}
