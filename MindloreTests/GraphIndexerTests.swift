import Foundation
import SwiftData
import Testing
@testable import Mindlore

// The resolver decides what a value means before anything is written, so its rules are
// tested on their own, without a store.
struct EntityResolverTests {
    private func candidate(
        _ key: String,
        _ kind: EntityKind,
        id: UUID = UUID(),
        aliases: [String] = [],
        hidden: Bool = false,
        kindEditedByUser: Bool = false,
        linkCount: Int = 0,
        confirmed: Bool = false
    ) -> EntityResolver.Candidate {
        .init(
            id: id, key: key, kind: kind, aliasKeys: aliases, hidden: hidden,
            kindEditedByUser: kindEditedByUser, linkCount: linkCount, confirmedByUser: confirmed
        )
    }

    private func value(_ surface: String, _ kind: EntityKind) -> EntityResolver.Value {
        .init(surface: surface, kind: kind)
    }

    @Test func anExactKeyMatchLinks() {
        let sarah = candidate("sarah kim", .person)
        #expect(EntityResolver.resolve(value("Sarah Kim", .person), among: [sarah])
            == .existing(id: sarah.id, inferred: false, upgradeKind: nil))
        // Same person, written with different case and a possessive.
        #expect(EntityResolver.resolve(value("SARAH KIM's", .person), among: [sarah])
            == .existing(id: sarah.id, inferred: false, upgradeKind: nil))
    }

    @Test func anAliasMatchLinks() {
        let sarah = candidate("sarah kim", .person, aliases: ["my sister", "sarah k"])
        #expect(EntityResolver.resolve(value("my sister", .person), among: [sarah])
            == .existing(id: sarah.id, inferred: false, upgradeKind: nil))
    }

    // Hiding something takes it out of the lists, not out of resolution: if it stopped
    // resolving, the next mention would create it again under a new id and it would be back.
    @Test func aHiddenEntityStillTakesItsExactMatches() {
        let monday = candidate("monday", .event, hidden: true)
        #expect(EntityResolver.resolve(value("Monday", .event), among: [monday])
            == .existing(id: monday.id, inferred: false, upgradeKind: nil))
    }

    @Test func aLoneFirstNameJoinsTheOnlyPersonItCouldBe() {
        let sarah = candidate("sarah kim", .person)
        #expect(EntityResolver.resolve(value("Sarah", .person), among: [sarah])
            == .existing(id: sarah.id, inferred: true, upgradeKind: nil))
    }

    @Test func aLoneFirstNameWithTwoCandidatesStaysItsOwnEntity() {
        let kim = candidate("sarah kim", .person)
        let lee = candidate("sarah lee", .person)
        #expect(EntityResolver.resolve(value("Sarah", .person), among: [kim, lee])
            == .create(key: "sarah", kind: .person))
    }

    // The guess is only worth making when the user can see the result. A mention that
    // disappeared into a hidden entity would look like nothing happened.
    @Test func theFirstNameGuessIgnoresHiddenPeople() {
        let hidden = candidate("sarah kim", .person, hidden: true)
        #expect(EntityResolver.resolve(value("Sarah", .person), among: [hidden])
            == .create(key: "sarah", kind: .person))
    }

    @Test func theFirstNameGuessIsPeopleOnly() {
        let park = candidate("golden gate park", .place)
        #expect(EntityResolver.resolve(value("Golden", .place), among: [park])
            == .create(key: "golden", kind: .place))
    }

    @Test func theFirstNameGuessMatchesAnAliasToo() {
        let sarah = candidate("s kim", .person, aliases: ["sarah kim"])
        #expect(EntityResolver.resolve(value("Sarah", .person), among: [sarah])
            == .existing(id: sarah.id, inferred: true, upgradeKind: nil))
    }

    @Test func aDifferentKindMakesADifferentEntity() {
        let paris = candidate("paris", .place)
        #expect(EntityResolver.resolve(value("Paris", .person), among: [paris])
            == .create(key: "paris", kind: .person))
    }

    // A mention the model typed `other` should stop being `other` once something says what
    // it is, as long as the user hasn't set the kind themselves.
    @Test func anUntouchedOtherIsUpgradedByALaterMention() {
        let vague = candidate("acme", .other)
        #expect(EntityResolver.resolve(value("Acme", .organization), among: [vague])
            == .existing(id: vague.id, inferred: false, upgradeKind: .organization))
    }

    @Test func aKindTheUserPickedIsNeverUpgraded() {
        let chosen = candidate("acme", .other, kindEditedByUser: true)
        #expect(EntityResolver.resolve(value("Acme", .organization), among: [chosen])
            == .create(key: "acme", kind: .organization))
    }

    @Test func aValueTypedOtherJoinsWhateverIsAlreadyThere() {
        let acme = candidate("acme", .organization)
        #expect(EntityResolver.resolve(value("Acme", .other), among: [acme])
            == .existing(id: acme.id, inferred: false, upgradeKind: nil))
    }

    @Test func aTagAndAThemeAreSeparateEntities() {
        let tag = candidate("career anxiety", .tag)
        #expect(EntityResolver.resolve(value("career anxiety", .theme), among: [tag])
            == .create(key: "career anxiety", kind: .theme))
    }

    @Test func nothingToKeyOnIsSkipped() {
        #expect(EntityResolver.resolve(value("...", .tag), among: []) == .skip)
        #expect(EntityResolver.resolve(value("   ", .person), among: []) == .skip)
    }

    // Two live entities can share a key after the user forces a rename through. The one they
    // confirmed wins, then the one the journal actually uses.
    @Test func anAmbiguousExactMatchPrefersTheConfirmedThenTheBusiest() {
        let confirmed = candidate("sarah kim", .person, linkCount: 1, confirmed: true)
        let busier = candidate("sarah kim", .person, linkCount: 40)
        #expect(EntityResolver.resolve(value("Sarah Kim", .person), among: [busier, confirmed])
            == .existing(id: confirmed.id, inferred: false, upgradeKind: nil))
        #expect(EntityResolver.isAmbiguous(value("Sarah Kim", .person), among: [busier, confirmed]))

        let quiet = candidate("sarah kim", .person, linkCount: 2)
        #expect(EntityResolver.resolve(value("Sarah Kim", .person), among: [quiet, busier])
            == .existing(id: busier.id, inferred: false, upgradeKind: nil))
    }

    @Test func oneMatchIsNotAmbiguous() {
        let sarah = candidate("sarah kim", .person)
        #expect(!EntityResolver.isAmbiguous(value("Sarah Kim", .person), among: [sarah]))
        #expect(!EntityResolver.isAmbiguous(value("Nobody", .person), among: [sarah]))
    }

    // 5c.4: two confirmed (or two unconfirmed) entities sharing a key is a real tie, and the
    // indexer records it instead of trusting `bestExact`'s linkCount/id tie-break silently.
    @Test func twoConfirmedCandidatesAreTied() {
        let a = candidate("lewis", .person, confirmed: true)
        let b = candidate("lewis", .person, confirmed: true)
        #expect(Set(EntityResolver.tied(value("Lewis", .person), among: [a, b])) == [a.id, b.id])
    }

    @Test func twoUnconfirmedCandidatesAreTiedToo() {
        let a = candidate("lewis", .person)
        let b = candidate("lewis", .person)
        #expect(Set(EntityResolver.tied(value("Lewis", .person), among: [a, b])) == [a.id, b.id])
    }

    @Test func oneConfirmedAmongUnconfirmedIsNotTied() {
        let confirmed = candidate("lewis", .person, confirmed: true)
        let unconfirmed = candidate("lewis", .person)
        #expect(EntityResolver.tied(value("Lewis", .person), among: [confirmed, unconfirmed]).isEmpty)
    }

    @Test func aSingleMatchIsNotTied() {
        let sarah = candidate("sarah kim", .person)
        #expect(EntityResolver.tied(value("Sarah Kim", .person), among: [sarah]).isEmpty)
    }
}

