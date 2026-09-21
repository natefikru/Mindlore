import Foundation
import SwiftData
import Testing
@testable import Mindlore

struct BioExcerptsTests {
    private func source(_ text: String, day: Double = 1, _ surfaces: String...) -> BioExcerpts.Source {
        .init(text: text, date: Date(timeIntervalSince1970: day * 86_400), surfaces: surfaces)
    }

    @Test func takesOnlyTheSentencesThatNameThem() {
        let sentences = BioExcerpts.sentences(
            in: "It rained all day. Walked with Sarah by the river. Then home.\nsarah's dog barked later.",
            naming: ["Sarah"]
        )
        #expect(sentences == ["Walked with Sarah by the river.", "sarah's dog barked later."])
    }

    @Test func aLongerWordIsNotTheName() {
        #expect(BioExcerpts.sentences(in: "The Sarahs came. Mosarah left.", naming: ["Sarah"]).isEmpty)
    }

    @Test func anySurfaceTheEntryUsedCounts() {
        let sentences = BioExcerpts.sentences(in: "Mom called. Then Sarah K did too.", naming: ["mom", "Sarah K"])
        #expect(sentences == ["Mom called.", "Then Sarah K did too."])
    }

    @Test func newestEightEntriesOnlyNewestFirst() {
        let sources = (1...10).map { source("Day \($0) with Sarah.", day: Double($0), "Sarah") }
        let selection = BioExcerpts.select(from: sources.shuffled())

        #expect(selection.sentences == (3...10).reversed().map { "Day \($0) with Sarah." })
        #expect(selection.entries == 8)
    }

    @Test func staysUnderTheCapWithoutCuttingASentence() {
        let long = "Sarah " + String(repeating: "x", count: 1_000) + "."
        let sources = [
            source(long, day: 3, "Sarah"),
            source(long, day: 2, "Sarah"),
            source("Sarah waved.", day: 1, "Sarah"),
        ]
        let selection = BioExcerpts.select(from: sources)

        #expect(selection.sentences == [long, "Sarah waved."])
        #expect(selection.characters <= BioExcerpts.maxCharacters)
        #expect(selection.entries == 2)
    }

    @Test func anEntryThatNoLongerNamesThemAddsNothing() {
        let selection = BioExcerpts.select(from: [
            source("Went out alone.", day: 2, "Sarah"),
            source("Sarah called.", day: 1, "Sarah"),
        ])
        #expect(selection.sentences == ["Sarah called."])
        #expect(selection.entries == 1)
    }

    @Test func noMatchGivesNothing() {
        #expect(BioExcerpts.select(from: [source("Nobody here.", "Sarah")]).isEmpty)
        #expect(BioExcerpts.select(from: []).isEmpty)
    }

    @Test func aRepeatedSentenceIsSentOnce() {
        let selection = BioExcerpts.select(from: [source("Sarah called.", day: 2, "Sarah"), source("Sarah called.", day: 1, "Sarah")])
        #expect(selection.sentences == ["Sarah called."])
    }
}

@MainActor
final class BioHarness {
    final class Switches {
        var automatic = true
        var resolveFailure: AIJobFailure?
    }

    let graph: GraphHarness
    let generator = FakeTextGenerator()
    let switches = Switches()
    let services: GraphServices
    var context: ModelContext { graph.context }

    init(log: DiagnosticsLog = .disabled) throws {
        graph = try GraphHarness()
        let generator = generator
        let switches = switches
        services = GraphServices(
            diagnostics: log,
            resolveText: {
                if let failure = switches.resolveFailure { return .failure(failure) }
                return .success(.init(generator: generator, model: "m", label: "openai:m"))
            },
            automaticBiosUsable: { switches.automatic }
        )
    }

    // An indexed entry whose insights were made from exactly this text.
    @discardableResult
    func entry(_ text: String, day: Double = 1, mentions: [(String, MentionKind)] = [], tags: [String] = []) throws -> Entry {
        let entry = try graph.entry(text, entryDate: Date(timeIntervalSince1970: day * 86_400), tags: tags, mentions: mentions)
        entry.insights?.sourceTextHash = TextHash.of(text)
        entry.updatedAt = Date(timeIntervalSince1970: 42)
        try context.save()
        graph.indexer.sweep(in: context)
        return entry
    }

