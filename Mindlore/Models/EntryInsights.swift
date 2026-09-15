import Foundation
import SwiftData

// AI output for one entry, kept apart from the entry's own text.
@Model
final class EntryInsights {
    var entry: Entry?
    var generatedAt: Date = Date.now
    var modelUsed: String = ""
    var sourceTextHash: String = ""
    var appliedTextHash: String?
    var summary: String?
    var primaryMoodRaw: String?
    var secondaryMoodsRaw: [String] = []
    var themes: [String] = []
    var tags: [String] = []
    var mentionsData: Data?
    var openThreads: [String] = []
    var cleanedText: String?
    var cleanedTextSkippedReasonRaw: String?
    var customCardsData: Data?

    init(generatedAt: Date = .now, modelUsed: String = "", sourceTextHash: String = "") {
        self.generatedAt = generatedAt
        self.modelUsed = modelUsed
        self.sourceTextHash = sourceTextHash
    }
}
