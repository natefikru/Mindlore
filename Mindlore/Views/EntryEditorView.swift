import SwiftUI
import SwiftData

struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Environment(GraphServices.self) private var graph
    @Environment(SettingsStore.self) private var settings
    @Environment(TranscriptionCoordinator.self) private var transcription
    @Environment(AIPassTrigger.self) private var aiPass
    @Environment(PageTranscriptionCoordinator.self) private var pageTranscription
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(InsightsCoordinator.self) private var insightsCoordinator
    @Environment(AppRouter.self) private var router
    @Environment(\.journalFont) private var journalFont
    @State private var currentEntry: Entry?
    // The entry the first keystroke created, held by reference as well as in `currentEntry`. A
    // redraw already under way when that keystroke lands still reads the state from before it,
    // with no entry, so the text read back empty: on the phone the text view was emptied and
    // refilled, the caret was left in front of the first letter, and "new" came out "ewN".
    @State private var newEntry = CreatedEntry()
    // The id a new entry is created with, so the close rules find it when its route leaves the path.
    private let newEntryID: UUID?
    // A Reflect card's prompt, seeded into the entry on appear rather than the first keystroke.
    private let startingText: String?
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
    // Where that caret goes instead of the end: the character a tap on the read text landed on.
    @State private var focusOffset: Int?
    // The read text's own width, so a tap on it can be turned into a character.
    @State private var readTextWidth: CGFloat = 0
    // Past entries open read-only; Edit switches to typing. Decided once when the editor opens.
    @State private var isReading: Bool
    @State private var openedForReading: Bool
    // Edit asks the text view, once it exists, to take focus with the caret at the end.
    @State private var focusWhenEditorAppears = false
    // The read text with names linked, and the text it was built from, so stale links never show.
    @State private var linked: (text: String, value: AttributedString)?
    @State private var peekTarget: PeekTarget?
    @State private var addingName = false
    // When the read text's link handler last opened a name, so the tap that opened it never also
    // opens the editor. A time rather than a flag: it holds whichever order SwiftUI delivers the
    // link and the tap in, and a link tap the gesture never saw can't swallow the next plain tap.
    @State private var lastLinkTap: Date?

    static let fallbackNoticeSeconds = 8.0

    init(entry: Entry?, newEntryID: UUID? = nil, opensForReading: Bool = false, startingText: String? = nil) {
        _currentEntry = State(initialValue: entry)
        self.newEntryID = newEntryID
        self.startingText = startingText
        _isReading = State(initialValue: opensForReading)
        _openedForReading = State(initialValue: opensForReading)
    }

    // The close rules run when the route leaves the path, while this view is still animating out,
    // and may delete a blank entry under it. A deleted entry reads as no entry.
    private var entry: Entry? {
        guard let currentEntry = currentEntry ?? newEntry.entry, !currentEntry.isDeleted, currentEntry.modelContext != nil else { return nil }
        return currentEntry
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if isReading, let entry {
                        readBody(for: entry)
                    } else {
                        // The text view grows with its text and never ends shorter than the screen, so the
                        // whole entry scrolls as one and a tap below short text still lands in the text.
                        ZStack(alignment: .topLeading) {
                            // A Reflect card's prompt shows as a hint, not real content: entry stays nil
                            // (and nothing is saved) until the user actually types, the same rule any
                            // other new entry follows. Seeding real text here once did create a
                            // permanent draft from a card the user only glanced at and left.
                            if entry == nil, let startingText, !startingText.isEmpty {
                                Text(startingText)
                                    .journalText(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                                    .accessibilityLabel(startingText)
                                    .accessibilityIdentifier("entryStartingTextPlaceholder")
                            }
                            GrowingTextEditor(
                                text: textBinding,
                                isFocused: editorFocused,
                                focusAtEndToken: focusAtEndToken,
                                focusOffset: focusOffset,
                                onFocusChange: { editorFocused = $0 }
                            )
                            .accessibilityIdentifier("entryEditor")
                        }
                        .padding(.horizontal)
                        .onAppear {
                            // A new entry and Edit on a read one both want the caret at the end of
                            // the text as soon as the text view exists. Asked for here, from the text
                            // view's own appearance, rather than from the screen's, which can run
                            // before the text view has been made and then be treated as handled.
                            guard focusWhenEditorAppears || entry == nil else { return }
                            focusWhenEditorAppears = false
                            focusAtEndToken += 1
                        }
                        // Tapping under the text continues the entry, rather than doing nothing or
                        // dropping the caret at the start.
                        Color.clear
                            .frame(minHeight: max(120, proxy.size.height / 2))
                            .contentShape(Rectangle())
                            .onTapGesture { focusAtEnd() }
                            .accessibilityHidden(true)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let entry {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isReading {
                        Button("Edit") {
                            focusOffset = nil
                            focusWhenEditorAppears = true
                            isReading = false
                        }
                        .accessibilityIdentifier("editEntryButton")
                    } else if AIPassTrigger.offersDone(entry, automationStartedAt: settings.automationStartedAt) {
                        Button("Done") { finish(entry) }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("finishEntryButton")
                    } else if openedForReading {
                        Button("Done") { stopEditing(entry) }
                            .fontWeight(.semibold)
                            .accessibilityIdentifier("doneEditingButton")
                    }
                    Button {
                        showingInsights = true
                        watchingForInsights = false
                    } label: {
                        Label("Insights", systemImage: insightsSymbol(for: entry))
                            .symbolVariant(InsightsPresentation.isFilled(insightsState(for: entry)) ? .fill : .none)
                    }
                    .accessibilityIdentifier("insightsButton")
                    // Done and Insights are what an entry is for; the rest are occasional and wait
                    // behind one menu, or a photo entry with cleaned text showed five icons at once.
                    Menu {
                        Button("Entry date", systemImage: "calendar") { editingDate = true }
                            .accessibilityIdentifier("entryDateButton")
                        if entry.source == .photo && entry.pagesConfirmed {
                            Button("Edit pages", systemImage: "doc.on.doc") { editingPages = true }
                                .disabled(pageTranscription.isRunning(entry))
                                .accessibilityIdentifier("editPagesButton")
                        }
                        if entry.originalText != nil {
                            Button("Use original text", systemImage: "arrow.uturn.backward") {
                                if entry.textChangedSinceCleanup {
                                    confirmingRevert = true
                                } else {
                                    revert(entry)
                                }
                            }
                            .accessibilityIdentifier("viewOriginalTextButton")
                        }
                        // For a name the insights missed, or an entry insights never read.
                        Button("Add a name", systemImage: "person.badge.plus") { addingName = true }
                            .accessibilityIdentifier("addNameButton")
                        Divider()
                        Button("Delete entry", systemImage: "trash", role: .destructive) {
                            saver.flush()
                            router.deleteEntry(entry.id)
                        }
                        .accessibilityIdentifier("deleteEntryButton")
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .accessibilityIdentifier("entryMoreButton")
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
                    graph.entryDateChanged(for: entry, in: modelContext)
                }
                    .presentationDetents([.medium, .large])
            }
        }
        // Opening and closing (presence, delete-if-blank, the AI pass) belong to the route, in
        // EditorLifecycle, so a tab switch or a cover over the editor never closes the entry.
        // One way only: an entry that needs the editor again (new pages, text to review) stops
        // being read, and never flips back by itself.
        .onChange(of: entry.map(EntryReadMode.mustType) ?? true) { _, mustType in
            if mustType && isReading { isReading = false }
        }
        // Full-screen covers stay: they hide the tab bar, so no jump can start under them, and
        // closing the page screen from outside would skip its own close rules.
        .onChange(of: editingPages || viewingPage != nil) { _, open in
            router.setCover("editor-\(newEntryID?.uuidString ?? currentEntry?.id.uuidString ?? "")", open: open)
        }
        // A tapped name. Presenting it touches nothing about the entry's close rules, which only run
        // when the route leaves Journal's path.
        .sheet(item: $peekTarget) { target in
            EntityPeekSheet(entityID: target.id)
        }
        .sheet(isPresented: $addingName) {
            if let entry {
                AddNameView(entry: entry)
            }
        }
        .onChange(of: router.dismissPresentationsToken) {
            peekTarget = nil
            addingName = false
            editingDate = false
            showingInsights = false
            reviewingCleanup = false
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
            if isReading, let entry {
                Text(entry.displayTitle)
                    .journalText(.title3, weight: .semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 21)
                    .padding(.top, 8)
                    .accessibilityIdentifier("entryTitleText")
            } else {
                TextField(entry.map(\.displayTitle) ?? "Title", text: titleBinding)
                    .journalText(.title3, weight: .semibold)
                    .padding(.horizontal, 21)
                    .padding(.top, 8)
                    .submitLabel(.next)
                    .onSubmit { focusAtEnd() }
                    .accessibilityIdentifier("entryTitleField")
            }
            // What the entry is, settled with a tap. Insights decide it strictly and the user
            // corrects it here; the row's badge and the map both follow.
            if let entry {
                EntryKindPicker(selection: entry.kind, setByUser: entry.creativeSetByUser) { kind in
                    setKind(kind, on: entry)
                }
                .padding(.horizontal, 21)
                .padding(.top, 10)
            }
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

    private func insightsState(for entry: Entry) -> InsightsPresentation.State {
        InsightsPresentation.state(.init(
            isDraft: entry.isDraft,
            awaitingText: entry.awaitingText,
            textReviewPending: entry.textReviewPending,
            hasText: !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasInsights: entry.insights != nil,
            insightsAreEmpty: entry.insights.map { EntryInsightsView.isEmpty($0, in: modelContext) } ?? false,
            insightsAreCurrent: entry.insights?.isCurrent(for: entry) ?? false,
            running: insightsCoordinator.isRunning(entry),
            failure: AIJobPolicy.failure(.insights, entry),
            aiEnabled: AIServices.insightsReadiness(settings: settings, accounts: accounts).enabled,
            hasKey: AIServices.insightsReadiness(settings: settings, accounts: accounts).ready
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
            Button("Decline", role: .cancel) {
                cleanupDismissed = true
                DiagnosticsLog.shared.record("cleanup.dismissed", ["id": .id(entry.id)])
            }
            .accessibilityIdentifier("declineCleanupButton")
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

    // Marked creative, the entry loses its names, area, mood, and open loose ends at once; marked
    // a note, its mood. Marked something that keeps more than before, it is read again so what
    // was dropped comes back, when there is something to read it with.
    private func setKind(_ kind: EntryKind, on entry: Entry) {
        let previous = entry.kind
        saver.flush()
        graph.setKind(kind, on: entry, in: modelContext)
        guard kind.keepsMore(than: previous), InsightsCoordinator.canRunAI(on: entry),
              AIServices.insightsUsable(settings: settings, accounts: accounts) else { return }
        let context = modelContext
        let coordinator = insightsCoordinator
        Task { await coordinator.runAI(for: entry, context: context) }
    }

    // A tap on the text of an entry being read means the user wants to write in it, the way a
    // tap into a note does. Names stay tappable: their link handler runs on the same tap and
    // claims it, so the switch is decided a moment later, once both have had their say.
    private func readTextTapped(at point: CGPoint, in text: String) {
        let tapped = Date.now
        // The gesture's point includes the read text's padding.
        let offset = ReadTapCaret.offset(
            at: CGPoint(x: point.x - Self.readTextInsets.leading, y: point.y - Self.readTextInsets.top),
            in: text,
            width: readTextWidth,
            font: .journal(.body, design: journalFont.uiDesign),
            lineSpacing: Self.readLineSpacing
        )
        Task {
            // Long enough for the link handler, which SwiftUI may deliver a beat after the gesture,
            // and far too short to feel.
            try? await Task.sleep(for: .milliseconds(150))
            if let lastLinkTap, abs(lastLinkTap.timeIntervalSince(tapped)) < 0.5 { return }
            guard isReading else { return }
            focusOffset = offset
            focusWhenEditorAppears = true
            isReading = false
            DiagnosticsLog.shared.record("editor.editFromReadTap", ["id": entry.map { .id($0.id) } ?? "none"])
        }
    }

    private func revert(_ entry: Entry) {
        guard entry.revertToOriginalText() else { return }
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("cleanup.reverted", ["id": .id(entry.id)])
    }

    private func readBody(for entry: Entry) -> some View {
        Text(readText(for: entry))
            .journalText()
            .lineSpacing(Self.readLineSpacing)
            .foregroundStyle(Palette.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { readTextWidth = $0 }
            .padding(.horizontal, Self.readTextInsets.leading)
            .padding(.top, Self.readTextInsets.top)
            .padding(.bottom, 48)
            .accessibilityIdentifier("entryReadText")
            .accessibilityHint("Tap to edit")
            .contentShape(Rectangle())
            // Simultaneous, so it never takes the tap away from a name's link.
            .simultaneousGesture(SpatialTapGesture().onEnded { readTextTapped(at: $0.location, in: entry.text) })
            // Only the read text opens names, so links in the editor's sheets keep their own handling.
            .environment(\.openURL, OpenURLAction { url in
                lastLinkTap = .now
                guard let id = EntryNameLinks.entityID(from: url) else { return .systemAction }
                peekTarget = PeekTarget(id: id)
                return .handled
            })
            .task(id: LinksKey(text: entry.text, revision: graph.revision)) {
                let candidates = EntryNameLinks.candidates(forEntry: entry.id, graph: graph, in: modelContext)
                linked = (entry.text, EntryNameLinks.attributed(entry.text, candidates: candidates))
            }
    }

    static let readLineSpacing: CGFloat = 6
    static let readTextInsets = EdgeInsets(top: 8, leading: 21, bottom: 48, trailing: 21)

    // Asks the text view for focus with the caret at the end of the text.
    private func focusAtEnd() {
        focusOffset = nil
        focusAtEndToken += 1
    }

    // Until links for the current text arrive, the plain text shows rather than stale links.
    private func readText(for entry: Entry) -> AttributedString {
        if let linked, linked.text == entry.text { return linked.value }
        return AttributedString(entry.text)
    }

    // Done after Edit on an entry that opened for reading: back to reading, unless it now needs the editor.
    private func stopEditing(_ entry: Entry) {
        editorFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        saver.flush()
        if !EntryReadMode.mustType(entry) { isReading = true }
    }

    // Done: the entry is finished, so its automatic pass runs now. Leaving without Done keeps a draft.
    private func finish(_ entry: Entry) {
        // A draft becomes finished; anything else Done is offered on already is, and only needs its pass.
        let wasDraft = entry.finishDraft()
        editorFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        if openedForReading && !EntryReadMode.mustType(entry) { isReading = true }
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
        aiPass.requestTitle(for: entry)
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
                    guard !newValue.isEmpty, let newEntryID else { return }
                    let created = Entry(text: newValue)
                    created.id = newEntryID
                    created.isDraft = true
                    modelContext.insert(created)
                    newEntry.entry = created
                    currentEntry = created
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
                    guard !newValue.isEmpty, let newEntryID else { return }
                    let created = Entry()
                    created.id = newEntryID
                    created.isDraft = true
                    created.userDidEditTitle(newValue)
                    modelContext.insert(created)
                    newEntry.entry = created
                    currentEntry = created
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
}

// A box, not a value, so every copy of the editor reads the same entry the moment it exists.
private final class CreatedEntry {
    var entry: Entry?
}

private struct LinksKey: Equatable {
    let text: String
    let revision: Int
}

struct PeekTarget: Identifiable {
    let id: UUID
}

private struct PageSelection: Identifiable {
    let index: Int
    var id: Int { index }
}
