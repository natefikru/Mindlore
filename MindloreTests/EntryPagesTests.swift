import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct EntryPagesTests {
    private func processed(_ widths: [Int]) -> [PageImageProcessor.ProcessedPage] {
        widths.map { PageImageProcessor.ProcessedPage(imageData: Data([UInt8($0 % 255)]), thumbnailData: Data([1]), pixelWidth: $0, pixelHeight: 100) }
    }

    private func photoEntry(_ widths: [Int], in context: ModelContext) -> Entry {
        let entry = Entry(source: .photo)
        context.insert(entry)
        entry.addPages(processed(widths), origin: .camera, in: context)
        return entry
    }

    private func order(_ entry: Entry) -> [Int] {
        entry.sortedPages.map(\.pixelWidth)
    }

    private func indexesAreContiguous(_ entry: Entry) -> Bool {
        entry.sortedPages.map(\.index) == Array(0..<entry.sortedPages.count)
    }

    @Test func addingPagesAppendsInOrderWithOrigin() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = photoEntry([10, 20], in: container.mainContext)
        entry.addPages(processed([30]), origin: .library, in: container.mainContext)

        #expect(order(entry) == [10, 20, 30])
        #expect(indexesAreContiguous(entry))
        #expect(entry.sortedPages.map(\.origin) == [.camera, .camera, .library])
        #expect(entry.isAwaitingPageConfirmation)
    }

    @Test func pagesPastTheCapAreLeftOut() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = photoEntry(Array(1...18), in: container.mainContext)

        let leftOut = entry.addPages(processed([100, 101, 102, 103]), origin: .library, in: container.mainContext)

        #expect(leftOut == 2)
        #expect(entry.sortedPages.count == 20)
        #expect(order(entry).suffix(2) == [100, 101])
        #expect(entry.remainingPageRoom == 0)
    }

    @Test func movingPagesFollowsListMoveSemantics() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = photoEntry([1, 2, 3, 4], in: container.mainContext)

        #expect(entry.movePages(from: [0], to: 3))
        #expect(order(entry) == [2, 3, 1, 4])
        #expect(entry.movePages(from: [3], to: 0))
        #expect(order(entry) == [4, 2, 3, 1])
        #expect(entry.movePages(from: [1, 2], to: 4))
        #expect(order(entry) == [4, 1, 2, 3])
        #expect(indexesAreContiguous(entry))
        #expect(!entry.movePages(from: [9], to: 0))
    }

    @Test func removingAPageDeletesItFromTheStoreAndReindexes() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = photoEntry([1, 2, 3], in: context)
        try context.save()

        #expect(entry.removePage(entry.sortedPages[1], in: context))
        try context.save()

        #expect(order(entry) == [1, 3])
        #expect(indexesAreContiguous(entry))
        #expect(try context.fetchCount(FetchDescriptor<EntryPage>()) == 2)
    }

    @Test func confirmingLocksTheOrder() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = photoEntry([1, 2], in: context)

        #expect(entry.confirmPages(aiUsable: true))
        #expect(entry.pagesConfirmed && entry.awaitingText)
        #expect(!entry.isAwaitingPageConfirmation)

        #expect(!entry.movePages(from: [0], to: 2))
        #expect(!entry.removePage(entry.sortedPages[0], in: context))
        #expect(entry.addPages(processed([9]), origin: .camera, in: context) == 1)
        #expect(order(entry) == [1, 2])
        #expect(!entry.confirmPages(aiUsable: true))
    }

    @Test func confirmingWithoutAIOnlySavesThePages() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = photoEntry([1], in: container.mainContext)

        #expect(entry.confirmPages(aiUsable: false))
        #expect(entry.pagesConfirmed)
        #expect(!entry.awaitingText)
    }

    @Test func anEntryWithNoPagesCantBeConfirmed() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = Entry(source: .photo)
        container.mainContext.insert(entry)
        #expect(!entry.confirmPages(aiUsable: true))
    }

    @Test func aPagesOnlyEntrySurvivesEditorClose() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let entry = photoEntry([1], in: context)
        entry.confirmPages(aiUsable: false)

        #expect(!Entry.editorDidClose(entry, keepAudio: false, in: context))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Entry>()) == 1)
    }

    @Test func pagesArentPickedUpByVoiceTranscriptionOrTheAIPass() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let entry = photoEntry([1], in: container.mainContext)
        entry.confirmPages(aiUsable: true)
        #expect(!AIPassTrigger.isEligible(entry, automationStartedAt: .distantPast))
    }

    @Test func processedPagesAreStoredAtStorageSizeWithThumbnails() throws {
        let jpeg = FakePages.make(count: 1, startingWidth: 3_000)[0]
        let page = try PageImageProcessor.process(jpeg)
        #expect(max(page.pixelWidth, page.pixelHeight) == PageImageProcessor.storageLongEdge)
        #expect(page.thumbnailData.count < page.imageData.count)
    }

    @Test func noticesDescribeLeftOutAndFailedPages() {
        #expect(PageOrderView.notice(leftOut: 0, failed: 0) == nil)
        #expect(PageOrderView.notice(leftOut: 2, failed: 0) == "2 pages were left out. An entry holds up to 20 pages.")
        #expect(PageOrderView.notice(leftOut: 1, failed: 1) == "1 page was left out. An entry holds up to 20 pages. 1 image couldn't be added.")
    }
}
