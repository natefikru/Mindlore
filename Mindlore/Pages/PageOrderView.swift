import PhotosUI
import SwiftData
import SwiftUI

// Collects journal pages from the camera or photo library and lets the user put them in order
// before transcription. Every change is saved right away, so a force-quit keeps the pages.
struct PageOrderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(EntrySaver.self) private var saver
    @Environment(SettingsStore.self) private var settings
    @Environment(ProviderAccountStore.self) private var accounts
    @Environment(EditorPresence.self) private var presence

    @State private var entry: Entry?
    @State private var showingCamera = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var processing = false
    @State private var notice: String?
    @State private var pageToRemove: EntryPage?
    private let startWithCamera: Bool
    private let onConfirmed: (Entry) -> Void

    init(entry: Entry?, startWithCamera: Bool, onConfirmed: @escaping (Entry) -> Void) {
        _entry = State(initialValue: entry)
        self.startWithCamera = startWithCamera
        self.onConfirmed = onConfirmed
    }

    private var pages: [EntryPage] { entry?.sortedPages ?? [] }
    private var aiUsable: Bool { settings.aiEnabled && accounts.resolve(.pages) != nil }

    var body: some View {
        NavigationStack {
            List {
                if let notice {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    ForEach(pages) { page in
                        PageRow(page: page) { pageToRemove = page }
                    }
                    .onMove(perform: move)
                } footer: {
                    if !pages.isEmpty {
                        Text("Drag pages into the order they were written. The order is locked once transcription starts.")
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .overlay {
                if pages.isEmpty && !processing {
                    ContentUnavailableView("No pages yet", systemImage: "doc.viewfinder", description: Text("Scan pages with the camera or add photos of your journal."))
                }
                if processing {
                    ProgressView("Adding pages…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Journal Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { close() }
                        .accessibilityIdentifier("pageOrderCloseButton")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Scan", systemImage: "doc.viewfinder") { scan() }
                        .disabled(processing || (entry?.remainingPageRoom ?? Entry.maxPages) == 0)
                        .accessibilityIdentifier("scanPagesButton")
                    addFromPhotosButton
                    Spacer()
                    Button(aiUsable ? "Transcribe \(pages.count) \(pages.count == 1 ? "page" : "pages")" : "Save pages") { confirm() }
                        .fontWeight(.semibold)
                        .disabled(pages.isEmpty || processing)
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
                pageToRemove.map { "Remove page \($0.index + 1)?" } ?? "",
                isPresented: Binding(get: { pageToRemove != nil }, set: { if !$0 { pageToRemove = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove Page", role: .destructive) {
                    if let page = pageToRemove { remove(page) }
                    pageToRemove = nil
                }
                .accessibilityIdentifier("confirmRemovePageButton")
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
                add(FakePages.make(count: 2, startingWidth: 2_000 + pages.count * 100), origin: .library)
            }
            .disabled(processing)
            .accessibilityIdentifier("addFromPhotosButton")
        } else {
            PhotosPicker(selection: $pickerItems, maxSelectionCount: max(1, entry?.remainingPageRoom ?? Entry.maxPages), selectionBehavior: .ordered, matching: .images) {
                Label("Photos", systemImage: "photo.on.rectangle")
            }
            .disabled(processing || (entry?.remainingPageRoom ?? Entry.maxPages) == 0)
            .accessibilityIdentifier("addFromPhotosButton")
        }
    }

    private func scan() {
        if FakePages.isEnabled {
            add(FakePages.make(count: 3, startingWidth: 1_000 + pages.count * 100), origin: .camera)
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
            if failedToLoad > 0 { notice = "\(failedToLoad) photos couldn't be loaded." }
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
            let target = entry ?? createEntry()
            let leftOut = target.addPages(processed, origin: origin, in: modelContext)
            saver.noteChange()
            saver.flush()
            notice = Self.notice(leftOut: leftOut, failed: failedToLoad + unreadable)
            DiagnosticsLog.shared.record("pages.added", [
                "id": .id(target.id),
                "count": .int(processed.count - leftOut),
                "origin": .string(origin.rawValue),
                "bytes": .int(processed.reduce(0) { $0 + $1.imageData.count }),
                "leftOut": .int(leftOut),
                "failed": .int(failedToLoad + unreadable),
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
        guard let entry, entry.movePages(from: source, to: destination) else { return }
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("pages.reordered", ["id": .id(entry.id), "count": .int(pages.count)])
    }

    private func remove(_ page: EntryPage) {
        guard let entry, entry.removePage(page, in: modelContext) else { return }
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("pages.removed", ["id": .id(entry.id), "count": 1, "remaining": .int(pages.count)])
    }

    private func confirm() {
        guard let entry, entry.confirmPages(aiUsable: aiUsable) else { return }
        saver.noteChange()
        saver.flush()
        DiagnosticsLog.shared.record("pages.confirmed", ["id": .id(entry.id), "count": .int(pages.count), "transcribe": .bool(entry.awaitingText)])
        presence.close(entry.id)
        dismiss()
        onConfirmed(entry)
    }

    // An entry with no pages is removed only on this explicit action, never when the view disappears.
    private func close() {
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
    let page: EntryPage
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let data = page.thumbnailData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 48, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading) {
                Text("Page \(page.index + 1)")
                Text(page.origin == .camera ? "Scanned" : "From Photos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remove page \(page.index + 1)", systemImage: "trash", role: .destructive, action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .accessibilityIdentifier("pageRow-\(page.pixelWidth)")
    }
}
