import Foundation

// What arrives while an answer is being written.
nonisolated enum TextStreamEvent: Sendable, Equatable {
    // The next piece of text, exactly as the provider sent it. With a schema this is raw JSON,
    // arriving a few characters at a time.
    case delta(String)
    // The whole thing, once: the same TextResult the single-shot path would have returned, so a
    // caller that only wants the end can ignore every delta and still count tokens.
    case finished(TextResult)
}

// A generator that can hand the answer over as it is written. Opting in is conformance, not a
// provider check, so a second streaming provider needs nothing from the caller.
nonisolated protocol StreamingTextGenerator: TextGenerator {
    func stream(_ request: TextRequest) -> AsyncThrowingStream<TextStreamEvent, any Error>
}
