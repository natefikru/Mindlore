import SwiftUI
import SwiftData

struct EntryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @Query(sort: \Entry.createdAt, order: .reverse) private var entries: [Entry]
    @State private var showingSettings = false
    @State private var writingNewEntry = false

    var body: some View {
        NavigationStack {
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
                        description: Text("Tap the pencil to write your first entry.")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Entry", systemImage: "square.and.pencil") { writingNewEntry = true }
                        .accessibilityIdentifier("newEntryButton")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
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
                Text(entry.createdAt, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
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
            Text(preview)
                .lineLimit(2)
                .foregroundStyle(entry.text.isEmpty ? .secondary : .primary)
        }
        .padding(.vertical, 2)
    }

    private var preview: String {
        let firstLine = entry.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return firstLine.isEmpty ? "No text yet" : firstLine
    }
}

#Preview {
    let container = try! ModelContainerFactory.make(.inMemory)
    container.mainContext.insert(Entry(text: "Walked to the river this morning.\nThe light was strange."))
    container.mainContext.insert(Entry(source: .voice, awaitingText: true, audioData: Data([0])))
    return EntryListView()
        .modelContainer(container)
        .environment(EntrySaver(context: container.mainContext))
        .environment(SettingsStore(store: UserDefaults(suiteName: "preview")!))
}
