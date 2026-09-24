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

// Leads with insight: who or what this is, how present it has been, how its entries felt beside
// the journal's usual, what is still open, who it turns up with, and the entries themselves.
// Admin that doesn't navigate is under Edit (EntityEditView); what does (merged rows, Merge into,
// Show in Mind) stays here in Manage, where this stack's destination and route replacer are.
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
    @Query private var matches: [Entity]
    @Query private var links: [EntityLink]
    @Query private var entities: [Entity]
    @Query(sort: \LooseEnd.lastMentionedAt, order: .reverse) private var allLooseEnds: [LooseEnd]
    @State private var showsEarlierLooseEnds = false
    @State private var looseEndSplit = LooseEndSplit()
    @State private var editing = false
    @State private var merging = false
    @State private var repointing: MentionRef?
    @State private var previewingRow: EntityPagePresentation.EntryRow?
    @State private var showsEntries = false
    @State private var showsAllPartners = false
    @State private var partners: [EntityPagePresentation.CoOccurrenceRow] = []
    @State private var themes: [EntityPagePresentation.CoOccurrenceRow] = []
    @State private var insight = PageInsight()

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
                    presenceSection
                    feelingSection
                    looseEndsSection
                    oftenWithSection
                    entriesSection
                    if entity.kind == .place, let coordinate = entity.placeCoordinate {
                        placeSection(entity, coordinate: coordinate)
                    }
                    manageSection(entity)
                }
                .listRowBackground(Palette.card)
            }
            .paperBackground()
            .navigationTitle(entity.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !entity.isMerged {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Edit") { editing = true }
                            .accessibilityIdentifier("entityEdit")
                    }
                }
            }
            .accessibilityIdentifier("entityPage")
            .onAppear {
                if !showsLoser { graph.pageOpened(id, in: modelContext) }
            }
            .task(id: looseEndKey) { loadLooseEnds() }
            .task(id: graph.revision) {
                let rows = EntityPagePresentation.coOccurrenceRows(graph.mentionedWith(of: id, in: modelContext, limit: .max))
                (partners, themes) = EntityPagePresentation.partners(rows)
                insight = PageInsight.load(id, links: links, in: modelContext)
            }
            .sheet(isPresented: $editing) {
                EntityEditView(id: id) { winnerID in routeReplacer.replace(id, winnerID) }
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
        }
    }

    private func merge(into targetID: UUID) {
        guard let winnerID = graph.merge(id, into: targetID, in: modelContext) else { return }
        routeReplacer.replace(id, winnerID)
    }

    // MARK: - Sections

    // Who or what this is: the avatar, its kind and area, and the description when there is one.
    private func header(_ entity: Entity) -> some View {
        Section {
            if !entity.isMerged,
               EntityPagePresentation.showsSpellingPrompt(confirmedByUser: entity.confirmedByUser, linkCount: entity.linkCount, kind: entity.kind) {
                Button {
                    editing = true
                } label: {
                    Label("Spelled right? \(entity.name)", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("entitySpellingPrompt")
            }
            HStack(alignment: .top, spacing: 12) {
                EntityAvatar(kind: entity.kind, contactIdentifier: entity.contactIdentifier, place: entity.placeCoordinate, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entity.name)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(entity.kind.label)
                            .foregroundStyle(.secondary)
                        if let area = insight.area {
                            Text(settings.name(of: area))
                                .chip(tint: area.color)
                                .accessibilityIdentifier("entityArea")
                        }
                    }
                    .font(.subheadline)
                    if entity.hidden {
                        Label("Hidden", systemImage: "eye.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if let bio = entity.bio {
                Text(bio)
                    .accessibilityIdentifier("entityBio")
            } else if graph.drafting.contains(id) {
                Label {
                    Text("Drafting a description…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("entityBioDrafting")
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

    // A bar per month across the journal, and the words under it.
    @ViewBuilder
    private var presenceSection: some View {
        if let presence = insight.presence {
            Section("Presence") {
                VStack(alignment: .leading, spacing: 8) {
                    Sparkline(values: presence.months, color: insight.area?.color ?? Palette.ember, recentCount: presence.months.count,
                              accessibilityText: EntityPagePresentation.presenceWords(presence))
                        .frame(height: 36)
                    Text(EntityPagePresentation.presenceWords(presence))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("entityPresence")
            }
        }
    }

    // The moods its entries carried beside the journal's usual, as counts.
    @ViewBuilder
    private var feelingSection: some View {
        if let feeling = insight.feeling {
            Section {
                ForEach(feeling.rows) { row in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(row.mood.color)
                            .frame(width: 8, height: 8)
                        Text(EntityPagePresentation.feelingWords(row, total: feeling.total, usualTotal: feeling.usualTotal))
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Feeling")
            } footer: {
                Text("From the mood of each entry that mentions them, beside every entry you've written.")
            }
            .accessibilityIdentifier("entityFeeling")
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

    // Names with the entries each shares, the strongest few inline and the rest one tap away, so
    // the page agrees with the graph, which draws every partner. Themes sit under them, quieter.
    @ViewBuilder
    private var oftenWithSection: some View {
        if !partners.isEmpty || !themes.isEmpty {
            Section {
                ForEach(showsAllPartners ? partners[...] : partners.prefix(Self.inlinePartners)) { row in
                    NavigationLink(value: EntityRoute(id: row.id)) {
                        HStack {
                            Label(row.name, systemImage: row.kind.symbol)
                            Spacer()
                            Text("\(row.entries)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("mentionedWithRow-\(row.name)")
                }
                if partners.count > Self.inlinePartners {
                    Button(showsAllPartners ? "Show fewer" : "Show all \(partners.count)") {
                        withAnimation { showsAllPartners.toggle() }
                    }
                    .accessibilityIdentifier("mentionedWithSeeAll")
                }
                if !themes.isEmpty {
                    Text("Themes: " + themes.prefix(Self.inlineThemes).map(\.name).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("entityThemes")
                }
            } header: {
                Text("Often with")
            } footer: {
                if !partners.isEmpty {
                    Text("Entries you wrote about both.")
                }
            }
        }
    }

    private static let inlinePartners = 8
    private static let inlineThemes = 6

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

    // Where this place actually is, with a handoff to Apple Maps. The preview is drawn from the
    // coordinate every time rather than stored; linking and unlinking are under Edit.
    private func placeSection(_ entity: Entity, coordinate: PlaceCoordinate) -> some View {
        Section("Place") {
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
        }
    }

    // What navigates, at the bottom: names merged into this one (each undoable), Merge into,
    // and Show in Mind.
    @ViewBuilder
    private func manageSection(_ entity: Entity) -> some View {
        let merged = EntityPagePresentation.mergedIn(
            entities.filter { !$0.isDeleted }.map { .init(id: $0.id, name: $0.name, mergedIntoID: $0.mergedIntoID, mergedAt: $0.mergedAt) },
            into: id
        )
        if !merged.isEmpty || !entity.isMerged {
            Section {
                ForEach(merged, id: \.id) { loser in
                    NavigationLink(value: EntityRoute(id: loser.id, follow: false)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(loser.name) merged into this")
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
                if !entity.isMerged {
                    Button("Merge into…") { merging = true }
                        .accessibilityIdentifier("entityMergeInto")
                    if !entity.hidden {
                        Button("Show in Mind") { router.showInMind(id) }
                            .accessibilityIdentifier("entityShowInMind")
                    }
                }
            } header: {
                Text("Manage")
            }
        }
    }

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

// Presence, feeling, and area for a page, worked out once per graph revision from the entries
// that mention the entity and one fetch of every entry's date and mood for the baseline.
private struct PageInsight {
    var presence: EntityPagePresentation.Presence?
    var feeling: EntityPagePresentation.Feeling?
    var area: LifeArea?

    static func load(_ id: UUID, links: [EntityLink], in context: ModelContext, now: Date = .now) -> PageInsight {
        let mine = Set(links.filter { $0.entityID == id && !$0.isDeleted }.compactMap(\.entryID))
        let all = ((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { !$0.isDraft }))) ?? []).filter { !$0.isDeleted }
        let theirs = all.filter { mine.contains($0.id) }
        let usual = ReflectAggregator.aggregate(
            facts: all.map { ReflectAggregator.EntryFact(date: $0.entryDate, mood: $0.insights?.primaryMood?.category) },
            in: DateInterval(start: .distantPast, end: .distantFuture)
        ).moodCounts
        return PageInsight(
            presence: EntityPagePresentation.presence(entryDates: theirs.map(\.entryDate), journalStart: all.map(\.entryDate).min(), now: now),
            feeling: EntityPagePresentation.feeling(moods: theirs.map { $0.insights?.primaryMood?.category }, usual: usual),
            area: EntityPagePresentation.primaryArea(theirs.map { (id: $0.id, date: $0.entryDate, areas: $0.insights?.areas ?? []) }, entityID: id)
        )
    }
}

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
