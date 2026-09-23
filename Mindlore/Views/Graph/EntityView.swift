import MapKit
import SwiftData
import SwiftUI

// Lets a page swap its own route after a merge it made. The sheet that owns the path sets it.
struct EntityRouteReplacer {
    var replace: (_ loserID: UUID, _ winnerID: UUID) -> Void = { _, _ in }
}

extension EnvironmentValues {
    @Entry var entityRouteReplacer = EntityRouteReplacer()
}

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
            EntityPage(id: id, showsLoser: id == route.id && !route.follow)
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
    // Reached from a "Merged into this" row: the page is about the merged entity itself.
    let showsLoser: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.entityRouteReplacer) private var routeReplacer
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(AppRouter.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(\.contactDirectory) private var contacts
    @Query private var matches: [Entity]
    @Query private var links: [EntityLink]
    @Query private var entities: [Entity]
    @Query(sort: \LooseEnd.lastMentionedAt, order: .reverse) private var allLooseEnds: [LooseEnd]
    @State private var showsEarlierLooseEnds = false
    @State private var looseEndSplit = LooseEndSplit()
    @State private var editingBio = false
    @State private var renaming = false
    @State private var pickingContact = false
    @State private var pickingPlace = false
    @State private var linkedContact: ContactMatch?
    @State private var contactLookedUp = false
    @State private var addingAlias = false
    @State private var draftText = ""
    @State private var merging = false
    @State private var collision: UUID?
    @State private var collidingEdit: ((Bool) -> GraphEditor.EditOutcome)?
    @State private var repointing: MentionRef?
    @State private var previewingRow: EntityPagePresentation.EntryRow?
    @State private var showsEntries = false
    @State private var showsAllPartners = false
    @State private var coOccurring: [EntityPagePresentation.CoOccurrenceRow] = []

    init(id: UUID, showsLoser: Bool) {
        self.id = id
        self.showsLoser = showsLoser
        _matches = Query(filter: #Predicate<Entity> { $0.id == id })
    }

    private var entity: Entity? { matches.first { !$0.isDeleted } }

    var body: some View {
        if let entity {
            // Still a Form: its sections are already rounded cards, and the rows carry swipe actions,
            // a disclosure, and links that a hand-built card would lose. Paper behind and card-coloured
            // rows are what make it read as the rest of the app.
            Form {
                Group {
                    header(entity)
                    if let winnerID = entity.mergedIntoID {
                        mergedAwaySection(entity, into: winnerID)
                    }
                    about(entity)
                    looseEndsSection
                    if entity.kind == .person, !entity.isMerged {
                        contactSection(entity)
                    }
                    if entity.kind == .place, !entity.isMerged {
                        placeSection(entity)
                    }
                    aliasesSection(entity)
                    entriesSection
                    mentionedWithSection
                    mergedInSection
                    if !entity.isMerged {
                        actionsSection(entity)
                    }
                }
                .listRowBackground(Palette.card)
            }
            .paperBackground()
            .navigationTitle(entity.name)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("entityPage")
            .onAppear {
                if !showsLoser { graph.pageOpened(id, in: modelContext) }
            }
            .task(id: looseEndKey) { loadLooseEnds() }
            .task(id: graph.revision) {
                coOccurring = EntityPagePresentation.coOccurrenceRows(graph.mentionedWith(of: id, in: modelContext, limit: .max))
            }
            .sheet(isPresented: $editingBio) {
                BioEditorSheet(initial: entity.bio ?? "") { text in
                    saver.flush()
                    graph.setBio(text, on: id, in: modelContext)
                }
            }
            .sheet(isPresented: $merging) {
                MergeIntoView(entityID: id) { targetID in
                    saver.flush()
                    merge(into: targetID)
                }
            }
            .sheet(item: $repointing) { mention in
                RepointView(mention: mention, currentEntityID: id)
            }
            .sheet(item: $previewingRow) { row in
                EntryPreview(entryID: row.id)
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
    // (out of scope here) and stays on plain `apply`, so it never offers to force one.
    private func applyForcible(_ edit: @escaping (Bool) -> GraphEditor.EditOutcome) {
        saver.flush()
        if case .collides(let other) = edit(false) {
            collision = other
            collidingEdit = edit
        }
    }

    private func merge(into targetID: UUID) {
        guard let winnerID = graph.merge(id, into: targetID, in: modelContext) else { return }
        routeReplacer.replace(id, winnerID)
    }

    private var collisionTitle: String {
        guard let collision, let other = graph.editor.entity(withID: collision, in: modelContext) else {
            return "That name is taken"
        }
        return "\(other.name)\(other.hidden ? " (hidden)" : "") already goes by that name"
    }

    // MARK: - Sections

    private func header(_ entity: Entity) -> some View {
        Section {
            if EntityPagePresentation.showsSpellingPrompt(confirmedByUser: entity.confirmedByUser, linkCount: entity.linkCount, kind: entity.kind) {
                Button {
                    renaming = true
                } label: {
                    Label("Spelled right? \(entity.name)", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("entitySpellingPrompt")
            }
            HStack(alignment: .top, spacing: 12) {
                EntityAvatar(kind: entity.kind, contactIdentifier: entity.contactIdentifier, place: entity.placeCoordinate, size: 52)
                VStack(alignment: .leading, spacing: 4) {
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
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if !entity.isMerged {
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
    }

    private func mergedAwaySection(_ entity: Entity, into winnerID: UUID) -> some View {
        Section {
            let winner = graph.editor.entity(withID: winnerID, in: modelContext)
            Text("Merged into \(winner?.name ?? "another entry")\(entity.mergedAt.map { " on \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "").")
            Button("Undo merge") {
                saver.flush()
                graph.unmerge(id, in: modelContext)
            }
            .accessibilityIdentifier("entityUnmerge")
        }
    }

    // Where this place actually is, with a handoff to Apple Maps. The preview is drawn from the
    // coordinate every time rather than stored.
    @ViewBuilder
    private func placeSection(_ entity: Entity) -> some View {
        Section {
            if let coordinate = entity.placeCoordinate {
                PlaceMapPreview(coordinate: coordinate)
                    .frame(height: 140)
                    .listRowInsets(EdgeInsets())
                    .accessibilityIdentifier("entityPlaceMap")
                Button {
                    Task {
                        let item = await MKPlaceDirectory.mapItem(
                            identifier: entity.placeIdentifier,
                            coordinate: coordinate,
                            name: entity.name
                        )
                        item.openInMaps()
                    }
                } label: {
                    Label("Open in Apple Maps", systemImage: "map")
                }
                .accessibilityIdentifier("entityPlaceOpenMaps")
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
                Text("Shows a map here and on its card, and opens it in Apple Maps.")
            }
        }
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
                Text("Shows their photo here and on their card. Mindlore reads only the contact you pick.")
            }
        }
    }

    @ViewBuilder
    private func aliasesSection(_ entity: Entity) -> some View {
        if !entity.aliases.isEmpty || !entity.isMerged {
            Section("Also called") {
                if !entity.aliases.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(entity.aliases, id: \.self) { alias in
                            AliasChip(alias: alias, removable: !entity.isMerged) {
                                saver.flush()
                                graph.removeAlias(alias, from: id, in: modelContext)
                            }
                        }
                    }
                }
                if !entity.isMerged {
                    Button("Add another name") {
                        draftText = ""
                        addingAlias = true
                    }
                    .accessibilityIdentifier("entityAddAlias")
                }
            }
        }
    }

    private func actionsSection(_ entity: Entity) -> some View {
        Section {
            if !entity.hidden {
                Button("Show in Mind") { router.showInMind(id) }
                    .accessibilityIdentifier("entityShowInMind")
            }
            Button("Merge into…") { merging = true }
                .accessibilityIdentifier("entityMergeInto")
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
            // A merged entity's bio is kept for undo; nothing drafts it.
            textUsable: !entity.isMerged && AIServices.textUsable(settings: settings, accounts: accounts)
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

    // One row that says how many entries mention them and expands in place, so a busy person's
    // page isn't a wall of entries. In place rather than pushed, so the three stacks that push
    // entity pages need no new route type.
    @ViewBuilder
    private var entriesSection: some View {
        let mine = links.filter { $0.entityID == id && !$0.isDeleted }
        let count = Set(mine.compactMap(\.entryID)).count
        if count > 0 {
            let guessed = Set(mine.filter(\.inferred).compactMap(\.entryID)).count
            Section {
                Button {
                    withAnimation { showsEntries.toggle() }
                } label: {
                    HStack {
                        Text(count == 1 ? "1 mentioned entry" : "\(count) mentioned entries")
                            .foregroundStyle(.primary)
                        Spacer()
                        if guessed > 0 {
                            Text("\(guessed) guessed").foregroundStyle(.orange)
                        }
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showsEntries ? 90 : 0))
                    }
                }
                .tint(.primary)
                .accessibilityIdentifier("entityEntriesSummary")
                if showsEntries {
                    ForEach(entryRows) { row in
                        entryRow(row)
                    }
                }
            }
        }
    }

    private func entryRow(_ row: EntityPagePresentation.EntryRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                saver.flush()
                previewingRow = row
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.heading).journalText(.headline)
                        Spacer()
                        if row.guessed != nil {
                            Text("Guessed")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(row.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // The user's own sentence, in the user's own face.
                    if let sentence = row.sentence {
                        Text(sentence)
                            .journalText(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("entityEntryRow-\(row.id)")
            if let guessed = row.guessed {
                Button("Not them") { repointing = guessed }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .accessibilityIdentifier("entityNotThem")
            }
        }
    }

    // Open loose ends about this entity first; settled, faded, and let-go ones fold away. Worked
    // out in a task, not in body, so typing in a sheet on this page never redoes it.
    @ViewBuilder
    private var looseEndsSection: some View {
        let byID = Dictionary(allLooseEnds.filter { !$0.isDeleted }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let open = looseEndSplit.open.compactMap { byID[$0] }
        let earlier = looseEndSplit.earlier.compactMap { byID[$0] }
        if !open.isEmpty || !earlier.isEmpty {
            Section("Loose ends") {
                ForEach(open) { looseEnd in
                    EntityLooseEndRow(looseEnd: looseEnd)
                        .swipeActions {
                            Button("Done") { setLooseEnd(looseEnd, .resolved) }
                                .tint(.green)
                            Button("Let go") { setLooseEnd(looseEnd, .dismissed) }
                                .tint(.gray)
                        }
                }
                if !earlier.isEmpty {
                    DisclosureGroup("Earlier (\(earlier.count))", isExpanded: $showsEarlierLooseEnds) {
                        ForEach(earlier) { looseEnd in
                            EntityLooseEndRow(looseEnd: looseEnd)
                                .swipeActions {
                                    Button("Reopen") { setLooseEnd(looseEnd, .open) }
                                }
                        }
                    }
                    .accessibilityIdentifier("entityEarlierLooseEnds")
                }
            }
            .accessibilityIdentifier("entityLooseEnds")
        }
    }

    // Changes when a loose end is added, removed, or has its status changed.
    private var looseEndKey: LooseEndKey {
        LooseEndKey(
            revision: graph.revision,
            count: allLooseEnds.count,
            lastChange: allLooseEnds.compactMap(\.statusChangedAt).max()
        )
    }

    private func loadLooseEnds() {
        let directory = EntityDirectory(in: modelContext)
        let items = allLooseEnds.filter { !$0.isDeleted }.map {
            EntityPagePresentation.LooseEndItem(id: $0.id, entityIDs: $0.entityIDs, isOpen: $0.isOpen, lastMentionedAt: $0.lastMentionedAt, statusChangedAt: $0.statusChangedAt)
        }
        let split = EntityPagePresentation.looseEnds(items, about: id, root: directory.root(of:))
        looseEndSplit = LooseEndSplit(open: split.open, earlier: split.earlier)
    }

    // Saved without stamping entries, the same as the insights card.
    private func setLooseEnd(_ looseEnd: LooseEnd, _ status: LooseEndStatus) {
        saver.flush()
        looseEnd.setByUser(status)
        try? modelContext.save()
    }

    // The strongest few partners inline and the rest one tap away, so the page agrees with the
    // graph, which draws every partner.
    @ViewBuilder
    private var mentionedWithSection: some View {
        if !coOccurring.isEmpty {
            Section("Mentioned with") {
                ForEach(showsAllPartners ? coOccurring[...] : coOccurring.prefix(Self.inlinePartners)) { row in
                    NavigationLink(value: EntityRoute(id: row.id)) {
                        Label(row.name, systemImage: row.kind.symbol)
                    }
                    .accessibilityIdentifier("mentionedWithRow-\(row.name)")
                }
                if coOccurring.count > Self.inlinePartners {
                    Button(showsAllPartners ? "Show fewer" : "Show all \(coOccurring.count)") {
                        withAnimation { showsAllPartners.toggle() }
                    }
                    .accessibilityIdentifier("mentionedWithSeeAll")
                }
            }
        }
    }

    private static let inlinePartners = 8

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
                    .accessibilityIdentifier("mergedInRow-\(loser.name)")
                    .swipeActions {
                        Button("Undo merge") {
                            saver.flush()
                            graph.unmerge(loser.id, in: modelContext)
                        }
                    }
                    .contextMenu {
                        Button("Undo merge", systemImage: "arrow.uturn.backward") {
                            saver.flush()
                            graph.unmerge(loser.id, in: modelContext)
                        }
                    }
                }
            }
        }
    }

    // Whether to default the rename sheet's "keep the old name" toggle on.
    // Links by id, one fetch filtered in memory, never through a relationship.
    private var linkedEntries: [Entry] {
        let ids = Set(links.filter { $0.entityID == id && !$0.isDeleted }.compactMap(\.entryID))
        guard !ids.isEmpty else { return [] }
        return ((try? modelContext.fetch(FetchDescriptor<Entry>(predicate: #Predicate { ids.contains($0.id) }))) ?? [])
            .filter { !$0.isDeleted }
    }

    private var entryRows: [EntityPagePresentation.EntryRow] {
        let mine = links.filter { $0.entityID == id && !$0.isDeleted }
        let byEntry = Dictionary(grouping: mine.compactMap { link in link.entryID.map { ($0, link) } }, by: \.0)
            .mapValues { $0.map(\.1) }
        guard !byEntry.isEmpty else { return [] }
        return EntityPagePresentation.entryRows(linkedEntries.map { entry in
            let links = byEntry[entry.id] ?? []
            return .init(
                entryID: entry.id,
                date: entry.entryDate,
                title: entry.title,
                text: entry.text,
                surfaces: links.map { $0.writtenSurface ?? $0.surface },
                guessed: links.first(where: \.inferred).map {
                    MentionRef(entryID: entry.id, surface: $0.surface, kind: $0.kind)
                }
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
private struct EntryPreview: View {
    let entryID: UUID
    @Environment(\.dismiss) private var dismiss
    @Query private var matches: [Entry]

    init(entryID: UUID) {
        self.entryID = entryID
        _matches = Query(filter: #Predicate<Entry> { $0.id == entryID })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let entry = matches.first(where: { !$0.isDeleted }) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(entry.entryDate.formatted(date: .long, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(entry.text)
                            .font(.body)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ContentUnavailableView("No longer in your journal", systemImage: "doc.text")
                }
            }
            .navigationTitle("Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("entryPreview")
    }
}

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

private struct EntityLooseEndRow: View {
    let looseEnd: LooseEnd

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(looseEnd.text)
                .strikethrough(looseEnd.status == .resolved)
                .foregroundStyle(looseEnd.isOpen ? .primary : .secondary)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("entityLooseEnd-\(looseEnd.status.rawValue)")
    }

    private var caption: String {
        let from = "From \(looseEnd.sourceEntryDate.formatted(date: .abbreviated, time: .omitted))"
        switch looseEnd.status {
        case .open: return looseEnd.dueDate.map { "\(from) · by \($0.formatted(date: .abbreviated, time: .omitted))" } ?? from
        case .resolved: return "\(from) · \(looseEnd.userTouched ? "marked done" : "settled by a later entry")"
        case .faded: return "\(from) · faded"
        case .dismissed: return "\(from) · let go"
        }
    }
}

private struct LooseEndSplit: Equatable {
    var open: [UUID] = []
    var earlier: [UUID] = []
}

private struct LooseEndKey: Equatable {
    let revision: Int
    let count: Int
    let lastChange: Date?
}
