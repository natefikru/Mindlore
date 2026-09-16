import SwiftData
import SwiftUI

// "This is someone else": moves one mention to another entity, or to a new one, and can make
// the name point there from now on.
struct RepointView: View {
    let mention: MentionRef
    // Where the mention points now, left out of the choices.
    let currentEntityID: UUID?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.entityRouteReplacer) private var routeReplacer
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Query(sort: \Entity.name) private var entities: [Entity]
    @State private var search = ""
    @State private var alsoFuture = false
    @State private var problem: Problem?

    private enum Problem: Identifiable {
        case mentionChanged
        case aliasTaken(entityID: UUID, other: UUID)

        var id: String {
            switch self {
            case .mentionChanged: "changed"
            case .aliasTaken(_, let other): other.uuidString
            }
        }
    }

    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var choices: [Entity] {
        entities.filter { entity in
            !entity.isDeleted && entity.isBrowsable && entity.id != currentEntityID
                && RepointChoices.accepts(entity.kind, for: mention.kind)
                && (query.isEmpty || entity.name.localizedStandardContains(query))
        }
    }

    // A typed name that nothing answers to yet becomes a new entity.
    private var offersNewName: Bool {
        !query.isEmpty && graph.editor.entity(answering: query, kind: mention.kind, in: modelContext) == nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Also for future mentions of \u{201C}\(mention.surface)\u{201D}", isOn: $alsoFuture)
                        .accessibilityIdentifier("repointAlsoFuture")
                }
                if offersNewName {
                    Section {
                        Button {
                            commit(.new(name: query))
                        } label: {
                            Label("New: \(query)", systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier("repointNew")
                    }
                }
                Section(query.isEmpty ? "In your journal" : "Matches") {
                    ForEach(choices) { entity in
                        Button {
                            commit(.existing(entity.id))
                        } label: {
                            Label(entity.name, systemImage: entity.kind.symbol)
                        }
                        .accessibilityIdentifier("repointChoice-\(entity.name)")
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Who or what is it?")
            .navigationTitle("\u{201C}\(mention.surface)\u{201D} is…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(item: $problem) { problem in
                switch problem {
                case .mentionChanged:
                    Alert(
                        title: Text("This mention changed"),
                        message: Text("The insights were made again, and this name isn't there any more."),
                        dismissButton: .default(Text("OK")) { dismiss() }
                    )
                case .aliasTaken(let entityID, let other):
                    Alert(
                        title: Text("\(name(of: other)) already goes by \u{201C}\(mention.surface)\u{201D}"),
                        message: Text("This mention moved, but future ones still go there. Merge them?"),
                        primaryButton: .default(Text("Merge")) {
                            if let winner = graph.merge(entityID, into: other, in: modelContext) {
                                routeReplacer.replace(entityID, winner)
                            }
                            dismiss()
                        },
                        secondaryButton: .cancel(Text("Not now")) { dismiss() }
                    )
                }
            }
        }
    }

    private func commit(_ target: GraphServices.RepointTarget) {
        saver.flush()
        switch graph.repoint(mention, to: target, addingAlias: alsoFuture, in: modelContext) {
        case .applied: dismiss()
        case .mentionChanged: problem = .mentionChanged
        case .aliasCollides(let entityID, let other): problem = .aliasTaken(entityID: entityID, other: other)
        }
    }

    private func name(of id: UUID) -> String {
        guard let entity = graph.editor.entity(withID: id, in: modelContext) else { return "Something else" }
        return entity.name + (entity.hidden ? " (hidden)" : "")
    }
}

nonisolated enum RepointChoices {
    // The same rule the resolver uses: a kind matches itself, and `other` matches any mention.
    static func accepts(_ candidate: EntityKind, for kind: EntityKind) -> Bool {
        switch kind {
        case .tag, .theme: candidate == kind
        default: candidate == kind || candidate == .other || (kind == .other && candidate != .tag && candidate != .theme)
        }
    }
}