@MainActor
final class GraphHarness {
    let container: ModelContainer
    let indexer = GraphIndexer(diagnostics: .disabled)
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    @discardableResult
    func entry(
        _ text: String = "an entry",
        entryDate: Date = Date(timeIntervalSince1970: 5_000),
        tags: [String] = [],
        themes: [String] = [],
        mentions: [(String, MentionKind)] = [],
        generatedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) throws -> Entry {
        let entry = Entry(text: text)
        entry.entryDate = entryDate
        context.insert(entry)
        let insights = EntryInsights(generatedAt: generatedAt, modelUsed: "test")
        context.insert(insights)
        insights.entry = entry
        insights.tags = tags
        insights.themes = themes
        insights.mentions = mentions.map { Mention(name: $0.0, kindRaw: $0.1.rawValue) }
        try context.save()
        return entry
    }

    func entities() throws -> [Entity] {
        try context.fetch(FetchDescriptor<Entity>(sortBy: [SortDescriptor(\.name)]))
    }

    func entity(_ name: String) throws -> Entity {
        try #require(try entities().first { $0.name == name })
    }

    func links(of entry: Entry) -> [EntityLink] {
        indexer.allLinks(in: context).filter { $0.entryID == entry.id }
    }
}

@MainActor
struct GraphIndexerTests {
    // Stored, so the container stays alive for the whole test. A harness in a local can be
    // released as soon as the test stops mentioning it, and a deallocated container turns
    // live objects into empty relationships part-way through the assertions.
    let harness: GraphHarness

