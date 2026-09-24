import SwiftData
import SwiftUI

// Something to try: one experiment drawn from the author's own lighter weeks, and how the ones
// they picked have gone. The one place in the app that suggests anything (owner, 2026-09-24),
// and only ever this: a small thing their own journal says went with better weeks, offered once.
// Hidden while the portrait has set itself aside out of concern.
struct LifeExperimentCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SettingsStore.self) private var settings
    @Environment(EntrySaver.self) private var saver

    let reading: LifeSignals.Reading
    let facts: LifeSource.Facts

    @State private var suggestion: LifeSignals.Suggestion?
    @State private var trying: [LifeExperiments.Experiment] = []
    @State private var concern = false
    @State private var accepted = 0

    var body: some View {
        Group {
            if !concern, suggestion != nil || !trying.isEmpty {
                LifeCard(title: "Something to try", symbol: "flask", tint: .teal) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let suggestion { offer(suggestion) }
                        ForEach(trying) { experiment in
                            report(experiment)
                        }
                    }
                    .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: suggestion)
                }
                .accessibilityIdentifier("lifeExperiment")
            }
        }
        .task(id: reading.entries) { load() }
        .sensoryFeedback(Haptics.kept, trigger: accepted)
    }

    private func offer(_ suggestion: LifeSignals.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LifeCopy.suggestion(suggestion, name: settings.name(of:)))
                .font(.body)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Try it this week") { accept(suggestion) }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)
                    .accessibilityIdentifier("lifeExperimentAccept")
                Button("Not this") { decline(suggestion) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("lifeExperimentDecline")
            }
            Text("It becomes a loose end due Sunday, and Life tells you how those weeks went.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func report(_ experiment: LifeExperiments.Experiment) -> some View {
        let tried = LifeSignals.tried(experiment.subject, since: experiment.since, entries: facts.entries, baseline: reading.baseline, now: .now)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "flask.fill")
                .foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(LifeCopy.subject(experiment.subject, name: settings.name(of:)).capitalized)
                    .font(.subheadline.weight(.semibold))
                Text(LifeCopy.tried(tried, subject: experiment.subject, name: settings.name(of:)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func load() {
        concern = LifeWords.portraitForThisMonth(in: modelContext)?.concern == true
        let all = LifeExperiments.all(in: modelContext)
        trying = Array(all.filter { $0.state == .trying }.prefix(3))
        // One experiment at a time: nothing new is offered while this week's is still open.
        let openThisWeek = trying.contains { Date.now.timeIntervalSince($0.since) < 7 * 86_400 }
        suggestion = openThisWeek ? nil : LifeSignals.suggestion(
            facts.entries,
            interval: reading.interval,
            baseline: reading.baseline,
            skipping: Set(all.map(\.subject)),
            hidden: Set(LifeArea.allCases.filter { !settings.visibleLifeAreas.contains($0) })
        )
    }

    private func accept(_ suggestion: LifeSignals.Suggestion) {
        saver.flush()
        LifeExperiments.accept(suggestion, threadText: LifeCopy.experimentThread(suggestion.subject, name: settings.name(of:)), in: modelContext)
        accepted += 1
        load()
    }

    private func decline(_ suggestion: LifeSignals.Suggestion) {
        LifeExperiments.decline(suggestion.subject, in: modelContext)
        load()
    }
}
