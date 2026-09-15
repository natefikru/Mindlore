import SwiftData
import SwiftUI

// Everything AI has to say about one entry. Opened over the editor, so the editor's close rules
// don't fire. Cleaned-up text is not offered here: replacing the user's own words happens in the
// editor, where they can see what changes.
struct EntryInsightsView: View {
    let entry: Entry
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(EntrySaver.self) private var saver
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(InsightsCoordinator.self) private var insightsCoordinator
    @Environment(AIPassTrigger.self) private var aiPass
    @State private var confirmingRun = false
    @State private var confirmingDelete = false

    private var insights: EntryInsights? { entry.insights }

    private var state: InsightsPresentation.State {
        InsightsPresentation.state(.init(
            isDraft: entry.isDraft,
            awaitingText: entry.awaitingText,
            textReviewPending: entry.textReviewPending,
            hasText: !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasInsights: insights != nil,
            insightsAreEmpty: insights.map(Self.isEmpty) ?? false,
            insightsAreCurrent: insights?.isCurrent(for: entry) ?? false,
            running: insightsCoordinator.isRunning(entry),
            failure: AIJobPolicy.failure(.insights, entry),
            aiEnabled: settings.aiEnabled,
            hasKey: accounts.resolve(.text) != nil
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                if let insights, state == .current || state == .stale {
                    cards(for: insights)
                        .opacity(state == .stale ? 0.6 : 1)
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
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
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("insightsMenuButton")
                }
            }
            .confirmationDialog("Generate again?", isPresented: $confirmingRun, titleVisibility: .visible) {
                Button("Generate again") { run() }
                    .accessibilityIdentifier("confirmGenerateAgainButton")
            } message: {
                Text("This sends the entry to OpenAI again and uses your credit.")
            }
            .confirmationDialog("Delete these insights?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete insights", role: .destructive) { deleteInsights() }
                    .accessibilityIdentifier("confirmDeleteInsightsButton")
            } message: {
                Text("The entry, its text, and its pages stay. You can generate insights again later.")
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section {
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
            switch state {
            case .aiOff, .missingKey:
                NavigationLink("Open AI settings") { AISettingsView() }
            case .awaitingApproval:
                Button("Approve text") { approve() }
                    .accessibilityIdentifier("approveFromInsightsButton")
            default:
                if let title = InsightsPresentation.runButtonTitle(for: state) {
                    Button(title) {
                        if InsightsPresentation.confirmsBeforeRunning(state) {
                            confirmingRun = true
                        } else {
                            run()
                        }
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("runInsightsButton")
                }
            }
        } header: {
            if let insights, state == .current || state == .stale || state == .empty {
                Text("\(insights.generatedAt.formatted(date: .abbreviated, time: .shortened)) · \(Self.modelName(insights.modelUsed))")
            }
        } footer: {
            if InsightsPresentation.runButtonTitle(for: state) != nil, state != .draft {
                Text("Sends this entry to OpenAI · \(settings.textModel)")
            }
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
            InsightCard(title: "Moods") {
                MoodRows(primary: insights.primaryMood, secondary: insights.secondaryMoods)
            }
        }
        if !insights.themes.isEmpty {
            InsightCard(title: "Themes", caption: "What this entry is about.", copyText: insights.themes.joined(separator: "\n")) {
                ForEach(insights.themes, id: \.self) { Text($0) }
            }
        }
        if !insights.tags.isEmpty {
            InsightCard(title: "Tags", caption: "Labels for grouping entries.", copyText: insights.tags.joined(separator: ", ")) {
                WrappingChips(items: insights.tags)
            }
        }
        if !insights.mentions.isEmpty {
            InsightCard(title: "Mentioned", copyText: insights.mentions.map(\.name).joined(separator: ", ")) {
                MentionGroups(mentions: insights.mentions)
            }
        }
        if !insights.openThreads.isEmpty {
            InsightCard(title: "Loose ends", copyText: insights.openThreads.joined(separator: "\n")) {
                ForEach(insights.openThreads, id: \.self) { thread in
                    Label(thread, systemImage: "circle")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        ForEach(insights.customResults, id: \.promptID) { result in
            InsightCard(title: result.name, copyText: result.content) {
                Text(result.content)
            }
        }
        if insights.cleanedTextSkippedReasonRaw == "tooLong" {
            Section {
                Text("This entry was too long to clean up.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Stored labels carry the provider ("openai:gpt-5.6-luna"); the screen only needs the model.
    static func modelName(_ label: String) -> String {
        label.split(separator: ":").last.map(String.init) ?? label
    }

    static func isEmpty(_ insights: EntryInsights) -> Bool {
        insights.summary == nil && insights.primaryMoodRaw == nil && insights.themes.isEmpty && insights.tags.isEmpty
            && insights.mentions.isEmpty && insights.openThreads.isEmpty && insights.customResults.isEmpty
    }

    private func run() {
        if entry.isDraft {
            entry.finishDraft()
            aiPass.fire(for: entry, at: .finished)
            saver.noteChange()
            saver.flush()
        }
        let context = modelContext
        Task { await insightsCoordinator.runAI(for: entry, context: context) }
    }

    private func approve() {
        guard entry.approveText() else { return }
        aiPass.fire(for: entry, at: .approved)
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("text.approved", ["id": .id(entry.id), "from": "insights"])
        aiPass.onFlagged?()
    }

    private func deleteInsights() {
        guard let insights else { return }
        modelContext.delete(insights)
        entry.insights = nil
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
        if settings.insightThemes { names.append("Themes") }
        if settings.insightTags { names.append("Tags") }
        if settings.insightMentions { names.append("Mentioned") }
        if settings.insightOpenThreads { names.append("Loose ends") }
        if settings.insightCleanedText && source == .voice { names.append("Cleaned-up text") }
        if settings.suggestEntryDates && source == .typed { names.append("Written date") }
        names.append(contentsOf: settings.customInsightPrompts.filter(\.enabled).map(\.name))
        return names
    }
}
