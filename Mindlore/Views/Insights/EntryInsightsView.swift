import SwiftData
import SwiftUI

// Everything AI has to say about one entry. Opened over the editor, so the editor's close rules
// don't fire. Cleaned-up text is not offered here: replacing the user's own words happens in the
// editor, where they can see what changes.
struct EntryInsightsView: View {
    let entry: Entry
    // Set when the entry's own Insights button opened this, so a first run needs no second tap.
    var runsWhenOpened = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(InsightsCoordinator.self) private var insightsCoordinator
    @Environment(TitleCoordinator.self) private var titleCoordinator
    @Environment(AIPassTrigger.self) private var aiPass
    @Environment(AppRouter.self) private var router
    @State private var confirmingRun = false
    @State private var confirmingDelete = false
    @State private var editingMoods = false
    // Entity pages pushed from the chips, by value, so a page can be replaced or dropped.
    @State private var path: [EntityRoute] = []
    @State private var chips = EntityChipIndex.empty
    @State private var added: [GraphServices.AddedName] = []
    @State private var addingName = false
    @State private var repointing: Repointing?
    @State private var startedOnOpen = false

    private struct Repointing: Identifiable {
        let mention: MentionRef
        let entityID: UUID
        var id: MentionRef { mention }
    }

    private var insights: EntryInsights? { entry.insights }

    private var state: InsightsPresentation.State {
        InsightsPresentation.state(inputs)
    }

