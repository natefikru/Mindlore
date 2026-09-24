import Foundation
import SwiftData

// Puts a Mindlore export back (owner, 2026-09-23: the only import there is). It restores records
// rather than re-analysing: links, merges, parts, and loose ends come back as they were exported,
// no AI runs, and the map is the one that was exported. Plan and review: tasks/import-and-redo.md.
//
// Nothing already in the journal is ever overwritten. An entry whose id is here keeps its own copy
// whole, and everything the export hangs off it (pages, insights, links, the loose ends it raised)
// is skipped with it, since grafting pieces onto an entry the journal already has would double its
// links and replace its insights. The same goes for a name, loose end, conversation, message, or
// Reflect summary already here. So importing a folder twice adds nothing the second time.
@MainActor
enum JournalImport {
    nonisolated enum Failure: Error, Equatable, Sendable {
        // No journal.json, or one that isn't Mindlore's.
        case notAnExport
        // Made before import existed: no records to restore from.
        case olderExport
    }

    // A folder read and checked, nothing written yet.
    nonisolated struct Prepared: Sendable {
        let folder: URL
        let records: JournalRecords
    }

    // What an import would do, for the sheet that asks first.
    struct Preview: Equatable {
        var newEntries = 0
        var existingEntries = 0
        var newNames = 0
        var newConversations = 0
    }

    struct Summary: Equatable {
        var entries = 0
        var skippedEntries = 0
        var names = 0
        var reusedNames = 0
        var looseEnds = 0
        var conversations = 0
        var missingMedia = 0
    }

