import SwiftData
import SwiftUI

// Everyone and everything the journal has gathered: browse, search, filter by kind, and resolve
// likely duplicates. Merge and hide stay on the entity page itself, unchanged from Phase 5a; this
// screen is how you get there without already knowing a chip to tap.
struct ConnectionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Query(sort: \Entity.name) private var entities: [Entity]
    @State private var search = ""
    @State private var kind: EntityKind?
    @State private var sortOption: ConnectionsPresentation.SortOption = .name
    @State private var suggestions: [EntityMatcher.Suggestion] = []
    @State private var loaded = false
    // Entity pages pushed from a row, by value, so a merge made from one can replace another.
    @State private var path: [EntityRoute] = []

    private struct RefreshKey: Equatable {
        let revision: Int
        let count: Int
    }

    private func refresh() {
        defer { loaded = true }
        suggestions = graph.editor.suggestions(in: modelContext)
    }

    private func entity(_ id: UUID) -> Entity? {
        entities.first { $0.id == id }
    }

    private func row(for entity: Entity) -> ConnectionsPresentation.ConnectionRow {
        .init(id: entity.id, name: entity.name, aliases: entity.aliases, kind: entity.kind, linkCount: entity.linkCount, lastLinkedAt: entity.lastLinkedAt)
    }

    private var visible: [ConnectionsPresentation.ConnectionRow] {
        let rows = entities.filter { !$0.isDeleted && $0.isBrowsable }.map(row)
        return ConnectionsPresentation.sort(ConnectionsPresentation.filter(rows, kind: kind, search: search), by: sortOption)
    }

    private var hiddenRows: [ConnectionsPresentation.ConnectionRow] {
        let rows = entities.filter { !$0.isDeleted && $0.hidden }.map(row)
        return ConnectionsPresentation.sort(ConnectionsPresentation.filter(rows, kind: kind, search: search), by: sortOption)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !suggestions.isEmpty {
                    Section("Review") {
                        ForEach(suggestions.indices, id: \.self) { index in
                            let suggestion = suggestions[index]
                            if let a = entity(suggestion.a), let b = entity(suggestion.b) {
                                ReviewSuggestionRow(a: a, b: b) { same in
                                    saver.flush()
                                    if same {
                                        graph.merge(a.id, into: b.id, in: modelContext)
                                    } else {
                                        graph.markNotSame(a.id, b.id, in: modelContext)
                                    }
                                }
                            }
                        }
                    }
                }
                Section("All") {
                    ForEach(visible) { row in
                        NavigationLink(value: EntityRoute(id: row.id)) {
                            ConnectionRowLabel(row: row)
                        }
                        .accessibilityIdentifier("connectionRow-\(row.name)")
                    }
                }
                if !hiddenRows.isEmpty {
                    Section("Hidden") {
                        ForEach(hiddenRows) { row in
                            NavigationLink(value: EntityRoute(id: row.id)) {
                                ConnectionRowLabel(row: row)
                            }
                            .accessibilityIdentifier("connectionRow-\(row.name)")
                        }
                    }
                }
            }
            .overlay {
                if loaded && suggestions.isEmpty && visible.isEmpty && hiddenRows.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView("No entities yet", systemImage: "person.2")
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .task(id: RefreshKey(revision: graph.revision, count: entities.count)) { refresh() }
            .navigationDestination(for: EntityRoute.self) { EntityView(route: $0) }
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Kind", selection: $kind) {
                            Text("All kinds").tag(EntityKind?.none)
                            ForEach(EntityKind.allCases, id: \.self) { candidate in
                                Label(candidate.heading, systemImage: candidate.symbol).tag(EntityKind?.some(candidate))
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityIdentifier("connectionsKindPicker")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort", selection: $sortOption) {
                            Text("Name").tag(ConnectionsPresentation.SortOption.name)
                            Text("Most mentioned").tag(ConnectionsPresentation.SortOption.mostMentioned)
                            Text("Recent").tag(ConnectionsPresentation.SortOption.recent)
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                    .accessibilityIdentifier("connectionsSortPicker")
                }
            }
            .environment(\.entityRouteReplacer, EntityRouteReplacer { loser, winner in
                path = EntityPagePresentation.replacing(loser, with: winner, in: path)
            })
        }
    }
}

private struct ConnectionRowLabel: View {
    let row: ConnectionsPresentation.ConnectionRow

    var body: some View {
        HStack {
            Label(row.name, systemImage: row.kind.symbol)
            Spacer()
            if row.linkCount > 0 {
                Text("\(row.linkCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// One pair EntityMatcher thinks might be the same thing. "Same" merges the first into the
// second; "Not the same" records it, and EntityMatcher won't suggest the pair again.
private struct ReviewSuggestionRow: View {
    let a: Entity
    let b: Entity
    let decide: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(a.name, systemImage: a.kind.symbol)
                Text("or").foregroundStyle(.secondary)
                Label(b.name, systemImage: b.kind.symbol)
            }
            HStack {
                Button("Same") { decide(true) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("reviewSame-\(a.id)")
                Button("Not the same") { decide(false) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("reviewNotSame-\(a.id)")
            }
        }
    }
}
