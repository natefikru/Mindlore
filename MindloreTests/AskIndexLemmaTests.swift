import Foundation
import Testing
@testable import Mindlore

// Lemmas as a second, weaker term beside the word the entry actually used.
//
// Two of these pin mistakes made while building it, both of which passed the paraphrase
// measurement while breaking something else: lemmas that skipped the stop list turned a question
// of nothing but stop words into a question about "go" and "what", and iterating an unordered set
// shuffled the term order the conversation is supposed to read in. The measurement went up in both
// cases, which is exactly why neither is measured by it.
@Suite(.enabled(if: LemmaAvailability.isAvailable, "NLTagger has no English lemma assets on this machine"))
struct AskIndexLemmaTests {
    private let now = Date(timeIntervalSince1970: 1_789_394_400)

    private func index(_ texts: [(key: String, text: String)]) -> AskIndex {
        let inputs = texts.map { entry in
            AskIndex.DocumentInput(
                id: id(for: entry.key),
                date: now.addingTimeInterval(-86_400),
                title: "",
                text: entry.text,
                entityIDs: [],
                entityNames: [],
                tags: [],
                areas: [],
                mood: nil,
                isSendable: true,
                blockCharacters: AskContextBuilder.blockCharacterEstimate(title: "", text: entry.text)
            )
        }
        return AskIndex.build(from: inputs, entities: [])
    }

    private func id(for key: String) -> UUID {
        var bytes = Array(key.utf8.prefix(16))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 16 - bytes.count))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private func found(_ question: String, in index: AskIndex, keys: [String]) -> [String] {
        let byID = Dictionary(keys.map { (id(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        // The real expansion, not the bare term list: the lemma pass is what is under test.
        let terms = AskRetrievalQuery.expanded(question).map { AskIndex.Term(text: $0.text, weight: $0.weight) }
        var query = AskIndex.Query(terms: terms)
        query.asOf = now
        return index.search(query).compactMap { byID[index.documents[Int($0.document)].id] }
    }

    // MARK: - What it is for

    @Test func anIrregularVerbIsFoundByItsDictionaryForm() {
        #expect(AskIndex.lemmas(in: "Ran the loop before work").contains("run"))
        #expect(AskIndex.lemmas(in: "Flew out on the Tuesday").contains("fly"))
    }

    @Test func aQuestionInOneFormFindsAnEntryWrittenInAnother() {
        let built = index([("ran", "Ran the loop in thirty-one minutes."), ("other", "Sold the car to a man who barely looked at it.")])

        #expect(found("How was the run?", in: built, keys: ["ran", "other"]).first == "ran")
    }

    // The other direction: the entry uses the dictionary form and the question inflects it. This
    // is the half the query-side lemmas exist for; the index-side ones cover the commoner half.
    @Test func itWorksWhenTheQuestionIsTheInflectedOne() {
        let built = index([("run", "I run the loop most mornings."), ("other", "Sold the car.")])

        #expect(found("How is the running going?", in: built, keys: ["run", "other"]).first == "run")
    }

    // MARK: - What it must not do

    @Test func aLemmaIsNeverAStopWord() {
        // "going" lemmatizes to "go", and "go" is a stop word. Left in, a question made entirely of
        // stop words asks for them and stops being about its subject.
        let lemmas = AskIndex.lemmas(in: "What is going on with Maya?")

        #expect(lemmas.contains("maya"))
        #expect(!lemmas.contains("go"))
        #expect(!lemmas.contains("what"))
    }

    @Test func aQuestionOfNothingButStopWordsAsksForNothing() {
        #expect(AskRetrievalQuery.terms(in: "Why?").isEmpty)
        #expect(AskIndex.lemmas(in: "Why? What happened?").isEmpty)
    }

    @Test func theSurfaceFormOutranksTheLemma() {
        // One entry writes the word the question used; the other only reaches it through a lemma.
        // Both are the same length and the same age, so the only thing separating them is that a
        // lemma is discounted. At equal weight these tie, and the pair that used to be separable
        // by which form they used stops being separable, which is what regressed at 1.0.
        let built = index([("wrote", "I run the loop."), ("lemma", "I ran the loop.")])

        #expect(found("run", in: built, keys: ["wrote", "lemma"]) == ["wrote", "lemma"])
        #expect(AskIndex.lemmaFactor < 1)
    }

    @Test func aLemmaDoesNotMakeAnEntryLookLonger() {
        // Document length is how many words were written, and BM25 divides by it. Counting shadow
        // terms would make every entry look more diluted than it is, and the dilution would land
        // hardest on the entries with the most irregular verbs.
        let plain = index([("a", "I run the loop.")])
        let inflected = index([("a", "I ran the loop.")])

        #expect(plain.documents[0].length == inflected.documents[0].length)
    }

    @Test func termsKeepTheirOrderWhenLemmasAreAdded() {
        // The term list reads the way the conversation ran, and the lemma pass must not shuffle it.
        let terms = AskRetrievalQuery.terms(in: "kayak paddle river")

        #expect(terms == ["kayak", "paddle", "river"])
    }

    // MARK: - Saying so on screen

    @Test func aRowThatRankedOnALemmaSaysWhy() {
        let entry = Entry(createdAt: now, text: "Ran the loop in thirty-one minutes.")

        #expect(JournalSearch.lemmaMatched(query: "run", in: entry))
        #expect(!JournalSearch.lemmaMatched(query: "kayak", in: entry))
        // A word the entry really wrote also answers true here, which is harmless: `reason` only
        // reaches this after `matchedWord` has already found it and returned no caption at all.
        #expect(JournalSearch.lemmaMatched(query: "loop", in: entry))
    }
}
