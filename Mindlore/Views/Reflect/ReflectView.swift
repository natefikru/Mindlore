import Charts
import SwiftData
import SwiftUI

// A look back over a week or a month: where the entries went and how the days felt. Presented as a
// sheet from Today's week strip, its own NavigationStack, no change to AppRouter or the tab bar
// (tasks/reflect-spec.md owner decision 1).
struct ReflectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(ProviderAccountStore.self) private var accounts
    @State private var selection: ReflectPeriodSelection
    @State private var period: ReflectAggregator.Period?
    @State private var trend: [(selection: ReflectPeriodSelection, period: ReflectAggregator.Period)] = []
    @State private var narrative: String?

    init(kind: ReflectPeriodKind = .week) {
        _selection = State(initialValue: ReflectPeriodSelection(kind: kind))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let period {
                    if period.entryCount > 0 {
                        List {
                            if let narrative {
                                Section {
                                    Text(narrative)
                                        .journalText(.body)
                                        .foregroundStyle(Palette.ink)
                                        .accessibilityIdentifier("reflectNarrative")
                                }
                            }
                            Section {
                                areaBalance(period)
                            } header: {
                                Text("Areas")
                            }
                            Section {
                                moodOverTime()
                            } header: {
                                Text("Mood")
                            }
                        }
                        .paperBackground()
                    } else {
                        ContentUnavailableView(
                            "Nothing here",
                            systemImage: "square.dashed",
                            description: Text("No entries in this \(selection.kind == .week ? "week" : "month").")
                        )
                    }
                } else {
                    // Distinct from the empty-period state above: nothing has been fetched yet
                    // (the first appearance, or a cold ModelContainer), not an empty period.
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .top) {
                periodControl
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
            }
            .navigationTitle("Reflect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: fingerprint) { await refresh() }
            .accessibilityIdentifier("reflectView")
        }
    }

    private var periodControl: some View {
        VStack(spacing: 10) {
            Picker("Period", selection: $selection.kind) {
                ForEach(ReflectPeriodKind.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("reflectPeriodKind")
            .onChange(of: selection.kind) { selection.offset = 0 }

            HStack {
                Button {
                    selection = selection.stepped(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityIdentifier("reflectStepBack")

                Spacer()
                Text(selection.title())
                    .font(.system(.subheadline, design: .serif).weight(.medium))
                    .foregroundStyle(Palette.ink)
                    .accessibilityIdentifier("reflectPeriodTitle")
                Spacer()

                Button {
                    selection = selection.stepped(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(selection.isAtPresent)
                .accessibilityIdentifier("reflectStepForward")
            }
        }
    }

    @ViewBuilder
    private func areaBalance(_ period: ReflectAggregator.Period) -> some View {
        let rows = period.areaCounts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }
        if rows.isEmpty {
            Text("No life area on any entry this \(selection.kind == .week ? "week" : "month").")
                .foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(rows, id: \.key) { row in
                    BarMark(
                        x: .value("Entries", row.value),
                        y: .value("Area", settings.name(of: row.key))
                    )
                    .foregroundStyle(row.key.color)
                    .cornerRadius(4)
                }
            }
            .frame(height: CGFloat(rows.count) * 34 + 16)
            .accessibilityIdentifier("reflectAreaChart")
        }
    }

    @ViewBuilder
    private func moodOverTime() -> some View {
        if trend.allSatisfy({ $0.period.moodCounts.isEmpty }) {
            Text("No mood recorded across this stretch.")
                .foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(trend, id: \.selection) { point in
                    ForEach(
                        point.period.moodCounts.sorted { $0.key.rawValue < $1.key.rawValue },
                        id: \.key
                    ) { mood, count in
                        BarMark(
                            x: .value("Period", point.selection.shortLabel()),
                            y: .value("Entries", count)
                        )
                        .foregroundStyle(by: .value("Mood", mood.name))
                    }
                }
            }
            .frame(height: 180)
            .accessibilityIdentifier("reflectMoodChart")
        }
    }

    private struct Fingerprint: Equatable {
        let selection: ReflectPeriodSelection
        let saver: Int
        let graph: Int
        let stamped: Int
    }

    // Keyed the same way Today and Ask key their own cached computation: the three monotonic
    // counters, never a count, so an add-then-delete that returns a period to where it was still
    // triggers a refresh.
    private var fingerprint: Fingerprint {
        Fingerprint(selection: selection, saver: saver.revision, graph: graph.revision, stamped: JournalSaves.revision)
    }

    // One async task per fingerprint change. SwiftUI cancels the running one before starting the
    // next, but that cancellation is cooperative: `ReflectNarrator.narrate` catches every error,
    // including a cancelled request's, and returns nil rather than throwing, so a stale task can
    // still resolve and reach its final assignment after a newer task already finished. Capturing
    // the fingerprint before the await and checking it after is what actually drops that result,
    // the same guard the AI coordinators take against a changed `contentRevision`.
    private func refresh() async {
        let requested = fingerprint
        let computed = ReflectSource.period(selection.interval(), in: modelContext)
        period = computed
        trend = ReflectSource.trend(for: selection, in: modelContext)
        narrative = nil

        guard case .success(let resolved) = AIServices.askGenerator(settings: settings, accounts: accounts) else { return }
        let result = await ReflectNarrator.narrate(
            period: computed,
            kind: selection.kind,
            title: selection.title(),
            provider: resolved,
            voice: settings.promptVoice,
            areaName: { settings.name(of: $0) }
        )
        guard requested == fingerprint else { return }
        narrative = result
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(.inMemory)
    let settings = SettingsStore(store: UserDefaults(suiteName: "preview")!)
    return ReflectView()
        .modelContainer(container)
        .environment(settings)
        .environment(EntrySaver(context: container.mainContext))
        .environment(GraphServices())
        .environment(ProviderAccountStore(settings: settings))
}
