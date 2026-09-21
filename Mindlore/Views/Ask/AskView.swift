import SwiftData
import SwiftUI

// The Ask tab. One field does two jobs: while you type it searches the journal, and when you send
// it asks. The tab always opens on a new, empty conversation; history is a button away.
struct AskView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AskService.self) private var ask
    @Environment(AppRouter.self) private var router
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts

    @State private var results = JournalSearch.Results()
    @State private var tagFilter: String?
    @State private var peekTarget: PeekTarget?
    @State private var showsHistory = false
    @State private var sentTurn: AskTurn?
    @State private var scrollPosition = ScrollPosition()
    @State private var suggestions: [AskSuggestion] = []
    // Counts sends, so the button's bounce and the tap both fire once per question.
    @State private var sends = 0
    @FocusState private var fieldFocused: Bool

    static let searchDelay = Duration.milliseconds(250)
    // Five follows a second: fast enough that the last line stays in view, slow enough that the
    // scroll reads as one movement.
    static let scrollFollowInterval = Duration.milliseconds(200)
    // Tall enough for a few rows, short enough that the conversation stays on screen behind it.
    static let searchPanelHeight: CGFloat = 320
    // The band above the field where the conversation fades out.
    static let fadeHeight: CGFloat = 28

    private var query: String {
        ask.draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        fieldFocused && !query.isEmpty
    }

    // Nothing to show is not worth a panel: a question that matches nothing in the journal is
    // just written and sent. The exception is a conversation that hasn't started, where the
    // screen is otherwise empty and silence would read as broken.
    private var showsSearchPanel: Bool {
        isSearching && (!results.isEmpty || ask.turns.isEmpty)
    }

    var body: some View {
        @Bindable var ask = ask

        NavigationStack {
            conversation
            .navigationTitle("Ask")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("History", systemImage: "clock.arrow.circlepath") { showsHistory = true }
                        .accessibilityIdentifier("askHistory")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New conversation", systemImage: "square.and.pencil") {
                        ask.newConversation()
                        fieldFocused = false
                    }
                    .accessibilityIdentifier("askNewConversation")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    // Search is a panel over the bottom of the screen, not the screen itself:
                    // typing a follow-up must never look like it wiped the conversation you are
                    // following up on.
                    if showsSearchPanel {
                        Divider()
                        AskSearchResultsView(
                            results: results,
                            tagFilter: tagFilter,
                            openEntry: open(entryID:),
                            openEntity: { peekTarget = PeekTarget(id: $0) },
                            selectTag: selectTag,
                            maxHeight: Self.searchPanelHeight
                        )
                        .background(Palette.paper)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    composer
                }
                // Solid behind the bottom stack, with a short fade above it, so the conversation
                // dissolves before it reaches the field. On the whole stack rather than the field,
                // or the fade lands on the search panel's last row. It never takes a touch.
                .background {
                    Palette.paper
                        .overlay(alignment: .top) {
                            LinearGradient(colors: [Palette.paper.opacity(0), Palette.paper], startPoint: .top, endPoint: .bottom)
                                .frame(height: Self.fadeHeight)
                                .offset(y: -Self.fadeHeight)
                        }
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                .animation(.snappy(duration: 0.2), value: showsSearchPanel)
            }
        }
        .sheet(isPresented: $showsHistory) {
            AskHistoryView { conversation in
                ask.open(conversation, in: modelContext)
                showsHistory = false
            }
        }
        .sheet(item: $peekTarget) { EntityPeekSheet(entityID: $0.id) }
        .sheet(item: $sentTurn) { turn in
            AskWhatWasSentView(turn: turn, openEntry: open(entryID:))
        }
        .onChange(of: router.dismissPresentationsToken) {
            peekTarget = nil
            sentTurn = nil
            showsHistory = false
        }
        .task {
            // The journal is read here, once, rather than on every pause in typing.
            await ask.refreshIndex(in: modelContext)
            // Until the user picks in Settings, the phone answers and a saved key takes over.
            // Checked on every open, so adding a key moves questions without a trip to Settings.
            settings.refreshAskGeneratorDefault(
                textUsable: AIServices.textUsable(settings: settings, accounts: accounts),
                onDeviceAvailable: FoundationModelsAvailability.isAvailable
            )
        }
        // Read when the empty state is about to show (first open, a new conversation), never from
        // the view body, which would fetch every entity each time the screen redrew.
        .task(id: ask.turns.isEmpty) {
            guard ask.turns.isEmpty else { return }
            suggestions = AskSuggestionSource.suggestions(in: modelContext, settings: settings)
        }
        .task(id: ask.draftQuestion) {
            guard query.count >= JournalSearch.minimumQueryCharacters else {
                results = JournalSearch.Results()
                tagFilter = nil
                return
            }
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled else { return }
            // An entry can have arrived while Ask stayed on screen, and this costs five counters.
            await ask.refreshIndex(in: modelContext)
            guard !Task.isCancelled else { return }
            results = JournalSearch.results(for: query, index: ask.index, in: modelContext)
            tagFilter = nil
        }
    }

    // MARK: - The conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if ask.turns.isEmpty {
                        empty
                    }
                    ForEach(ask.turns) { turn in
                        AskTurnView(
                            turn: turn,
                            handles: ask.handles,
                            openEntry: open(entryID:),
                            showWhatWasSent: { sentTurn = turn },
                            retry: { Task { await ask.retryLast(in: modelContext) } },
                            isLast: turn.id == ask.turns.last?.id
                        )
                        .id(turn.id)
                    }
                    // Only the wait before the first word. Once text is arriving, the answer is
                    // its own progress.
                    if ask.isWaitingForFirstWord {
                        ProgressView()
                            .padding(.horizontal)
                            .accessibilityIdentifier("askThinking")
                    }
                }
                .padding(.vertical)
            }
            .scrollPosition($scrollPosition)
            // The keyboard covers the tab bar, so there has to be a way out besides sending: drag
            // the conversation down, or tap anywhere that isn't a control. Not on the search
            // results, which only show while the field is focused and would vanish mid-scroll.
            .scrollDismissesKeyboard(.immediately)
            .contentShape(Rectangle())
            .onTapGesture { fieldFocused = false }
            .background(Palette.paper.ignoresSafeArea())
            .onChange(of: ask.turns.count) {
                guard let last = ask.turns.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            // A growing answer is followed on a tick rather than per delta: deltas arrive tens of
            // times a second, and a scroll per delta is a fight with the thumb rather than a
            // follow. Once the reader has scrolled themselves, the screen is theirs.
            .task(id: ask.canStop) {
                guard ask.canStop else { return }
                while !Task.isCancelled, ask.canStop {
                    try? await Task.sleep(for: Self.scrollFollowInterval)
                    guard !Task.isCancelled, !scrollPosition.isPositionedByUser, let last = ask.turns.last else { continue }
                    withAnimation(.linear(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask your journal")
                    .journalText(.title2)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("askEmptyState")
                Text("Answers come from what you've written, and nothing else.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(Array(suggestions.enumerated()), id: \.element) { index, suggestion in
                    AskSuggestionCard(suggestion: suggestion) {
                        ask.draftQuestion = suggestion.text
                        fieldFocused = true
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    .animation(Motion.settle.delay(Double(index) * Motion.stagger), value: suggestions)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    // MARK: - The field

    private var composer: some View {
        @Bindable var ask = ask

        return VStack(alignment: .leading, spacing: 8) {
            if let failure = ask.unavailableFailure {
                Text(unavailableMessage(failure))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .accessibilityIdentifier("askUnavailable")
            }
            HStack(spacing: 10) {
                // A sparkle when sending would ask, a magnifying glass when the field can only
                // search: empty, or Ask switched off.
                Image(systemName: canSend ? "sparkle" : "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(fieldFocused || canSend ? Palette.ember : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20)
                    .accessibilityHidden(true)
                // One line, so the keyboard's Send key sends. On a vertical field it inserts a
                // newline instead, which is not what a question wants.
                TextField("Ask or search", text: $ask.draftQuestion)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .accessibilityIdentifier("askField")
                if ask.canStop {
                    Button("Stop", systemImage: "stop.fill") { ask.stop() }
                        .labelStyle(.iconOnly)
                        .font(.caption.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(Palette.ember, in: Circle())
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("askStop")
                } else {
                    Button("Ask", systemImage: "arrow.up") { send() }
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                        .background(canSend ? Palette.ember : Color(.tertiaryLabel), in: Circle())
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: sends)
                        .disabled(!canSend)
                        .accessibilityIdentifier("askSend")
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Palette.ember.opacity(fieldFocused ? 0.55 : 0), lineWidth: 1.5)
            }
            .animation(Motion.settle, value: fieldFocused)
            .animation(Motion.settle, value: canSend)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .sensoryFeedback(Haptics.selected, trigger: sends)
    }

    private var canSend: Bool {
        !query.isEmpty && !ask.isRunning && ask.isAvailable
    }

    // Off is rarely a decision: nearly always it means this iPhone can't run Apple's model and
    // no key has been saved yet, so the message says that rather than implying a choice.
    private func unavailableMessage(_ failure: AIJobFailure) -> String {
        switch failure.raw {
        case "settings.off" where !settings.hasChosenAskGenerator:
            "Ask needs an OpenAI key on this iPhone. Search works either way."
        case "settings.off":
            "Ask is off in Settings. Search works either way."
        case "settings.aiOff", "ai.missingKey":
            "Turn on AI in Settings to ask questions. Search works either way."
        default:
            "\(AskFailureText.message(for: failure)) Search works either way."
        }
    }

    private func send() {
        // The keyboard's Send key reaches here even when Ask is off, and that path still posts the
        // question so the answer can say why. Only a send that will be answered bounces.
        if canSend { sends += 1 }
        let question = ask.draftQuestion
        fieldFocused = false
        results = JournalSearch.Results()
        tagFilter = nil
        Task { await ask.send(question, in: modelContext) }
    }

    private func selectTag(_ tag: String) {
        tagFilter = tag
        results.entries = JournalSearch.entries(taggedWith: tag, index: ask.index, in: modelContext)
    }

    private func open(entryID: UUID) {
        guard let entry = AskEntryRefs.entry(entryID, in: modelContext) else { return }
        router.showEntry(entry.id, forReading: EntryReadMode.opensForReading(entry, automationStartedAt: settings.automationStartedAt))
    }
}
