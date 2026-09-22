import Foundation
import SwiftData

nonisolated enum ReflectSummaryKind: String, CaseIterable, Sendable {
    case week, month
}

// A period's generated queue items, read back on every later view instead of asked for again. A
// week's is rewritten while the week is still open and its entries change, and is final once a
// summary has been written after the week ended (ReflectSummaryStore.generateIfNeeded). Every stored property is optional or defaulted and nothing is
// `@Attribute(.unique)`, the same CloudKit rule `Entry`, `Entity`, and `LooseEnd` follow;
// `CloudKitSchemaRulesTests` checks this model too.
@Model
final class ReflectSummary {
    var id: UUID = UUID()
    var periodKindRaw: String = ReflectSummaryKind.week.rawValue
    // The interval's start: which week or which month this is. Together with the kind, this is
    // the identity a lookup keys on; there is deliberately no uniqueness constraint (CloudKit
    // rule), so a caller that finds two rows for the same period reads the newest by
    // `generatedAt` and the launch sweep's own cache check is what keeps a second one from being
    // written in the first place.
    var periodStart: Date = Date.distantPast
    var generatedAt: Date = Date.distantPast
    var itemsData: Data?
    // A hash of the entries a week's summary was written from, so an open week knows when it has
    // fallen behind. Nil for months, which are written once.
    var sourceFingerprint: String?

    init(kind: ReflectSummaryKind, periodStart: Date, generatedAt: Date, items: [ReflectQueueItem], sourceFingerprint: String? = nil) {
        self.periodKindRaw = kind.rawValue
        self.periodStart = periodStart
        self.generatedAt = generatedAt
        self.itemsData = try? JSONEncoder().encode(items)
        self.sourceFingerprint = sourceFingerprint
    }

    var kind: ReflectSummaryKind {
        ReflectSummaryKind(rawValue: periodKindRaw) ?? .week
    }

    // Never throws outward: a row whose data can't decode (a future version wrote a shape this
    // one doesn't know) is treated as if nothing were cached, not as a crash.
    var items: [ReflectQueueItem] {
        guard let itemsData else { return [] }
        return (try? JSONDecoder().decode([ReflectQueueItem].self, from: itemsData)) ?? []
    }
}