    private var inputs: InsightsPresentation.Inputs {
        .init(
            isDraft: entry.isDraft,
            awaitingText: entry.awaitingText,
            textReviewPending: entry.textReviewPending,
            hasText: !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasInsights: insights != nil,
            insightsAreEmpty: insights.map { Self.isEmpty($0, in: modelContext) } ?? false,
            insightsAreCurrent: insights?.isCurrent(for: entry) ?? false,
            running: insightsCoordinator.isRunning(entry),
            failure: AIJobPolicy.failure(.insights, entry),
            aiEnabled: AIServices.insightsReadiness(settings: settings, accounts: accounts).enabled,
            hasKey: AIServices.insightsReadiness(settings: settings, accounts: accounts).ready
        )
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    statusCard
                    // What the entry is, where its consequences show: no mood on a note, no
                    // names on a poem. Outside the state check, like the names the user added.
                    kindCard
                    // Outside the state check: a name the user added stands whether or not
                    // the insights are current, or there at all.
                    if !added.isEmpty {
                        addedCard
                    }
                    if let insights, state == .current || state == .stale {
                        Group {
                            cards(for: insights)
                        }
                        .opacity(state == .stale ? 0.6 : 1)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            // Named, so a UI test scrolls this sheet rather than the editor underneath it.
            .accessibilityIdentifier("insightsSheet")
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: EntityRoute.self) { route in
                EntityView(route: route)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if insights != nil {
                            NavigationLink {
                                WhatWasSentView(entry: entry, settings: settings)
                            } label: {
                                Label("What was sent", systemImage: "paperplane")
                            }
                            Button("Delete insights", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        }
                        Button("Add a name", systemImage: "person.badge.plus") { addingName = true }
                            .accessibilityIdentifier("insightsAddNameButton")
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("insightsMenuButton")
                }
            }
            .task(id: ChipsKey(generatedAt: insights?.generatedAt, revision: graph.revision)) {
                chips = graph.chipIndex(for: entry.id, in: modelContext)
                added = graph.addedNames(for: entry, in: modelContext)
            }
            .sheet(isPresented: $addingName) {
                AddNameView(entry: entry)
            }
            .task {
                guard runsWhenOpened, !startedOnOpen, InsightsPresentation.runsWhenOpened(inputs) else { return }
                startedOnOpen = true
                run()
            }
            .sheet(item: $repointing) { item in
                RepointView(mention: item.mention, currentEntityID: item.entityID)
            }
            .sheet(isPresented: $editingMoods) {
                if let insights {
                    MoodPickerView(insights: insights) {
                        saver.noteChange()
                        saver.flush()
                        graph.moodsEdited()
                        DiagnosticsLog.shared.record("insights.moodsEdited", ["id": .id(entry.id)])
                    }
                }
            }
            .confirmationDialog("Generate again?", isPresented: $confirmingRun, titleVisibility: .visible) {
                Button("Generate again") { run() }
                    .accessibilityIdentifier("confirmGenerateAgainButton")
            } message: {
                Text(insights?.moodsEditedByUser == true
                     ? "This sends the entry to OpenAI again, uses your credit, and replaces the moods you set."
                     : "This sends the entry to OpenAI again and uses your credit.")
            }
            .confirmationDialog("Delete these insights?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete insights", role: .destructive) { deleteInsights() }
                    .accessibilityIdentifier("confirmDeleteInsightsButton")
            } message: {
                Text("The entry, its text, and its pages stay. You can generate insights again later.")
            }
        }
        // On the stack, so pushed pages and their sheets see it.
        .environment(\.entityRouteReplacer, EntityRouteReplacer { loser, winner in
            path = EntityPagePresentation.replacing(loser, with: winner, in: path)
        })
    }

    // What state the insights are in and what can be done about it. Every state has something to
    // say here, so the card is never empty.
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let insights, state == .current || state == .stale || state == .empty {
                Text("\(insights.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(Self.modelName(insights.modelUsed))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if let explanation = InsightsPresentation.explanation(for: state) {
                Label {
                    Text(explanation)
                } icon: {
                    if state == .running {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: state == .stale ? "clock.badge.exclamationmark" : "sparkles")
                    }
                }
                .foregroundStyle(state == .stale ? .orange : .secondary)
                .accessibilityIdentifier("insightsExplanation")
            }
            if case .failed(let message) = state {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("insightsFailure")
            }
            statusAction
            if InsightsPresentation.runButtonTitle(for: state) != nil, state != .draft {
                Text("Sends this entry to OpenAI · \(settings.textModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var statusAction: some View {
        switch state {
        case .aiOff, .missingKey:
            Button("Open AI settings") { router.showSettings() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("openAISettingsButton")
        case .awaitingApproval:
            Button("Approve text") { approve() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("approveFromInsightsButton")
        default:
            if let title = InsightsPresentation.runButtonTitle(for: state) {
                let button = Button(title) {
                    if InsightsPresentation.confirmsBeforeRunning(state) {
                        confirmingRun = true
                    } else {
                        run()
                    }
                }
                .fontWeight(.semibold)
                .accessibilityIdentifier("runInsightsButton")
                // Filled only where running is the obvious next step. On insights that are already
                // current it would be the loudest thing on the sheet, and it costs money.
                if Self.runIsTheNextStep(state) {
                    button.buttonStyle(.borderedProminent)
                } else {
                    button.buttonStyle(.borderless)
                }
            }
        }
    }

    static func runIsTheNextStep(_ state: InsightsPresentation.State) -> Bool {
        switch state {
        case .none, .stale, .failed, .draft: true
        default: false
        }
    }

    @ViewBuilder
    private func cards(for insights: EntryInsights) -> some View {
        if let summary = insights.summary {
            InsightCard(title: "Summary", copyText: summary) {
                Text(summary)
            }
        }
        if insights.primaryMood != nil || !insights.secondaryMoods.isEmpty {
            InsightCard(title: "Moods", caption: insights.moodsEditedByUser ? "You set these." : nil) {
                MoodRows(primary: insights.primaryMood, secondary: insights.secondaryMoods)
                Button("Edit moods", systemImage: "pencil") { editingMoods = true }
                    .accessibilityIdentifier("editMoodsButton")
            }
        }
        if insights.areas.contains(where: { !settings.isHidden($0) }) {
            InsightCard(title: "Life areas", caption: "What part of life this entry is about.") {
                LifeAreaChips(areas: insights.areas)
            }
        }
        // Chip cards have no card-wide Copy: each chip has its own menu.
        if !insights.tags.isEmpty {
            InsightCard(title: "Tags", caption: "Labels for grouping entries.") {
                EntityChips(values: insights.tags, kind: .tag, index: chips, open: openEntity)
            }
        }
        if !insights.mentions.isEmpty {
            InsightCard(title: "Mentioned") {
                MentionGroups(mentions: insights.mentions, entryID: entry.id, index: chips, open: openEntity) { mention, entityID in
                    repointing = Repointing(mention: mention, entityID: entityID)
                }
            }
        }
        LooseEndsCard(entryID: entry.id)
        if insights.sections.count > 1 {
            sectionsCard(insights.sections)
        }
        ForEach(insights.customResults, id: \.promptID) { result in
            InsightCard(title: result.name, copyText: result.content) {
                Text(result.content)
            }
        }
        if let note = cleanupNote(insights.cleanedTextSkippedReasonRaw) {
            Text(note)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private var kindCard: some View {
        InsightCard(title: "This entry is") {
            EntryKindPicker(selection: entry.kind, setByUser: entry.creativeSetByUser, showsMeaning: true) { kind in
                setKind(kind)
            }
        }
    }

    // The same rule as the editor's picker: what the new kind drops goes at once, and what it
    // brings back is read again when there is something to read it with.
    private func setKind(_ kind: EntryKind) {
        let previous = entry.kind
        saver.flush()
        graph.setKind(kind, on: entry, in: modelContext)
        guard kind.keepsMore(than: previous), InsightsCoordinator.canRunAI(on: entry),
              AIServices.insightsUsable(settings: settings, accounts: accounts) else { return }
        let context = modelContext
        Task { await insightsCoordinator.runAI(for: entry, context: context) }
    }

    // The entry's parts by topic, for a long entry that covered several things. Read-only: the
    // parts are the run's reading, and the tags and names they carry are already on the cards above.
    private func sectionsCard(_ sections: [EntrySection]) -> some View {
        InsightCard(title: "Parts", caption: "Where the entry moved from one thing to another.") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(section.topic)
                            .font(.subheadline.weight(.semibold))
                        if let summary = section.summary {
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        let chips = section.areas.filter { !settings.isHidden($0) }.map { settings.name(of: $0) } + section.tags + section.names
                        if !chips.isEmpty {
                            Text(chips.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("insightsPart-\(index)")
                    if index < sections.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

    // Names the user added by hand. Each opens its page; the menu takes it off this entry.
    private var addedCard: some View {
        InsightCard(title: "Added by you") {
            FlowLayout(spacing: 6) {
                ForEach(added) { name in
                    Button { openEntity(name.id) } label: {
                        Label(name.name, systemImage: name.kind.symbol)
                            .lineLimit(1)
                            .fixedSize()
                            .chip(tint: name.kind.color)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(.contextMenuPreview, Capsule())
                    .contextMenu {
                        Button("Open", systemImage: "arrow.right.circle") { openEntity(name.id) }
                        Button("Remove from this entry", systemImage: "minus.circle", role: .destructive) {
                            saver.flush()
                            graph.removeAddedName(name.id, from: entry, in: modelContext)
                        }
                    }
                    .accessibilityHint("Opens its page")
                    .accessibilityIdentifier("addedName-\(name.name)")
                }
            }
        }
    }

    private func cleanupNote(_ reason: String?) -> String? {
        switch reason {
        case "tooLong": "This entry was too long to clean up."
        case "onDevice": "Clean-up needs OpenAI. The on-device model can't rewrite a whole entry."
        default: nil
        }
    }

    private struct ChipsKey: Equatable {
        let generatedAt: Date?
        let revision: Int
    }

    private func openEntity(_ id: UUID) {
        path.append(EntityRoute(id: id))
    }

    // Stored labels carry the provider ("openai:gpt-5.6-luna"); the screen only needs the model.
    static func modelName(_ label: String) -> String {
        label.split(separator: ":").last.map(String.init) ?? label
    }

    static func isEmpty(_ insights: EntryInsights, in context: ModelContext) -> Bool {
        insights.summary == nil && insights.primaryMoodRaw == nil && insights.areasRaw.isEmpty && insights.tags.isEmpty
            && insights.mentions.isEmpty && insights.customResults.isEmpty
            && !(insights.entry.map { LooseEnd.hasAny(from: $0.id, in: context) } ?? false)
    }

    private func run() {
        if entry.isDraft {
            entry.finishDraft()
            aiPass.fire(for: entry, at: .finished)
            saver.noteChange()
            saver.flush()
        }
        let context = modelContext
        Task {
            await insightsCoordinator.runAI(for: entry, context: context)
            // The title shares the entry's AI state, so Run AI is also its way back from a failure.
            await titleCoordinator.runAI(for: entry, context: context)
        }
    }

    private func approve() {
        guard entry.approveText() else { return }
        aiPass.fire(for: entry, at: .approved)
        aiPass.requestTitle(for: entry)
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("text.approved", ["id": .id(entry.id), "from": "insights"])
        aiPass.onFlagged?()
    }

    private func deleteInsights() {
        guard insights != nil else { return }
        graph.insightsDeleted(for: entry, in: modelContext)
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("insights.deleted", ["id": .id(entry.id)])
    }
}

// What left the phone for this entry's insights, and what it cost.
struct WhatWasSentView: View {
    let entry: Entry
    let settings: SettingsStore

    var body: some View {
        Form {
            Section("Sent to OpenAI") {
                LabeledContent("Model", value: EntryInsightsView.modelName(entry.insights?.modelUsed ?? settings.textModel))
                LabeledContent("Entry text", value: "\(entry.text.count) characters")
                LabeledContent("When", value: entry.insights?.generatedAt.formatted(date: .abbreviated, time: .shortened) ?? "Not yet")
            }
            Section("Asked for") {
                ForEach(Self.sections(settings, source: entry.source), id: \.self) { Text($0) }
            }
            if let insights = entry.insights, insights.sentTagCount + insights.sentNameCount + insights.sentLooseEndCount > 0 {
                Section {
                    if insights.sentTagCount > 0 { LabeledContent("Tags", value: "\(insights.sentTagCount)") }
                    if insights.sentNameCount > 0 { LabeledContent("Names", value: "\(insights.sentNameCount)") }
                    if insights.sentLooseEndCount > 0 { LabeledContent("Loose ends", value: "\(insights.sentLooseEndCount)") }
                } header: {
                    Text("Also sent: words this journal already uses")
                } footer: {
                    Text("Tags, the names of people, places, and other things, and loose ends from your other entries, including names you typed yourself, so the wording matches what you already have and a later entry can close what an earlier one left open.")
                }
            }
            Section {
                Text(entry.text.prefix(300) + (entry.text.count > 300 ? "…" : ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Beginning of what was sent")
            } footer: {
                Text("Your recordings and page photos are not sent for insights, only the entry's text.")
            }
        }
        .navigationTitle("What was sent")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func sections(_ settings: SettingsStore, source: EntrySource) -> [String] {
        var names: [String] = []
        if settings.insightSummary { names.append("Summary") }
        if settings.insightMoods { names.append("Moods") }
        if settings.insightLifeAreas { names.append("Life areas") }
        if settings.insightTags { names.append("Tags") }
        if settings.insightMentions { names.append("Mentioned") }
        if settings.insightLooseEnds { names.append("Loose ends") }
        if settings.insightCleanedText && (source == .voice || source == .photo) { names.append("Cleaned-up text") }
        if settings.suggestEntryDates && (source == .typed || source == .photo) { names.append("Written date") }
        if settings.insightTags || settings.insightMentions || settings.insightLifeAreas { names.append("Parts by topic") }
        names.append(contentsOf: settings.customInsightPrompts.filter(\.enabled).map(\.name))
        return names
    }
}
