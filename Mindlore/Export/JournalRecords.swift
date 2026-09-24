import Foundation
import SwiftData

// Everything `JournalImport` needs to put a journal back as it was, written into `journal.json`
// beside the readable fields (owner, 2026-09-23: import only ever reads a Mindlore export). One
// record per model, each field named after the stored property it copies, so
// `JournalRecordsTests` can hold every record against SwiftData's own schema: a property added to
// a model later fails that test until it is carried here or listed as left out on purpose.
//
// Left out on purpose: job bookkeeping (attempts, failures, pending flags, chunk plans,
// `contentRevision`, `graphIndexedAt`), which the importer sets, and what `GraphIndexer.recount`
// derives (`linkCount`, `firstLinkedAt`, `lastLinkedAt`). Recordings and page photos are files in
// `media/`, named by the readable half of the export; a thumbnail is small and goes inline.
nonisolated struct JournalRecords: Codable, Equatable, Sendable {
    var entries: [EntryRecord] = []
    var entities: [EntityRecord] = []
    var looseEnds: [LooseEndRecord] = []
    var conversations: [ConversationRecord] = []
    var messages: [MessageRecord] = []
    var reflectSummaries: [ReflectSummaryRecord] = []
}

nonisolated struct EntryRecord: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var sourceRaw: String
    var text: String
    var formattingRaw: String?
    var textWasGenerated: Bool
    var textEditedByUser: Bool
    var awaitingText: Bool
    // `audioData`, as a path inside the export.
    var audioFile: String?
    var audioDuration: Double?
    var entryDate: Date
    var entryDateIsDayOnly: Bool
    var suggestedEntryDate: Date?
    var title: String
    var titleWasGenerated: Bool
    var originalText: String?
    var originalFormattingRaw: String?
    var cleanupAppliedHash: String?
    var textGeneratedBy: String?
    var textReviewPending: Bool
    var textFallbackReasonRaw: String?
    var pagesConfirmed: Bool
    var isDraft: Bool
    var isCreative: Bool
    var isNote: Bool
    var creativeSetByUser: Bool
    var pages: [PageRecord]
    var insights: InsightsRecord?
    var links: [LinkRecord]
}

nonisolated struct PageRecord: Codable, Equatable, Sendable {
    var index: Int
    // `imageData`, as a path inside the export.
    var imageFile: String?
    var thumbnailData: Data?
    var pixelWidth: Int
    var pixelHeight: Int
    var originRaw: String
    var addedAt: Date
    var transcribedText: String?
    var writtenDate: Date?
}

nonisolated struct InsightsRecord: Codable, Equatable, Sendable {
    var generatedAt: Date
    var modelUsed: String
    var sourceTextHash: String
    var summary: String?
    var primaryMoodRaw: String?
    var secondaryMoodsRaw: [String]
    var moodsEditedByUser: Bool
    var areasRaw: [String]
    var tags: [String]
    var mentionsData: Data?
    var cleanedText: String?
    var cleanedTextSkippedReasonRaw: String?
    var customCardsData: Data?
    var sectionsData: Data?
    var sentTagCount: Int
    var sentNameCount: Int
    var sentLooseEndCount: Int
}

// A link has no id of its own: it is one entry naming one entity, and it travels with its entry.
nonisolated struct LinkRecord: Codable, Equatable, Sendable {
    var entityID: UUID?
    var surface: String
    var writtenSurface: String?
    var kindRaw: String
    var sourceRaw: String
    var inferred: Bool
    var originalEntityID: UUID?
    var unsureAmong: [UUID]
}

nonisolated struct EntityRecord: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var key: String
    var kindRaw: String
    var aliases: [String]
    var bio: String?
    var bioWasGenerated: Bool
    var bioEditedByUser: Bool
    var bioDraftedAt: Date?
    var bioModelUsed: String?
    var bioSourceEntries: Int
    var bioSourceCharacters: Int
    var kindEditedByUser: Bool
    var confirmedByUser: Bool
    var hidden: Bool
    var resurfacingMuted: Bool
    var mergedIntoID: UUID?
    var mergedAt: Date?
    var contributedAliases: [String]
    var notSameAs: [UUID]
    var contactIdentifier: String?
    var placeIdentifier: String?
    var placeLatitude: Double?
    var placeLongitude: Double?
    var createdAt: Date
}

