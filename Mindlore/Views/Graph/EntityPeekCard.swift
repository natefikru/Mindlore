import SwiftData
import SwiftUI

// A tapped name's card as a sheet: card-sized, full height while a page is pushed. It owns
// its stack, so a merge made from a page it pushed redirects this stack's own path.
struct EntityPeekSheet: View {
    let entityID: UUID
    @State private var path: [EntityRoute] = []
    @State private var detent: PresentationDetent = Self.cardDetent

    // Scaled with the text size, like MindView.cardHeight, so the card's content fits.
    static var cardDetent: PresentationDetent { .height(min(UIFontMetrics.default.scaledValue(for: 220), 420)) }

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

// The glance: name, kind, the bio's first line, and how recently the journal mentions it. It
// never calls pageOpened, so looking at a card never starts a bio draft.
struct EntityPeekCard: View {
    let route: EntityRoute
    // Mind shows a focused entity's card even when its filters leave the entity off the map.
    var showsMapHint = false
    let open: (EntityRoute) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph
    @Query private var matches: [Entity]
    @State private var summary: EntityPeekPresentation.Summary?
    @State private var loaded = false

    init(route: EntityRoute, showsMapHint: Bool = false, open: @escaping (EntityRoute) -> Void) {
        self.route = route
        self.showsMapHint = showsMapHint
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
                        .accessibilityIdentifier("entityPeekOpen")
                }
                Text(details(summary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if showsMapHint {
                    Text("Not on the map with these filters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("entityPeekOffMap")
                }
                if let looseEnd = summary.openLooseEnd {
                    Label(looseEnd, systemImage: "circle.dashed")
                        .font(.subheadline)
                        .lineLimit(1)
                        .accessibilityLabel("Still open: \(looseEnd)")
                        .accessibilityIdentifier("entityPeekLooseEnd")
                }
                if let bio = summary.bioFirstLine {
                    Text(bio)
                        .lineLimit(2)
                        .accessibilityIdentifier("entityPeekBio")
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if loaded {
            gone
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var gone: some View {
        ContentUnavailableView("No longer in your journal", systemImage: "person.crop.circle.badge.questionmark")
    }

    private func details(_ summary: EntityPeekPresentation.Summary) -> String {
        var parts = [summary.kind.label]
        if let last = summary.lastMentioned {
            parts.append("last mentioned \(last.formatted(date: .abbreviated, time: .omitted))")
        }
        let count = summary.recentEntryCount
        parts.append(count == 1 ? "1 entry in the last 30 days" : "\(count) entries in the last 30 days")
        return parts.joined(separator: " · ")
    }
}

private struct PeekKey: Equatable {
    let id: UUID
    let revision: Int
}
