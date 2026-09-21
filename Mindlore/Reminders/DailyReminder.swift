import Foundation
import Observation
import SwiftData
import UserNotifications

// The part of the notification centre the reminder uses, so tests can stand in for it.
protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

final class SystemNotificationCenter: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()

    // No badge: a count on the icon is a debt, and nothing here keeps score.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
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

    @ObservationIgnored private let center: any NotificationScheduling
    @ObservationIgnored private let diagnostics: DiagnosticsLog

    init(center: any NotificationScheduling = SystemNotificationCenter(), diagnostics: DiagnosticsLog = .shared) {
        self.center = center
        self.diagnostics = diagnostics
    }

    func requestPermission() async -> Bool {
        let allowed = await center.requestAuthorization()
        diagnostics.record("reminder.permission", ["allowed": .bool(allowed)])
        return allowed
    }

    // Replaces whatever was scheduled, so calling it again is always safe.
    func reschedule(enabled: Bool, minutesAfterMidnight: Int, todayHasEntry: Bool, now: Date = .now, calendar: Calendar = .current) async {
        center.removePendingRequests(withIdentifiers: Self.identifiers)
        guard enabled else { return }

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
        diagnostics.record("reminder.scheduled", ["count": .int(added), "skippedToday": .bool(todayHasEntry)])
    }

    // Anything that reached the app today counts, a draft included: the user showed up.
    static func todayHasEntry(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: now)
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.createdAt >= start })
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).contains { !$0.isDeleted }
    }
}
