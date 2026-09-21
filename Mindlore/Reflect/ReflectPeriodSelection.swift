import Foundation

// Week and month only in v1 (tasks/reflect-spec.md owner decision 2): no custom range, no year
// view. `offset` steps whole periods from now, 0 being the one containing today.
nonisolated enum ReflectPeriodKind: String, CaseIterable, Identifiable, Sendable {
    case week, month

    var id: Self { self }

    var label: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        }
    }

    fileprivate var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

nonisolated struct ReflectPeriodSelection: Hashable, Sendable {
    var kind: ReflectPeriodKind
    var offset: Int = 0

    func interval(now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let anchor = calendar.date(byAdding: kind.component, value: offset, to: now) ?? now
        return calendar.dateInterval(of: kind.component, for: anchor)
            ?? DateInterval(start: anchor, duration: 0)
    }

    // "Week of 14 September 2026" or "September 2026" — a title, not a range; the chart screen
    // itself shows the exact dates covered.
    func title(now: Date = .now, calendar: Calendar = .current) -> String {
        let interval = interval(now: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        switch kind {
        case .week:
            formatter.dateFormat = "d MMMM yyyy"
            return "Week of \(formatter.string(from: interval.start))"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: interval.start)
        }
    }

    // "14 Sep" or "Sep" — an axis tick, not a title.
    func shortLabel(now: Date = .now, calendar: Calendar = .current) -> String {
        let interval = interval(now: now, calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = kind == .week ? "d MMM" : "MMM"
        return formatter.string(from: interval.start)
    }

    // Never past the period containing now: Reflect looks back, not forward.
    var isAtPresent: Bool { offset >= 0 }

    func stepped(by delta: Int) -> ReflectPeriodSelection {
        var next = self
        next.offset = min(0, offset + delta)
        return next
    }
}
