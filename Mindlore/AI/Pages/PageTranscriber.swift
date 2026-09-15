import Foundation

nonisolated struct PageRequest: Sendable {
    let imageJPEG: Data
    let pageNumber: Int
    let pageCount: Int
    // The end of the previous page's text, so a sentence that runs across pages stays whole.
    let previousPageTail: String?
}

nonisolated struct PageResult: Sendable, Equatable {
    // Empty for a blank page.
    let text: String
    let writtenDate: Date?
    let inputTokens: Int?
    let outputTokens: Int?
}

nonisolated protocol PageTranscriber: Sendable {
    func transcribe(_ request: PageRequest) async throws -> PageResult
}

// Transcribes a handwritten page through a vision-capable text model with a verbatim prompt.
nonisolated struct OpenAICompatiblePageTranscriber: PageTranscriber {
    static let tailLength = 300
    static let maxOutputTokens = 4_000

    let generator: any TextGenerator
    let model: String
    var calendar: Calendar = .current

    static let systemPrompt = """
    You transcribe photographed pages of a personal handwritten journal.

    Copy the writing exactly as written: keep the writer's words, spelling, grammar, and punctuation. \
    Do not correct, summarize, reword, or add anything. Keep paragraph breaks; join lines that were only \
    wrapped by the edge of the page. Write [illegible] for any word you cannot read. Ignore printed page \
    furniture such as ruled lines, page numbers, and headers. If the page has no handwriting, return an empty string.

    writtenDate is the date this journal entry was written on, if the page states it with a year, month, and \
    day, as yyyy-MM-dd. Ignore other dates mentioned in the writing. Use null if there is no such date or any part is missing.
    """

    static let schema = JSONSchema.object([
        .init("text", .string(description: "The page's writing, transcribed verbatim.")),
        .init("writtenDate", .string(description: "yyyy-MM-dd, or null.", nullable: true)),
    ])

    func transcribe(_ request: PageRequest) async throws -> PageResult {
        var user = "Page \(request.pageNumber) of \(request.pageCount)."
        if let tail = request.previousPageTail, !tail.isEmpty {
            user += "\n\nThe previous page ended with:\n\(tail)\n\nDo not repeat that text; transcribe only this page."
        }
        let result = try await generator.generate(TextRequest(
            model: model,
            system: Self.systemPrompt,
            user: user,
            images: [TextImage(jpegData: request.imageJPEG, detail: .high)],
            schema: Self.schema,
            schemaName: "journal_page",
            maxOutputTokens: Self.maxOutputTokens
        ))
        struct Page: Decodable {
            let text: String
            let writtenDate: String?
        }
        let page = try StructuredOutputParser.decode(Page.self, from: result.text)
        return PageResult(
            text: page.text.trimmingCharacters(in: .whitespacesAndNewlines),
            writtenDate: page.writtenDate.flatMap { EntryDates.parseDay($0, calendar: calendar) },
            inputTokens: result.inputTokens,
            outputTokens: result.outputTokens
        )
    }

    static func tail(of text: String) -> String {
        String(text.suffix(tailLength))
    }
}
