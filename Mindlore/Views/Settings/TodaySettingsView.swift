import SwiftUI

// What the journal brings back on its own: quiet names on Today, and the one daily reminder.
struct TodaySettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(DailyReminder.self) private var reminder
    @State private var reminderDenied = false

    // Turning it on is when iOS asks. A refusal puts the switch back and says where to change it.
    private var reminderToggle: Binding<Bool> {
        Binding(
            get: { settings.reminderEnabled },
            set: { wanted in
                guard wanted else {
                    settings.reminderEnabled = false
                    return
                }
                Task {
                    let allowed = await reminder.requestPermission()
                    reminderDenied = !allowed
                    settings.reminderEnabled = allowed
                }
            }
        )
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { TodaySettingsView.date(forMinutes: settings.reminderMinutes) },
            set: { settings.reminderMinutes = TodaySettingsView.minutes(of: $0) }
        )
    }

    static func date(forMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }

    static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Resurface quiet names", isOn: $settings.resurfacingEnabled)
                    .accessibilityIdentifier("resurfacingToggle")
            } header: {
                Text("Today")
            } footer: {
                Text("Today can mention a person, a place, or a project that hasn't appeared in your journal for a while. You can also turn off a single one from its card.")
            }

            Section {
                Toggle("Daily reminder", isOn: reminderToggle)
                    .accessibilityIdentifier("reminderToggle")
                if settings.reminderEnabled {
                    DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("reminderTime")
                }
            } header: {
                Text("Reminder")
            } footer: {
                Text(reminderDenied || reminder.permissionLost
                     ? "Notifications are off for Mindlore. Turn them on in the Settings app, then try again."
                     : "One a day, skipped when you've already written. It only ever says \u{201C}\(DailyReminder.body)\u{201D}, never anything from your journal.")
            }
        }
        .paperBackground()
        .navigationTitle("Today and Reminders")
        .navigationBarTitleDisplayMode(.inline)
    }
}
