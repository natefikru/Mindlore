import Foundation
import Testing
@testable import Mindlore

// Written against what NameMatching actually does, not what it looks like it does: it is a
// whole-word, case-insensitive matcher, so every rule here exists to narrow it.
struct EntityProseRewriterTests {
    @Test func anExactWholeWordMatchIsReplaced() {
        #expect(EntityProseRewriter.rewrite("Sarah walks by the river.", from: "Sarah", to: "Sarah Kim")
                == "Sarah Kim walks by the river.")
    }

    @Test func nothingToChangeReturnsNil() {
        #expect(EntityProseRewriter.rewrite("Tom walks by the river.", from: "Sarah", to: "Sarah Kim") == nil)
        #expect(EntityProseRewriter.rewrite("", from: "Sarah", to: "Sarah Kim") == nil)
    }

    // The reason the rule isn't just NameMatching: entities named Mark, Will, Ray, or Hope match
    // ordinary words, and a case-insensitive replacement would rewrite prose into nonsense.
    @Test func aDifferentlyCasedMatchIsLeftAlone() {
        #expect(EntityProseRewriter.rewrite("I want to make my mark this year.", from: "Mark", to: "Mark Ruiz") == nil)
        #expect(EntityProseRewriter.rewrite("I will go tomorrow.", from: "Will", to: "Will Baker") == nil)
        #expect(EntityProseRewriter.rewrite("sarah called.", from: "Sarah", to: "Sarah Kim") == nil)
    }

    // NameMatching matches "Sarah" inside "Sarah Jane", because a space is not a letter.
    @Test func aNameInsideALongerNameIsLeftAlone() {
        #expect(EntityProseRewriter.rewrite("Sarah Jane came by.", from: "Sarah", to: "Sarah Kim") == nil)
        #expect(EntityProseRewriter.rewrite("Dinner with Jane Sarah.", from: "Sarah", to: "Sarah Kim") == nil)
    }

    // Over-skipping is the safe way to be wrong: leaving prose alone beats editing the wrong
    // words in a rewrite nobody can undo.
    @Test func aCapitalizedNeighbourIsSkippedEvenWhenItIsNotAName() {
        #expect(EntityProseRewriter.rewrite("Saw Sarah Monday evening.", from: "Sarah", to: "Sarah Kim") == nil)
    }

    // A capital at the start of a sentence is punctuation, not a surname. Treating it as one
    // would leave almost every real occurrence untouched, since a name so often follows the
    // first word of a sentence.
    @Test func aSentenceInitialWordIsNotASurname() {
        #expect(EntityProseRewriter.rewrite("Told Sarah about it.", from: "Sarah", to: "Luis")
                == "Told Luis about it.")
        #expect(EntityProseRewriter.rewrite("Call Sarah about the weekend", from: "Sarah", to: "Luis")
                == "Call Luis about the weekend")
        #expect(EntityProseRewriter.rewrite("It rained. Met Sarah anyway.", from: "Sarah", to: "Luis")
                == "It rained. Met Luis anyway.")
        // Mid-sentence, the same capital really does read as part of a name.
        #expect(EntityProseRewriter.rewrite("Dinner with Jane Sarah.", from: "Sarah", to: "Luis") == nil)
    }

    @Test func aLowercaseNeighbourIsNotANeighbour() {
        #expect(EntityProseRewriter.rewrite("Sarah and Tom came by.", from: "Sarah", to: "Sarah Kim")
                == "Sarah Kim and Tom came by.")
        #expect(EntityProseRewriter.rewrite("Told Sarah about it.", from: "Sarah", to: "Sarah Kim")
                == "Told Sarah Kim about it.")
    }

    // Replacing forwards would invalidate every range after the first.
    @Test func severalOccurrencesAreAllReplaced() {
        #expect(EntityProseRewriter.rewrite("Sarah called, then Sarah left, then Sarah called again.", from: "Sarah", to: "Sarah Kim")
                == "Sarah Kim called, then Sarah Kim left, then Sarah Kim called again.")
    }

    @Test func punctuationAndPossessivesAroundTheNameSurvive() {
        #expect(EntityProseRewriter.rewrite("Dinner with Sarah, then home.", from: "Sarah", to: "Luis")
                == "Dinner with Luis, then home.")
        #expect(EntityProseRewriter.rewrite("This is Sarah's idea.", from: "Sarah", to: "Luis")
                == "This is Luis's idea.")
    }

    @Test func anEmptyOrUnchangedNameIsANoOp() {
        #expect(EntityProseRewriter.rewrite("Sarah called.", from: "", to: "Luis") == nil)
        #expect(EntityProseRewriter.rewrite("Sarah called.", from: "   ", to: "Luis") == nil)
        #expect(EntityProseRewriter.rewrite("Sarah called.", from: "Sarah", to: "") == nil)
        #expect(EntityProseRewriter.rewrite("Sarah called.", from: "Sarah", to: "Sarah") == nil)
    }

    // The warning and the rewrite have to agree, so they share the rules.
    @Test func containsAgreesWithRewrite() {
        for (text, name) in [("Sarah walks.", "Sarah"), ("Sarah Jane walks.", "Sarah"), ("make my mark", "Mark")] {
            let rewrote = EntityProseRewriter.rewrite(text, from: name, to: name + " Q") != nil
            #expect(EntityProseRewriter.contains(name, in: text) == rewrote, "\(text) / \(name)")
        }
    }
}
