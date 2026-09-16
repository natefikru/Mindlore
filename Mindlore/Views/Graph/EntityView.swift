import SwiftData
import SwiftUI

// One entity's page, pushed by value. It holds an id, never an Entity: an edit, a merge, or a
// prune can change what the id means, and the query follows it.
struct EntityView: View {
    let route: EntityRoute
    @Query private var matches: [Entity]

    init(route: EntityRoute) {
        self.route = route
        let id = route.id
        _matches = Query(filter: #Predicate<Entity> { $0.id == id })
    }

    private var resolution: EntityPagePresentation.Resolution {
        let entity = matches.first { !$0.isDeleted }
        return EntityPagePresentation.resolve(route, exists: entity != nil, mergedIntoID: entity?.mergedIntoID)
    }

    var body: some View {
        switch resolution {
        case .show(let id):
            EntityPage(id: id)
                .id(id)
        case .gone:
            ContentUnavailableView(
                "No longer in your journal",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Nothing mentions this any more.")
            )
            .accessibilityIdentifier("entityGone")
        }
    }
}

private struct EntityPage: View {
    let id: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @Query private var matches: [Entity]
    @Query private var links: [EntityLink]
    @Query private var entities: [Entity]
    @State private var editingBio = false

    init(id: UUID) {
        self.id = id
        _matches = Query(filter: #Predicate<Entity> { $0.id == id })
    }

    private var entity: Entity? { matches.first { !$0.isDeleted } }

    var body: some View {
        if let entity {
            Form {
                header(entity)
                about(entity)
                if !entity.aliases.isEmpty {
                    Section("Also called") {
                        WrappingChips(items: entity.aliases)
                    }
                }
                entriesSection
                mergedInSection
            }
            .navigationTitle(entity.name)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("entityPage")
            .onAppear { graph.pageOpened(id, in: modelContext) }
            .sheet(isPresented: $editingBio) {
                BioEditorSheet(initial: entity.bio ?? "") { text in
                    saver.flush()
                    graph.setBio(text, on: id, in: modelContext)
                }
            }
        }
    }

    // MARK: - Sections

    private func header(_ entity: Entity) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label(entity.kind.label, systemImage: entity.kind.symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(EntityPagePresentation.mentionSummary(count: entity.linkCount))
                if let range = EntityPagePresentation.dateRange(first: entity.firstLinkedAt, last: entity.lastLinkedAt) {
                    Text(range)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if entity.hidden {
                    Label("Hidden", systemImage: "eye.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func about(_ entity: Entity) -> some View {
        let state = EntityPagePresentation.bioState(.init(
            bio: entity.bio,
            wasGenerated: entity.bioWasGenerated,
            editedByUser: entity.bioEditedByUser,
            draftedAt: entity.bioDraftedAt,
            sourceEntries: entity.bioSourceEntries,
            modelUsed: entity.bioModelUsed,
            drafting: graph.drafting.contains(id),
            failure: graph.bioFailures[id],
            withoutExcerpts: graph.withoutExcerpts.contains(id),
            textUsable: AIServices.textUsable(settings: settings, accounts: accounts)
        ))
        return Section("About") {
            switch state {
            case .userWritten(let bio):
                Text(bio)
                    .accessibilityIdentifier("entityBio")
                editButton("Edit")
            case .drafted(let bio, let disclosure, let canRedraft):
                VStack(alignment: .leading, spacing: 6) {
                    Text(bio)
                        .accessibilityIdentifier("entityBio")
                    Label(disclosure, systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("entityBioDrafted")
                }
                editButton("Edit")
                if canRedraft { draftButton("Draft again") }
            case .drafting:
                Label {
                    Text("Drafting a description…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("entityBioDrafting")
            case .failed(let message, let canRetry):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("entityBioFailure")
                if canRetry { draftButton("Try again") }
                editButton("Write one")
            case .notEnough(let canDraft):
                Text("Not enough in your entries yet.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("entityBioNotEnough")
                if canDraft { draftButton("Draft") }
                editButton("Write one")
            case .empty(let canDraft):
                if canDraft { draftButton("Draft with AI") }
                editButton("Write one")
            }
        }
    }

    private func editButton(_ title: String) -> some View {
        Button(title) { editingBio = true }
            .accessibilityIdentifier("entityBioEdit")
    }

    private func draftButton(_ title: String) -> some View {
        Button(title) { graph.draftBio(id, in: modelContext) }
            .accessibilityIdentifier("entityBioDraft")
    }

    @ViewBuilder
    private var entriesSection: some View {
        let rows = entryRows
        if !rows.isEmpty {
            Section("Entries") {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.heading).font(.headline)
                            Spacer()
                            if row.guessed {
                                Text("Guessed")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Text(row.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let sentence = row.sentence {
                            Text(sentence)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private var mergedInSection: some View {
        let merged = EntityPagePresentation.mergedIn(
            entities.filter { !$0.isDeleted }.map { .init(id: $0.id, name: $0.name, mergedIntoID: $0.mergedIntoID, mergedAt: $0.mergedAt) },
            into: id
        )
        if !merged.isEmpty {
            Section("Merged into this") {
                ForEach(merged, id: \.id) { loser in
                    NavigationLink(value: EntityRoute(id: loser.id, follow: false)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loser.name)
                            if let mergedAt = loser.mergedAt {
                                Text("Merged \(mergedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // Links by id, one fetch filtered in memory, never through a relationship.
    private var entryRows: [EntityPagePresentation.EntryRow] {
        let mine = links.filter { $0.entityID == id && !$0.isDeleted }
        let byEntry = Dictionary(grouping: mine.compactMap { link in link.entryID.map { ($0, link) } }, by: \.0)
            .mapValues { $0.map(\.1) }
        guard !byEntry.isEmpty else { return [] }
        let ids = Set(byEntry.keys)
        let entries = ((try? modelContext.fetch(FetchDescriptor<Entry>(predicate: #Predicate { ids.contains($0.id) }))) ?? [])
            .filter { !$0.isDeleted }
        return EntityPagePresentation.entryRows(entries.map { entry in
            let links = byEntry[entry.id] ?? []
            return .init(
                entryID: entry.id,
                date: entry.entryDate,
                title: entry.title,
                text: entry.text,
                surfaces: links.map(\.surface),
                guessed: links.contains(where: \.inferred)
            )
        })
    }
}

private struct BioEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    let onSave: (String) -> Void

    init(initial: String, onSave: @escaping (String) -> Void) {
        _text = State(initialValue: initial)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("A line about who or what this is", text: $text, axis: .vertical)
                    .lineLimit(3...10)
                    .accessibilityIdentifier("entityBioField")
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .accessibilityIdentifier("entityBioSave")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
