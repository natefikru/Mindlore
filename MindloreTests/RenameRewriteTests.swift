import Foundation
import SwiftData
import Testing
@testable import Mindlore

// A rename fixes the name in the app's own sentences and never in the user's. The entry's text is
// what the user wrote; the alias is what keeps it resolving.
@MainActor
struct RenameRewriteTests {
    let harness: GraphHarness
    let editor = GraphEditor(diagnostics: .disabled)

    init() throws {
        harness = try GraphHarness()
    }

    // An entry that names Sarah, with every kind of app-written prose hanging off it.
    @discardableResult
    private func sarahEntry(text: String = "Walked with Sarah by the river.") throws -> Entry {
        let entry = try harness.entry(text, mentions: [("Sarah", .person)])
        entry.title = "Sarah by the river"
        entry.titleWasGenerated = true
        entry.insights?.summary = "Sarah and I walked by the river."
        entry.insights?.customResults = [
            CustomInsightResult(promptID: UUID(), name: "Gratitude", content: "Grateful that Sarah came along.")
        ]
        harness.indexer.sweep(in: harness.context)
        try harness.context.save()
        return entry
    }

    private func rename(_ entity: Entity, to name: String) -> GraphEditor.RenameOutcome {
        editor.rename(entity, to: name, in: harness.context)
    }

    @Test func theAppsOwnSentencesAreFixed() throws {
        let entry = try sarahEntry()
        let sarah = try harness.entity("Sarah")
        sarah.bio = "Sarah walks by the river."

        let result = rename(sarah, to: "Sarah Kim")

        #expect(result.outcome == .applied)
        #expect(entry.insights?.summary == "Sarah Kim and I walked by the river.")
        #expect(entry.title == "Sarah Kim by the river")
        #expect(entry.insights?.customResults.first?.content == "Grateful that Sarah Kim came along.")
        #expect(sarah.bio == "Sarah Kim walks by the river.")
        #expect(result.counts.summaries == 1)
        #expect(result.counts.titles == 1)
        #expect(result.counts.cards == 1)
        #expect(result.counts.bios == 1)
    }

    // The rule the owner was explicit about.
    @Test func theEntrysOwnWordsAreNeverTouched() throws {
        let entry = try sarahEntry()
        entry.originalText = entry.text
        let sarah = try harness.entity("Sarah")
        let surfaces = ((try? harness.context.fetch(FetchDescriptor<EntityLink>())) ?? []).map(\.surface)

        rename(sarah, to: "Sarah Kim")

        #expect(entry.text == "Walked with Sarah by the river.")
        #expect(entry.originalText == "Walked with Sarah by the river.")
        #expect(((try? harness.context.fetch(FetchDescriptor<EntityLink>())) ?? []).map(\.surface) == surfaces)
    }

    // cleanedText is the user's words tidied, and cleanupAppliedHash measures against them.
    @Test func cleanedTextAndTheSourceHashAreLeftAlone() throws {
        let entry = try sarahEntry()
        entry.insights?.cleanedText = "Walked with Sarah by the river."
        // Insights describe the text they were made from, so the hash has to match to begin with.
        entry.insights?.sourceTextHash = TextHash.of(entry.text)
        let hash = entry.insights?.sourceTextHash
        let sarah = try harness.entity("Sarah")

        rename(sarah, to: "Sarah Kim")

        #expect(entry.insights?.cleanedText == "Walked with Sarah by the river.")
        #expect(entry.insights?.sourceTextHash == hash)
        #expect(entry.insights?.isCurrent(for: entry) == true)
    }

    // Writing a summary marks its entry changed through the relationship, but that is not an
    // edit the user made.
    @Test func aRewrittenEntrysEditedTimeDoesNotMove() throws {
        let entry = try sarahEntry()
        let before = Date(timeIntervalSince1970: 1_000)
        entry.updatedAt = before
        try harness.context.save()
        let sarah = try harness.entity("Sarah")

        let services = GraphServices(diagnostics: .disabled)
        #expect(services.rename(sarah.id, to: "Sarah Kim", in: harness.context) == .applied)

        #expect(entry.insights?.summary?.contains("Sarah Kim") == true, "the rewrite ran")
        #expect(entry.updatedAt == before)
    }

    @Test func aBioTheUserWroteIsSkipped() throws {
        try sarahEntry()
        let sarah = try harness.entity("Sarah")
        sarah.bio = "Sarah is my oldest friend."
        sarah.bioEditedByUser = true

        let result = rename(sarah, to: "Sarah Kim")

        #expect(sarah.bio == "Sarah is my oldest friend.")
        #expect(result.counts.bios == 0)
    }

    @Test func aTitleTheUserTypedIsSkipped() throws {
        let entry = try sarahEntry()
        entry.title = "Sarah day"
        entry.titleWasGenerated = false
        let sarah = try harness.entity("Sarah")

        let result = rename(sarah, to: "Sarah Kim")

        #expect(entry.title == "Sarah day")
        #expect(result.counts.titles == 0)
    }

