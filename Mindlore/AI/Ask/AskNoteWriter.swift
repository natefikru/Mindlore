import Foundation
import SwiftData

// What Chat may write (owner, 2026-09-24): a new note the author asked for, or a new version of a
// note it was shown whole. Never a journal entry or a creative piece, never a draft, never a
// delete. A new note's kind is set here, not taken from the model, and a change re-checks the
// entry it lands on (isEditable) at the moment it is applied.
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

    // The only entries Chat may change: a finished note Ask could send. Checked again when an edit
    // lands, because the entry can have been re-filed, reopened as a draft, or deleted since the
    // prompt went out.
    static func isEditable(_ entry: Entry) -> Bool {
        !entry.isDeleted && entry.kind == .note && !entry.isDraft && InsightsCoordinator.canRunAI(on: entry)
    }

    // A new version of a note, replacing its text whole, as a typed edit would. `sentText` is the
    // text the model was shown: if the note changed since, the rewrite was made from something the
    // author has already moved past, and applying it would undo their edit, so nothing is written.
    // Nil when nothing was written, which is the only case in which no chip shows. The caller saves.
    //
    // Like a typed edit, it leaves contentRevision alone (that counter is for a page restart, and
    // bumping it would throw away a title or insights run already on its way), and the insights go
    // stale by their text hash, to be run again from the insights sheet. The previous text is not
    // kept: there is nowhere to keep it without a model change.
    @discardableResult
    static func replace(
        _ request: AskAnswerParser.NoteRequest,
        id entryID: UUID,
        sentText: String,
        providerLabel: String,
        now: Date,
        in context: ModelContext
    ) -> Entry? {
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == entryID })
        guard let note = ((try? context.fetch(descriptor)) ?? []).first(where: { !$0.isDeleted }),
              isEditable(note), note.text == sentText else { return nil }
        let parsed = MarkdownCodec.parse(String(request.text.prefix(maxTextCharacters)))
        guard !parsed.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let title = String(request.title.prefix(maxTitleCharacters))
        let newTitle = title.isEmpty ? note.title : title
        // A rewrite identical to what is there changed nothing, and must not say it did.
        guard parsed.text != note.text || parsed.formatting != note.formatting || newTitle != note.title else { return nil }

        note.text = parsed.text
        note.formatting = parsed.formatting
        if newTitle != note.title {
            note.title = newTitle
            note.titleWasGenerated = false
        }
        // The words on the page are now the model's, written at the author's request.
        note.textWasGenerated = true
        note.textGeneratedBy = generatedBy(providerLabel)
        note.textEditedByUser = false
        note.updatedAt = now
        return note
    }
}
