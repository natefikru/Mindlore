import SwiftUI
import SwiftData

struct EntryEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(EntrySaver.self) private var saver
    @State private var entry: Entry?
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
            TextEditor(text: textBinding)
                .focused($editorFocused)
                .padding(.horizontal)
                .accessibilityIdentifier("entryEditor")
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if entry == nil {
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
                }
                saver.noteChange()
            }
        )
    }

    private var title: String {
        guard let entry else { return "New Entry" }
        return entry.createdAt.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func close() {
        if let entry, entry.isBlank {
            Entry.delete(entry, in: modelContext)
        }
        saver.flush()
    }
}
