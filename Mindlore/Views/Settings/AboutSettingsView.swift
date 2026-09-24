import SwiftUI

// The journal in numbers, whole-journal totals only (anything about a week or a month is
// Reflect's). `JournalTotals` holds the rule: counts, never averages or streaks. A row whose count
// is zero is left out rather than shown as a nought.
struct AboutSettingsView: View {
    let totals: JournalTotals

    var body: some View {
        Form {
            Section {
                count("Entries", totals.entries, id: "totalEntries")
                count("Days written on", totals.days, id: "totalDays")
                if let firstDay = totals.firstDay {
                    LabeledContent("Writing since", value: firstDay.formatted(date: .long, time: .omitted))
                        .accessibilityIdentifier("writingSince")
                }
                count("Words", totals.words, id: "totalWords")
            } header: {
                Text("Your journal")
            }

            section("How they came in", [
                ("Spoken", totals.bySource[.voice] ?? 0),
                ("Typed", totals.bySource[.typed] ?? 0),
                ("Photographed", totals.bySource[.photo] ?? 0),
                ("Page photos", totals.pages),
            ])

            section("What they are", [
                ("Journal entries", totals.byKind[.journal] ?? 0),
                ("Notes", totals.byKind[.note] ?? 0),
                ("Creative pieces", totals.byKind[.creative] ?? 0),
            ])

            Section {
                count("People, places, and more", totals.names, id: "totalNames")
                ForEach(Self.nameRows(totals), id: \.0) { row in
                    count(row.0, row.1)
                }
                if totals.threadsClosed > 0 {
                    count("Loose ends closed", totals.threadsClosed)
                }
                if totals.conversations > 0 {
                    count("Chats", totals.conversations)
                }
            } header: {
                Text("What it knows")
            } footer: {
                Text(Self.version)
                    .accessibilityIdentifier("appVersion")
            }
        }
        .paperBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let nameKinds: [(EntityKind, String)] = [
        (.person, "People"), (.place, "Places"), (.organization, "Organizations"),
        (.project, "Projects"), (.event, "Events"), (.other, "Other"),
    ]

    static func nameRows(_ totals: JournalTotals) -> [(String, Int)] {
        nameKinds.compactMap { kind, title in
            let n = totals.namesByKind[kind] ?? 0
            return n > 0 ? (title, n) : nil
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Mindlore \(short) (\(build))"
    }

    @ViewBuilder
    private func section(_ title: String, _ rows: [(String, Int)]) -> some View {
        let shown = rows.filter { $0.1 > 0 }
        if !shown.isEmpty {
            Section {
                ForEach(shown, id: \.0) { row in count(row.0, row.1) }
            } header: {
                Text(title)
            }
        }
    }

    private func count(_ title: String, _ value: Int, id: String? = nil) -> some View {
        LabeledContent(title, value: value.formatted())
            .accessibilityIdentifier(id ?? title)
    }
}
