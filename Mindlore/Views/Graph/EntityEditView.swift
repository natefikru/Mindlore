import MapKit
import SwiftData
import SwiftUI

// The admin half of an entity page, as a sheet from its Edit button: the name and kind, the
// description, the contact or place it links to, the other names it goes by, and hiding it. None
// of it navigates, which is why it can live in a sheet; everything that pushes another page
// (merged rows, Merge into, Show in Mind) stays on the page, where its stack's
// `navigationDestination` and `entityRouteReplacer` are.
struct EntityEditView: View {
    let id: UUID
    // A collision answered with "Merge" merges from here; the page swaps its route to the winner.
    let merged: (UUID) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(\.contactDirectory) private var contacts
    @Query private var matches: [Entity]
    @State private var editingBio = false
    @State private var renaming = false
    @State private var pickingContact = false
    @State private var pickingPlace = false
    @State private var linkedContact: ContactMatch?
    @State private var contactLookedUp = false
    @State private var addingAlias = false
    @State private var draftText = ""
    @State private var collision: UUID?
    @State private var collidingEdit: ((Bool) -> GraphEditor.EditOutcome)?

    init(id: UUID, merged: @escaping (UUID) -> Void) {
        self.id = id
        self.merged = merged
        _matches = Query(filter: #Predicate<Entity> { $0.id == id })
    }

    private var entity: Entity? { matches.first { !$0.isDeleted } }

    var body: some View {
        NavigationStack {
            Group {
                if let entity {
                    Form {
                        Group {
                            nameSection(entity)
                            about(entity)
                            if entity.kind == .person {
                                contactSection(entity)
                            }
                            if entity.kind == .place {
                                placeSection(entity)
                            }
                            aliasesSection(entity)
                            hideSection(entity)
                        }
                        .listRowBackground(Palette.card)
                    }
                    .paperBackground()
                    .sheet(isPresented: $editingBio) {
                        BioEditorSheet(initial: entity.bio ?? "") { text in
                            saver.flush()
                            graph.setBio(text, on: id, in: modelContext)
                        }
                    }
                    .sheet(isPresented: $pickingPlace) {
                        PlacePickerSheet(entityName: entity.name) { match in
                            apply { graph.linkPlace(id, identifier: match.identifier, coordinate: match.coordinate, in: modelContext) }
                        }
                    }
                    .sheet(isPresented: $pickingContact) {
                        ContactPickerSheet(entityName: entity.name) { match in
                            apply { graph.linkContact(id, identifier: match.identifier, in: modelContext) }
                            linkedContact = match
                            contactLookedUp = true
                        }
                    }
                    .sheet(isPresented: $renaming) {
                        RenameEntitySheet(initial: entity.name, kind: entity.kind, rewrites: graph.renamePreview(id, in: modelContext)) { name in
                            applyForcible { force in graph.rename(id, to: name, force: force, in: modelContext) }
                        }
                    }
                } else {
                    ContentUnavailableView("No longer in your journal", systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("entityEditDone")
                }
            }
            .alert("Add another name", isPresented: $addingAlias) {
                TextField("Name", text: $draftText)
                    .accessibilityIdentifier("entityAliasField")
                Button("Add") { applyForcible { force in graph.addAlias(draftText, to: id, force: force, in: modelContext) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Future mentions of this name will link here.")
            }
            .alert(collisionTitle, isPresented: Binding(get: { collision != nil }, set: { if !$0 { collision = nil; collidingEdit = nil } })) {
                Button("Merge") {
                    if let collision { merge(into: collision) }
                    collidingEdit = nil
                }
                if collidingEdit != nil {
                    Button("No, someone else") {
                        _ = collidingEdit?(true)
                        collision = nil
                        collidingEdit = nil
                    }
                }
                Button("Cancel", role: .cancel) { collidingEdit = nil }
            } message: {
                Text("Merge them? Everything that mentions this will link there, and you can undo it from that page.")
            }
        }
        .accessibilityIdentifier("entityEditSheet")
    }

    // MARK: - Edits

    // Every edit starts from saved entries, so the graph's save can't stamp one by accident.
    private func apply(_ edit: () -> GraphEditor.EditOutcome) {
        saver.flush()
        if case .collides(let other) = edit() {
            collision = other
            collidingEdit = nil
        }
    }

    // Rename and alias edits alone can be forced through a collision (5c.3); `edit` is asked with
    // `force: false` first, and a collision keeps the closure around so the alert's "No, someone
    // else" can replay it with `force: true`. `setKind`'s collision is a different, rarer shape
    // and stays on plain `apply`, so it never offers to force one.
    private func applyForcible(_ edit: @escaping (Bool) -> GraphEditor.EditOutcome) {
        saver.flush()
        if case .collides(let other) = edit(false) {
            collision = other
            collidingEdit = edit
        }
    }

    private func merge(into targetID: UUID) {
        saver.flush()
        guard let winnerID = graph.merge(id, into: targetID, in: modelContext) else { return }
        dismiss()
        merged(winnerID)
    }

    private var collisionTitle: String {
        guard let collision, let other = graph.editor.entity(withID: collision, in: modelContext) else {
            return "That name is taken"
        }
        return "\(other.name)\(other.hidden ? " (hidden)" : "") already goes by that name"
    }

    // MARK: - Sections

    private func nameSection(_ entity: Entity) -> some View {
        Section {
            Button {
                renaming = true
            } label: {
                LabeledContent("Name", value: entity.name)
            }
            .accessibilityIdentifier("entityRename")
            let kinds = GraphEditor.kinds(changeableFrom: entity.kind)
            if kinds.count > 1 {
                Picker(selection: Binding(
                    get: { entity.kind },
                    set: { kind in apply { graph.setKind(kind, on: id, in: modelContext) } }
                )) {
                    ForEach(kinds, id: \.self) { kind in
                        Label(kind.label, systemImage: kind.symbol).tag(kind)
                    }
                } label: {
                    Text("Kind")
                }
                .accessibilityIdentifier("entityKind")
            } else {
                LabeledContent("Kind", value: entity.kind.label)
                    .accessibilityIdentifier("entityKind")
            }
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

    // Read-only, and only ever what the user picked. The name and photo are read live from
    // Contacts, so nothing about the contact is stored here but its identifier.
    @ViewBuilder
    private func contactSection(_ entity: Entity) -> some View {
        Section {
            if let identifier = entity.contactIdentifier {
                if let linkedContact {
                    LabeledContent("Contact", value: linkedContact.name)
                        .accessibilityIdentifier("entityContactName")
                } else if contactLookedUp {
                    // Deleted from the phone, or access was narrowed since it was linked. The
                    // identifier is kept either way: granting access again brings it back.
                    Label("Mindlore can't read this contact", systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("entityContactUnreadable")
                } else {
                    ProgressView()
                }
                Button("Unlink", role: .destructive) {
                    apply { graph.unlinkContact(entity.id, in: modelContext) }
                    linkedContact = nil
                }
                .accessibilityIdentifier("entityContactUnlink")
                .task(id: identifier) {
                    contactLookedUp = false
                    linkedContact = await contacts.contact(identifier)
                    contactLookedUp = true
                }
            } else {
                Button {
                    pickingContact = true
                } label: {
                    Label("Link to a contact", systemImage: "person.crop.circle.badge.plus")
                }
                .accessibilityIdentifier("entityContactLink")
            }
        } header: {
            Text("Contact")
        } footer: {
            if entity.contactIdentifier == nil {
                Text("Shows their photo on their page and card. Mindlore reads only the contact you pick.")
            }
        }
    }

    // Linking and unlinking; the map itself is on the page.
    @ViewBuilder
    private func placeSection(_ entity: Entity) -> some View {
        Section {
            if entity.placeCoordinate != nil {
                Button("Unlink", role: .destructive) {
                    apply { graph.unlinkPlace(entity.id, in: modelContext) }
                }
                .accessibilityIdentifier("entityPlaceUnlink")
            } else {
                Button {
                    pickingPlace = true
                } label: {
                    Label("Find this place", systemImage: "mappin.and.ellipse")
                }
                .accessibilityIdentifier("entityPlaceLink")
            }
        } header: {
            Text("Place")
        } footer: {
            if entity.placeCoordinate == nil {
                Text("Shows a map on its page and card, and opens it in Apple Maps.")
            }
        }
    }

    private func aliasesSection(_ entity: Entity) -> some View {
        Section("Also called") {
            if !entity.aliases.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(entity.aliases, id: \.self) { alias in
                        AliasChip(alias: alias, removable: true) {
                            saver.flush()
                            graph.removeAlias(alias, from: id, in: modelContext)
                        }
                    }
                }
            }
            Button("Add another name") {
                draftText = ""
                addingAlias = true
            }
            .accessibilityIdentifier("entityAddAlias")
        }
    }

    private func hideSection(_ entity: Entity) -> some View {
        Section {
            Button(entity.hidden ? "Unhide" : "Hide") {
                saver.flush()
                graph.setHidden(!entity.hidden, on: id, in: modelContext)
            }
            .accessibilityIdentifier("entityHide")
        } footer: {
            Text(entity.hidden
                 ? "Hidden things stay linked but don't appear in insights prompts or lists."
                 : "Hiding keeps its links but leaves it out of lists and of what AI is told about your journal.")
        }
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

// A sheet, not an alert: the rewrite warning doesn't render inside `.alert`'s action builder,
// which is backed by UIAlertController and only really supports buttons and text fields.
private struct RenameEntitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    let initial: String
    let kind: EntityKind
    // What the app would rewrite. Counted off the old name when the sheet opened, so it doesn't
    // change as the user types and doesn't walk the store on every keystroke.
    let rewrites: EntityProseRewriter.Counts
    let onSave: (String) -> Void

    init(initial: String, kind: EntityKind, rewrites: EntityProseRewriter.Counts, onSave: @escaping (String) -> Void) {
        self.initial = initial
        self.kind = kind
        self.rewrites = rewrites
        _name = State(initialValue: initial)
        self.onSave = onSave
    }

    // The same key comparison GraphEditor.rename uses to decide whether the old name is worth
    // keeping, so the note never promises an alias a spelling-only change wouldn't add.
    private var changesKey: Bool {
        EntityNormalizer.key(for: name, kind: kind) != EntityNormalizer.key(for: initial, kind: kind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("entityRenameField")
                } footer: {
                    if changesKey {
                        // "Up to": a background insights pass or bio draft can land while this
                        // sheet is open. What actually changed is counted again at save.
                        Text(footer)
                            .accessibilityIdentifier("entityRenameFooter")
                    }
                }
            }
            .navigationTitle("Rename")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name)
                        dismiss()
                    }
                    .accessibilityIdentifier("entityRenameSave")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var footer: String {
        let kept = "\"\(initial)\" is kept as another name, so entries that say it still point here. Your entries are never changed."
        guard rewrites.total > 0 else { return kept }
        let things = rewrites.total == 1 ? "1 thing" : "\(rewrites.total) things"
        return kept + " Also updates up to \(things) the app wrote about them."
    }
}

// Read-only: reaching the full editor would mean dismissing through however many sheets got the
// user to this entity page (the insights sheet, a name's card, or Mind), each with its own stack.
private struct AliasChip: View {
    let alias: String
    let removable: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(alias)
            if removable {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(alias)")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }
}

