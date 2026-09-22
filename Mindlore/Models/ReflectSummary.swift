import Foundation
import SwiftData

nonisolated enum ReflectSummaryKind: String, CaseIterable, Sendable {
    case week, month
}

// A period's generated queue items, written once and read back on every later view instead of
// asked for again. Every stored property is optional or defaulted and nothing is
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

    init(kind: ReflectSummaryKind, periodStart: Date, generatedAt: Date, items: [ReflectQueueItem]) {
        self.periodKindRaw = kind.rawValue
        self.periodStart = periodStart
        self.generatedAt = generatedAt
        self.itemsData = try? JSONEncoder().encode(items)
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
