import SwiftData
import SwiftUI

// A tapped name's card as a sheet: card-sized, full height while a page is pushed. It owns
// its stack, so a merge made from a page it pushed redirects this stack's own path.
struct EntityPeekSheet: View {
    let entityID: UUID
    @State private var path: [EntityRoute] = []
    @State private var detent: PresentationDetent = Self.cardDetent

    // Scaled with the text size, like MindView.cardHeight, so the card's content fits.
    static var cardDetent: PresentationDetent { .height(min(UIFontMetrics.default.scaledValue(for: 300), 520)) }

    var body: some View {
        NavigationStack(path: $path) {
            EntityPeekCard(route: EntityRoute(id: entityID)) { path.append($0) }
                .navigationDestination(for: EntityRoute.self) { EntityView(route: $0) }
        }
        .environment(\.entityRouteReplacer, EntityRouteReplacer { loser, winner in
            path = EntityPagePresentation.replacing(loser, with: winner, in: path)
        })
        .presentationDetents([Self.cardDetent, .large], selection: $detent)
        .onChange(of: path.isEmpty) { _, isEmpty in
            detent = isEmpty ? Self.cardDetent : .large
        }
    }
}

// The glance: name and kind, half a year of weekly bars with when it last came up, who it turns up
// with and how often, what is still open about it, and the bio's first line. It never calls
// pageOpened, so looking at a card never starts a bio draft.
struct EntityPeekCard: View {
    let route: EntityRoute
    // Why a focused entity's card is showing without its node: the window or kind leaves it off,
    // or no journal entry names it at all, which no filter will change.
    enum MapHint: Equatable {
        case outsideView
        case notInJournal

        var text: String {
            switch self {
            case .outsideView: "Not on the map in this stretch"
            case .notInJournal: "Only in notes or creative pieces, which stay off the map"
            }
        }
    }

    var mapHint: MapHint?
    let open: (EntityRoute) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph
    @Query private var matches: [Entity]
    @State private var summary: EntityPeekPresentation.Summary?
    @State private var loaded = false

    init(route: EntityRoute, mapHint: MapHint? = nil, open: @escaping (EntityRoute) -> Void) {
        self.route = route
        self.mapHint = mapHint
        self.open = open
        let id = route.id
        _matches = Query(filter: #Predicate<Entity> { $0.id == id })
    }

    private var resolution: EntityPagePresentation.Resolution {
        let entity = matches.first { !$0.isDeleted }
        return EntityPagePresentation.resolve(route, exists: entity != nil, mergedIntoID: entity?.mergedIntoID)
    }

    var body: some View {
        Group {
            switch resolution {
            case .show(let id):
                content(id: id)
                    .task(id: PeekKey(id: id, revision: graph.revision)) {
                        summary = EntityPeekPresentation.load(id, graph: graph, in: modelContext)
                        loaded = true
                    }
            case .gone:
                gone
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("entityPeekCard")
    }

    @ViewBuilder
    private func content(id: UUID) -> some View {
        if let summary {
            // Plain while it fits, so the overlay's swipe up and down keep working; scrolling
            // only when a large text size makes the card taller than its frame. The text stops
            // growing at the second accessibility size, where a name and three lines still fit.
            ViewThatFits(in: .vertical) {
                card(summary, id: id)
                ScrollView { card(summary, id: id) }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if loaded {
            gone
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func card(_ summary: EntityPeekPresentation.Summary, id: UUID) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                // Centre-aligned, not baseline-aligned: a square photo next to .title3 text would
                // sit on the text's baseline and push the Open button down with it. The details
                // line stays below at full width, or the avatar and the button squeeze it into
                // three wrapped lines.
                HStack(spacing: 12) {
                    EntityAvatar(kind: summary.kind, contactIdentifier: summary.contactIdentifier, place: summary.place)
                    Text(summary.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .accessibilityIdentifier("entityPeekName")
                    Spacer(minLength: 8)
                    Button("Open") { open(EntityRoute(id: id)) }
                        .buttonStyle(.borderedProminent)
                        .fixedSize()
                        .accessibilityIdentifier("entityPeekOpen")
                }
                Text(details(summary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                // Side by side when there is room, the words under the bars when there isn't.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 10) {
                        presenceBars(summary)
                        lastMentioned(summary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        presenceBars(summary)
                        lastMentioned(summary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("entityPeekPresence")
                if let mapHint {
                    Text(mapHint.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("entityPeekOffMap")
                }
                if !summary.connections.isEmpty {
                    Text(oftenWith(summary.connections))
                        .font(.subheadline)
                        .lineLimit(3)
                        .accessibilityIdentifier("entityPeekOftenWith")
                }
                if !summary.themes.isEmpty {
                    Text("Themes: " + summary.themes.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("entityPeekThemes")
                }
                if let looseEnd = summary.openLooseEnd {
                    Label(summary.openLooseEndCount > 1 ? "\(summary.openLooseEndCount) open · \(looseEnd)" : looseEnd, systemImage: "circle.dashed")
                        .font(.subheadline)
                        .lineLimit(2)
                        .accessibilityLabel(summary.openLooseEndCount > 1 ? "\(summary.openLooseEndCount) still open, the latest: \(looseEnd)" : "Still open: \(looseEnd)")
                        .accessibilityIdentifier("entityPeekLooseEnd")
                }
                if let bio = summary.bioFirstLine {
                    Text(bio)
                        .lineLimit(2)
                        .accessibilityIdentifier("entityPeekBio")
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func presenceBars(_ summary: EntityPeekPresentation.Summary) -> some View {
        Sparkline(values: summary.series, color: summary.kind.color, recentCount: 4, accessibilityText: presence(summary))
            .frame(width: 160, height: 22)
    }

    @ViewBuilder
    private func lastMentioned(_ summary: EntityPeekPresentation.Summary) -> some View {
        if let last = summary.lastMentioned {
            Text("last mentioned \(EntityPeekPresentation.lastMentionedWords(last, now: .now))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gone: some View {
        ContentUnavailableView("No longer in your journal", systemImage: "person.crop.circle.badge.questionmark")
    }

    private func details(_ summary: EntityPeekPresentation.Summary) -> String {
        let count = summary.recentEntryCount
        let recent = count == 1 ? "1 entry in the last 30 days" : "\(count) entries in the last 30 days"
        return "\(summary.kind.label) · \(recent)"
    }

    // "Often with Danny (14), Mom (9), Omar (6)": the entries each shares with this name.
    private func oftenWith(_ connections: [EntityPeekPresentation.Connection]) -> String {
        "Often with " + connections.map { "\($0.name) (\($0.entries))" }.joined(separator: ", ")
    }

    private func presence(_ summary: EntityPeekPresentation.Summary) -> String {
        let total = summary.series.reduce(0, +)
        return total == 1 ? "1 entry in the last six months" : "\(total) entries in the last six months"
    }
}

private struct PeekKey: Equatable {
    let id: UUID
    let revision: Int
}
