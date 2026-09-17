import Foundation
import SwiftData

// Page rules for photo entries. Before confirmation pages can change freely and every change is
// saved; once confirmed, the order is locked and these refuse (Phase 8 restarts the entry instead).
extension Entry {
    static let maxPages = 20

    var isAwaitingPageConfirmation: Bool {
        source == .photo && !pagesConfirmed
    }

    var remainingPageRoom: Int {
        max(0, Self.maxPages - (pages ?? []).count)
    }

    // Returns how many pages didn't fit under the cap.
    @discardableResult
    func addPages(_ processed: [PageImageProcessor.ProcessedPage], origin: PageOrigin, in context: ModelContext) -> Int {
        guard !pagesConfirmed else { return processed.count }
        let accepted = processed.prefix(remainingPageRoom)
        var next = (pages ?? []).count
        for item in accepted {
            let page = EntryPage(index: next, imageData: item.imageData, thumbnailData: item.thumbnailData, pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight, origin: origin)
            context.insert(page)
            page.entry = self
            next += 1
        }
        return processed.count - accepted.count
    }

    @discardableResult
    func movePages(from source: IndexSet, to destination: Int) -> Bool {
        guard !pagesConfirmed else { return false }
        let current = sortedPages
        guard source.allSatisfy({ current.indices.contains($0) }), (0...current.count).contains(destination) else { return false }
        // Same semantics as SwiftUI's onMove: destination is an index in the list before removal.
        let moving = source.map { current[$0] }
        var ordered = current.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.filter { $0 < destination }.count
        ordered.insert(contentsOf: moving, at: insertAt)
        reindex(ordered)
        return true
    }

    // Deletes the page itself, not just the link, so no orphaned image stays in the store.
    @discardableResult
    func removePage(_ page: EntryPage, in context: ModelContext) -> Bool {
        guard !pagesConfirmed, page.entry?.id == id else { return false }
        let remaining = sortedPages.filter { $0.persistentModelID != page.persistentModelID }
        pages?.removeAll { $0.persistentModelID == page.persistentModelID }
        context.delete(page)
        reindex(remaining)
        return true
    }

    // Locks the order. Transcription starts only when AI can run; otherwise the pages wait for a tap.
    @discardableResult
    func confirmPages(aiUsable: Bool) -> Bool {
        guard isAwaitingPageConfirmation, !(pages ?? []).isEmpty else { return false }
        pagesConfirmed = true
        awaitingText = aiUsable
        return true
    }

    private func reindex(_ ordered: [EntryPage]) {
        for (index, page) in ordered.enumerated() where page.index != index {
            page.index = index
        }
    }
}

// MARK: - Page transcription and review

extension Entry {
    var allPagesTranscribed: Bool {
        let pages = sortedPages
        return !pages.isEmpty && pages.allSatisfy { $0.transcribedText != nil }
    }

    // Page texts in order, blank pages skipped, separated by blank lines.
    var joinedPageText: String {
        sortedPages.compactMap(\.transcribedText).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    // Whether to offer bringing back the page transcription after the user typed over it.
    var canReplaceWithPageTranscription: Bool {
        source == .photo && pagesConfirmed && allPagesTranscribed && !awaitingText && !textReviewPending && text != joinedPageText
    }

    // Returns false if there was nothing to approve. The caller fires the automatic AI pass.
    @discardableResult
    func approveText() -> Bool {
        guard textReviewPending else { return false }
        textReviewPending = false
        return true
    }

    // Puts the page transcription back as the entry text, to be reviewed again.
    @discardableResult
    func replaceWithPageTranscription() -> Bool {
        guard canReplaceWithPageTranscription else { return false }
        text = joinedPageText
        textWasGenerated = true
        textEditedByUser = false
        textReviewPending = true
        return true
    }

    // Applies an edited page list to a confirmed entry and starts it over: everything derived from the
    // old pages (text, title, insights, AI state) is cleared. Pages, createdAt, and the entry date stay.
    func restartPages(applying draft: [PageDraftItem], aiUsable: Bool, in context: ModelContext) {
        let keptIDs = Set(draft.compactMap(\.existingPage).map(\.persistentModelID))
        for page in sortedPages where !keptIDs.contains(page.persistentModelID) {
            pages?.removeAll { $0.persistentModelID == page.persistentModelID }
            context.delete(page)
        }
        for (index, item) in draft.enumerated() {
            switch item.content {
            case .existing(let page):
                page.index = index
            case .new(let processed, let origin):
                let page = EntryPage(index: index, imageData: processed.imageData, thumbnailData: processed.thumbnailData, pixelWidth: processed.pixelWidth, pixelHeight: processed.pixelHeight, origin: origin)
                context.insert(page)
                page.entry = self
            }
        }

        contentRevision += 1
        text = ""
        title = ""
        titleWasGenerated = false
        textWasGenerated = false
        textEditedByUser = false
        originalText = nil
        textGeneratedBy = nil
        textFallbackReasonRaw = nil
        textReviewPending = false
        suggestedEntryDate = nil
        for page in sortedPages {
            page.transcribedText = nil
            page.writtenDate = nil
        }
        awaitingText = false
        titlePending = false
        insightsPending = false
        textAttempts = 0
        textFailureRaw = nil
        titleAttempts = 0
        titleFailureRaw = nil
        insightsAttempts = 0
        insightsFailureRaw = nil
        pageRequestCount = 0
        automaticAIPassUsed = false
        removeInsights(in: context)
        pagesConfirmed = true
        awaitingText = aiUsable
    }
}

// One row of the page list while editing a confirmed entry: an existing page or a newly added one.
struct PageDraftItem: Identifiable {
    enum Content {
        case existing(EntryPage)
        case new(PageImageProcessor.ProcessedPage, PageOrigin)
    }

    let id = UUID()
    let content: Content

    var existingPage: EntryPage? {
        if case .existing(let page) = content { page } else { nil }
    }

    var thumbnailData: Data? {
        switch content {
        case .existing(let page): page.thumbnailData
        case .new(let processed, _): processed.thumbnailData
        }
    }

    var pixelWidth: Int {
        switch content {
        case .existing(let page): page.pixelWidth
        case .new(let processed, _): processed.pixelWidth
        }
    }

    var origin: PageOrigin {
        switch content {
        case .existing(let page): page.origin
        case .new(_, let origin): origin
        }
    }

    static func draft(from entry: Entry) -> [PageDraftItem] {
        entry.sortedPages.map { PageDraftItem(content: .existing($0)) }
    }

    // True when applying the draft would change the entry's pages or their order.
    static func differs(_ draft: [PageDraftItem], from entry: Entry) -> Bool {
        let current = entry.sortedPages
        guard draft.count == current.count else { return true }
        return zip(draft, current).contains { item, page in
            item.existingPage?.persistentModelID != page.persistentModelID
        }
    }
}
