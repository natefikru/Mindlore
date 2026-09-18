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
    @State private var estimate = (entries: 0, characters: 0)
    @FocusState private var fieldFocused: Bool

    static let searchDelay = Duration.milliseconds(250)
    // The cost line waits longer than the search does: working it out reads the whole journal,
    // and nobody needs it until they have stopped typing.
    static let costDelay = Duration.milliseconds(600)

    private var query: String {
        ask.draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Results replace the conversation while the field is focused and something is typed.
    private var isSearching: Bool {
        fieldFocused && !query.isEmpty
    }

    var body: some View {
        @Bindable var ask = ask

        NavigationStack {
            // The results sit over the conversation rather than replacing it: swapping the
            // stack's own content while the keyboard is up resigns focus, and the next
            // keystroke is lost.
            ZStack {
                conversation
                if isSearching {
                    AskSearchResultsView(
                        results: results,
                        tagFilter: tagFilter,
                        openEntry: open(entryID:),
                        openEntity: { peekTarget = PeekTarget(id: $0) },
                        selectTag: selectTag
                    )
                    .background(Color(.systemBackground))
                }
            }
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
            .safeAreaInset(edge: .bottom) { composer }
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
                estimate = (0, 0)
                return
            }
            try? await Task.sleep(for: Self.searchDelay)
            guard !Task.isCancelled else { return }
            results = JournalSearch.results(for: query, in: modelContext)
            tagFilter = nil
            estimate = (0, 0)
            try? await Task.sleep(for: Self.costDelay)
            guard !Task.isCancelled else { return }
            estimate = ask.estimate(for: query, in: modelContext)
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
                    if ask.isRunning {
                        ProgressView()
                            .padding(.horizontal)
                            .accessibilityIdentifier("askThinking")
                    }
                }
                .padding(.vertical)
            }
            .onChange(of: ask.turns.count) {
                guard let last = ask.turns.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask about anything you've written")
                .font(.title3.weight(.semibold))
            Text("Answers come from your own entries, with the entry each one used.")
                .foregroundStyle(.secondary)
            ForEach(AskSources.examples(in: modelContext), id: \.self) { example in
                Button {
                    ask.draftQuestion = example
                    fieldFocused = true
                } label: {
                    Text(example)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .accessibilityIdentifier("askEmptyState")
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
                TextField("Ask or search", text: $ask.draftQuestion, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .submitLabel(.send)
                    .accessibilityIdentifier("askField")
                Button("Ask", systemImage: "arrow.up.circle.fill") { send() }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .disabled(query.isEmpty || ask.isRunning || !ask.isAvailable)
                    .accessibilityIdentifier("askSend")
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if query.count >= JournalSearch.minimumQueryCharacters, ask.isAvailable, estimate.entries > 0 {
                Text("^[\(estimate.entries) entry](inflect: true), about \(estimate.characters.formatted(.number.rounded(rule: .down).precision(.significantDigits(2)))) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("askCost")
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .background(.bar)
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
        results.entries = JournalSearch.entries(taggedWith: tag, in: modelContext)
    }

    private func open(entryID: UUID) {
        guard let entry = AskEntryRefs.entry(entryID, in: modelContext) else { return }
        router.showEntry(entry.id, forReading: EntryReadMode.opensForReading(entry, automationStartedAt: settings.automationStartedAt))
    }
}
