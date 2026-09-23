import SwiftData
import SwiftUI

// Adds a name the insights missed to one entry: someone already in the journal, or someone new.
// Works with AI off, since it only writes a link the user owns.
struct AddNameView: View {
    let entry: Entry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Query(sort: \Entity.name) private var entities: [Entity]
    @State private var name = ""
    @State private var kind: EntityKind = .person
    @FocusState private var nameFocused: Bool

    private var query: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    // Everything browsable whose name or alias holds what was typed, best match first.
    private var matches: [Entity] {
        guard !query.isEmpty else { return [] }
        let rows = entities.filter { !$0.isDeleted && $0.isBrowsable }.map {
            EntitySearch.Row(id: $0.id, name: $0.name, aliases: $0.aliases, kind: $0.kind, linkCount: $0.linkCount, lastMentioned: $0.lastLinkedAt)
        }
        let byID = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return EntitySearch.rank(EntitySearch.filter(rows, segment: .all, query: query), query: query)
            .prefix(8)
            .compactMap { byID[$0.id] }
    }

    // What Add would land on: a typed name something already answers to is that entity, not a new one.
    private var existingForTyped: Entity? {
        query.isEmpty ? nil : graph.editor.entity(answering: query, kind: kind, in: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addTyped)
                        .accessibilityIdentifier("addNameField")
                    Picker("Kind", selection: $kind) {
                        ForEach(Self.kinds, id: \.self) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    .accessibilityIdentifier("addNameKind")
                } footer: {
                    if let existing = existingForTyped {
                        Text("This will link \(existing.name), already in your journal.")
                    } else {
                        Text("Adds this name to the entry and to Mind. It stays if insights run again.")
                    }
                }
                if !matches.isEmpty {
                    Section("Already in your journal") {
                        ForEach(matches) { entity in
                            Button {
                                add(.existing(entity.id))
                            } label: {
                                Label(entity.name, systemImage: entity.kind.symbol)
                                    .foregroundStyle(Palette.ink)
                            }
                            .accessibilityIdentifier("addNameMatch-\(entity.name)")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Add a name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: addTyped)
                        .disabled(query.isEmpty)
                        .accessibilityIdentifier("addNameConfirm")
                }
            }
            .onAppear { nameFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    static let kinds: [EntityKind] = [.person, .place, .organization, .project, .event, .other, .tag]

    private func addTyped() {
        guard !query.isEmpty else { return }
        add(.new(name: query, kind: kind))
    }

    private func add(_ target: GraphServices.AddedNameTarget) {
        saver.flush()
        graph.addName(target, to: entry, in: modelContext)
        dismiss()
    }
}
