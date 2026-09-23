import Foundation

// How far back Mind looks. Chosen per launch, never stored as a setting.
nonisolated enum MindWindow: String, CaseIterable, Sendable {
    case month, quarter, year, all

    static let `default` = MindWindow.quarter

    // Fixed lengths rather than calendar months, so a window and the three before it are equal
    // stretches and a share measured in one is comparable with the others. `all` has none.
    var days: Int? {
        switch self {
        case .month: 30
        case .quarter: 90
        case .year: 365
        case .all: nil
        }
    }

    var length: TimeInterval? { days.map { Double($0) * 86_400 } }

    // The stretch ending at `end`, or nil for all time. A date on the start instant belongs to
    // the window before (MindStats reads windows as start-exclusive), so consecutive windows
    // never count one entry twice.
    func interval(endingAt end: Date) -> DateInterval? {
        guard let length else { return nil }
        return DateInterval(start: end.addingTimeInterval(-length), end: end)
    }
}
