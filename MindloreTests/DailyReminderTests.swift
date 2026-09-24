import Foundation
import SwiftData
import Testing
import UserNotifications
@testable import Mindlore

final class FakeNotificationCenter: NotificationScheduling {
    struct Suspended: Error {}

    var allows = true
    // What iOS would say now, which the user can change in the Settings app at any time.
    var authorized = true
    // Every add after this many throws, standing in for the app being suspended mid-way.
    var addsBeforeSuspension: Int?
    private(set) var authorizationRequests = 0
    private(set) var pending: [UNNotificationRequest] = []
    private(set) var removals = 0
    private var adds = 0

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return allows
    }

    func isAuthorized() async -> Bool { authorized }

    // Like the real centre, a request replaces the pending one with its identifier.
    func add(_ request: UNNotificationRequest) async throws {
        if let limit = addsBeforeSuspension, adds >= limit { throw Suspended() }
        adds += 1
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removals += 1
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    var fireDates: [DateComponents] {
        pending.compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents }
    }
}

// Which days, and what it says. The plan is pure; the reminder is tested against a fake centre,
// so nothing here touches the simulator's real notifications.
@MainActor
struct DailyReminderTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private let nine = 21 * 60

    // MARK: - The plan

    @Test func aWeekAheadStartingToday() {
        let dates = ReminderPlan.dates(now: date(2026, 9, 21, hour: 12), minutesAfterMidnight: nine, todayHasEntry: false, calendar: utc)
        #expect(dates.count == 7)
        #expect(dates.first == date(2026, 9, 21, hour: 21))
        #expect(dates.last == date(2026, 9, 27, hour: 21))
    }

    @Test func todayIsSkippedOnceTheUserHasWritten() {
        let dates = ReminderPlan.dates(now: date(2026, 9, 21, hour: 12), minutesAfterMidnight: nine, todayHasEntry: true, calendar: utc)
        #expect(dates.count == 6)
        #expect(dates.first == date(2026, 9, 22, hour: 21))
    }

    @Test func todayIsSkippedOnceItsTimeHasPassed() {
        let dates = ReminderPlan.dates(now: date(2026, 9, 21, hour: 22), minutesAfterMidnight: nine, todayHasEntry: false, calendar: utc)
        #expect(dates.first == date(2026, 9, 22, hour: 21))
    }

    @Test func minutesAreReadAsHourAndMinute() {
        let dates = ReminderPlan.dates(now: date(2026, 9, 21, hour: 6), minutesAfterMidnight: 7 * 60 + 45, todayHasEntry: false, calendar: utc)
        #expect(dates.first == date(2026, 9, 21, hour: 7, minute: 45))
    }

    // A clock change moves "9 pm" in absolute time, never on the wall.
    @Test func aClockChangeDoesNotMoveTheReminder() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // US clocks go back on 1 November 2026.
        let now = try #require(newYork.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 9)))

        let dates = ReminderPlan.dates(now: now, minutesAfterMidnight: nine, todayHasEntry: false, calendar: newYork)
        #expect(dates.allSatisfy { newYork.component(.hour, from: $0) == 21 && newYork.component(.minute, from: $0) == 0 })
    }

    @Test func anOutOfRangeTimeIsClamped() {
        let late = ReminderPlan.dates(now: date(2026, 9, 21, hour: 1), minutesAfterMidnight: 99_999, todayHasEntry: false, calendar: utc)
        #expect(late.first == date(2026, 9, 21, hour: 23, minute: 59))
        let early = ReminderPlan.dates(now: date(2026, 9, 21, hour: 1), minutesAfterMidnight: -5, todayHasEntry: false, calendar: utc)
        #expect(early.first == date(2026, 9, 22, hour: 0), "midnight today has already passed")
    }

    // MARK: - Scheduling

    @Test func offSchedulesNothingAndClearsWhatWasThere() async {
        let center = FakeNotificationCenter()
        let reminder = DailyReminder(center: center, diagnostics: .disabled)
        await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)
        #expect(!center.pending.isEmpty)

        await reminder.reschedule(enabled: false, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)
        #expect(center.pending.isEmpty)
    }

    @Test func onSchedulesAWeekOfSingleReminders() async {
        let center = FakeNotificationCenter()
        let reminder = DailyReminder(center: center, diagnostics: .disabled)

        await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)

        #expect(center.pending.count == 7)
        #expect(center.pending.allSatisfy { ($0.trigger as? UNCalendarNotificationTrigger)?.repeats == false })
        #expect(Set(center.pending.map(\.identifier)).isSubset(of: Set(DailyReminder.identifiers)))
        #expect(center.fireDates.first?.day == 21)
        #expect(center.fireDates.first?.hour == 21)
    }

    // Writing today and then leaving the app is what reschedules; today's reminder is gone.
    @Test func reschedulingAfterWritingDropsToday() async {
        let center = FakeNotificationCenter()
        let reminder = DailyReminder(center: center, diagnostics: .disabled)
        await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)

        await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: true, now: date(2026, 9, 21, hour: 13), calendar: utc)

        #expect(center.pending.count == 6)
        #expect(!center.fireDates.contains { $0.day == 21 })
    }

    // Going to the background is when this usually runs, and the app can be suspended mid-way.
    // Clearing first would leave nothing; adding first leaves the old week standing.
    @Test func aRescheduleCutShortNeverLeavesNothing() async {
        let center = FakeNotificationCenter()
        let reminder = DailyReminder(center: center, diagnostics: .disabled)
        await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)
        #expect(center.pending.count == 7)

        center.addsBeforeSuspension = center.pending.count + 2
        await reminder.reschedule(enabled: true, minutesAfterMidnight: 8 * 60, todayHasEntry: false, now: date(2026, 9, 21, hour: 6), calendar: utc)

        #expect(center.pending.count == 7, "two replaced, five from the old week, none lost")
        #expect(center.fireDates.contains { $0.hour == 8 })
        #expect(center.fireDates.contains { $0.hour == 21 })
    }

    // Permission can be taken away in the Settings app. A reminder iOS won't show is reported, not
    // scheduled into nothing.
    @Test func permissionTakenAwayLaterIsNoticed() async {
        let center = FakeNotificationCenter()
        let reminder = DailyReminder(center: center, diagnostics: .disabled)
        await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)
        #expect(!reminder.permissionLost)

        center.authorized = false
        let outcome = await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)

        #expect(outcome == .notAllowed)
        #expect(center.pending.isEmpty)
        #expect(reminder.permissionLost, "so Settings can say why")
    }

    @Test func permissionGivenBackClearsTheNotice() async {
        let center = FakeNotificationCenter()
        center.authorized = false
        let reminder = DailyReminder(center: center, diagnostics: .disabled)
        await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)
        #expect(reminder.permissionLost)

        #expect(await reminder.requestPermission())
        #expect(!reminder.permissionLost)
    }

    @Test func offNeverAsksWhetherItsAllowed() async {
        let center = FakeNotificationCenter()
        center.authorized = false
        let reminder = DailyReminder(center: center, diagnostics: .disabled)

        let outcome = await reminder.reschedule(enabled: false, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)

        #expect(outcome == .off)
        #expect(!reminder.permissionLost, "a switch that's off has nothing to lose")
    }

    @Test func reschedulingTwiceLeavesOneWeekNotTwo() async {
        let center = FakeNotificationCenter()
        let reminder = DailyReminder(center: center, diagnostics: .disabled)
        for _ in 0..<3 {
            await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)
        }
        #expect(center.pending.count == 7)
    }

    // A lock screen is public: the words are fixed, and nothing from the journal is in them.
    @Test func itSaysOnlyTheFixedLine() async {
        let center = FakeNotificationCenter()
        let reminder = DailyReminder(center: center, diagnostics: .disabled)
        await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)

        #expect(center.pending.allSatisfy { $0.content.body == DailyReminder.body && $0.content.title.isEmpty && $0.content.subtitle.isEmpty })
        #expect(center.pending.allSatisfy { $0.content.badge == nil }, "no badge: a count on the icon is a debt")
    }

    @Test func permissionIsAskedOnlyWhenRequested() async {
        let center = FakeNotificationCenter()
        let reminder = DailyReminder(center: center, diagnostics: .disabled)
        await reminder.reschedule(enabled: false, minutesAfterMidnight: nine, todayHasEntry: false, now: date(2026, 9, 21), calendar: utc)
        #expect(center.authorizationRequests == 0)

        center.allows = false
        #expect(await reminder.requestPermission() == false)
        #expect(center.authorizationRequests == 1)
    }

    // MARK: - Today

    @Test func anEntryCreatedTodayCounts() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let now = date(2026, 9, 21, hour: 15)
        #expect(!DailyReminder.todayHasEntry(in: context, now: now, calendar: utc))

        let yesterday = Entry(text: "yesterday")
        yesterday.createdAt = date(2026, 9, 20, hour: 22)
        context.insert(yesterday)
        try context.save()
        #expect(!DailyReminder.todayHasEntry(in: context, now: now, calendar: utc))

        let today = Entry(text: "")
        today.createdAt = date(2026, 9, 21, hour: 8)
        context.insert(today)
        try context.save()
        #expect(DailyReminder.todayHasEntry(in: context, now: now, calendar: utc))
    }

    // MARK: - Settings

    @Test func theReminderIsOffAtNineByDefault() {
        let settings = SettingsStore(store: FakeKeyValueStore(), diagnostics: .disabled)
        #expect(settings.reminderEnabled == false)
        #expect(settings.reminderMinutes == ReminderPlan.defaultMinutes)
    }

    @Test func theReminderSettingsSurviveARelaunch() {
        let store = FakeKeyValueStore()
        let settings = SettingsStore(store: store, diagnostics: .disabled)
        settings.reminderEnabled = true
        settings.reminderMinutes = 7 * 60 + 30

        let reopened = SettingsStore(store: store, diagnostics: .disabled)
        #expect(reopened.reminderEnabled)
        #expect(reopened.reminderMinutes == 7 * 60 + 30)
    }

    @Test func theTimePickerRoundTrips() {
        let minutes = 18 * 60 + 5
        #expect(TodaySettingsView.minutes(of: TodaySettingsView.date(forMinutes: minutes, calendar: utc), calendar: utc) == minutes)
    }

    // MARK: - Privacy

    @Test func theLogCarriesCountsOnly() async throws {
        let file = URL.temporaryDirectory.appending(path: "reminder-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: file) }
        let reminder = DailyReminder(center: FakeNotificationCenter(), diagnostics: DiagnosticsLog(fileURL: file))

        _ = await reminder.requestPermission()
        await reminder.reschedule(enabled: true, minutesAfterMidnight: nine, todayHasEntry: true, now: date(2026, 9, 21), calendar: utc)

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written.contains("reminder.permission"))
        #expect(written.contains("reminder.scheduled"))
        #expect(!written.contains(DailyReminder.body), "not even the fixed line")
    }
}
