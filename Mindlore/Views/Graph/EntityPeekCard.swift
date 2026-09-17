import SwiftData
import SwiftUI

// A tapped name's card as a sheet: card-sized, full height while a page is pushed. It owns
// its stack, so a merge made from a page it pushed redirects this stack's own path.
struct EntityPeekSheet: View {
    let entityID: UUID
    @State private var path: [EntityRoute] = []
    @State private var detent: PresentationDetent = Self.cardDetent

    static let cardDetent = PresentationDetent.height(220)

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
    let open: (EntityRoute) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(GraphServices.self) private var graph
    @Query private var matches: [Entity]
    @State private var summary: EntityPeekPresentation.Summary?
    @State private var loaded = false

    init(route: EntityRoute, open: @escaping (EntityRoute) -> Void) {
        self.route = route
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
                HStack(alignment: .firstTextBaseline) {
                    Label {
                        Text(summary.name)
                            .font(.title3.weight(.semibold))
                    } icon: {
                        Image(systemName: summary.kind.symbol)
                            .foregroundStyle(summary.kind.color)
                    }
                    .accessibilityIdentifier("entityPeekName")
                    Spacer()
                    Button("Open") { open(EntityRoute(id: id)) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("entityPeekOpen")
                }
                Text(details(summary))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