    init() throws {
        harness = try GraphHarness()
    }

    @Test func indexingBuildsAnEntityPerValue() throws {
        let entry = try harness.entry(
            tags: ["nature", "family"],
            themes: ["walking"],
            mentions: [("Sarah", .person), ("the river", .place)]
        )

        harness.indexer.index(entry, in: harness.context)
        try harness.context.save()

        #expect(harness.links(of: entry).count == 5)
        let entities = try harness.entities()
        #expect(entities.map(\.name).sorted() == ["Sarah", "family", "nature", "the river", "walking"])
        #expect(try harness.entity("Sarah").kind == .person)
        #expect(try harness.entity("the river").kind == .place)
        #expect(try harness.entity("nature").kind == .tag)
        #expect(try harness.entity("walking").kind == .theme)
        // The key is normalized; the name keeps what the model wrote.
        #expect(try harness.entity("the river").key == "the river")
        #expect(entry.graphIndexedAt == entry.insights?.generatedAt)
    }

    // 5c.1: what InsightsPromptBuilder.parse records on a corrected Mention reaches the link.
    @Test func indexingCopiesWrittenSurfaceFromTheMention() throws {
        let entry = try harness.entry("dinner with Lewis last night")
        entry.insights?.mentions = [Mention(name: "Luis", kindRaw: MentionKind.person.rawValue, writtenSurface: "Lewis")]
        try harness.context.save()

        harness.indexer.index(entry, in: harness.context)
        try harness.context.save()

        let link = try #require(harness.links(of: entry).first)
        #expect(link.surface == "Luis")
        #expect(link.writtenSurface == "Lewis")
    }

