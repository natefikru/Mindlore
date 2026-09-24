import Foundation
import SwiftData

// The one thing Chat may write: a new note the author asked for (owner, 2026-09-24). Never a
// journal entry or a creative piece, never a draft, and never a change to an entry that already
// exists: the kind is set here, not taken from the model, and there is no path in here that
// fetches an entry to change it.
//
// The note's id is the id of the answer that made it. That is what lets a conversation reopened
// from history find its note again without a field on AskMessage (a model change, and a CloudKit
// schema deploy), and what makes creating it twice impossible: a second call for the same answer
// finds the first note and stops.
enum AskNoteWriter {
    // Generous for a list or a plan, and a ceiling on a model that ran on.
    static let maxTitleCharacters = 120
    static let maxTextCharacters = 20_000

    // Who wrote the text, in the field transcription uses for the same question.
    static func generatedBy(_ providerLabel: String) -> String {
        "chat:\(providerLabel)"
    }

    // Inserts the note; the caller saves (through saveStampingEntries, so the entry is backed up
    // and the journal's save counter moves), in the same save as the answer that confirms it. Nil
    // when there was nothing to write, or the note already exists.
    @discardableResult
    static func insert(
        _ request: AskAnswerParser.NoteRequest,
        id: UUID,
        providerLabel: String,
        now: Date,
        in context: ModelContext
    ) -> Entry? {
        let existing = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
        guard ((try? context.fetch(existing)) ?? []).isEmpty else { return nil }
        // Markdown at the edge, as a cleanup is read: a checklist the model wrote becomes the
        // editor's own checklist, and no syntax is ever stored in the text.
        let parsed = MarkdownCodec.parse(String(request.text.prefix(maxTextCharacters)))
        guard !parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let note = Entry(id: id, createdAt: now, source: .typed, text: parsed.text)
        note.formatting = parsed.formatting
        // The author's own call, in their own words, so a later insights run never files it as
        // something else.
        note.setKindByUser(.note)
        note.isDraft = false
        // Written by the model at the author's request, not typed by them. A title stays the
        // author's: marked generated, the title pass would replace the one they asked for.
        note.textWasGenerated = true
        note.textGeneratedBy = generatedBy(providerLabel)
        note.title = String(request.title.prefix(maxTitleCharacters))
        context.insert(note)
        return note
    }
}
