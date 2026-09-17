import CryptoKit
import Foundation
import SwiftData

// AI output for one entry, kept apart from the entry's own text.
@Model
final class EntryInsights {
    var entry: Entry?
    var generatedAt: Date = Date.now
    var modelUsed: String = ""
    var sourceTextHash: String = ""
    var summary: String?
    var primaryMoodRaw: String?
    var secondaryMoodsRaw: [String] = []
    // Set when the user picks the moods themselves, so the screen can say so and a rerun can warn.
    var moodsEditedByUser: Bool = false
    var areasRaw: [String] = []
    var tags: [String] = []
    var mentionsData: Data?
    var cleanedText: String?
    var cleanedTextSkippedReasonRaw: String?
    var customCardsData: Data?
    // How many of the journal's own tags, names, and loose ends went with the request, for the
    // disclosure screen. Zero for insights made before those were sent.
    var sentTagCount: Int = 0
    var sentNameCount: Int = 0
    var sentLooseEndCount: Int = 0

    init(generatedAt: Date = .now, modelUsed: String = "", sourceTextHash: String = "") {
        self.generatedAt = generatedAt
        self.modelUsed = modelUsed
        self.sourceTextHash = sourceTextHash
    }

    var primaryMood: Mood? {
        primaryMoodRaw.flatMap(Mood.init(rawValue:))
    }

    var secondaryMoods: [Mood] {
        secondaryMoodsRaw.compactMap(Mood.init(rawValue:))
    }

    func setMoods(primary: Mood?, secondary: [Mood], editedByUser: Bool = true) {
        primaryMoodRaw = primary?.rawValue
        secondaryMoodsRaw = Array(secondary.filter { $0 != primary }.prefix(2)).map(\.rawValue)
        moodsEditedByUser = editedByUser
    }

    var areas: [LifeArea] {
        get { areasRaw.compactMap(LifeArea.init(rawValue:)) }
        set { areasRaw = newValue.map(\.rawValue) }
    }

    var mentions: [Mention] {
        get { mentionsData.flatMap { try? JSONDecoder().decode([Mention].self, from: $0) } ?? [] }
        set { mentionsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    var customResults: [CustomInsightResult] {
        get { customCardsData.flatMap { try? JSONDecoder().decode([CustomInsightResult].self, from: $0) } ?? [] }
        set { customCardsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }

    // Insights describe the text they were made from; text the user cleaned up counts as the same.
    func isCurrent(for entry: Entry) -> Bool {
        let hash = TextHash.of(entry.text)
        return hash == sourceTextHash || hash == entry.cleanupAppliedHash
    }
}

nonisolated enum TextHash {
    static func of(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
