import Foundation

// "Not today" on a Reflect card, the same shape TodayDismissal is, keyed by a period (kind plus
// interval start, not an offset) instead of a day, and never expiring: a week you looked back on
// stays looked back on. Item ids are plain strings here, not ReflectQueueItem itself, so settings
// never depends on Reflect's shape.
nonisolated struct ReflectDismissal: Codable, Equatable, Sendable {
    var dismissed: [String: Set<String>] = [:]

    static func periodKey(kind: ReflectSummaryKind, periodStart: Date) -> String {
        "\(kind.rawValue):\(Int(periodStart.timeIntervalSince1970))"
    }

    func itemIDs(for periodKey: String) -> Set<String> {
        dismissed[periodKey] ?? []
    }

    mutating func dismiss(_ itemID: String, for periodKey: String) {
        dismissed[periodKey, default: []].insert(itemID)
    }
}