    @Test func indexingLeavesWrittenSurfaceNilWhenTheMentionHasNone() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])

        harness.indexer.index(entry, in: harness.context)
        try harness.context.save()

        let link = try #require(harness.links(of: entry).first)
        #expect(link.writtenSurface == nil)
    }

    // 5c.4: two live, unconfirmed entities sharing a key (the shape a forced rename or alias
    // leaves behind) tie instead of silently picking one; the link still resolves to something
    // (today's bestExact pick) so nothing breaks while it waits in Review.
    @Test func indexingAValueThatTiesMarksTheLinkUnsure() throws {
        let a = Entity(name: "Lewis", key: "lewis", kind: .person)
        let b = Entity(name: "Lewis", key: "lewis", kind: .person)
        harness.context.insert(a)
        harness.context.insert(b)
        try harness.context.save()

        let entry = try harness.entry(mentions: [("Lewis", .person)])
        harness.indexer.index(entry, in: harness.context)
        try harness.context.save()

        let link = try #require(harness.links(of: entry).first)
        #expect(Set(link.unsureAmong) == [a.id, b.id])
        #expect(link.entityID == a.id || link.entityID == b.id, "still resolves to something while it waits in Review")
    }

    @Test func indexingAValueThatDoesNotTieLeavesUnsureAmongEmpty() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.index(entry, in: harness.context)
        try harness.context.save()

        let link = try #require(harness.links(of: entry).first)
        #expect(link.unsureAmong.isEmpty)
    }

    @Test func twoEntriesNamingTheSameThingShareOneEntity() throws {
        let monday = try harness.entry(mentions: [("Sarah Kim", .person)])
        let friday = try harness.entry(mentions: [("sarah kim", .person)])

        harness.indexer.index(monday, in: harness.context)
        harness.indexer.index(friday, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        let entities = try harness.entities()
        #expect(entities.count == 1)
        #expect(entities[0].linkCount == 2)
    }

    // Running AI again must not pile a second copy of everything on the entry.
    @Test func reindexingIsIdempotent() throws {
        let entry = try harness.entry(tags: ["nature"], mentions: [("Sarah", .person)])

        harness.indexer.index(entry, in: harness.context)
        try harness.context.save()
        harness.indexer.index(entry, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        #expect(harness.links(of: entry).count == 2)
        #expect(try harness.entities().count == 2)
        #expect(try harness.entity("Sarah").linkCount == 1)
    }

    // The entity has to come back with the same id, or a pushed entity page and every
    // notSameAs pointing at it would break.
    @Test func reindexingTheOnlyEntryForAnEntityKeepsItsID() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.index(entry, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()
        let id = try harness.entity("Sarah").id

        harness.indexer.index(entry, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        #expect(try harness.entity("Sarah").id == id)
    }

    @Test func regeneratedInsightsDropTheValuesThatWentAway() throws {
        let entry = try harness.entry(tags: ["nature", "family"])
        harness.indexer.index(entry, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        entry.insights?.tags = ["nature"]
        entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)
        harness.indexer.index(entry, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        #expect(harness.links(of: entry).map(\.surface) == ["nature"])
        // "family" is nobody's now and nothing the user touched, so it goes.
        #expect(try harness.entities().map(\.name) == ["nature"])
    }

    @Test func aLinkTheUserRepointedSurvivesReindexing() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.index(entry, in: harness.context)
        try harness.context.save()

        let someoneElse = Entity(name: "Sarah Lee", key: "sarah lee", kind: .person)
        someoneElse.confirmedByUser = true
        harness.context.insert(someoneElse)
        // Saved before the link is pointed at it: an existing link silently refuses an entity
        // the store has not seen yet.
        try harness.context.save()
        let link = try #require(harness.links(of: entry).first)
        link.repoint(to: someoneElse)
        try harness.context.save()

        harness.indexer.index(entry, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        // One link, still the user's, still pointing where they put it. No AI link beside it.
        let links = harness.links(of: entry)
        try #require(links.count == 1)
        #expect(links[0].source == .user)
        #expect(links[0].entityID == someoneElse.id)
    }

    @Test func removingInsightsRemovesTheLinksAndTheStamp() throws {
        let entry = try harness.entry(tags: ["nature"])
        harness.indexer.index(entry, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        entry.removeInsights(in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        #expect(harness.links(of: entry).isEmpty)
        #expect(entry.graphIndexedAt == nil)
        #expect(try harness.entities().isEmpty)
    }

    @Test func deletingAnEntryPrunesWhatNobodyElseUses() throws {
        let entry = try harness.entry(tags: ["nature"], mentions: [("Sarah", .person)])
        harness.indexer.index(entry, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()
        // The user made this one theirs, so it outlives its last link.
        let sarah = try harness.entity("Sarah")
        sarah.confirmedByUser = true
        try harness.context.save()

        Entry.delete(entry, in: harness.context)
        try harness.context.save()
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        #expect(try harness.entities().map(\.name) == ["Sarah"])
        #expect(try harness.entity("Sarah").linkCount == 0)
        #expect(try harness.entity("Sarah").lastLinkedAt == nil)
    }

    @Test func aMergeLoserSurvivesTheRecountThatFollowsIt() throws {
        try harness.entry(mentions: [("Sarah", .person)])
        try harness.entry(mentions: [("Sarah Kim", .person)])
        harness.indexer.sweep(in: harness.context)

        GraphEditor(diagnostics: .disabled).merge(try harness.entity("Sarah"), into: try harness.entity("Sarah Kim"), in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        #expect(try harness.entities().count == 2)
        #expect(try harness.entity("Sarah").isMerged)
        #expect(try harness.entity("Sarah Kim").linkCount == 2)
    }

    @Test func countersFollowTheEntryDateNotTheIndexingOrder() throws {
        let recent = try harness.entry(entryDate: Date(timeIntervalSince1970: 9_000), tags: ["nature"])
        let old = try harness.entry(entryDate: Date(timeIntervalSince1970: 1_000), tags: ["nature"])

        harness.indexer.index(recent, in: harness.context)
        harness.indexer.index(old, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        let nature = try harness.entity("nature")
        #expect(nature.linkCount == 2)
        #expect(nature.firstLinkedAt == Date(timeIntervalSince1970: 1_000))
        #expect(nature.lastLinkedAt == Date(timeIntervalSince1970: 9_000))
    }

    @Test func theSweepDeletesLinksWhoseEntityIsGone() throws {
        let entry = try harness.entry(tags: ["nature"])
        harness.indexer.index(entry, in: harness.context)
        try harness.context.save()

        harness.context.delete(try harness.entity("nature"))
        try harness.context.save()
        // Counting leaves it alone; the sweep is what clears it, against saved state.
        harness.indexer.recount(in: harness.context)
        #expect(try harness.context.fetchCount(FetchDescriptor<EntityLink>()) == 1)

        entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)
        harness.indexer.sweep(in: harness.context)

        #expect(harness.links(of: entry).count == 1, "the entry was reindexed, so it has a fresh link")
        #expect(try harness.context.fetchCount(FetchDescriptor<EntityLink>()) == 1)
    }

    @Test func theSameValueTwiceInOneEntryLinksOnce() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person), ("sarah", .person), ("Sarah's", .person)])

        harness.indexer.index(entry, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.save()

        #expect(harness.links(of: entry).count == 1)
        #expect(try harness.entities().count == 1)
    }

    // MARK: - Sweep

    @Test func theSweepIndexesEveryEntryThatHasNeverBeenIndexed() throws {
        for _ in 0..<3 { try harness.entry(tags: ["nature"]) }

        let indexed = harness.indexer.sweep(in: harness.context)

        #expect(indexed == 3)
        #expect(try harness.entities().map(\.name) == ["nature"])
        #expect(try harness.entity("nature").linkCount == 3)
    }

    @Test func theSweepSkipsWhatIsAlreadyCurrentAndPicksUpWhatChanged() throws {
        let entry = try harness.entry(tags: ["nature"])
        #expect(harness.indexer.sweep(in: harness.context) == 1)
        #expect(harness.indexer.sweep(in: harness.context) == 0)

        entry.insights?.tags = ["family"]
        entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)

        #expect(harness.indexer.sweep(in: harness.context) == 1)
        #expect(try harness.entities().map(\.name) == ["family"])
    }

    @Test func anEntryWithNoInsightsIsNotSwept() throws {
        let bare = Entry(text: "no insights yet")
        harness.context.insert(bare)
        try harness.context.save()

        #expect(harness.indexer.sweep(in: harness.context) == 0)
        #expect(try harness.entities().isEmpty)
    }

    // The backfill runs over the user's whole journal. If it stamped the entries, every one of
    // them would look edited today.
    @Test func theSweepNeverStampsAnEntry() throws {
        var before: [UUID: Date] = [:]
        for index in 0..<3 {
            let entry = try harness.entry(tags: ["nature"], mentions: [("Sarah", .person)])
            entry.updatedAt = Date(timeIntervalSince1970: Double(100 + index))
            before[entry.id] = entry.updatedAt
        }
        try harness.context.save()

        #expect(harness.indexer.sweep(in: harness.context) == 3)

        for entry in try harness.context.fetch(FetchDescriptor<Entry>()) {
            #expect(entry.updatedAt == before[entry.id])
        }
    }

    // Indexing on the insights path rides in the coordinator's save, which excludes the entry
    // for exactly this reason.
    @Test func indexingOneEntryInsideItsOwnSaveNeverStampsIt() throws {
        let entry = try harness.entry(tags: ["nature"])
        entry.updatedAt = Date(timeIntervalSince1970: 100)
        try harness.context.save()

        harness.indexer.index(entry, in: harness.context)
        harness.indexer.recount(in: harness.context)
        try harness.context.saveStampingEntries(except: [entry.persistentModelID])

        #expect(entry.updatedAt == Date(timeIntervalSince1970: 100))
        #expect(harness.links(of: entry).count == 1)
    }
}

@MainActor
struct EntityLabelSeparationTests {
    let harness: GraphHarness

    init() throws {
        harness = try GraphHarness()
    }

    // A tag and a mention can be written identically. They are still different things, and
    // only the Review list may put them together.
    @Test func aMentionNeverJoinsATagOrATheme() throws {
        try harness.entry(tags: ["work"], themes: ["moving house"])
        harness.indexer.sweep(in: harness.context)

        try harness.entry(mentions: [("work", .other), ("moving house", .other)])
        harness.indexer.sweep(in: harness.context)

        let byName = try harness.entities().filter { $0.name == "work" }
        #expect(byName.count == 2, "the tag and the named thing stay apart")
        #expect(Set(byName.map(\.kind)) == [.tag, .other])
        #expect(try harness.entity("work").kind == .tag, "and the tag was not converted")
    }
}

@MainActor
struct UserLinkReindexTests {
    let harness: GraphHarness

    init() throws {
        harness = try GraphHarness()
    }

    private func repointed(_ entry: Entry) throws -> Entity {
        let someoneElse = Entity(name: "Sarah Lee", key: "sarah lee", kind: .person)
        let link = try #require(harness.links(of: entry).first)
        GraphEditor(diagnostics: .disabled).repoint(link, to: someoneElse, addingAlias: false, in: harness.context)
        return someoneElse
    }

    // The model calls her a person one run and `other` the next. The user's correction still
    // covers her, so no AI link appears beside it.
    @Test func aUserLinkClaimsTheSameNameUnderAnotherKind() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.sweep(in: harness.context)
        let someoneElse = try repointed(entry)

        entry.insights?.mentions = [Mention(name: "Sarah", kindRaw: MentionKind.other.rawValue)]
        entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)
        harness.indexer.sweep(in: harness.context)

        let links = harness.links(of: entry)
        #expect(links.count == 1)
        #expect(links.first?.entityID == someoneElse.id)
    }

    // A user link is theirs even when the name it came from is no longer in the insights.
    @Test func aUserLinkOutlivesItsNameLeavingTheInsights() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.sweep(in: harness.context)
        let someoneElse = try repointed(entry)

        entry.insights?.mentions = []
        entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)
        harness.indexer.sweep(in: harness.context)

        #expect(harness.links(of: entry).map(\.entityID) == [someoneElse.id])
    }

    // A tag written like a corrected name is still its own thing.
    @Test func aUserLinkOnAPersonDoesNotClaimATag() throws {
        let entry = try harness.entry(mentions: [("Sarah", .person)])
        harness.indexer.sweep(in: harness.context)
        _ = try repointed(entry)

        entry.insights?.tags = ["sarah"]
        entry.insights?.generatedAt = Date(timeIntervalSince1970: 2_000)
        harness.indexer.sweep(in: harness.context)

        #expect(harness.links(of: entry).count == 2)
    }

    @Test func anAmbiguousMatchIsRecorded() throws {
        let file = DiagnosticsFile()
        let indexer = GraphIndexer(diagnostics: DiagnosticsLog(fileURL: file.url))
        for name in ["Sarah Kim", "Sarah Kim"] {
            let entity = Entity(name: name, key: "sarah kim", kind: .person)
            harness.context.insert(entity)
        }
        try harness.context.save()
        let entry = try harness.entry(mentions: [("Sarah Kim", .person)])

        indexer.index(entry, in: harness.context)

        #expect(file.contents().contains("graph.ambiguous"))
    }
}

