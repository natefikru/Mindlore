@testable import Mindlore

// Whether this machine's NLTagger can lemmatize English, asked of the app's own lemmatizer.
//
// The lemma assets live on the host, not in the simulator: every simulator on a Mac that has
// used them works on its first run, and a GitHub runner that never has returns no lemmas at all,
// with NLTagger.requestAssets waiting forever on a download it cannot make. Tests that measure
// what lemmas add are enabled on this, the same shape as FoundationModelsAvailability for the
// on-device model: they run wherever lemmas work (every Mac here, every phone) and show as skipped
// where they don't, instead of failing on an empty list. See tasks/lessons.md, "A fresh simulator
// has no lemmas".
enum LemmaAvailability {
    static let isAvailable: Bool = AskIndex.lemmas(in: "She ran home").contains("run")
}