    // A bio about Tom can name Sarah, so the bio walk isn't narrowed to the renamed entity. It is
    // narrowed to entities that share an entry where the name was actually written, which is how
    // a stranger's bio saying "April" survives an April being renamed.
    @Test func renamingOneEntityFixesTheBioOfSomeoneWhoSharesAnEntry() throws {
        let entry = try harness.entry("Walked with Sarah and Tom.", mentions: [("Sarah", .person), ("Tom", .person)])
        entry.insights?.summary = "Sarah and Tom walked with me."
        harness.indexer.sweep(in: harness.context)
        try harness.context.save()
        let tom = try harness.entity("Tom")
        tom.bio = "Tom is Sarah's brother."
        try harness.context.save()
        let sarah = try harness.entity("Sarah")

        rename(sarah, to: "Sarah Kim")

        #expect(tom.bio == "Tom is Sarah Kim's brother.")
    }

    // The failure the rule exists for: April, Grace, Will, and May are ordinary words. A bio that
    // says one, on someone who never shared an entry with that person, is left alone.
    @Test func aStrangersBioThatHappensToSayTheNameIsLeftAlone() throws {
        try sarahEntry()
        let tom = Entity(name: "Tom", key: EntityNormalizer.key(for: "Tom", kind: .person), kind: .person)
        tom.bio = "Tom is Sarah's brother."
        harness.context.insert(tom)
        try harness.context.save()
        let sarah = try harness.entity("Sarah")

        let result = rename(sarah, to: "Sarah Kim")

        #expect(tom.bio == "Tom is Sarah's brother.")
        #expect(result.counts.bios == 0)
    }

    // A tag's name is an ordinary lowercase word, so exact case would match every occurrence.
    @Test func aTagIsNeverRewritten() throws {
        let entry = try harness.entry("Walked by the river.", tags: ["river"])
        entry.insights?.summary = "A walk by the river."
        harness.indexer.sweep(in: harness.context)
        try harness.context.save()
        let river = try harness.entity("river")

        let result = rename(river, to: "riverside")

        #expect(entry.insights?.summary == "A walk by the river.")
        #expect(result.counts.isEmpty)
    }

    // An entry that never mentioned her has no business containing her name.
    @Test func aSummaryOnAnUnlinkedEntryIsSkipped() throws {
        try sarahEntry()
        let other = try harness.entry("A different day.", mentions: [("Tom", .person)])
        other.insights?.summary = "Sarah is not in this entry's links."
        harness.indexer.sweep(in: harness.context)
        try harness.context.save()
        let sarah = try harness.entity("Sarah")

        let result = rename(sarah, to: "Sarah Kim")

        #expect(other.insights?.summary == "Sarah is not in this entry's links.")
        #expect(result.counts.summaries == 1, "only the linked entry")
    }

    @Test func aLooseEndAboutTheEntityIsFixed() throws {
        let entry = try sarahEntry()
        let sarah = try harness.entity("Sarah")
        let end = LooseEnd(text: "Call Sarah about the weekend", sourceEntryID: entry.id, sourceEntryDate: entry.entryDate, entityIDs: [sarah.id])
        harness.context.insert(end)
        try harness.context.save()

        let result = rename(sarah, to: "Sarah Kim")

        #expect(end.text == "Call Sarah Kim about the weekend")
        #expect(result.counts.looseEnds == 1)
    }

    @Test func theOldNameAlwaysBecomesAnAlias() throws {
        try sarahEntry()
        let sarah = try harness.entity("Sarah")

        rename(sarah, to: "Sarah Kim")

        #expect(sarah.aliases.contains("Sarah"))
        #expect(sarah.name == "Sarah Kim")
    }

    // A change that normalizes to the same key already matches, so an alias adds nothing.
    @Test func aCapitalizationFixAddsNoAlias() throws {
        let entity = Entity(name: "sarah", key: EntityNormalizer.key(for: "sarah", kind: .person), kind: .person)
        harness.context.insert(entity)
        try harness.context.save()

        rename(entity, to: "Sarah")

        #expect(entity.aliases.isEmpty)
        #expect(entity.name == "Sarah")
    }

    // A merged loser is not what any screen shows, so its name is not in the app's prose.
    @Test func renamingAMergedLoserRewritesNothing() throws {
        let entry = try sarahEntry()
        let sarah = try harness.entity("Sarah")
        let winner = Entity(name: "Sarah Kim", key: EntityNormalizer.key(for: "Sarah Kim", kind: .person), kind: .person)
        harness.context.insert(winner)
        try harness.context.save()
        sarah.mergedIntoID = winner.id

        let result = rename(sarah, to: "Sarah K")

        #expect(result.counts.isEmpty)
        #expect(entry.insights?.summary == "Sarah and I walked by the river.")
    }

    // What the sheet promises and what the rename does come from one walk.
    @Test func thePreviewCountsWhatTheRenameThenChanges() throws {
        try sarahEntry()
        let sarah = try harness.entity("Sarah")
        sarah.bio = "Sarah walks by the river."
        try harness.context.save()

        let preview = editor.renamePreview(sarah, in: harness.context)
        let result = rename(sarah, to: "Sarah Kim")

        #expect(preview == result.counts)
        #expect(preview.total == 4)
    }

    @Test func thePreviewDoesNotWriteAnything() throws {
        let entry = try sarahEntry()
        let sarah = try harness.entity("Sarah")

        _ = editor.renamePreview(sarah, in: harness.context)

        #expect(entry.insights?.summary == "Sarah and I walked by the river.")
        #expect(entry.title == "Sarah by the river")
    }
}
