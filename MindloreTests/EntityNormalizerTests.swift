import Foundation
import Testing
@testable import Mindlore

// The key is what decides whether two mentions are the same thing, so every rule in it
// is pinned here. Changing one of these answers re-partitions an existing graph.
struct EntityNormalizerTests {
    @Test(arguments: [
        // Case, whitespace, and padding all fold away.
        ("Sarah", "sarah"),
        ("SARAH", "sarah"),
        ("  sarah  ", "sarah"),
        ("New   York", "new york"),
        ("new\tyork\n", "new york"),
        // Diacritics: the same person typed two ways.
        ("Němeček", "nemecek"),
        ("NĚMEČEK", "nemecek"),
        ("José", "jose"),
        // Possessives, straight and curly.
        ("Sarah's", "sarah"),
        ("Sarah\u{2019}s", "sarah"),
        ("James'", "james"),
        ("the river's edge", "the river's edge"),
        // Edge punctuation goes, interior marks stay.
        ("Sarah,", "sarah"),
        ("(Sarah)", "sarah"),
        ("\"Sarah\"", "sarah"),
        ("O'Brien", "o'brien"),
        ("Jean-Luc", "jean-luc"),
        ("R2-D2", "r2-d2"),
        // Nothing left to key on.
        ("", ""),
        ("   ", ""),
        ("...", ""),
    ])
    func keysForAnyKind(_ input: String, _ expected: String) {
        #expect(EntityNormalizer.key(for: input, kind: .other) == expected)
    }

    @Test(arguments: [
        ("Dr. Kim", "kim"),
        ("Dr Kim", "kim"),
        ("Mrs. Sarah Kim", "sarah kim"),
        ("Aunt May", "may"),
        ("uncle bob", "bob"),
        ("Professor Lyle Jenkins", "lyle jenkins"),
        // Two honorifics in front of a name still leave the name.
        ("Dr. Mrs. Kim", "kim"),
    ])
    func honorificsAreStrippedFromPeople(_ input: String, _ expected: String) {
        #expect(EntityNormalizer.key(for: input, kind: .person) == expected)
    }

    // An honorific is only noise in front of something else. Alone it is the name.
    @Test func anHonorificOnItsOwnSurvives() {
        #expect(EntityNormalizer.key(for: "Mom", kind: .person) == "mom")
        #expect(EntityNormalizer.key(for: "Aunt", kind: .person) == "aunt")
        #expect(EntityNormalizer.key(for: "Dr.", kind: .person) == "dr")
    }

    // Only people carry honorifics. A place called "Uncle Sam's" keeps its first word.
    @Test func honorificsAreLeftAloneForEveryOtherKind() {
        #expect(EntityNormalizer.key(for: "Uncle Sam's", kind: .place) == "uncle sam")
        #expect(EntityNormalizer.key(for: "Dr Pepper", kind: .organization) == "dr pepper")
        #expect(EntityNormalizer.key(for: "Aunt May", kind: .other) == "aunt may")
    }

    @Test func tagsAndThemesNormalizeLikeEverythingElse() {
        #expect(EntityNormalizer.key(for: "Work", kind: .tag) == "work")
        #expect(EntityNormalizer.key(for: "  career anxiety ", kind: .theme) == "career anxiety")
        // A tag and a theme written the same way produce the same key, which is what
        // lets the Review list offer to merge them.
        #expect(EntityNormalizer.key(for: "Career Anxiety", kind: .tag) == EntityNormalizer.key(for: "career anxiety", kind: .theme))
    }

    @Test func tokensSplitOnSpacesOnly() {
        #expect(EntityNormalizer.tokens(of: "sarah kim") == ["sarah", "kim"])
        #expect(EntityNormalizer.tokens(of: "sarah") == ["sarah"])
        #expect(EntityNormalizer.tokens(of: "") == [])
        #expect(EntityNormalizer.tokens(of: "jean-luc picard") == ["jean-luc", "picard"])
    }

    // The first-name rule in the resolver compares a single token against the first token
    // of a longer name, so these two have to agree.
    @Test func aFirstNameIsTheFirstTokenOfTheFullName() {
        let full = EntityNormalizer.key(for: "Sarah Kim", kind: .person)
        let short = EntityNormalizer.key(for: "Sarah", kind: .person)
        #expect(EntityNormalizer.tokens(of: full).first == short)
        #expect(EntityNormalizer.tokens(of: full).count == 2)
    }

    @Test func normalizingIsIdempotent() {
        for input in ["Dr. Sarah's", "  NĚMEČEK  ", "(Jean-Luc)", "New   York"] {
            let once = EntityNormalizer.key(for: input, kind: .person)
            #expect(EntityNormalizer.key(for: once, kind: .person) == once)
        }
    }
}
