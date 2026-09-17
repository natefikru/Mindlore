import Foundation
import Testing
@testable import Mindlore

@MainActor
struct EntryReadModeTests {
    private let automationStart = Date(timeIntervalSince1970: 1_000)

    private func finished(_ text: String = "A walk by the river.", source: EntrySource = .typed) -> Entry {
        let entry = Entry(createdAt: Date(timeIntervalSince1970: 5_000), source: source, text: text)
        entry.automaticAIPassUsed = true
        return entry
    }

    private func reads(_ entry: Entry?, typing: Bool = false, automation: Date? = Date(timeIntervalSince1970: 1_000)) -> Bool {
        EntryReadMode.opensForReading(entry, routeWantsTyping: typing, automationStartedAt: automation)
    }

    @Test func aFinishedEntryOpensForReading() {
        #expect(reads(finished()))
        #expect(reads(finished(), automation: nil))
    }

    @Test func aNewRouteOpensForTyping() {
        #expect(!reads(nil))
    }

    @Test func workInProgressOpensForTyping() {
        let draft = finished()
        draft.isDraft = true
        #expect(!reads(draft))

        let waiting = finished()
        waiting.awaitingText = true
        #expect(!reads(waiting))

        let review = finished(source: .photo)
        review.pagesConfirmed = true
        review.textReviewPending = true
        #expect(!reads(review))

        let unconfirmed = finished(source: .photo)
        #expect(!reads(unconfirmed))

        #expect(!reads(finished("  \n ")))
    }

    @Test func anEntryStillOfferingDoneOpensForTyping() {
        let entry = finished()
        entry.automaticAIPassUsed = false
        #expect(!reads(entry))
        // Made before automation started, it has no pass to offer, so it reads.
        #expect(reads(entry, automation: Date(timeIntervalSince1970: 9_000)))
    }

    @Test func aRouteThatAsksForTypingGetsIt() {
        #expect(!reads(finished(source: .voice), typing: true))
        #expect(!reads(finished(source: .voice), typing: true, automation: nil))
    }

    @Test func mustTypeCoversEveryStateThatNeedsTheEditor() {
        #expect(!EntryReadMode.mustType(finished()))
        let emptied = finished()
        emptied.text = ""
        #expect(EntryReadMode.mustType(emptied))
        let restarted = finished(source: .photo)
        restarted.pagesConfirmed = true
        restarted.awaitingText = true
        #expect(EntryReadMode.mustType(restarted))
    }
}
