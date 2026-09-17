import Foundation
import SwiftData
import Testing
@testable import Mindlore

@MainActor
struct ReviewQueueTests {
    private func unsure(_ surface: String) -> GraphServices.UnsureMention {
        .init(mention: MentionRef(entryID: UUID(), surface: surface, kind: .person),
              candidates: [.init(id: UUID(), name: "A"), .init(id: UUID(), name: "B")])
    }

    @Test func whichOneComesBeforeLikelySame() {
        let pair = EntityMatcher.Suggestion(a: UUID(), b: UUID(), score: 0.95)
        let which = unsure("Sam")
        let question = ReviewQueue.next(suggestions: [pair], unsure: [which], skipped: [])
        guard case .whichOne(let asked) = question else {
            Issue.record("expected which one, got \(String(describing: question))")
            return
        }
        #expect(asked.mention == which.mention)
    }

    @Test func skippingAdvancesAndTheEndIsNil() throws {
        let first = EntityMatcher.Suggestion(a: UUID(), b: UUID(), score: 0.95)
        let second = EntityMatcher.Suggestion(a: UUID(), b: UUID(), score: 0.9)
        let which = unsure("Sam")
        var skipped: Set<String> = []

        let one = try #require(ReviewQueue.next(suggestions: [first, second], unsure: [which], skipped: skipped))
        skipped.insert(one.id)
        let two = try #require(ReviewQueue.next(suggestions: [first, second], unsure: [which], skipped: skipped))
        guard case .same(let a, _) = two else {
            Issue.record("expected a pair")
            return
        }
        #expect(a == first.a)
        skipped.insert(two.id)
        let three = try #require(ReviewQueue.next(suggestions: [first, second], unsure: [which], skipped: skipped))
        skipped.insert(three.id)
        #expect(ReviewQueue.next(suggestions: [first, second], unsure: [which], skipped: skipped) == nil)
        #expect(ReviewQueue.next(suggestions: [], unsure: [], skipped: []) == nil)
    }

    // Answering through the graph removes the question the next time the queue is asked.
    @Test func answeringRemovesTheQuestion() throws {
        let harness = try GraphHarness()
        let graph = GraphServices(diagnostics: .disabled)
        let context = harness.context
        try harness.entry("Sarah.", mentions: [("Sarah", .person)])
        try harness.entry("Sara.", mentions: [("Sara", .person)])
        graph.indexer.sweep(in: context)

        func ask() -> ReviewQueue.Question? {
            ReviewQueue.next(suggestions: graph.editor.suggestions(in: context), unsure: graph.unsureLinks(in: context), skipped: [])
        }
        guard case .same(let a, let b) = try #require(ask()) else {
            Issue.record("expected Sarah and Sara to look alike")
            return
        }
        graph.markNotSame(a, b, in: context)
        #expect(ask() == nil)
    }

    // A tie left with one visible candidate answers itself inside unsureLinks, so no question.
    @Test func aTieThatResolvesItselfAsksNothing() throws {
        let harness = try GraphHarness()
        let graph = GraphServices(diagnostics: .disabled)
        let context = harness.context
        let entry = try harness.entry("Sam called.")
        let visible = Entity(name: "Sam Lee", key: "sam lee", kind: .person)
        let hidden = Entity(name: "Sam Ortiz", key: "sam ortiz", kind: .person)
        hidden.hidden = true
        context.insert(visible)
        context.insert(hidden)
        let link = EntityLink(surface: "Sam", kind: .person)
        context.insert(link)
        link.attach(to: entry, entity: hidden)
        link.unsureAmong = [visible.id, hidden.id]
        try context.save()

        #expect(graph.unsureLinks(in: context).isEmpty)
        #expect(ReviewQueue.next(suggestions: [], unsure: graph.unsureLinks(in: context), skipped: []) == nil)
        #expect(link.entityID == visible.id)
    }
}

extension ReviewQueue.Question: @retroactive Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
