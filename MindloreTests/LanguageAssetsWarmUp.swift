import NaturalLanguage
import Testing

// Ask's index lemmatizes with NLTagger, whose English lemma assets load on first use. On a machine
// that has never used them (every CI runner) the tagger returns nothing until they arrive, and
// AskIndexLemmaTests, AskRetrievalQualityTests, and the live Ask test fail with empty lemma lists
// (tasks/lessons.md, "A fresh simulator has no lemmas"). CI runs this suite on its own before the
// unit run so the assets are in place first; locally it passes at once.
@Suite struct LanguageAssetsWarmUp {
    @Test(.timeLimit(.minutes(5)))
    func englishLemmaAssetsAreAvailable() async throws {
        let result = try await NLTagger.requestAssets(for: .english, tagScheme: .lemma)
        #expect(result == .available)
    }
}
