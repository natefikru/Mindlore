import SwiftUI

// The Settings tab: five rows, each its own screen (owner, 2026-09-23), because one Form of eight
// sections ran past two screens. Still organised by what a setting touches, not which subsystem
// owns it: life areas and the name you are written by are journal concepts that work with AI off,
// so they live under Your journal rather than inside AI. Each row carries the one value worth
// seeing without opening it.
struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SyncStatusMonitor.self) private var sync
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @State private var totals = JournalTotals()

    // Today's fingerprint, minus the day: `saver` and `graph` are observable and redraw this view
    // when they move, and `JournalSaves.revision` rides along for the coordinators that save
    // straight through `saveStampingEntries`. Never a count, which an add and a delete can return
    // to where it was.
    private struct TotalsFingerprint: Equatable {
        let saver: Int
        let graph: Int
        let stamped: Int
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    row("General", symbol: "gearshape", value: "iCloud \(sync.status.summary.lowercased())", id: "generalSettingsLink") {
                        GeneralSettingsView()
                    }
                    row("AI", symbol: "sparkles", value: settings.aiEnabled ? "On" : "Off", id: "aiSettingsLink") {
                        AISettingsView()
                    }
                    row("Your journal", symbol: "book", value: nil, id: "journalSettingsLink") {
                        JournalSettingsView()
                    }
                    row("Today and reminders", symbol: "bell", value: reminderSummary, id: "todaySettingsLink") {
                        TodaySettingsView()
                    }
                    row("About", symbol: "info.circle", value: entriesSummary, id: "aboutSettingsLink") {
                        AboutSettingsView(totals: totals)
                    }
                }
            }
            .paperBackground()
            .navigationTitle("Settings")
            .task(id: TotalsFingerprint(saver: saver.revision, graph: graph.revision, stamped: JournalSaves.revision)) {
                totals = JournalTotals.count(in: modelContext)
            }
        }
    }

    private func row<Destination: View>(
        _ title: String,
        symbol: String,
        value: String?,
        id: String,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            LabeledContent {
                if let value { Text(value) }
            } label: {
                Label(title, systemImage: symbol)
            }
        }
        .accessibilityIdentifier(id)
    }

    private var reminderSummary: String {
        guard settings.reminderEnabled else { return "Off" }
        return TodaySettingsView.date(forMinutes: settings.reminderMinutes).formatted(date: .omitted, time: .shortened)
    }

    private var entriesSummary: String {
        totals.entries == 1 ? "1 entry" : "\(totals.entries) entries"
    }
}

// No #Preview: every screen behind these rows reads half the app's environment, and a preview that
// has to build it is worth less than the screenshot test that drives the real thing.
