import PhotosUI
import SwiftData
import SwiftUI

// Collects journal pages from the camera or photo library and lets the user put them in order.
// Before confirmation every change is saved right away, so a force-quit keeps the pages. For a
// confirmed entry ("Edit pages") changes stay in a draft until the user confirms a real difference,
// which restarts the entry.
struct PageOrderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(EntrySaver.self) private var saver
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(EditorPresence.self) private var presence
    @Environment(PageTranscriptionCoordinator.self) private var pageTranscription

    @State private var entry: Entry?
    @State private var draft: [PageDraftItem]?
    @State private var showingCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var processing = false
    @State private var notice: String?
    @State private var removalIndex: Int?
    @State private var confirmingRestart = false
    private let startWithCamera: Bool
    private let onConfirmed: (Entry) -> Void

    init(entry: Entry?, startWithCamera: Bool, onConfirmed: @escaping (Entry) -> Void) {
        _entry = State(initialValue: entry)
        _draft = State(initialValue: entry.flatMap { $0.pagesConfirmed ? PageDraftItem.draft(from: $0) : nil })
        self.startWithCamera = startWithCamera
        self.onConfirmed = onConfirmed
    }

    private struct Row: Identifiable {
        let id: AnyHashable
        let thumbnailData: Data?
        let pixelWidth: Int
        let origin: PageOrigin
    }

    private var rows: [Row] {
        if let draft {
            return draft.map { Row(id: $0.id, thumbnailData: $0.thumbnailData, pixelWidth: $0.pixelWidth, origin: $0.origin) }
        }
        return (entry?.sortedPages ?? []).map { Row(id: $0.persistentModelID, thumbnailData: $0.thumbnailData, pixelWidth: $0.pixelWidth, origin: $0.origin) }
    }

    private var remainingRoom: Int { Entry.maxPages - rows.count }
    private var aiUsable: Bool { AIServices.pagesUsable(settings: settings, accounts: accounts) }

    var body: some View {
        NavigationStack {
            List {
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { position, row in
                        PageRow(number: position + 1, thumbnailData: row.thumbnailData, pixelWidth: row.pixelWidth, origin: row.origin) {
                            removalIndex = position
                        }
                    }
                    .onMove(perform: move)
                } footer: {
                    if draft != nil {
                        Text("Changing pages erases this entry's text, title, and insights and transcribes the pages again.")
                    } else if !rows.isEmpty {
                        Text("Drag pages into the order they were written. The order is locked once you confirm.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .overlay {
                if rows.isEmpty && !processing {
                    ContentUnavailableView("No pages yet", systemImage: "doc.viewfinder", description: Text("Scan pages with the camera or add photos of your journal."))
                }
                if processing {
                    ProgressView("Adding pages…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle(draft == nil ? "Journal Pages" : "Edit Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(draft == nil ? "Close" : "Cancel") { close() }
                        .accessibilityIdentifier("pageOrderCloseButton")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Scan", systemImage: "doc.viewfinder") { scan() }
                        .disabled(processing || remainingRoom <= 0)
                        .accessibilityIdentifier("scanPagesButton")
                    addFromPhotosButton
                    Spacer()
                    Button(aiUsable ? "Transcribe \(rows.count) \(rows.count == 1 ? "page" : "pages")" : "Save pages") { confirm() }
                        .fontWeight(.semibold)
                        .disabled(rows.isEmpty || processing)
                        .accessibilityIdentifier("confirmPagesButton")
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                DocumentCameraView(
                    onFinish: { images in
                        showingCamera = false
                        add(images, origin: .camera)
                    },
                    onCancel: { showingCamera = false }
                )
                .ignoresSafeArea()
            }
            .confirmationDialog(
                removalIndex.map { "Remove page \($0 + 1)?" } ?? "",
                isPresented: Binding(get: { removalIndex != nil }, set: { if !$0 { removalIndex = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove Page", role: .destructive) {
                    if let removalIndex { remove(at: removalIndex) }
                    removalIndex = nil
                }
                .accessibilityIdentifier("confirmRemovePageButton")
            }
            .alert("Start this entry over?", isPresented: $confirmingRestart) {
                Button("Cancel", role: .cancel) {}
                Button("Erase and Transcribe", role: .destructive) { restart() }
                    .accessibilityIdentifier("confirmRestartPagesButton")
            } message: {
                Text("Changing pages will erase this entry's text, title, and insights and transcribe the pages again.")
            }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                pickerItems = []
                Task { await load(items) }
            }
        }
        .onAppear {
            if let entry {
                presence.open(entry.id)
            } else if startWithCamera {
                scan()
            }
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private var addFromPhotosButton: some View {
        if FakePages.isEnabled {
            Button("Photos", systemImage: "photo.on.rectangle") {
                add(FakePages.make(count: 2, startingWidth: 2_000 + rows.count * 100), origin: .library)
            }
            .disabled(processing || remainingRoom <= 0)
            .accessibilityIdentifier("addFromPhotosButton")
        } else {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, remainingRoom), selectionBehavior: .ordered, matching: .images) {
                Label("Photos", systemImage: "photo.on.rectangle")
            }
            .disabled(processing || remainingRoom <= 0)
            .accessibilityIdentifier("addFromPhotosButton")
        }
    }

    private func scan() {
        if FakePages.isEnabled {
            add(FakePages.make(count: 3, startingWidth: 1_000 + rows.count * 100), origin: .camera)
        } else if DocumentCameraView.isSupported {
            showingCamera = true
        }
    }

    // iCloud photos that can't download are skipped and counted rather than failing the whole batch.
    private func load(_ items: [PhotosPickerItem]) async {
        processing = true
        var loaded: [Data] = []
        var failed = 0
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded.append(data)
            } else {
                failed += 1
            }
        }
        processing = false
        add(loaded, origin: .library, failedToLoad: failed)
    }

    private func add(_ images: [Data], origin: PageOrigin, failedToLoad: Int = 0) {
        guard !images.isEmpty else {
            if failedToLoad > 0 { notice = Self.notice(leftOut: 0, failed: failedToLoad) }
            return
        }
        processing = true
        Task {
            var processed: [PageImageProcessor.ProcessedPage] = []
            var unreadable = 0
            // One image at a time, off the main actor, so only one decoded page is in memory.
            for image in images {
                if let page = try? await Self.process(image) {
                    processed.append(page)
                } else {
                    unreadable += 1
                }
            }
            processing = false
            guard !processed.isEmpty else {
                notice = "Those images couldn't be read."
                return
            }
            let leftOut: Int
            if draft != nil {
                let accepted = processed.prefix(max(0, remainingRoom))
                draft?.append(contentsOf: accepted.map { PageDraftItem(content: .new($0, origin)) })
                leftOut = processed.count - accepted.count
            } else {
                let target = entry ?? createEntry()
                leftOut = target.addPages(processed, origin: origin, in: modelContext)
                saver.noteChange()
                saver.flush()
            }
            notice = Self.notice(leftOut: leftOut, failed: failedToLoad + unreadable)
            DiagnosticsLog.shared.record("pages.added", [
                "id": entry.map { .id($0.id) } ?? "new",
                "count": .int(processed.count - leftOut),
                "origin": .string(origin.rawValue),
                "bytes": .int(processed.reduce(0) { $0 + $1.imageData.count }),
                "leftOut": .int(leftOut),
                "failed": .int(failedToLoad + unreadable),
                "draft": .bool(draft != nil),
            ])
        }
    }

    @concurrent
    nonisolated private static func process(_ data: Data) async throws -> PageImageProcessor.ProcessedPage {
        try PageImageProcessor.process(data)
    }

    private func createEntry() -> Entry {
        let created = Entry(source: .photo)
        modelContext.insert(created)
        entry = created
        presence.open(created.id)
        DiagnosticsLog.shared.record("entry.created", ["id": .id(created.id), "source": .string(created.source.rawValue)])
        return created
    }

    private func move(from source: IndexSet, to destination: Int) {
        if draft != nil {
            draft?.move(fromOffsets: source, toOffset: destination)
            return
        }
        guard let entry, entry.movePages(from: source, to: destination) else { return }
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("pages.reordered", ["id": .id(entry.id), "count": .int(rows.count)])
    }

    private func remove(at position: Int) {
        if draft != nil {
            guard draft?.indices.contains(position) == true else { return }
            draft?.remove(at: position)
            return
        }
        guard let entry, entry.sortedPages.indices.contains(position), entry.removePage(entry.sortedPages[position], in: modelContext) else { return }
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("pages.removed", ["id": .id(entry.id), "count": 1, "remaining": .int(rows.count)])
    }

    private func confirm() {
        guard let entry else { return }
        if let draft {
            guard PageDraftItem.differs(draft, from: entry) else { return finish() }
            confirmingRestart = true
            return
        }
        guard entry.confirmPages(aiUsable: aiUsable) else { return }
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("pages.confirmed", ["id": .id(entry.id), "count": .int(rows.count), "transcribe": .bool(entry.awaitingText)])
        finish()
        onConfirmed(entry)
        startTranscription()
    }

    private func restart() {
        guard let entry, let draft else { return }
        entry.restartPages(applying: draft, aiUsable: aiUsable, in: modelContext)
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("pages.restarted", ["id": .id(entry.id), "count": .int(draft.count), "transcribe": .bool(entry.awaitingText)])
        finish()
        startTranscription()
    }

    private func startTranscription() {
        let context = modelContext
        let coordinator = pageTranscription
        Task { await coordinator.processQueue(context: context) }
    }

    private func finish() {
        if let entry { presence.close(entry.id) }
        dismiss()
    }

    // Nothing is deleted when the view disappears; an unconfirmed entry with no pages is removed only here.
    private func close() {
        if draft != nil {
            DiagnosticsLog.shared.record("pages.editCancelled", ["id": entry.map { .id($0.id) } ?? "none"])
            return finish()
        }
        if let entry {
            presence.close(entry.id)
            if (entry.pages ?? []).isEmpty {
                DiagnosticsLog.shared.record("entry.deleted", ["id": .id(entry.id), "reason": "noPages"])
                Entry.delete(entry, in: modelContext)
            }
            saver.flush()
        }
        dismiss()
    }

    static func notice(leftOut: Int, failed: Int) -> String? {
        var parts: [String] = []
        if leftOut > 0 { parts.append("\(leftOut) \(leftOut == 1 ? "page was" : "pages were") left out. An entry holds up to \(Entry.maxPages) pages.") }
        if failed > 0 { parts.append("\(failed) \(failed == 1 ? "image" : "images") couldn't be added.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

private struct PageRow: View {
    let number: Int
    let thumbnailData: Data?
    let pixelWidth: Int
    let origin: PageOrigin
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnailData, let image = UIImage(data: thumbnailData) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 48, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading) {
                Text("Page \(number)")
                Text(origin == .camera ? "Scanned" : "From Photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove page \(number)", systemImage: "trash", role: .destructive, action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .accessibilityIdentifier("pageRow-\(pixelWidth)")
    }
}