    // Reads and checks journal.json whole before anything is written. Media is read later, one
    // entry at a time, so a journal of recordings never sits in memory at once.
    nonisolated static func read(folder: URL) throws -> Prepared {
        let data: Data
        do {
            data = try Data(contentsOf: folder.appendingPathComponent("journal.json"))
        } catch {
            throw Failure.notAnExport
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let document = try? decoder.decode(JournalExport.Document.self, from: data) else {
            throw Failure.notAnExport
        }
        guard let records = document.records, (document.version ?? 1) >= 2 else {
            throw Failure.olderExport
        }
        return Prepared(folder: folder, records: records)
    }

    static func preview(_ prepared: Prepared, in context: ModelContext) -> Preview {
        let entryIDs = ids(of: Entry.self, \.id, in: context)
        let entityIDs = ids(of: Entity.self, \.id, in: context)
        let conversationIDs = ids(of: AskConversation.self, \.id, in: context)
        var preview = Preview()
        for entry in prepared.records.entries {
            if entryIDs.contains(entry.id) { preview.existingEntries += 1 } else { preview.newEntries += 1 }
        }
        preview.newNames = prepared.records.entities.filter { !entityIDs.contains($0.id) && $0.mergedIntoID == nil && $0.kindRaw != EntityKind.tag.rawValue }.count
        preview.newConversations = prepared.records.conversations.filter { !conversationIDs.contains($0.id) }.count
        return preview
    }

    static func apply(
        _ prepared: Prepared,
        into context: ModelContext,
        batchSize: Int = 100,
        diagnostics: DiagnosticsLog = .shared
    ) async throws -> Summary {
        let records = prepared.records
        var summary = Summary()

        // Names first, so every link and loose end has somewhere to point.
        let existingEntities = (try? context.fetch(FetchDescriptor<Entity>())) ?? []
        let existingIDs = Set(existingEntities.map(\.id))
        // A name the journal already has under another id (the same key and kind, visible, not
        // merged) is used as it is, or a journal started fresh on a new phone would get a second
        // Maya beside the one its own insights already made.
        var byKey: [String: Entity] = [:]
        for entity in existingEntities where entity.isBrowsable {
            byKey[entity.kindRaw + "|" + entity.key] = byKey[entity.kindRaw + "|" + entity.key] ?? entity
        }
        var remap: [UUID: UUID] = [:]
        var created: [(Entity, EntityRecord)] = []
        for record in records.entities where !existingIDs.contains(record.id) {
            if !record.hidden, record.mergedIntoID == nil, let existing = byKey[record.kindRaw + "|" + record.key] {
                remap[record.id] = existing.id
                for alias in record.aliases where !existing.aliases.contains(alias) && alias != existing.name {
                    existing.aliases.append(alias)
                }
                if existing.bio == nil, existing.bioDraftedAt == nil, let bio = record.bio {
                    existing.bio = bio
                    existing.bioWasGenerated = record.bioWasGenerated
                    existing.bioEditedByUser = record.bioEditedByUser
                    existing.bioDraftedAt = record.bioDraftedAt
                    existing.bioModelUsed = record.bioModelUsed
                }
                summary.reusedNames += 1
                continue
            }
            let entity = Entity(id: record.id, name: record.name, key: record.key, kind: EntityKind(rawValue: record.kindRaw) ?? .other, createdAt: record.createdAt)
            context.insert(entity)
            created.append((entity, record))
        }
        func mapped(_ id: UUID) -> UUID { remap[id] ?? id }
        // Every field holding a name's id goes through the remap, once all of them are known.
        for (entity, record) in created {
            entity.kindRaw = record.kindRaw
            entity.aliases = record.aliases
            entity.bio = record.bio
            entity.bioWasGenerated = record.bioWasGenerated
            entity.bioEditedByUser = record.bioEditedByUser
            entity.bioDraftedAt = record.bioDraftedAt
            entity.bioModelUsed = record.bioModelUsed
            entity.bioSourceEntries = record.bioSourceEntries
            entity.bioSourceCharacters = record.bioSourceCharacters
            entity.kindEditedByUser = record.kindEditedByUser
            entity.confirmedByUser = record.confirmedByUser
            entity.hidden = record.hidden
            entity.resurfacingMuted = record.resurfacingMuted
            entity.mergedIntoID = record.mergedIntoID.map(mapped)
            entity.mergedAt = record.mergedAt
            entity.contributedAliases = record.contributedAliases
            entity.notSameAs = record.notSameAs.map(mapped)
            entity.contactIdentifier = record.contactIdentifier
            entity.placeIdentifier = record.placeIdentifier
            entity.placeLatitude = record.placeLatitude
            entity.placeLongitude = record.placeLongitude
        }
        summary.names = created.count
        // Saved before any link points at them: a link can't take a target the store hasn't seen.
        try context.saveStampingEntries()

        let entitiesByID = Dictionary(((try? context.fetch(FetchDescriptor<Entity>())) ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let existingEntryIDs = ids(of: Entry.self, \.id, in: context)
        var skippedEntryIDs: Set<UUID> = []
        var inserted: Set<PersistentIdentifier> = []
        for record in records.entries {
            if existingEntryIDs.contains(record.id) {
                skippedEntryIDs.insert(record.id)
                summary.skippedEntries += 1
                continue
            }
            let entry = makeEntry(record, folder: prepared.folder, missingMedia: &summary.missingMedia, in: context)
            for link in record.links {
                guard let entityID = link.entityID, let entity = entitiesByID[mapped(entityID)] else { continue }
                let restored = EntityLink(surface: link.surface, kind: EntityKind(rawValue: link.kindRaw) ?? .other, source: EntityLinkSource(rawValue: link.sourceRaw) ?? .ai, inferred: link.inferred)
                context.insert(restored)
                restored.writtenSurface = link.writtenSurface
                restored.originalEntityID = link.originalEntityID.map(mapped)
                restored.unsureAmong = link.unsureAmong.map(mapped)
                restored.attach(to: entry, entity: entity)
            }
            inserted.insert(entry.persistentModelID)
            summary.entries += 1
            // In batches, so a journal of recordings and photos isn't held in one save. Imported
            // entries are left unstamped: their updatedAt is the one they were exported with.
            if summary.entries % batchSize == 0 {
                try context.saveStampingEntries(except: inserted)
                inserted = []
                // Lets the screen draw between batches, so a long import shows its progress
                // instead of freezing.
                await Task.yield()
            }
        }
        try context.saveStampingEntries(except: inserted)

        let existingLooseEnds = ids(of: LooseEnd.self, \.id, in: context)
        for record in records.looseEnds where !existingLooseEnds.contains(record.id) {
            // Raised by an entry the journal kept its own copy of: that copy's loose ends stand.
            if let source = record.sourceEntryID, skippedEntryIDs.contains(source) { continue }
            let end = LooseEnd(text: record.text, sourceEntryID: record.sourceEntryID ?? UUID(), sourceEntryDate: record.sourceEntryDate, entityIDs: record.entityIDs.map(mapped), dueDate: record.dueDate)
            end.id = record.id
            end.sourceEntryID = record.sourceEntryID
            end.createdAt = record.createdAt
            end.statusRaw = record.statusRaw
            end.resolvedByEntryID = record.resolvedByEntryID
            end.statusChangedAt = record.statusChangedAt
            end.lastMentionedAt = record.lastMentionedAt
            end.promptedAt = record.promptedAt
            end.userTouched = record.userTouched
            context.insert(end)
            summary.looseEnds += 1
        }

        let existingConversations = ids(of: AskConversation.self, \.id, in: context)
        var importedConversations: Set<UUID> = []
        for record in records.conversations where !existingConversations.contains(record.id) {
            let conversation = AskConversation(id: record.id, createdAt: record.createdAt, title: record.title)
            conversation.updatedAt = record.updatedAt
            conversation.handleMapData = record.handleMapData
            context.insert(conversation)
            importedConversations.insert(record.id)
        }
        summary.conversations = importedConversations.count
        let existingMessages = ids(of: AskMessage.self, \.id, in: context)
        for record in records.messages where !existingMessages.contains(record.id) {
            // A conversation the journal already had keeps its own turns.
            guard let conversationID = record.conversationID, importedConversations.contains(conversationID) else { continue }
            context.insert(AskMessage(
                id: record.id, conversationID: conversationID, index: record.index,
                role: AskRole(rawValue: record.roleRaw) ?? .user, text: record.text,
                citedEntryIDs: record.citedEntryIDs, providerLabel: record.providerLabel,
                sentEntryIDs: record.sentEntryIDs, sentCharacters: record.sentCharacters,
                matchedCount: record.matchedCount, rollupMonthCount: record.rollupMonthCount,
                digestEntryCount: record.digestEntryCount, failureRaw: record.failureRaw,
                wasStopped: record.wasStopped
            ))
        }

        // A period the journal already has a summary for keeps it: it was written from this
        // journal's entries.
        let summaries = (try? context.fetch(FetchDescriptor<ReflectSummary>())) ?? []
        let summaryIDs = Set(summaries.map(\.id))
        let periods = Set(summaries.map { "\($0.periodKindRaw)|\($0.periodStart.timeIntervalSince1970)" })
        for record in records.reflectSummaries where !summaryIDs.contains(record.id) && !periods.contains("\(record.periodKindRaw)|\(record.periodStart.timeIntervalSince1970)") {
            let restored = ReflectSummary(kind: ReflectSummaryKind(rawValue: record.periodKindRaw) ?? .week, periodStart: record.periodStart, generatedAt: record.generatedAt, items: [])
            restored.id = record.id
            restored.itemsData = record.itemsData
            restored.sourceFingerprint = record.sourceFingerprint
            context.insert(restored)
        }

        // The counts on each name are derived; the links are what was restored.
        GraphIndexer(diagnostics: diagnostics).recount(in: context)
        try context.saveStampingEntries()

        diagnostics.record("journal.imported", [
            "entries": .int(summary.entries),
            "skippedEntries": .int(summary.skippedEntries),
            "names": .int(summary.names),
            "reusedNames": .int(summary.reusedNames),
            "looseEnds": .int(summary.looseEnds),
            "conversations": .int(summary.conversations),
            "missingMedia": .int(summary.missingMedia),
        ])
        return summary
    }

    private static func makeEntry(_ record: EntryRecord, folder: URL, missingMedia: inout Int, in context: ModelContext) -> Entry {
        let entry = Entry(id: record.id, createdAt: record.createdAt, source: EntrySource(rawValue: record.sourceRaw) ?? .typed, text: record.text)
        context.insert(entry)
        entry.updatedAt = record.updatedAt
        entry.formattingRaw = record.formattingRaw
        entry.textWasGenerated = record.textWasGenerated
        entry.textEditedByUser = record.textEditedByUser
        entry.awaitingText = record.awaitingText
        if let file = record.audioFile {
            if let data = media(file, in: folder) {
                entry.audioData = data
                entry.audioDuration = record.audioDuration
            } else {
                missingMedia += 1
            }
        }
        entry.entryDate = record.entryDate
        entry.entryDateIsDayOnly = record.entryDateIsDayOnly
        entry.suggestedEntryDate = record.suggestedEntryDate
        entry.title = record.title
        entry.titleWasGenerated = record.titleWasGenerated
        entry.originalText = record.originalText
        entry.originalFormattingRaw = record.originalFormattingRaw
        entry.cleanupAppliedHash = record.cleanupAppliedHash
        entry.textGeneratedBy = record.textGeneratedBy
        entry.textReviewPending = record.textReviewPending
        entry.textFallbackReasonRaw = record.textFallbackReasonRaw
        entry.pagesConfirmed = record.pagesConfirmed
        entry.isDraft = record.isDraft
        entry.isCreative = record.isCreative
        entry.isNote = record.isNote
        entry.creativeSetByUser = record.creativeSetByUser
        // Analysed where it came from: no automatic pass, and nothing queued.
        entry.automaticAIPassUsed = true
        entry.titlePending = false
        entry.insightsPending = false

        for page in record.pages {
            var imageData: Data?
            if let file = page.imageFile {
                imageData = media(file, in: folder)
                if imageData == nil { missingMedia += 1 }
            }
            let restored = EntryPage(index: page.index, imageData: imageData, thumbnailData: page.thumbnailData, pixelWidth: page.pixelWidth, pixelHeight: page.pixelHeight, origin: PageOrigin(rawValue: page.originRaw) ?? .camera, addedAt: page.addedAt)
            context.insert(restored)
            restored.transcribedText = page.transcribedText
            restored.writtenDate = page.writtenDate
            restored.entry = entry
        }

        if let record = record.insights {
            let insights = EntryInsights(generatedAt: record.generatedAt, modelUsed: record.modelUsed, sourceTextHash: record.sourceTextHash)
            context.insert(insights)
            insights.summary = record.summary
            insights.primaryMoodRaw = record.primaryMoodRaw
            insights.secondaryMoodsRaw = record.secondaryMoodsRaw
            insights.moodsEditedByUser = record.moodsEditedByUser
            insights.areasRaw = record.areasRaw
            insights.tags = record.tags
            insights.mentionsData = record.mentionsData
            insights.cleanedText = record.cleanedText
            insights.cleanedTextSkippedReasonRaw = record.cleanedTextSkippedReasonRaw
            insights.customCardsData = record.customCardsData
            insights.sectionsData = record.sectionsData
            insights.sentTagCount = record.sentTagCount
            insights.sentNameCount = record.sentNameCount
            insights.sentLooseEndCount = record.sentLooseEndCount
            insights.entry = entry
        }
        // The graph treats an entry as stale when these differ and re-resolves its links against
        // today's names, which would undo the restore. Equal, it leaves them alone.
        entry.graphIndexedAt = record.insights?.generatedAt
        return entry
    }

    // A path from the export, kept inside the folder: `..` or an absolute path in a hand-edited
    // journal.json can't reach anything else on the phone.
    private static func media(_ path: String, in folder: URL) -> Data? {
        let root = folder.standardizedFileURL.path
        let url = folder.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(root + "/") else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func ids<T: PersistentModel>(of type: T.Type, _ id: KeyPath<T, UUID>, in context: ModelContext) -> Set<UUID> {
        Set(((try? context.fetch(FetchDescriptor<T>())) ?? []).map { $0[keyPath: id] })
    }
}