nonisolated struct LooseEndRecord: Codable, Equatable, Sendable {
    var id: UUID
    var text: String
    var createdAt: Date
    var sourceEntryID: UUID?
    var sourceEntryDate: Date
    var entityIDs: [UUID]
    var dueDate: Date?
    var statusRaw: String
    var resolvedByEntryID: UUID?
    var statusChangedAt: Date?
    var lastMentionedAt: Date
    var promptedAt: Date?
    var userTouched: Bool
}

nonisolated struct ConversationRecord: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    var handleMapData: Data?
}

nonisolated struct MessageRecord: Codable, Equatable, Sendable {
    var id: UUID
    var conversationID: UUID?
    var index: Int
    var roleRaw: String
    var text: String
    var citedEntryIDs: [UUID]
    var providerLabel: String
    var sentEntryIDs: [UUID]
    var sentCharacters: Int
    var matchedCount: Int
    var rollupMonthCount: Int
    var digestEntryCount: Int
    var failureRaw: String?
    var wasStopped: Bool
}

nonisolated struct ReflectSummaryRecord: Codable, Equatable, Sendable {
    var id: UUID
    var periodKindRaw: String
    var periodStart: Date
    var generatedAt: Date
    var itemsData: Data?
    var sourceFingerprint: String?
}

// MARK: - From the store

extension EntryRecord {
    @MainActor init(_ entry: Entry, audioFile: String?, pages: [PageRecord], links: [LinkRecord]) {
        self.init(
            id: entry.id, createdAt: entry.createdAt, updatedAt: entry.updatedAt, sourceRaw: entry.sourceRaw,
            text: entry.text, formattingRaw: entry.formattingRaw, textWasGenerated: entry.textWasGenerated,
            textEditedByUser: entry.textEditedByUser, awaitingText: entry.awaitingText, audioFile: audioFile,
            audioDuration: entry.audioDuration, entryDate: entry.entryDate, entryDateIsDayOnly: entry.entryDateIsDayOnly,
            suggestedEntryDate: entry.suggestedEntryDate, title: entry.title, titleWasGenerated: entry.titleWasGenerated,
            originalText: entry.originalText, originalFormattingRaw: entry.originalFormattingRaw,
            cleanupAppliedHash: entry.cleanupAppliedHash, textGeneratedBy: entry.textGeneratedBy,
            textReviewPending: entry.textReviewPending, textFallbackReasonRaw: entry.textFallbackReasonRaw,
            pagesConfirmed: entry.pagesConfirmed, isDraft: entry.isDraft, isCreative: entry.isCreative,
            isNote: entry.isNote, creativeSetByUser: entry.creativeSetByUser, pages: pages,
            insights: entry.insights.map(InsightsRecord.init), links: links
        )
    }
}

extension PageRecord {
    @MainActor init(_ page: EntryPage, imageFile: String?) {
        self.init(
            index: page.index, imageFile: imageFile, thumbnailData: page.thumbnailData, pixelWidth: page.pixelWidth,
            pixelHeight: page.pixelHeight, originRaw: page.originRaw, addedAt: page.addedAt,
            transcribedText: page.transcribedText, writtenDate: page.writtenDate
        )
    }
}

