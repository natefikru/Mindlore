import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Environment(SettingsStore.self) private var settings
    // Backdated entries share noon of their day, so createdAt keeps their order stable.
    @Query(sort: [SortDescriptor(\Entry.entryDate, order: .reverse), SortDescriptor(\Entry.createdAt, order: .reverse)])
    private var entries: [Entry]
    @State private var path: [Entry] = []
    @State private var showingSettings = false
    @State private var writingNewEntry = false
    @State private var recording = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(entries) { entry in
                    NavigationLink(value: entry) {
                        EntryRow(entry: entry)
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No entries yet",
                        systemImage: "book.closed",
                        description: Text("Tap the microphone to speak an entry, or the pencil to write one.")
                    )
                }
            }
            .navigationTitle("Mindlore")
            .navigationDestination(for: Entry.self) { entry in
                EntryEditorView(entry: entry)
            }
            .navigationDestination(isPresented: $writingNewEntry) {
                EntryEditorView(entry: nil)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showingSettings = true }
                }
                // The default entry mode sits in the outermost, easiest-to-reach position.
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if settings.defaultEntryMode == .voice {
                        newTypedEntryButton
                        newVoiceEntryButton
                    } else {
                        newVoiceEntryButton
                        newTypedEntryButton
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $recording) {
                RecordingView { entry in path.append(entry) }
            }
        }
    }

    private var newTypedEntryButton: some View {
        Button("New Written Entry", systemImage: "square.and.pencil") { writingNewEntry = true }
            .accessibilityIdentifier("newEntryButton")
    }

    private var newVoiceEntryButton: some View {
        Button("New Voice Entry", systemImage: "mic") { recording = true }
            .accessibilityIdentifier("newVoiceEntryButton")
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            DiagnosticsLog.shared.record("entry.deleted", ["id": .id(entries[index].id), "reason": "swipe"])
            Entry.delete(entries[index], in: modelContext)
        }
        saver.flush()
    }
}

private struct EntryRow: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if entry.source == .voice {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Voice entry")
                }
                EntryDateText(entry: entry)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if entry.awaitingText {
                    Text("Getting text")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }
            EntryAddedText(entry: entry)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.text.isEmpty && entry.title.isEmpty ? "No text yet" : entry.displayTitle)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(entry.text.isEmpty && entry.title.isEmpty ? .secondary : .primary)
            // The preview is skipped when it would just repeat the headline.
            if let preview, preview != entry.displayTitle {
                Text(preview)
                    .lineLimit(2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("entryRow")
    }

    private var preview: String? {
        let lines = entry.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        // Without a title the first line is already the headline, so preview what follows it.
        if entry.title.isEmpty {
            return lines.count > 1 && first.count <= Entry.derivedTitleLength ? lines[1] : (first.count > Entry.derivedTitleLength ? first : nil)
        }
        return first
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(.inMemory)
    container.mainContext.insert(Entry(text: "Walked to the river this morning.\nThe light was strange."))
    container.mainContext.insert(Entry(source: .voice, awaitingText: true, audioData: Data([0])))
    return EntryListView()
        .modelContainer(container)
        .environment(EntrySaver(context: container.mainContext))
        .environment(RecordingIngestor())
        .environment(TranscriptionCoordinator())
        .environment(EditorPresence())
        .environment(AIPassTrigger(settings: SettingsStore(store: UserDefaults(suiteName: "preview")!), presence: EditorPresence(), titleUsable: { false }))
        .environment(SettingsStore(store: UserDefaults(suiteName: "preview")!))
}
