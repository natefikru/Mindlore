import Foundation
import Observation
import SwiftData
import UserNotifications

// The part of the notification centre the reminder uses, so tests can stand in for it.
protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    // Whether iOS will show a notification now. Separate from asking, because the user can take
    // permission away later in the Settings app without the app hearing about it.
    func isAuthorized() async -> Bool
    // Replaces a pending request with the same identifier.
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

final class SystemNotificationCenter: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()

    // No badge: a count on the icon is a debt, and nothing here keeps score.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorized() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional || status == .ephemeral
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

// Which days get a reminder, decided in one pure pass. A week of single notifications rather than
// one that repeats, because "not if you've already written today" can't be decided when a
// repeating one fires, only when it's scheduled. The app reschedules whenever it's used, so the
// week keeps rolling forward; a journal left alone for a week stops asking.
nonisolated enum ReminderPlan {
    static let daysAhead = 7
    // 9 pm.
    static let defaultMinutes = 21 * 60

    static func dates(now: Date, minutesAfterMidnight: Int, todayHasEntry: Bool, calendar: Calendar) -> [Date] {
        let minutes = min(max(minutesAfterMidnight, 0), 24 * 60 - 1)
        let start = calendar.startOfDay(for: now)
        return (0..<daysAhead).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start),
                  // By hour and minute, not minutes added to midnight, so a clock change that day
                  // doesn't move the reminder by an hour.
                  let at = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
            else { return nil }
            if offset == 0, todayHasEntry || at <= now { return nil }
            return at
        }
    }
}

// The one notification the app sends: once a day at a time the user picks, off until they turn it
// on, skipped on a day they've already written. Its words are fixed and neutral, because a lock
// screen is public: nothing from the journal is ever in it.
@MainActor
@Observable
final class DailyReminder {
    static let identifiers = (0..<ReminderPlan.daysAhead).map { "dailyReminder-\($0)" }
    static let body = "A moment for today?"

    enum Outcome: Equatable {
        case off
        case scheduled(Int)
        // Switched on in the app, but iOS won't show it: permission was taken away in Settings.
        case notAllowed
    }

    // Set when a reschedule finds permission gone, so Settings can say why the switch went off.
    private(set) var permissionLost = false

    @ObservationIgnored private let center: any NotificationScheduling
    @ObservationIgnored private let diagnostics: DiagnosticsLog

    init(center: any NotificationScheduling = SystemNotificationCenter(), diagnostics: DiagnosticsLog = .shared) {
        self.center = center
        self.diagnostics = diagnostics
    }

    func requestPermission() async -> Bool {
        let allowed = await center.requestAuthorization()
        if allowed { permissionLost = false }
        diagnostics.record("reminder.permission", ["allowed": .bool(allowed)])
        return allowed
    }

    // Replaces whatever was scheduled, so calling it again is always safe.
    @discardableResult
    func reschedule(enabled: Bool, minutesAfterMidnight: Int, todayHasEntry: Bool, now: Date = .now, calendar: Calendar = .current) async -> Outcome {
        guard enabled else {
            center.removePendingRequests(withIdentifiers: Self.identifiers)
            return .off
        }
        guard await center.isAuthorized() else {
            center.removePendingRequests(withIdentifiers: Self.identifiers)
            permissionLost = true
            diagnostics.record("reminder.scheduled", ["count": .int(0), "allowed": .bool(false)])
            return .notAllowed
        }
        permissionLost = false

        // New ones first, each replacing the request it shares an identifier with, and only then
        // the ones this week doesn't use. Clearing first would mean an app suspended mid-way, which
        // is likely when this runs on the way to the background, is left with nothing scheduled.
        // Cut short this way, it keeps the old week.
        let dates = ReminderPlan.dates(now: now, minutesAfterMidnight: minutesAfterMidnight, todayHasEntry: todayHasEntry, calendar: calendar)
        var added = 0
        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.body = Self.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: Self.identifiers[index], content: content, trigger: trigger)
            if (try? await center.add(request)) != nil { added += 1 }
        }
        center.removePendingRequests(withIdentifiers: Array(Self.identifiers.dropFirst(dates.count)))
        diagnostics.record("reminder.scheduled", ["count": .int(added), "allowed": .bool(true), "skippedToday": .bool(todayHasEntry)])
        return .scheduled(added)
    }

    // Anything that reached the app today counts, a draft included: the user showed up.
    static func todayHasEntry(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: now)
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.createdAt >= start })
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).contains { !$0.isDeleted }
    }
}