    func entity(_ name: String) throws -> Entity {
        try graph.entity(name)
    }

    func open(_ entity: Entity) async {
        services.pageOpened(entity.id, in: context)
        await services.draftFinished(entity.id)
    }

    func draft(_ entity: Entity) async {
        services.draftBio(entity.id, in: context)
        await services.draftFinished(entity.id)
    }
}

@MainActor
struct EntityBioDrafterTests {
    let harness: BioHarness

    init() throws {
        harness = try BioHarness()
    }

    private func sarah(_ text: String = "It rained. Walked with Sarah by the river.") throws -> Entity {
        try harness.entry(text, mentions: [("Sarah", .person)])
        return try harness.entity("Sarah")
    }

    @Test func aDraftLandsWithWhatWasSent() async throws {
        let sarah = try sarah()
        harness.generator.results = [.success(#"{"bio":"  Sarah is a friend I walk with. "}"#)]
        let revision = harness.services.revision

        await harness.open(sarah)

        #expect(sarah.bio == "Sarah is a friend I walk with.")
        #expect(sarah.bioWasGenerated)
        #expect(!sarah.bioEditedByUser)
        #expect(sarah.bioDraftedAt != nil)
        #expect(sarah.bioModelUsed == "m")
        #expect(sarah.bioSourceEntries == 1)
        #expect(sarah.bioSourceCharacters == "Walked with Sarah by the river.".count)
        #expect(!sarah.confirmedByUser, "a draft is not the user's edit")
        #expect(harness.services.revision > revision)
        #expect(harness.services.drafting.isEmpty)

        let request = try #require(harness.generator.requests.first)
        #expect(request.schemaName == "entity_bio")
        #expect(request.system.contains("Sarah"))
        #expect(request.user == "Name: Sarah\nKind: person\nExcerpts:\n- Walked with Sarah by the river.")
    }

    @Test func draftingNeverStampsAnEntry() async throws {
        let entry = try harness.entry("Sarah called.", mentions: [("Sarah", .person)])
        harness.generator.results = [.success(#"{"bio":"A friend."}"#)]

        await harness.open(try harness.entity("Sarah"))

        #expect(entry.updatedAt == Date(timeIntervalSince1970: 42))
    }

    @Test func aNullAnswerIsRecordedAndNotAskedAgain() async throws {
        let sarah = try sarah()
        harness.generator.results = [.success(#"{"bio":null}"#)]

        await harness.open(sarah)
        await harness.open(sarah)

        #expect(sarah.bio == nil)
        #expect(sarah.bioWasGenerated)
        #expect(sarah.bioDraftedAt != nil)
        #expect(harness.generator.requests.count == 1)
    }

    @Test func nothingToQuoteSendsNothingAndRecordsNothing() async throws {
        let sarah = try sarah("A day out, nobody named.")

        await harness.open(sarah)

        #expect(harness.generator.requests.isEmpty)
        #expect(sarah.bioDraftedAt == nil)
        #expect(harness.services.withoutExcerpts.contains(sarah.id))
    }

    // The provider has only ever seen finished, current text, up to the insights limit.
    @Test func quotesOnlyTextTheProviderAlreadyHas() throws {
        let draft = try harness.entry("Sarah draft.", day: 1, mentions: [("Sarah", .person)])
        draft.isDraft = true
        let review = try harness.entry("Sarah review.", day: 2, mentions: [("Sarah", .person)])
        review.textReviewPending = true
        let edited = try harness.entry("Sarah old.", day: 3, mentions: [("Sarah", .person)])
        edited.text = "Sarah new, never analyzed."
        let filler = String(repeating: "word ", count: InsightsPromptBuilder.maxInputCharacters / 5)
        try harness.entry(filler + "Sarah beyond the limit.", day: 4, mentions: [("Sarah", .person)])
        let photo = try harness.entry("Sarah on a page.", day: 6, mentions: [("Sarah", .person)])
        photo.sourceRaw = EntrySource.photo.rawValue
        photo.pagesConfirmed = false
        try harness.entry("Sarah sent.", day: 5, mentions: [("Sarah", .person)])

        let selection = harness.services.drafter.excerpts(for: try harness.entity("Sarah").id, in: harness.context)

        #expect(selection.sentences == ["Sarah sent."])
    }

    // 5c.1: a corrected name's excerpt is found by what the entry actually wrote, not by the
    // model's correction, which the entry's own text may not contain at all.
    @Test func writtenSurfaceIsSearchedInsteadOfTheCorrectedSurface() throws {
        let entry = try harness.entry("dinner with Lewis last night.", mentions: [("Luis", .person)])
        let link = try #require(harness.graph.links(of: entry).first)
        link.writtenSurface = "Lewis"
        try harness.context.save()

        let selection = harness.services.drafter.excerpts(for: try harness.entity("Luis").id, in: harness.context)

        #expect(selection.sentences == ["dinner with Lewis last night."])
    }

    @Test func cleanedUpTextStillCounts() throws {
        let entry = try harness.entry("sarah um called.", mentions: [("Sarah", .person)])
        entry.text = "Sarah called."
        entry.cleanupAppliedHash = TextHash.of(entry.text)

        let selection = harness.services.drafter.excerpts(for: try harness.entity("Sarah").id, in: harness.context)
        #expect(selection.sentences == ["Sarah called."])
    }

    @Test func theUsersBioIsNeverReplaced() async throws {
        let sarah = try sarah()
        harness.services.editor.setBio("My sister.", on: sarah)

        await harness.open(sarah)
        await harness.draft(sarah)

        #expect(harness.generator.requests.isEmpty)
        #expect(sarah.bio == "My sister.")
    }

    @Test func aBioTypedWhileTheRequestWasOutWins() async throws {
        let sarah = try sarah()
        harness.generator.suspends = true

        harness.services.pageOpened(sarah.id, in: harness.context)
        await harness.generator.waitForRequest(number: 1)
        #expect(harness.services.drafting.contains(sarah.id))
        harness.services.editor.setBio("Mine.", on: sarah)
        harness.generator.answer(.success(#"{"bio":"AI's."}"#))
        await harness.services.draftFinished(sarah.id)

        #expect(sarah.bio == "Mine.")
        #expect(!sarah.bioWasGenerated)
        #expect(sarah.bioDraftedAt == nil)
    }

    @Test func aClearedBioIsOnlyRedraftedWhenAsked() async throws {
        let sarah = try sarah()
        harness.services.editor.setBio("   ", on: sarah)
        #expect(sarah.bio == nil)
        #expect(sarah.bioEditedByUser)

        await harness.open(sarah)
        #expect(harness.generator.requests.isEmpty)

        harness.generator.results = [.success(#"{"bio":"A friend."}"#)]
        await harness.draft(sarah)
        #expect(sarah.bio == "A friend.")
        #expect(!sarah.bioEditedByUser)
    }

    @Test func anEntityMergedWhileTheRequestWasOutGetsNothing() async throws {
        let sarah = try sarah()
        try harness.entry("Tom again.", mentions: [("Tom", .person)])
        let kim = try harness.entity("Tom")
        harness.generator.suspends = true

        harness.services.pageOpened(sarah.id, in: harness.context)
        await harness.generator.waitForRequest(number: 1)
        #expect(harness.services.editor.merge(sarah, into: kim, in: harness.context) == .merged)
        harness.generator.answer(.success(#"{"bio":"A friend."}"#))
        await harness.services.draftFinished(sarah.id)

        #expect(sarah.bio == nil)
        #expect(kim.bio == nil)
    }

    @Test func anEntityPrunedWhileTheRequestWasOutGetsNothing() async throws {
        let entry = try harness.entry("Sarah called.", mentions: [("Sarah", .person)])
        let id = try harness.entity("Sarah").id
        harness.generator.suspends = true

        harness.services.pageOpened(id, in: harness.context)
        await harness.generator.waitForRequest(number: 1)
        Entry.delete(entry, in: harness.context)
        try harness.context.save()
        harness.services.entriesDeleted(in: harness.context)
        try harness.context.save()
        harness.generator.answer(.success(#"{"bio":"A friend."}"#))
        await harness.services.draftFinished(id)

        #expect(try harness.graph.entities().isEmpty)
    }

    // A draft doesn't make the entity the user's: it goes with its last mention.
    @Test func anUnconfirmedEntityIsPrunedWithItsDraftedBio() async throws {
        let entry = try harness.entry("Sarah called.", mentions: [("Sarah", .person)])
        harness.generator.results = [.success(#"{"bio":"A friend."}"#)]
        await harness.open(try harness.entity("Sarah"))

        Entry.delete(entry, in: harness.context)
        try harness.context.save()
        harness.services.entriesDeleted(in: harness.context)
        try harness.context.save()

        #expect(try harness.graph.entities().isEmpty)
    }

    @Test func aFailureRecordsNothingAndTheNextOpenTriesAgain() async throws {
        let sarah = try sarah()
        harness.generator.results = [.failure(AIError.serverError(status: 500)), .success(#"{"bio":"A friend."}"#)]

        await harness.open(sarah)
        #expect(harness.services.bioFailures[sarah.id] == AIJobFailure(.serverError(status: 500)))
        #expect(sarah.bioDraftedAt == nil)
        #expect(sarah.bio == nil)

        await harness.open(sarah)
        #expect(harness.services.bioFailures[sarah.id] == nil)
        #expect(sarah.bio == "A friend.")
    }

    @Test func anUnreadableAnswerIsAFailure() async throws {
        let sarah = try sarah()
        harness.generator.results = [.success("not json")]

        await harness.open(sarah)

        #expect(harness.services.bioFailures[sarah.id] == AIJobFailure(.invalidResponse))
        #expect(sarah.bioDraftedAt == nil)
    }

    @Test func aCancelledDraftRecordsNothing() async throws {
        let file = DiagnosticsFile()
        let harness = try BioHarness(log: DiagnosticsLog(fileURL: file.url))
        try harness.entry("Walked with Sarah.", mentions: [("Sarah", .person)])
        let sarah = try harness.entity("Sarah")
        harness.generator.suspends = true

        harness.services.pageOpened(sarah.id, in: harness.context)
        await harness.generator.waitForRequest(number: 1)
        harness.services.cancelDrafts()
        harness.generator.answer(.success(#"{"bio":"A friend."}"#))
        await harness.services.draftFinished(sarah.id)

        #expect(sarah.bio == nil)
        #expect(sarah.bioDraftedAt == nil)
        #expect(harness.services.bioFailures.isEmpty)
        #expect(harness.services.drafting.isEmpty)
        #expect(!file.contents().contains("graph.bio"))
    }

    @Test func aPermanentFailureWaitsForTryAgain() async throws {
        let sarah = try sarah()
        harness.generator.results = [.failure(AIError.quotaExceeded), .success(#"{"bio":"A friend."}"#)]

        await harness.open(sarah)
        await harness.open(sarah)
        #expect(harness.generator.requests.count == 1)

        await harness.draft(sarah)
        #expect(sarah.bio == "A friend.")
    }

    // A merged entity's bio is its undo record: nothing drafts it, and asking changes nothing.
    @Test func aMergedEntityIsNeverDrafted() async throws {
        let sarah = try sarah()
        try harness.entry("Tom called.", mentions: [("Tom", .person)])
        harness.services.editor.setBio(nil, on: sarah)
        harness.services.merge(sarah.id, into: try harness.entity("Tom").id, in: harness.context)

        await harness.draft(sarah)

        #expect(harness.generator.requests.isEmpty)
        #expect(sarah.bioEditedByUser)
    }

    @Test func aClearedBioKeepsItsFlagWhenNoRequestCanGo() async throws {
        let sarah = try sarah()
        harness.services.editor.setBio(nil, on: sarah)
        harness.switches.resolveFailure = AIJobFailure(.missingKey)

        await harness.draft(sarah)

        #expect(sarah.bioEditedByUser)
        #expect(harness.services.bioFailures[sarah.id] == AIJobFailure(.missingKey))
    }

    @Test func twoOpensSendOneRequest() async throws {
        let sarah = try sarah()
        harness.generator.suspends = true

        harness.services.pageOpened(sarah.id, in: harness.context)
        harness.services.pageOpened(sarah.id, in: harness.context)
        harness.services.draftBio(sarah.id, in: harness.context)
        await harness.generator.waitForRequest(number: 1)
        harness.generator.answer(.success(#"{"bio":"A friend."}"#))
        await harness.services.draftFinished(sarah.id)

        #expect(harness.generator.requests.count == 1)
        #expect(sarah.bio == "A friend.")
    }

    @Test func tagsAreDraftedOnlyWhenAsked() async throws {
        try harness.entry("By the river again.", tags: ["river"])
        let river = try harness.entity("river")

        await harness.open(river)
        #expect(harness.generator.requests.isEmpty)

        harness.generator.results = [.success(#"{"bio":"Where I walk."}"#)]
        await harness.draft(river)
        #expect(river.bio == "Where I walk.")
    }

    @Test func automaticInsightsOffMeansNoAutomaticDraft() async throws {
        let sarah = try sarah()
        harness.switches.automatic = false

        await harness.open(sarah)

        #expect(harness.generator.requests.isEmpty)
    }

    @Test func noUsableAccountFailsWithoutARequest() async throws {
        let sarah = try sarah()
        harness.switches.resolveFailure = AIJobFailure(.missingKey)

        await harness.draft(sarah)

        #expect(harness.generator.requests.isEmpty)
        #expect(harness.services.bioFailures[sarah.id] == AIJobFailure(.missingKey))
        #expect(harness.services.drafting.isEmpty)
    }

    // Only the name, its kind, and the quoted sentences go out.
    @Test func theRequestCarriesNoBioAliasOrOtherEntity() async throws {
        try harness.entry("Walked with Sarah. Tom stayed home.", mentions: [("Sarah", .person), ("Tom", .person)])
        let sarah = try harness.entity("Sarah")
        #expect(harness.services.editor.addAlias("ALIAS-QX", to: sarah, in: harness.context) == .applied)
        sarah.bio = "OLD-BIO-QX"
        sarah.bioWasGenerated = true
        harness.generator.results = [.success(#"{"bio":"A friend."}"#)]

        await harness.draft(sarah)

        let request = try #require(harness.generator.requests.first)
        for text in [request.system, request.user] {
            #expect(!text.contains("OLD-BIO-QX"))
            #expect(!text.contains("ALIAS-QX"))
            #expect(!text.contains("Tom"))
        }
        #expect(sarah.bio == "A friend.")
    }

    @Test func theUITestStubAnswersWithTheRequestedName() async throws {
        let generator = OpenAICompatibleTextGenerator(
            baseURL: URL(string: "https://api.openai.com/v1")!,
            apiKey: UITestingHTTPClient.validKey,
            http: UITestingHTTPClient()
        )
        var excerpts = BioExcerpts.Selection()
        excerpts.sentences = ["Walked with Mara."]
        let request = try #require(EntityBioDrafter.request(name: "Mara", kind: .person, excerpts: excerpts, model: "m"))

        let result = try await generator.generate(request)

        #expect(result.text.contains("Mara is a friend"))
    }
}

@MainActor
struct BioDiagnosticsPrivacyTests {
    @Test func draftingNeverLogsNamesExcerptsOrBios() async throws {
        let file = DiagnosticsFile()
        let harness = try BioHarness(log: DiagnosticsLog(fileURL: file.url))
        let sentinel = DiagnosticsPrivacyTests.sentinel
        try harness.entry("Walked with \(sentinel) today.", mentions: [(sentinel, .person)])
        let entity = try harness.entity(sentinel)
        harness.generator.results = [
            .failure(AIError.badRequest(code: "invalid_value")),
            .success(#"{"bio":"\#(sentinel) is a friend."}"#),
        ]

        await harness.draft(entity)
        await harness.draft(entity)

        #expect(entity.bio == "\(sentinel) is a friend.")
        let contents = file.contents()
        #expect(contents.contains("graph.bioFailed"))
        #expect(contents.contains("graph.bioDrafted"))
        #expect(contents.contains(sentinel) == false)
    }
}
