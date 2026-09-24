import SwiftData
import SwiftUI

// Reflect's Life side: what keeps happening, and how it has felt, over a window (owner,
// 2026-09-24). A headline, the areas as bubbles (size is how much you wrote about it, height how
// it felt against your usual), then cards: what keeps coming up, what went quiet, what changed, and
// how loose ends close by area. Every number is `LifeSignals`'; nothing here calls a model.
struct LifeAreaRoute: Hashable {
    let area: LifeArea
    let window: MindWindow
}

struct LifeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SettingsStore.self) private var settings
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph

    @Binding var window: MindWindow
    let openArea: (LifeAreaRoute) -> Void
    let showLooseEnds: () -> Void

    @State private var facts: LifeSource.Facts?
    @State private var reading: LifeSignals.Reading?
    @State private var progress = LifeSignals.Progress(entries: 0, days: 0)
    // A written portrait is the heart of the page and sits under the bubbles; until there is one,
    // its placeholder waits at the end, below everything that stands without AI.
    @State private var hasPortrait = false

    static let windows: [MindWindow] = [.month, .quarter, .year]

    private struct Fingerprint: Equatable {
        let saver: Int
        let graph: Int
        let stamped: Int
        let hidden: Set<String>
    }

    private var fingerprint: Fingerprint {
        Fingerprint(saver: saver.revision, graph: graph.revision, stamped: JournalSaves.revision, hidden: settings.hiddenLifeAreas)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if facts == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if let reading {
                    windowPicker
                    header(reading)
                    LifeBubbleField(reading: reading, name: settings.name(of:)) { area in
                        openArea(LifeAreaRoute(area: area, window: window))
                    }
                    LifePrioritiesCard(reading: reading)
                    if hasPortrait {
                        LifePortraitCard(reading: reading) { hasPortrait = true }
                    }
                    cards(reading)
                    if let facts {
                        LifeExperimentCard(reading: reading, facts: facts)
                    }
                    if !hasPortrait {
                        LifePortraitCard(reading: reading) { hasPortrait = true }
                    }
                } else {
                    LifeNeedsMoreCard(progress: progress)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .paperBackground()
        .task(id: fingerprint) { load() }
        .onChange(of: window) { recompute(animated: true) }
        .accessibilityIdentifier("lifeView")
    }

    private var windowPicker: some View {
        Picker("Window", selection: $window) {
            ForEach(Self.windows, id: \.self) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(Haptics.selected, trigger: window)
        .accessibilityIdentifier("lifeWindowPicker")
    }

    private func header(_ reading: LifeSignals.Reading) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let headline = reading.headline {
                Text(LifeCopy.headline(headline, window: reading.window, name: settings.name(of:)))
                    .journalText(.title2, weight: .semibold)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("lifeHeadline")
            } else {
                Text("Nothing filed under an area \(LifeCopy.windowPhrase(reading.window)).")
                    .journalText(.title3, weight: .semibold)
            }
            Text(LifeCopy.basis(entries: reading.entries, since: reading.interval.start))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func cards(_ reading: LifeSignals.Reading) -> some View {
        let name = settings.name(of:)
        if !reading.recurring.isEmpty {
            LifeCard(title: "Keeps coming up", symbol: "arrow.trianglehead.2.clockwise", tint: Palette.ember) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(reading.recurring) { item in
                        LifeRecurringRow(item: item, interval: reading.interval)
                    }
                }
            }
            .accessibilityIdentifier("lifeRecurring")
        }
        if !reading.quiet.isEmpty {
            LifeCard(title: "Gone quiet", symbol: "moon", tint: .indigo) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(reading.quiet) { quiet in
                        LifeSentenceRow(area: quiet.area, text: LifeCopy.quiet(quiet, window: reading.window, name: name)) {
                            openArea(LifeAreaRoute(area: quiet.area, window: window))
                        }
                    }
                }
            }
            .accessibilityIdentifier("lifeQuiet")
        }
        if !reading.changes.isEmpty {
            LifeCard(title: "What changed", symbol: "arrow.left.arrow.right", tint: .teal) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(reading.changes) { change in
                        LifeSentenceRow(area: change.area, text: LifeCopy.change(change, window: reading.window, name: name)) {
                            openArea(LifeAreaRoute(area: change.area, window: window))
                        }
                    }
                }
            }
            .accessibilityIdentifier("lifeChanges")
        }
        if !reading.thinking.isEmpty {
            LifeCard(title: "How you talk to yourself", symbol: "text.bubble", tint: .indigo) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(reading.thinking) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.pattern.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Text(item.pattern.sounds)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(LifeCopy.thinking(item, window: reading.window, name: name))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Text("Habits of a sentence, not facts about you. Noticing one is usually enough to loosen it.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .accessibilityIdentifier("lifeThinking")
        }
        if !reading.followThrough.isEmpty || reading.openThreads > 0 {
            LifeCard(title: "Loose ends", symbol: "circle.dashed", tint: Palette.ember) {
                VStack(alignment: .leading, spacing: 14) {
                    if let contrast = reading.contrast {
                        Text(LifeCopy.contrast(contrast, name: name))
                            .font(.subheadline)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(reading.followThrough) { follow in
                        LifeFollowRow(follow: follow, name: name(follow.area))
                    }
                    if reading.openThreads > 0 {
                        Button(action: showLooseEnds) {
                            HStack {
                                Text("\(reading.openThreads) still open")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.ember)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lifeOpenThreads")
                    }
                }
            }
            .accessibilityIdentifier("lifeFollowThrough")
        }
    }

    private func load() {
        let started = Date.now
        facts = LifeSource.facts(in: modelContext)
        hasPortrait = LifeWords.portraitForThisMonth(in: modelContext) != nil
        recompute(animated: false)
        LifeDiagnostics.rendered(reading: reading, progress: progress, started: started)
    }

    private func recompute(animated: Bool) {
        guard let facts else { return }
        let next = LifeSignals.reading(entries: facts.entries, threads: facts.threads, window: window, now: .now, hidden: Set(LifeArea.allCases.filter { !settings.visibleLifeAreas.contains($0) }))
        progress = LifeSignals.progress(facts.entries)
        withAnimation(animated ? Motion.resolve(Motion.settle, reduceMotion: reduceMotion) : nil) {
            reading = next
        }
    }
}

// MARK: - The field

struct LifeBubbleField: View {
    let reading: LifeSignals.Reading
    let name: (LifeArea) -> String
    let open: (LifeArea) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    static let height: CGFloat = 320
    // The axis lives in its own strip on the left, so no bubble can sit on its labels.
    static let gutter: CGFloat = 50

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let field = CGSize(width: max(0, size.width - Self.gutter), height: size.height)
            let bubbles = LifeBubbleLayout.layout(reading.areas, in: field).map {
                LifeBubbleLayout.Bubble(area: $0.area, center: CGPoint(x: $0.center.x + Self.gutter, y: $0.center.y), radius: $0.radius)
            }
            let readings = Dictionary(uniqueKeysWithValues: reading.areas.map { ($0.area, $0) })
            ZStack(alignment: .topLeading) {
                usualLine(from: Self.gutter - 6, to: size.width, y: size.height / 2)
                axisLabels(size: size)
                ForEach(Array(bubbles.enumerated()), id: \.element.area) { index, bubble in
                    if let area = readings[bubble.area] {
                        bubbleView(bubble, reading: area)
                            .position(bubble.center)
                            .scaleEffect(appeared || reduceMotion ? 1 : 0.3, anchor: .center)
                            .opacity(appeared ? 1 : 0)
                            .animation(Motion.resolve(Motion.bloom, reduceMotion: reduceMotion)?.delay(Double(index) * Motion.stagger), value: appeared)
                    }
                }
            }
        }
        .frame(height: Self.height)
        .padding(12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Corner.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Corner.card, style: .continuous).strokeBorder(Palette.hairline))
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lifeBubbles")
    }

    private func usualLine(from start: CGFloat, to end: CGFloat, y: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: start, y: y))
            path.addLine(to: CGPoint(x: end, y: y))
        }
        .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
        .accessibilityHidden(true)
    }

    private func axisLabels(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 2) {
                Image(systemName: "arrow.up")
                Text("Lighter")
            }
            .position(x: Self.gutter / 2 - 4, y: 18)
            Text("Usual")
                .position(x: Self.gutter / 2 - 4, y: size.height / 2)
            VStack(spacing: 2) {
                Text("Heavier")
                Image(systemName: "arrow.down")
            }
            .position(x: Self.gutter / 2 - 4, y: size.height - 18)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func bubbleView(_ bubble: LifeBubbleLayout.Bubble, reading: LifeSignals.AreaReading) -> some View {
        let diameter = bubble.radius * 2
        let title = name(bubble.area)
        return Button {
            open(bubble.area)
        } label: {
            ZStack {
                Circle()
                    .fill(bubble.area.color.opacity(0.2).gradient)
                Circle()
                    .strokeBorder(bubble.area.color.opacity(0.55), lineWidth: 1.5)
                VStack(spacing: 1) {
                    if bubble.radius >= 34 {
                        Image(systemName: bubble.area.symbol)
                            .font(.system(size: min(22, bubble.radius * 0.36), weight: .semibold))
                            .foregroundStyle(bubble.area.color)
                    }
                    Text(title)
                        .font(.system(size: max(10, min(16, bubble.radius * 0.3)), weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(LifeCopy.percent(reading.share))
                        .font(.system(size: max(9, min(13, bubble.radius * 0.24)), weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .frame(width: diameter * 0.86)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(LifeBubbleButtonStyle())
        .accessibilityLabel("\(title), \(LifeCopy.percent(reading.share)) of entries, \(LifeCopy.areaLine(reading, name: name))")
        .accessibilityIdentifier("lifeBubble-\(bubble.area.rawValue)")
    }
}

private struct LifeBubbleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Motion.carry, value: configuration.isPressed)
    }
}

// MARK: - Cards

struct LifeCard<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct LifeSentenceRow: View {
    let area: LifeArea
    let text: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: area.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(area.color)
                    .frame(width: 22)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LifeRecurringRow: View {
    let item: LifeSignals.Recurring
    let interval: DateInterval
    @Environment(\.calendar) private var calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.tag)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(LifeCopy.recurringDetail(item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            monthDots
        }
        .accessibilityElement(children: .combine)
    }

    // One dot per month (a year) or week (three months) of the window, filled where it came up.
    private var monthDots: some View {
        let unit: Calendar.Component = item.periodIsMonth ? .month : .weekOfYear
        let periods = Self.periods(of: unit, in: interval, calendar: calendar)
        let present = Set(item.periodStarts)
        return HStack(spacing: item.periodIsMonth ? 4 : 3) {
            ForEach(periods, id: \.self) { start in
                Capsule()
                    .fill(present.contains(start) ? Palette.ember : Color.secondary.opacity(0.18))
                    .frame(height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    static func periods(of unit: Calendar.Component, in interval: DateInterval, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var cursor = calendar.dateInterval(of: unit, for: interval.start)?.start ?? interval.start
        while cursor <= interval.end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}

struct LifeFollowRow: View {
    let follow: LifeSignals.FollowThrough
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(name, systemImage: follow.area.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .labelStyle(LifeTintedLabelStyle(tint: follow.area.color))
                Spacer()
                Text(LifeCopy.followLine(follow))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    segment(follow.resolved, of: follow.closed, width: geometry.size.width, color: follow.area.color)
                    segment(follow.faded, of: follow.closed, width: geometry.size.width, color: Color.secondary.opacity(0.35))
                    segment(follow.dismissed, of: follow.closed, width: geometry.size.width, color: Color.secondary.opacity(0.15))
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func segment(_ count: Int, of total: Int, width: CGFloat, color: Color) -> some View {
        if count > 0, total > 0 {
            Rectangle()
                .fill(color)
                .frame(width: max(4, (width - 4) * CGFloat(count) / CGFloat(total)))
        }
    }
}

struct LifeTintedLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

struct LifeNeedsMoreCard: View {
    let progress: LifeSignals.Progress

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Palette.ember.gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "leaf")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Palette.ember)
            }
            .frame(width: 96, height: 96)
            Text("Life is still reading")
                .font(.title3.weight(.semibold))
            Text(LifeCopy.needsMore(progress))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("lifeNeedsMore")
    }

    private var fraction: CGFloat {
        let entries = Double(progress.entries) / Double(LifeSignals.minimumEntries)
        let days = Double(progress.days) / Double(LifeSignals.minimumDays)
        return CGFloat(max(0.04, min(1, min(entries, days))))
    }
}
