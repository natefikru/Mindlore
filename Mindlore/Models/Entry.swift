import Foundation
import SwiftData

// CloudKit sync requires every stored property to be optional or have a default,
// and forbids unique constraints. CloudKitSchemaRulesTests enforces this.
@Model
final class Entry {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var sourceRaw: String = EntrySource.typed.rawValue
    var text: String = ""
    var textWasGenerated: Bool = false
    var textEditedByUser: Bool = false
    var awaitingText: Bool = false
    @Attribute(.externalStorage) var audioData: Data?
    var audioDuration: Double?

    // When the entry belongs in the journal. Equals createdAt until the user picks a day,
    // then it is noon of that day and entryDateIsDayOnly hides the time.
    var entryDate: Date = Date.now
    var entryDateIsDayOnly: Bool = false
    var suggestedEntryDate: Date?

    var title: String = ""
    var titleWasGenerated: Bool = false
    // The text before the first applied cleanup, so a revert always has the original.
    var originalText: String?
    // The text as it was right after a cleanup was applied, so "changed since" and revert survive
    // insights being regenerated or deleted.
    var cleanupAppliedHash: String?
    var textGeneratedBy: String?
    var textReviewPending: Bool = false
    var textFallbackReasonRaw: String?
    var pagesConfirmed: Bool = false
    // Bumped by page changes and restarts; AI jobs drop results captured under an older revision.
    var contentRevision: Int = 0
    var pageRequestCount: Int = 0

    // AI job state is persisted so failures and attempt caps survive relaunches.
    var textAttempts: Int = 0
    var textFailureRaw: String?
    // Each finished chunk of a long cloud transcription, in order ("" for a silent one), for the chunk
    // plan named in `textChunkPlan`. A failure part-way resends only the chunks still missing.
    // Cleared once the entry has its text.
    var textChunkPlan: String?
    var textChunkTexts: [String] = []
    var automaticAIPassUsed: Bool = false
    // A typed entry the user hasn't finished with Done. Drafts never get the automatic AI pass.
    var isDraft: Bool = false
    // A piece of creative work (a poem, lyrics, a story, an abstract fragment) rather than the
    // author's account of their life. Its names, area, and loose ends are never taken as facts:
    // a lyric about Rosa driving to Memphis must not put Rosa on the map (owner, 2026-09-22).
    // Insights set it, strictly, unless the user has; the user's call is never overridden.
    var isCreative: Bool = false
    var creativeSetByUser: Bool = false
    var titlePending: Bool = false
    var titleAttempts: Int = 0
    var titleFailureRaw: String?
    var insightsPending: Bool = false
    var insightsAttempts: Int = 0
    var insightsFailureRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \EntryPage.entry)
    var pages: [EntryPage]? = []
    @Relationship(deleteRule: .cascade, inverse: \EntryInsights.entry)
    var insights: EntryInsights?
    // The graph's view of this entry's tags and mentions. Deleting the entry deletes them.
    @Relationship(deleteRule: .cascade, inverse: \EntityLink.entry)
    var entityLinks: [EntityLink]? = []
    // The exact EntryInsights.generatedAt the graph last indexed. Any difference means stale,
    // so a clock that steps back can't hide regenerated insights.
    var graphIndexedAt: Date?

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .typed }
        set { sourceRaw = newValue.rawValue }
    }

    var sortedPages: [EntryPage] {
        (pages ?? []).sorted { $0.index < $1.index }
    }

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        source: EntrySource = .typed,
        text: String = "",
        awaitingText: Bool = false,
        audioData: Data? = nil,
        audioDuration: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.entryDate = createdAt
        self.sourceRaw = source.rawValue
        self.text = text
        self.awaitingText = awaitingText
        self.audioData = audioData
        self.audioDuration = audioDuration
    }
}
