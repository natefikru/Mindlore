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
    static let identifierPrefix = "dailyReminder-"
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
    static let identifiers = (0..<ReminderPlan.daysAhead).map { "\(ReminderPlan.identifierPrefix)\($0)" }
    static let body = "A moment for today?"

    enum Outcome: Equatable {
        case off
        case scheduled(Int)
        // Switched on in the app, but iOS won't show it: permission was taken away in Settings.
        case notAllowed
    }

    // Set when a reschedule finds permission gone, so Settings can say why the switch went off.
    private(set) var permissionLost = false
    // What Settings says about the reminder, so a day it skipped never looks like one that broke
    // (owner, 2026-09-23: turned it on, saw nothing, and nothing said why). The next one actually
    // scheduled, and whether today went because the user had already written.
    private(set) var next: Date?
    private(set) var skippedToday = false

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
            next = nil
            skippedToday = false
            return .off
        }
        guard await center.isAuthorized() else {
            center.removePendingRequests(withIdentifiers: Self.identifiers)
            next = nil
            skippedToday = false
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
        var first: Date?
        for (index, date) in dates.enumerated() {
            let content = UNMutableNotificationContent()
            content.body = Self.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date),
                repeats: false
            )
            let request = UNNotificationRequest(identifier: Self.identifiers[index], content: content, trigger: trigger)
            if (try? await center.add(request)) != nil {
                added += 1
                first = first ?? date
            }
        }
        next = first
        // Today's slot was still ahead, and only the entry took it away.
        skippedToday = todayHasEntry && ReminderPlan.dates(
            now: now, minutesAfterMidnight: minutesAfterMidnight, todayHasEntry: false, calendar: calendar
        ).first.map { calendar.isDate($0, inSameDayAs: now) } == true
        center.removePendingRequests(withIdentifiers: Array(Self.identifiers.dropFirst(dates.count)))
        diagnostics.record("reminder.scheduled", ["count": .int(added), "allowed": .bool(true), "skippedToday": .bool(todayHasEntry)])
        return .scheduled(added)
    }

    // The line Settings shows above the reminder's rules: "Next: tomorrow at 9:00 PM." Nil when
    // nothing is scheduled, which the switch or the permission sentence already explains.
    static func nextLine(next: Date?, skippedToday: Bool, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let next else { return nil }
        let time = next.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
        let day: String
        if calendar.isDate(next, inSameDayAs: now) {
            day = "today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(next, inSameDayAs: tomorrow) {
            day = "tomorrow"
        } else {
            day = "on " + next.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
        }
        let line = "Next reminder: \(day) at \(time)."
        return skippedToday ? "Not today, since you've already written. " + line : line
    }

    // Anything that reached the app today counts, a draft included: the user showed up.
    static func todayHasEntry(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let start = calendar.startOfDay(for: now)
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.createdAt >= start })
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).contains { !$0.isDeleted }
    }
}

// iOS drops a notification that arrives while its app is open unless a delegate says to show it,
// so without this a reminder set a minute ahead, with Mindlore still on screen, never appeared.
// Held by a static: the centre keeps its delegate weakly, and one made inside `MindloreApp.init`
// would be freed at once, taking the fix with it.
final class ReminderPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderPresenter()

    nonisolated static func presents(_ identifier: String) -> Bool {
        identifier.hasPrefix(ReminderPlan.identifierPrefix)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard Self.presents(notification.request.identifier) else { return [] }
        DiagnosticsLog.shared.record("reminder.presented", ["foreground": .bool(true)])
        return [.banner, .list, .sound]
    }
}
