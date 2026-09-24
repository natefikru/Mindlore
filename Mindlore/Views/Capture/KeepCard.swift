import SwiftUI
import SwiftData

// The Keep moment: what the user sees in the seconds after a recording ends. It says the entry is
// safe, shows their first words back to them, and then fills in with what the app noticed as the
// pipeline lands: a title, moods, areas, the people and places, and any loose end this entry closed.
//
// The entry was saved before the card appeared, so the card holds nothing and dismissing it at any
// moment is safe. It reads the entry by id on every refresh and says nothing if the entry is gone.
struct KeepCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(GraphServices.self) private var graph
    @Environment(InsightsCoordinator.self) private var insights
    @Environment(AppRouter.self) private var router
    @Environment(SettingsStore.self) private var settings
    let entryID: UUID

    @State private var entry: Entry?
    @State private var snapshot = KeepSnapshot.empty
    @State private var appeared = false
    @State private var shownAt = Date.now
    @State private var dragOffset: CGFloat = 0
    @State private var openedEntry = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(appeared ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .accessibilityHidden(true)
            if appeared {
                card
                    .offset(y: max(0, dragOffset))
                    .gesture(drag)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .accessibilityAddTraits(.isModal)
        .sensoryFeedback(Haptics.kept, trigger: appeared) { _, new in new }
        .sensoryFeedback(Haptics.insightsLanded, trigger: entry?.insights != nil) { _, new in new }
        .sensoryFeedback(Haptics.looseEndClosed, trigger: snapshot.closed.count) { old, new in new > old }
        .task(id: graph.revision) { refresh() }
        .onAppear {
            refresh()
            shownAt = .now
            DiagnosticsLog.shared.record("keep.shown", KeepCopy.shownFields(entryID: entryID, entry: entry))
            withAnimation(Motion.resolve(Motion.carry, reduceMotion: reduceMotion)) { appeared = true }
        }
        .onDisappear {
            DiagnosticsLog.shared.record("keep.dismissed", KeepCopy.dismissedFields(
                entryID: entryID, entry: entry, snapshot: snapshot, seconds: Date.now.timeIntervalSince(shownAt), openedEntry: openedEntry
            ))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule().fill(.tertiary).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            header
            if let entry {
                words(of: entry)
                noticedSection(for: entry)
            }
            actions
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            // The fill runs under the home indicator; the content stays above it.
            UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous)
                .fill(Palette.card)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(Motion.resolve(Motion.bloom, reduceMotion: reduceMotion), value: snapshot)
        .animation(Motion.resolve(Motion.bloom, reduceMotion: reduceMotion), value: entry?.insights != nil)
        .animation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), value: entry?.title)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keepCard")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(Palette.ember)
                .symbolEffect(.bounce, value: appeared)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kept").font(.title2.weight(.semibold))
                if let entry {
                    Text(KeepCopy.measure(duration: entry.audioDuration, words: KeepCopy.wordCount(entry.text)))
                        .roundedNumerals(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("keepMeasure")
                }
            }
        }
    }

    @ViewBuilder
    private func words(of entry: Entry) -> some View {
        if entry.awaitingText {
            Label("Getting your words", systemImage: "waveform")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .breathing()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !entry.title.isEmpty {
                    Text(entry.title)
                        .journalText(.headline)
                        .transition(.bloom)
                }
                Text(entry.text)
                    .journalText(.callout)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .accessibilityIdentifier("keepWords")
            }
        }
    }

    @ViewBuilder
    private func noticedSection(for entry: Entry) -> some View {
        if let found = entry.insights {
            VStack(alignment: .leading, spacing: 12) {
                let moods = ([found.primaryMood].compactMap { $0 } + found.secondaryMoods).prefix(3)
                if !moods.isEmpty || !found.areas.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(Array(moods), id: \.self) { Text($0.name).chip() }
                        ForEach(found.areas.filter { !settings.isHidden($0) }, id: \.self) { area in
                            Label(settings.name(of: area), systemImage: area.symbol).chip(tint: area.color)
                        }
                    }
                    .transition(.bloom)
                }
                if !snapshot.noticed.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Noticed").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(snapshot.noticed) { noticed in
                            HStack(spacing: 10) {
                                EntityAvatar(kind: noticed.kind, contactIdentifier: noticed.contactIdentifier, size: 28)
                                Text(noticed.name).font(.subheadline)
                                if noticed.isNew {
                                    Text("new").chip(tint: Palette.ember)
                                }
                            }
                            .transition(.bloom)
                        }
                    }
                    .accessibilityIdentifier("keepNoticed")
                }
                ForEach(snapshot.closed) { closed in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "checkmark").foregroundStyle(Palette.ember)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Closed: \(closed.text)").font(.subheadline.weight(.medium))
                            Text("Open since \(closed.openSince.formatted(.dateTime.day().month(.abbreviated)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .transition(.bloom)
                    .accessibilityIdentifier("keepClosed")
                }
                if snapshot.entryOnMap, snapshot.namesOnTheMap > 0, let first = snapshot.noticed.first {
                    Button { router.showInMind(first.id) } label: {
                        HStack {
                            Image(systemName: "circle.hexagongrid")
                            Text(KeepCopy.map(names: snapshot.namesOnTheMap, new: snapshot.newCount))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .font(.subheadline)
                    }
                    .accessibilityIdentifier("keepShowInMind")
                    .transition(.bloom)
                }
            }
        } else if entry.insightsPending {
            if insights.pausedForOffline {
                Text("Insights will arrive when you're online.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Label("Reading", systemImage: "sparkles").font(.subheadline).foregroundStyle(.secondary).breathing()
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("Open entry") {
                openedEntry = true
                router.showEntry(entryID)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("keepOpenEntry")
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("keepDone")
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation.height }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 300 {
                    dismiss()
                } else {
                    withAnimation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion)) { dragOffset = 0 }
                }
            }
    }

    private func dismiss() {
        withAnimation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion)) { router.dismissKeep() }
    }

    private func refresh() {
        let id = entryID
        entry = try? modelContext.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })).first
        guard entry != nil else {
            // Deleted underneath the card (a blank recording, a delete from another path).
            router.dismissKeep()
            return
        }
        snapshot = KeepSnapshot.make(entryID: entryID, links: graph.indexer.allLinks(in: modelContext), in: modelContext)
    }
}

