import SwiftUI
import SwiftData

struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Environment(SettingsStore.self) private var settings
    @Environment(TranscriptionCoordinator.self) private var transcription
    @Environment(EditorPresence.self) private var presence
    @State private var entry: Entry?
    @State private var editingDate = false
    @FocusState private var editorFocused: Bool

    init(entry: Entry?) {
        _entry = State(initialValue: entry)
    }

    var body: some View {
        VStack(spacing: 0) {
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
            if let audioData = entry?.audioData {
                AudioPlayerView(data: audioData, duration: entry?.audioDuration)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            if let entry, let reason = entry.textFallbackReasonRaw {
                fallbackNotice(for: entry, reason: AIJobFailure(raw: reason))
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            if let entry, entry.awaitingText {
                transcriptionStatus(for: entry)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
            TextEditor(text: textBinding)
                .focused($editorFocused)
                .padding(.horizontal)
                .accessibilityIdentifier("entryEditor")
                .overlay(alignment: .topLeading) {
                    if let entry, entry.awaitingText, entry.text.isEmpty {
                        Text("Text from your recording will appear here. You can also start typing.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 21)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if entry != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Entry date", systemImage: "calendar") { editingDate = true }
                        .accessibilityIdentifier("entryDateButton")
                }
            }
        }
        .sheet(isPresented: $editingDate) {
            if let entry {
                EntryDateSheet(entry: entry) { saver.noteChange() }
                    .presentationDetents([.medium, .large])
            }
        }
        .onAppear {
            if let entry {
                presence.open(entry.id)
            } else {
                editorFocused = true
            }
        }
        .onDisappear(perform: close)
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
            }
        }
        saver.flush()
    }
}
