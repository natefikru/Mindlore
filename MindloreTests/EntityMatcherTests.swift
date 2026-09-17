import Foundation
import Testing
@testable import Mindlore

struct JaroWinklerTests {
    // Published values for the algorithm, so a rewrite of the inner loop is caught.
    @Test(arguments: [
        ("martha", "marhta", 0.961),
        ("dixon", "dicksonx", 0.813),
        ("dwayne", "duane", 0.840),
        ("jellyfish", "smellyfish", 0.896),
    ])
    func matchesKnownValues(_ a: String, _ b: String, _ expected: Double) {
        #expect(abs(EntityMatcher.jaroWinkler(a, b) - expected) < 0.001)
    }

    @Test func identicalAndEmpty() {
        #expect(EntityMatcher.jaroWinkler("sarah", "sarah") == 1)
        #expect(EntityMatcher.jaroWinkler("", "") == 1)
        #expect(EntityMatcher.jaroWinkler("sarah", "") == 0)
        #expect(EntityMatcher.jaroWinkler("", "sarah") == 0)
    }

    @Test func nothingInCommonScoresZero() {
        #expect(EntityMatcher.jaroWinkler("abc", "xyz") == 0)
    }

    @Test func itIsSymmetric() {
        for (a, b) in [("sarah kim", "sarah kym"), ("mom", "tom"), ("acme", "acme corp")] {
            #expect(abs(EntityMatcher.jaroWinkler(a, b) - EntityMatcher.jaroWinkler(b, a)) < 0.0001)
        }
    }

    @Test func subsetIsAboutWholeWords() {
        #expect(EntityMatcher.isSubset("sarah", "sarah kim"))
        #expect(EntityMatcher.isSubset("sarah kim", "sarah"))
        #expect(!EntityMatcher.isSubset("sarah", "sarah"), "the same name is not a subset of itself")
        #expect(!EntityMatcher.isSubset("sar", "sarah kim"), "half a word is not a word")
        #expect(!EntityMatcher.isSubset("", "sarah"))
    }
}

struct EntityMatcherTests {
    private func candidate(
        _ key: String,
        _ kind: EntityKind = .person,
        id: UUID = UUID(),
        linkCount: Int = 1,
        notSameAs: [UUID] = []
    ) -> EntityMatcher.Candidate {
        .init(id: id, key: key, kind: kind, linkCount: linkCount, notSameAs: notSameAs)
    }

    @Test func aNearMissIsSuggested() {
        let a = candidate("sarah kim")
        let b = candidate("sarah kym")
        let found = EntityMatcher.suggestions(among: [a, b])
        #expect(found.count == 1)
        #expect(Set([found[0].a, found[0].b]) == Set([a.id, b.id]))
    }

    @Test func aFirstNameInsideAFullNameIsSuggested() {
        let a = candidate("sarah")
        let b = candidate("sarah kim")
        let found = EntityMatcher.suggestions(among: [a, b])
        #expect(found.count == 1)
        // The subset rule sets a floor; spelling similarity can push it higher.
        #expect((found.first?.score ?? 0) >= EntityMatcher.subsetScore)
    }

    @Test func twoDifferentPeopleAreNotSuggested() {
        #expect(EntityMatcher.suggestions(among: [candidate("sarah kim"), candidate("robert jones")]).isEmpty)
        // The pair that sets the threshold: close in spelling, obviously not the same name.
        #expect(EntityMatcher.suggestions(among: [candidate("mom"), candidate("tom")]).isEmpty)
    }

    @Test func aDismissedPairIsNeverSuggestedAgain() {
        let a = candidate("sarah kim")
        let b = candidate("sarah kym", id: UUID(), linkCount: 1, notSameAs: [a.id])
        #expect(EntityMatcher.suggestions(among: [a, b]).isEmpty)

        // Dismissing is recorded on both sides, but one side is enough to stop it.
        let c = candidate("sarah kim", notSameAs: [b.id])
        #expect(EntityMatcher.suggestions(among: [c, b]).isEmpty)
    }

    @Test func differentKindsAreNotCompared() {
        #expect(EntityMatcher.suggestions(among: [candidate("sarah kim", .person), candidate("sarah kym", .place)]).isEmpty)
    }

    // An `other` is a kind nobody has pinned down, so it is allowed to match anything.
    @Test func anOtherIsComparedAgainstEveryKind() {
        let vague = candidate("acme corp", .other)
        let organization = candidate("acme corp.", .organization)
        #expect(EntityMatcher.suggestions(among: [vague, organization]).count == 1)
    }

    // Two tags written nearly alike are worth a look, like any other pair of the same kind.
    @Test func nearlyIdenticalTagsAreSuggested() {
        let tag = candidate("career anxiety", .tag)
        let nearly = candidate("career anxieties", .tag)
        #expect(EntityMatcher.suggestions(among: [tag, nearly]).count == 1)
        #expect(EntityMatcher.suggestions(among: [tag, candidate("career anxiety", .person)]).isEmpty)
    }

    @Test func identicalKeysScoreOne() {
        let a = candidate("sarah kim")
        let b = candidate("sarah kim")
        #expect(EntityMatcher.suggestions(among: [a, b]).first?.score == 1)
    }

    // The user's attention is worth more on the entities the journal actually uses.
    @Test func busierPairsRankFirst() {
        let quietA = candidate("bob smith", linkCount: 1)
        let quietB = candidate("bob smyth", linkCount: 1)
        let busyA = candidate("sarah kim", linkCount: 30)
        let busyB = candidate("sarah kym", linkCount: 20)

        let found = EntityMatcher.suggestions(among: [quietA, quietB, busyA, busyB])
        #expect(found.count == 2)
        #expect(Set([found[0].a, found[0].b]) == Set([busyA.id, busyB.id]))
    }

    @Test func everyPairIsOfferedOnce() {
        let a = candidate("sarah kim")
        let b = candidate("sarah kym")
        let c = candidate("sarah kimm")
        let found = EntityMatcher.suggestions(among: [a, b, c])
        #expect(found.count == 3)
        let pairs = Set(found.map { Set([$0.a, $0.b]) })
        #expect(pairs.count == 3)
    }

    @Test func anEmptyKeyIsNeverSuggested() {
        #expect(EntityMatcher.suggestions(among: [candidate(""), candidate("")]).isEmpty)
        #expect(EntityMatcher.suggestions(among: [candidate(""), candidate("sarah")]).isEmpty)
    }
}
