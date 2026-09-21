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
    @FocusState private var fieldFocused: Bool

    static let searchDelay = Duration.milliseconds(250)
    // Five follows a second: fast enough that the last line stays in view, slow enough that the
    // scroll reads as one movement.
    static let scrollFollowInterval = Duration.milliseconds(200)
    // Tall enough for a few rows, short enough that the conversation stays on screen behind it.
    static let searchPanelHeight: CGFloat = 320

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
                        .background(Color(.systemBackground))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    composer
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about anything you've written. Answers come from your own journal, and nothing else.")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("askEmptyState")
            ForEach(AskSources.examples(in: modelContext), id: \.self) { example in
                Button {
                    ask.draftQuestion = example
                    fieldFocused = true
                } label: {
                    Text(verbatim: example)
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("askExample")
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: - The field

    private var composer: some View {
        @Bindable var ask = ask

        return VStack(alignment: .leading, spacing: 6) {
            if let failure = ask.unavailableFailure {
                Text(unavailableMessage(failure))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("askUnavailable")
            }
            HStack(spacing: 8) {
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
                        .font(.caption2.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor, in: Circle())
                        .foregroundStyle(Color(.systemBackground))
                        .accessibilityIdentifier("askStop")
                } else {
                    Button("Ask", systemImage: "arrow.up") { send() }
                        .labelStyle(.iconOnly)
                        .font(.footnote.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(canSend ? Color.accentColor : Color(.tertiaryLabel), in: Circle())
                        .foregroundStyle(Color(.systemBackground))
                        .disabled(!canSend)
                        .accessibilityIdentifier("askSend")
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: Capsule())
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .background(.bar)
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
