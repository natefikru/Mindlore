import SwiftUI
import SwiftData

struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(SettingsStore.self) private var settings
    @Environment(TranscriptionCoordinator.self) private var transcription
    @Environment(EditorPresence.self) private var presence
    @Environment(AIPassTrigger.self) private var aiPass
    @Environment(PageTranscriptionCoordinator.self) private var pageTranscription
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(InsightsCoordinator.self) private var insightsCoordinator
    @State private var entry: Entry?
    @State private var editingDate = false
    @State private var editingPages = false
    @State private var viewingPage: Int?
    @State private var confirmingReplace = false
    @State private var showingInsights = false
    @State private var reviewingCleanup = false
    @State private var confirmingRevert = false
    // Set by Done, so the entry can say when its insights are ready without interrupting.
    @State private var watchingForInsights = false
    // Hides the cleanup offer without discarding it: it stays in the entry's insights.
    @State private var cleanupDismissed = false
    // Not @FocusState: the text view is a UITextView so it can grow with its content, and it
    // reports focus back through this flag.
    @State private var editorFocused = false
    // Bumped to put the caret at the end, for taps in the blank space under the text.
    @State private var focusAtEndToken = 0

    static let fallbackNoticeSeconds = 8.0

    init(entry: Entry?) {
        _entry = State(initialValue: entry)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    // The text view grows with its text and never ends shorter than the screen, so the
                    // whole entry scrolls as one and a tap below short text still lands in the text.
                    GrowingTextEditor(
                        text: textBinding,
                        isFocused: editorFocused,
                        focusAtEndToken: focusAtEndToken,
                        onFocusChange: { editorFocused = $0 }
                    )
                    .padding(.horizontal)
                    .accessibilityIdentifier("entryEditor")
                    // Tapping under the text continues the entry, rather than doing nothing or
                    // dropping the caret at the start.
                    Color.clear
                        .frame(minHeight: max(120, proxy.size.height / 2))
                        .contentShape(Rectangle())
                        .onTapGesture { focusAtEndToken += 1 }
                        .accessibilityHidden(true)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let entry {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if AIPassTrigger.offersDone(entry, automationStartedAt: settings.automationStartedAt) {
                        Button("Done") { finish(entry) }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("finishEntryButton")
                    }
                    Button {
                        showingInsights = true
                        watchingForInsights = false
                    } label: {
                        Label("Insights", systemImage: insightsSymbol(for: entry))
                            .symbolVariant(InsightsPresentation.isFilled(insightsState(for: entry)) ? .fill : .none)
                    }
                    .accessibilityIdentifier("insightsButton")
                    if entry.originalText != nil {
                        Menu {
                            Button("Use original text", systemImage: "arrow.uturn.backward") {
                                if entry.textChangedSinceCleanup {
                                    confirmingRevert = true
                                } else {
                                    revert(entry)
                                }
                            }
                            .accessibilityIdentifier("viewOriginalTextButton")
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                    if entry.source == .photo && entry.pagesConfirmed {
                        Button("Edit pages", systemImage: "doc.on.doc") { editingPages = true }
                            .disabled(pageTranscription.isRunning(entry))
                            .accessibilityIdentifier("editPagesButton")
                    }
                    Button("Entry date", systemImage: "calendar") { editingDate = true }
                        .accessibilityIdentifier("entryDateButton")
                }
            }
        }
        .fullScreenCover(isPresented: $editingPages) {
            if let entry {
                PageOrderView(entry: entry) { _ in }
            }
        }
        .fullScreenCover(item: Binding(get: { viewingPage.map(PageSelection.init) }, set: { viewingPage = $0?.index })) { selection in
            if let entry {
                PageViewer(pages: entry.sortedPages, selection: selection.index)
            }
        }
        .alert("Replace the text?", isPresented: $confirmingReplace) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                guard let entry, entry.replaceWithPageTranscription() else { return }
                saver.noteChange()
                saver.flush()
                DiagnosticsLog.shared.record("pages.textReplaced", ["id": .id(entry.id)])
            }
        } message: {
            Text("The entry's text will be replaced with the transcription of its pages, for you to review again.")
        }
        .sheet(isPresented: $showingInsights) {
            if let entry {
                EntryInsightsView(entry: entry, runsWhenOpened: true)
            }
        }
        .sheet(isPresented: $reviewingCleanup) {
            if let entry, let cleaned = entry.pendingCleanedText, !cleanupDismissed {
                CleanupReviewView(entry: entry, cleaned: cleaned) { applyCleanup(entry, cleaned: cleaned) }
            }
        }
        .alert("Go back to your original text?", isPresented: $confirmingRevert) {
            Button("Cancel", role: .cancel) {}
            Button("Use original", role: .destructive) { if let entry { revert(entry) } }
        } message: {
            Text("You've edited this entry since the cleaned-up text was used, and those edits will be replaced.")
        }
        .sheet(isPresented: $editingDate) {
            if let entry {
                EntryDateSheet(entry: entry) {
                    saver.noteChange()
                    graph.entryDateChanged(in: modelContext)
                }
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            if let entry {
                presence.open(entry.id)
            } else {
                focusAtEndToken += 1
            }
        }
        // A full-screen cover removes the presenting view, which would otherwise run the editor's
        // close rules (delete-if-blank, discard audio, fire the AI pass) while the entry is still open.
        .onDisappear {
            guard !isPresentingOverEditor else { return }
            close()
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            if saver.lastError != nil {
                Label("Couldn't save. Your text is still here and will be saved on your next change.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
            }
            if let entry, entry.shouldShowDateSuggestion(), let suggested = entry.suggestedEntryDate {
                dateSuggestion(for: entry, suggested: suggested)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            if let entry, let cleaned = entry.pendingCleanedText, !cleanupDismissed {
                cleanupBanner(for: entry, cleaned: cleaned)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            if let entry, watchingForInsights || insightsCoordinator.isRunning(entry) || entry.insightsPending {
                insightsReadyLine(for: entry)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            if let entry, entry.source == .photo, !(entry.pages ?? []).isEmpty {
                PageStripView(pages: entry.sortedPages) { viewingPage = $0 }
                    .padding(.top, 8)
                pageStatus(for: entry)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            if let audioData = entry?.audioData {
                AudioPlayerView(data: audioData, duration: entry?.audioDuration)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            if let entry, let reason = entry.textFallbackReasonRaw {
                fallbackNotice(for: entry, reason: AIJobFailure(raw: reason))
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .task(id: reason) {
                        try? await Task.sleep(for: .seconds(Self.fallbackNoticeSeconds))
                        guard !Task.isCancelled, entry.textFallbackReasonRaw == reason else { return }
                        entry.textFallbackReasonRaw = nil
                        saver.noteChange()
                    }
            }
            if let entry, entry.awaitingText, entry.source != .photo {
                transcriptionStatus(for: entry)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            TextField(entry.map(\.displayTitle) ?? "Title", text: titleBinding)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 21)
                .padding(.top, 8)
                .submitLabel(.next)
                .onSubmit { focusAtEndToken += 1 }
                .accessibilityIdentifier("entryTitleField")
            if let entry, entry.awaitingText, entry.text.isEmpty {
                Text(entry.source == .photo ? "Text from your pages will appear here. You can also start typing." : "Text from your recording will appear here. You can also start typing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 21)
                    .padding(.top, 4)
            }
            Spacer().frame(height: 4)
        }
    }

    // Progress, failures, review, and recovery for an entry made from journal pages.
    @ViewBuilder
    private func pageStatus(for entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.textReviewPending {
                HStack(alignment: .firstTextBaseline) {
                    Label(entry.text.isEmpty ? "No writing was found on these pages. Type the text, or edit the pages." : "Check the text against your pages, then approve it.", systemImage: "checkmark.circle")
                    Spacer()
                    Button("Approve") { approve(entry) }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("approveTextButton")
                }
            }
            if entry.awaitingText {
                switch pageTranscription.activity[entry.id] {
                case .transcribing(let page, let count):
                    Label {
                        Text("Transcribing page \(page) of \(count)…")
                    } icon: {
                        ProgressView().controlSize(.small)
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("pageTranscriptionProgress")
                case .failed(let message):
                    retryRow(message: message, entry: entry)
                case nil:
                    if let failure = AIJobPolicy.failure(.text, entry) {
                        retryRow(message: failure.userMessage, entry: entry)
                    } else if !AIServices.pagesUsable(settings: settings, accounts: accounts) {
                        Label("Turn on AI in Settings to transcribe these pages, or type the text yourself.", systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if entry.text.isEmpty && !entry.allPagesTranscribed && AIServices.pagesUsable(settings: settings, accounts: accounts) {
                Button("Transcribe pages", systemImage: "text.viewfinder") {
                    Task { await pageTranscription.transcribePages(for: entry, context: modelContext) }
                }
                .accessibilityIdentifier("transcribePagesButton")
            }
            if entry.canReplaceWithPageTranscription {
                Button("Replace with page transcription", systemImage: "arrow.uturn.backward") { confirmingReplace = true }
                    .accessibilityIdentifier("replaceWithPagesButton")
            }
        }
        .padding(.top, 6)
    }

    private func retryRow(message: String, entry: Entry) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Spacer()
            Button("Retry") {
                Task { await pageTranscription.transcribePages(for: entry, context: modelContext) }
            }
        }
    }

    private var isPresentingOverEditor: Bool {
        editingPages || viewingPage != nil || showingInsights || reviewingCleanup || editingDate
    }

    private func insightsState(for entry: Entry) -> InsightsPresentation.State {
        InsightsPresentation.state(.init(
            isDraft: entry.isDraft,
            awaitingText: entry.awaitingText,
            textReviewPending: entry.textReviewPending,
            hasText: !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasInsights: entry.insights != nil,
            insightsAreEmpty: entry.insights.map(EntryInsightsView.isEmpty) ?? false,
            insightsAreCurrent: entry.insights?.isCurrent(for: entry) ?? false,
            running: insightsCoordinator.isRunning(entry),
            failure: AIJobPolicy.failure(.insights, entry),
            aiEnabled: settings.aiEnabled,
            hasKey: accounts.hasUsableKey && accounts.settingsAccount(for: .text) != nil
        ))
    }

    private func insightsSymbol(for entry: Entry) -> String {
        let state = insightsState(for: entry)
        if InsightsPresentation.showsStaleBadge(state) { return "sparkles.rectangle.stack" }
        return InsightsPresentation.symbol(for: state)
    }

    // Offers the cleaned-up version without touching the entry: the user sees the changes first.
    private func cleanupBanner(for entry: Entry, cleaned: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Cleaned up punctuation and paragraphs.", systemImage: "text.badge.checkmark")
                .font(.footnote)
            Spacer()
            Button("Review") { reviewingCleanup = true }
                .accessibilityIdentifier("reviewCleanupButton")
            Button("Not now", role: .cancel) {
                cleanupDismissed = true
                DiagnosticsLog.shared.record("cleanup.dismissed", ["id": .id(entry.id)])
            }
        }
        .buttonStyle(.borderless)
    }

    private func insightsReadyLine(for entry: Entry) -> some View {
        Group {
            if insightsCoordinator.isRunning(entry) {
                Label { Text("Finding insights…") } icon: { ProgressView().controlSize(.small) }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if entry.insightsPending {
                Label { Text("Insights queued…") } icon: { Image(systemName: "sparkles") }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if entry.insights?.isCurrent(for: entry) == true, watchingForInsights {
                Button {
                    showingInsights = true
                    watchingForInsights = false
                } label: {
                    Label("Insights ready", systemImage: "sparkles")
                        .font(.footnote)
                }
                .accessibilityIdentifier("insightsReadyButton")
            }
        }
    }

    private func applyCleanup(_ entry: Entry, cleaned: String) {
        guard entry.applyCleanedText(cleaned) else { return }
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("cleanup.applied", ["id": .id(entry.id), "trigger": "manual"])
    }

    private func revert(_ entry: Entry) {
        guard entry.revertToOriginalText() else { return }
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("cleanup.reverted", ["id": .id(entry.id)])
    }

    // Done: the entry is finished, so its automatic pass runs now. Leaving without Done keeps a draft.
    private func finish(_ entry: Entry) {
        // A draft becomes finished; anything else Done is offered on already is, and only needs its pass.
        let wasDraft = entry.finishDraft()
        editorFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard aiPass.fire(for: entry, at: .finished) || wasDraft else { return }
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("entry.finished", ["id": .id(entry.id), "source": .string(entry.source.rawValue), "wasDraft": .bool(wasDraft)])
        watchingForInsights = settings.insightsTrigger == .automatic && AIServices.automaticInsightsUsable(settings: settings, accounts: accounts)
        aiPass.onFlagged?()
    }

    private func approve(_ entry: Entry) {
        guard entry.approveText() else { return }
        aiPass.fire(for: entry, at: .approved)
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("text.approved", ["id": .id(entry.id)])
        aiPass.onFlagged?()
    }

    // The entry is created on the first non-empty change, so opening and leaving a new entry leaves nothing behind.
    private var textBinding: Binding<String> {
        Binding(
            get: { entry?.text ?? "" },
            set: { newValue in
                if let entry {
                    guard entry.text != newValue else { return }
                    entry.text = newValue
                    entry.userDidEditText()
                } else {
                    guard !newValue.isEmpty else { return }
                    let created = Entry(text: newValue)
                    created.isDraft = true
                    modelContext.insert(created)
                    entry = created
                    presence.open(created.id)
                    DiagnosticsLog.shared.record("entry.created", ["id": .id(created.id), "source": .string(created.source.rawValue)])
                }
                saver.noteChange()
            }
        )
    }

    // Like the text, typing a title into a new entry creates it.
    private var titleBinding: Binding<String> {
        Binding(
            get: { entry?.title ?? "" },
            set: { newValue in
                if let entry {
                    guard entry.title != newValue else { return }
                    entry.userDidEditTitle(newValue)
                } else {
                    guard !newValue.isEmpty else { return }
                    let created = Entry()
                    created.isDraft = true
                    created.userDidEditTitle(newValue)
                    modelContext.insert(created)
                    entry = created
                    presence.open(created.id)
                    DiagnosticsLog.shared.record("entry.created", ["id": .id(created.id), "source": .string(created.source.rawValue)])
                }
                saver.noteChange()
            }
        )
    }

    // Typing is always possible; any typing clears awaitingText, which hides this.
    @ViewBuilder
    private func transcriptionStatus(for entry: Entry) -> some View {
        switch transcription.activity[entry.persistentModelID] {
        case .transcribing:
            Label {
                Text("Getting text from your recording…")
            } icon: {
                ProgressView().controlSize(.small)
            }
            .foregroundStyle(.secondary)
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                Button("Retry") {
                    Task { await transcription.retry(entry.persistentModelID, context: modelContext) }
                }
            }
        case .unsupported(let message):
            Label(message, systemImage: "text.bubble")
                .foregroundStyle(.secondary)
        case nil:
            // After a relaunch the failure is only on the entry, not in the coordinator's memory.
            if let failure = AIJobPolicy.failure(.text, entry) {
                HStack {
                    Label(failure.userMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("Retry") {
                        Task { await transcription.retry(entry.persistentModelID, context: modelContext) }
                    }
                }
            }
        }
    }

    // The fallback notice is information, not a decision, so it clears itself.
    private func fallbackNotice(for entry: Entry, reason: AIJobFailure) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Transcribed on this iPhone. \(reason.userMessage)", systemImage: "iphone")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Dismiss") {
                entry.textFallbackReasonRaw = nil
                saver.noteChange()
            }
            .font(.footnote)
        }
    }

    private var title: String {
        guard let entry else { return "New Entry" }
        return entry.entryDate.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func dateSuggestion(for entry: Entry, suggested: Date) -> some View {
        HStack {
            Label("Written on \(suggested.formatted(.dateTime.month(.wide).day().year()))?", systemImage: "calendar.badge.clock")
                .font(.footnote)
            Spacer()
            Button("Use") {
                let previous = entry.entryDate
                entry.acceptSuggestedEntryDate()
                saver.noteChange()
                EntryDateSheet.recordChange(entry: entry, from: previous, reason: "suggestion")
            }
            .accessibilityIdentifier("useSuggestedDateButton")
            Button("Dismiss", role: .cancel) {
                entry.dismissSuggestedEntryDate()
                saver.noteChange()
                DiagnosticsLog.shared.record("entryDate.dismissed", ["id": .id(entry.id)])
            }
        }
        .buttonStyle(.borderless)
    }

    private func close() {
        // If the view is still on screen (a cancelled back swipe), dropping the reference means
        // the next keystroke creates a fresh entry instead of writing to a deleted one.
        if let entry {
            presence.close(entry.id)
            let id = entry.id
            let hadAudio = entry.audioData != nil
            let deleted = Entry.editorDidClose(entry, keepAudio: settings.keepAudioAfterTranscription, in: modelContext)
            DiagnosticsLog.shared.record("editor.closed", [
                "id": .id(id),
                "deleted": .bool(deleted),
                "audioDiscarded": .bool(hadAudio && (deleted || entry.audioData == nil)),
                "characters": .int(deleted ? 0 : entry.text.count),
            ])
            if deleted {
                self.entry = nil
            } else {
                aiPass.fire(for: entry, at: .editorClosed)
            }
        }
        saver.flush()
        aiPass.onFlagged?()
    }
}

private struct PageSelection: Identifiable {
    let index: Int
    var id: Int { index }
}
