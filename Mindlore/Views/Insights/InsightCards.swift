import SwiftUI

extension MoodCategory {
    // A dot only: the mood word and its meaning carry the information, never the color alone.
    var color: Color {
        switch self {
        case .joyful: .orange
        case .calm: .teal
        case .connected: .pink
        case .reflective: .indigo
        case .anxious: .yellow
        case .angry: .red
        case .low: .blue
        case .drained: .gray
        }
    }
}

extension LifeArea {
    var color: Color {
        switch self {
        case .work: .blue
        case .money: .green
        case .health: .red
        case .mind: .indigo
        case .family: .orange
        case .love: .pink
        case .friends: .yellow
        case .play: .purple
        case .home: .brown
        }
    }
}

// An entry's life areas as small labelled capsules, with the user's names and without hidden areas.
struct LifeAreaChips: View {
    @Environment(SettingsStore.self) private var settings
    let areas: [LifeArea]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(areas.filter { !settings.isHidden($0) }, id: \.self) { area in
                HStack(spacing: 5) {
                    Image(systemName: area.symbol)
                        .foregroundStyle(area.color)
                    Text(settings.name(of: area))
                }
                .font(.subheadline)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("lifeArea-\(area.rawValue)")
            }
        }
    }
}

extension MentionKind {
    var symbol: String { EntityKind(self).symbol }
    var heading: String { EntityKind(self).heading }
}

extension EntityKind {
    var symbol: String {
        switch self {
        case .person: "person"
        case .place: "mappin"
        case .organization: "building.2"
        case .project: "hammer"
        case .event: "calendar"
        case .other: "tag"
        case .tag: "number"
        }
    }

    // Plural, for a section of them.
    var heading: String {
        switch self {
        case .person: "People"
        case .place: "Places"
        case .organization: "Organizations"
        case .project: "Projects"
        case .event: "Events"
        case .other: "Other"
        case .tag: "Tags"
        }
    }

    // The graph canvas's node fill, and any kind legend beside it. Seven fixed, visually distinct
    // colours; never derived from anything else, so a kind's colour stays stable across a session.
    var color: Color {
        switch self {
        case .person: .blue
        case .place: .green
        case .organization: .purple
        case .project: .orange
        case .event: .red
        case .tag: .teal
        case .other: .gray
        }
    }

    // Singular, for one entity's kind picker and its page.
    var label: String {
        switch self {
        case .person: "Person"
        case .place: "Place"
        case .organization: "Organization"
        case .project: "Project"
        case .event: "Event"
        case .other: "Other"
        case .tag: "Tag"
        }
    }
}

// One card in the insights list. Its contents can be copied.
struct InsightCard<Content: View>: View {
    let title: String
    var caption: String?
    var copyText: String?
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            content
        } header: {
            Text(title)
        } footer: {
            if let caption {
                Text(caption)
            }
        }
        .contextMenu {
            if let copyText {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = copyText }
            }
        }
    }
}

struct MoodRows: View {
    let primary: Mood?
    let secondary: [Mood]

    var body: some View {
        if let primary {
            VStack(alignment: .leading, spacing: 2) {
                Text("Primary").font(.caption).foregroundStyle(.secondary)
                MoodRow(mood: primary, filled: true)
                Text("\(primary.category.name) · \(primary.category.energy.rawValue) energy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        if !secondary.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Also").font(.caption).foregroundStyle(.secondary)
                ForEach(secondary, id: \.self) { mood in
                    MoodRow(mood: mood, filled: false)
                }
            }
        }
    }
}

private struct MoodRow: View {
    let mood: Mood
    let filled: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: filled ? "circle.fill" : "circle")
                .font(.caption2)
                .foregroundStyle(mood.category.color)
            Text(mood.name).fontWeight(filled ? .semibold : .regular)
            Text(mood.meaning)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled ? "Primary mood" : "Also"), \(mood.name), \(mood.meaning)")
    }
}

// Chips that wrap instead of scrolling sideways, so large text still fits.
struct WrappingChips: View {
    let items: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rows = 1.0
        var x = 0.0
        var rowHeight = 0.0
        var height = 0.0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                height += rowHeight + spacing
                rows += 1
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: height + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight = 0.0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// Names grouped by kind, each one its own chip so it can be opened.
struct MentionGroups: View {
    let mentions: [Mention]
    let entryID: UUID
    let index: EntityChipIndex
    let open: (UUID) -> Void
    let repoint: (MentionRef, UUID) -> Void

    var body: some View {
        ForEach(MentionKind.allCases, id: \.self) { kind in
            let named = mentions.filter { $0.kind == kind }.map(\.name)
            if !named.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(kind.heading, systemImage: kind.symbol)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    EntityChips(
                        values: named,
                        kind: EntityKind(kind),
                        index: index,
                        open: open,
                        repoint: { surface, entityID in
                            repoint(MentionRef(entryID: entryID, surface: surface, kind: EntityKind(kind)), entityID)
                        }
                    )
                }
            }
        }
    }
}

// Values that open their entity's page. Several share one Form row, so each is its own
// borderless button; a row-level tap would otherwise fire all of them.
struct EntityChips: View {
    let values: [String]
    let kind: EntityKind
    let index: EntityChipIndex
    let open: (UUID) -> Void
    // Offered for names only: "this is someone else".
    var repoint: ((String, UUID) -> Void)?

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(values, id: \.self) { value in
                if let chip = index.chip(for: value, kind: kind) {
                    Button { open(chip.entityID) } label: {
                        chipLabel(value, guessed: chip.guessed, unsure: chip.unsure)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(.contextMenuPreview, Capsule())
                    .contextMenu {
                        Button("Open", systemImage: "arrow.right.circle") { open(chip.entityID) }
                        if let repoint {
                            Button("This is someone else", systemImage: "person.crop.circle.badge.questionmark") {
                                repoint(chip.surface, chip.entityID)
                            }
                        }
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
                    }
                    .accessibilityLabel(chip.unsure ? "\(value), unsure which one" : chip.guessed ? "\(value), guessed" : value)
                    .accessibilityHint("Opens its page")
                    .accessibilityIdentifier("entityChip-\(kind.rawValue)-\(value)")
                } else {
                    chipLabel(value, guessed: false, unsure: false)
                        .foregroundStyle(.primary)
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
                        }
                }
            }
        }
    }

    private func chipLabel(_ value: String, guessed: Bool, unsure: Bool) -> some View {
        Text(value)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
            .overlay {
                if guessed {
                    Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .topTrailing) {
                if unsure {
                    Text("?")
                        .font(.caption2.bold())
                        .frame(width: 14, height: 14)
                        .background(.orange, in: Circle())
                        .foregroundStyle(.white)
                        .offset(x: 4, y: -4)
                }
            }
    }
}
