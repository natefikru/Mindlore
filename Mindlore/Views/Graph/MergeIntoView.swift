import SwiftData
import SwiftUI

// Picks the entity this one is the same as. Likely duplicates first, then everything of the
// same kind, then the rest.
struct MergeIntoView: View {
    let entityID: UUID
    let onMerge: (UUID) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(GraphServices.self) private var graph
    @Query(sort: \Entity.name) private var entities: [Entity]
    @State private var search = ""
    @State private var confirming: Entity?

    private var me: Entity? { entities.first { $0.id == entityID } }

    private var candidates: [MergeCandidates.Candidate] {
        let suggested = Set(graph.editor.suggestions(in: modelContext).compactMap { pair -> UUID? in
            if pair.a == entityID { return pair.b }
            if pair.b == entityID { return pair.a }
            return nil
        })
        return MergeCandidates.order(
            entities.filter { !$0.isDeleted && $0.isBrowsable }.map {
                .init(id: $0.id, name: $0.name, kind: $0.kind, linkCount: $0.linkCount, suggested: suggested.contains($0.id))
            },
            excluding: entityID,
            kind: me?.kind ?? .other,
            search: search
        )
    }

    var body: some View {
        NavigationStack {
            List(candidates) { candidate in
                Button {
                    confirming = entities.first { $0.id == candidate.id }
                } label: {
                    HStack {
                        Label(candidate.name, systemImage: candidate.kind.symbol)
                        Spacer()
                        if candidate.suggested {
                            Text("Likely the same")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("mergeCandidate-\(candidate.name)")
            }
            .overlay {
                if candidates.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Merge \(me?.name ?? "") into")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Merge \(me?.name ?? "this") into \(confirming?.name ?? "")?",
                isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                titleVisibility: .visible
            ) {
                Button("Merge") {
                    if let target = confirming {
                        onMerge(target.id)
                        dismiss()
                    }
                }
                .accessibilityIdentifier("confirmMergeButton")
            } message: {
                Text("Its mentions and names move over. You can undo this from the merged page.")
            }
        }
    }
}

nonisolated enum MergeCandidates {
    struct Candidate: Equatable, Identifiable {
        let id: UUID
        let name: String
        let kind: EntityKind
        let linkCount: Int
        let suggested: Bool
    }

    static func order(_ candidates: [Candidate], excluding id: UUID, kind: EntityKind, search: String) -> [Candidate] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates
            .filter { $0.id != id }
            .filter { query.isEmpty || $0.name.localizedStandardContains(query) }
            .sorted { lhs, rhs in
                let left = (lhs.suggested ? 0 : 1, lhs.kind == kind ? 0 : 1, -lhs.linkCount)
                let right = (rhs.suggested ? 0 : 1, rhs.kind == kind ? 0 : 1, -rhs.linkCount)
                if left != right { return left < right }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }
}
