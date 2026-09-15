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