@MainActor
struct RemoveInsightsGuardTests {
    let harness: GraphHarness

    init() throws {
        harness = try GraphHarness()
    }

    // Indexing and deleting in one unsaved batch still removes everything. This does not prove the
    // switch to removal by id: the relationship happened to read correctly here too, so the test
    // passes either way. It stays because the behavior itself is worth pinning.
    @Test func removingInsightsFindsLinksMadeInTheSameUnsavedBatch() throws {
        let entry = try harness.entry(tags: ["nature", "family"], mentions: [("Sarah", .person)])

        harness.indexer.index(entry, in: harness.context)
        entry.removeInsights(in: harness.context)
        try harness.context.save()

        #expect(harness.links(of: entry).isEmpty)
    }
}

@MainActor
struct SweepLoggingTests {
    // One summary for the whole pass, not a line per entry: a first launch over a large
    // journal would otherwise bury the device log.
    @Test func theSweepLogsOneSummaryLine() throws {
        let harness = try GraphHarness()
        for _ in 0..<5 { try harness.entry(tags: ["nature"], mentions: [("Sarah", .person)]) }
        let file = DiagnosticsFile()
        let indexer = GraphIndexer(diagnostics: DiagnosticsLog(fileURL: file.url))

        indexer.sweep(in: harness.context)

        let lines = file.contents().split(separator: "\n")
        #expect(!lines.contains { $0.contains("\"graph.indexed\"") })
        let summary = try #require(lines.first { $0.contains("\"graph.sweep\"") })
        #expect(summary.contains("\"entries\":5"))
        #expect(summary.contains("\"created\":2"))
        #expect(summary.contains("\"links\":10"))
    }
}