extension InsightsRecord {
    @MainActor init(_ insights: EntryInsights) {
        self.init(
            generatedAt: insights.generatedAt, modelUsed: insights.modelUsed, sourceTextHash: insights.sourceTextHash,
            summary: insights.summary, primaryMoodRaw: insights.primaryMoodRaw, secondaryMoodsRaw: insights.secondaryMoodsRaw,
            moodsEditedByUser: insights.moodsEditedByUser, areasRaw: insights.areasRaw, tags: insights.tags,
            mentionsData: insights.mentionsData, cleanedText: insights.cleanedText,
            cleanedTextSkippedReasonRaw: insights.cleanedTextSkippedReasonRaw, customCardsData: insights.customCardsData,
            sectionsData: insights.sectionsData, sentTagCount: insights.sentTagCount, sentNameCount: insights.sentNameCount,
            sentLooseEndCount: insights.sentLooseEndCount
        )
    }
}

extension LinkRecord {
    @MainActor init(_ link: EntityLink) {
        self.init(
            entityID: link.entityID, surface: link.surface, writtenSurface: link.writtenSurface, kindRaw: link.kindRaw,
            sourceRaw: link.sourceRaw, inferred: link.inferred, originalEntityID: link.originalEntityID,
            unsureAmong: link.unsureAmong
        )
    }
}

extension EntityRecord {
    @MainActor init(_ entity: Entity) {
        self.init(
            id: entity.id, name: entity.name, key: entity.key, kindRaw: entity.kindRaw, aliases: entity.aliases,
            bio: entity.bio, bioWasGenerated: entity.bioWasGenerated, bioEditedByUser: entity.bioEditedByUser,
            bioDraftedAt: entity.bioDraftedAt, bioModelUsed: entity.bioModelUsed, bioSourceEntries: entity.bioSourceEntries,
            bioSourceCharacters: entity.bioSourceCharacters, kindEditedByUser: entity.kindEditedByUser,
            confirmedByUser: entity.confirmedByUser, hidden: entity.hidden, resurfacingMuted: entity.resurfacingMuted,
            mergedIntoID: entity.mergedIntoID, mergedAt: entity.mergedAt, contributedAliases: entity.contributedAliases,
            notSameAs: entity.notSameAs, contactIdentifier: entity.contactIdentifier,
            placeIdentifier: entity.placeIdentifier, placeLatitude: entity.placeLatitude,
            placeLongitude: entity.placeLongitude, createdAt: entity.createdAt
        )
    }
}

extension LooseEndRecord {
    @MainActor init(_ end: LooseEnd) {
        self.init(
            id: end.id, text: end.text, createdAt: end.createdAt, sourceEntryID: end.sourceEntryID,
            sourceEntryDate: end.sourceEntryDate, entityIDs: end.entityIDs, dueDate: end.dueDate,
            statusRaw: end.statusRaw, resolvedByEntryID: end.resolvedByEntryID, statusChangedAt: end.statusChangedAt,
            lastMentionedAt: end.lastMentionedAt, promptedAt: end.promptedAt, userTouched: end.userTouched
        )
    }
}

extension ConversationRecord {
    @MainActor init(_ conversation: AskConversation) {
        self.init(
            id: conversation.id, createdAt: conversation.createdAt, updatedAt: conversation.updatedAt,
            title: conversation.title, handleMapData: conversation.handleMapData
        )
    }
}

extension MessageRecord {
    @MainActor init(_ message: AskMessage) {
        self.init(
            id: message.id, conversationID: message.conversationID, index: message.index, roleRaw: message.roleRaw,
            text: message.text, citedEntryIDs: message.citedEntryIDs, providerLabel: message.providerLabel,
            sentEntryIDs: message.sentEntryIDs, sentCharacters: message.sentCharacters, matchedCount: message.matchedCount,
            rollupMonthCount: message.rollupMonthCount, digestEntryCount: message.digestEntryCount,
            failureRaw: message.failureRaw, wasStopped: message.wasStopped
        )
    }
}

extension ReflectSummaryRecord {
    @MainActor init(_ summary: ReflectSummary) {
        self.init(
            id: summary.id, periodKindRaw: summary.periodKindRaw, periodStart: summary.periodStart,
            generatedAt: summary.generatedAt, itemsData: summary.itemsData, sourceFingerprint: summary.sourceFingerprint
        )
    }
}