// The card's words, kept apart from the view so they can be tested without one.
enum KeepCopy {
    // What the card logs. Ids, counts, and durations: never the words, a title, a name, or a loose end.
    static func shownFields(entryID: UUID, entry: Entry?) -> [String: DiagnosticValue] {
        ["id": .id(entryID), "hasText": .bool(!(entry?.awaitingText ?? true))]
    }

    static func dismissedFields(entryID: UUID, entry: Entry?, snapshot: KeepSnapshot, seconds: Double, openedEntry: Bool) -> [String: DiagnosticValue] {
        [
            "id": .id(entryID),
            "seconds": .double(seconds),
            "insights": .bool(entry?.insights != nil),
            "noticed": .int(snapshot.noticed.count),
            "new": .int(snapshot.newCount),
            "closed": .int(snapshot.closed.count),
            "openedEntry": .bool(openedEntry),
        ]
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    static func measure(duration: Double?, words: Int) -> String {
        var parts: [String] = []
        if let duration, duration >= 1 {
            let seconds = Int(duration.rounded())
            parts.append(seconds < 60 ? "\(seconds) sec" : "\(seconds / 60) min \(seconds % 60) sec")
        }
        if words > 0 { parts.append(words == 1 ? "1 word" : "\(words) words") }
        return parts.joined(separator: " · ")
    }

    static func map(names: Int, new: Int) -> String {
        let total = names == 1 ? "1 name on your mind map" : "\(names) names on your mind map"
        return new > 0 ? "\(total), \(new) new" : total
    }
}

private struct Breathing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? 0.45 : 1)
            .onAppear {
                guard let animation = Motion.resolve(Motion.breathe, reduceMotion: reduceMotion) else { return }
                withAnimation(animation) { dimmed = true }
            }
    }
}

extension View {
    // Waiting, shown as a slow pulse. Still under Reduce Motion.
    func breathing() -> some View { modifier(Breathing()) }
}
