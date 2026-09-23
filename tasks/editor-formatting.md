# Editor formatting

Branch `claude/editor-formatting`, off `claude/journal-app-improvements-o5kfzx` at `766c69c` (the
commit with `JournalFont`, parts offsets, and the first-keystroke fix; `main` at `ead7a53` has none
of them). Revision 2: the owner's answers folded in (2026-09-23) and phase 1 built. Revision 1's
research (Apple Notes, iOS 26 text APIs, Obsidian and its plugin counts, Day One, Bear, Apple
Journal) is summarised under Findings; the rest of the document is what was decided and built.

## What the editor had

`Entry.text` was a plain `String` in a `UITextView` (`GrowingTextEditor`) set in one font, with no
attributes, no bar above the keyboard, and no typing shortcuts. Read mode was a SwiftUI `Text`
over the same string with name links laid on top, and a tap on it was turned into a caret
position by `ReadTapCaret` re-laying the string out with TextKit. Every reader downstream
(insights, cleanup, parts offsets, Ask, search, export, previews, titles) took the string as prose.

## Findings, in short

Notes has five paragraph styles, four inline marks, three list kinds plus checklists, quotes,
indent, tables, highlights, and collapsible headings, and stores rich text; Markdown is only its
import/export format as of iOS 26. Obsidian, Bear, and Day One store Markdown and render it in
place, and Obsidian's popular plugins (Tasks 4.3M downloads, Templater 5.7M, Editing Toolbar
1.9M, Outliner 1.4M, Various Complements 0.6M, Natural Language Dates 0.5M) add checkbox
metadata, a toolbar, subtree indenting, `[[` autocomplete, and `@today`. Apple's own Journal app
shipped with four inline marks and added flat lists and quotes a year later, no headings. The iOS
26 SwiftUI `TextEditor` over `AttributedString` exists (typechecked against the 26.5 SDK) but its
attribute scope has no paragraph intents: no headings, lists, or checklists to edit or draw.

## Owner decisions (2026-09-23)

1. The user never sees or has to know Markdown. Formatting comes from the keyboard bar and Notes'
   Return and Backspace behaviour. Markers hidden, not dimmed, if that stays simple; typing
   shortcuts only if nearly free.
2. Two heading levels. The entry title uses heading 1's style so the title and headings are one
   type scale.
3. Checklists are visual only. No link to loose ends; the AI keeps finding those in the text. A
   ten-box checklist must not become ten loose ends.
4. `@` picks a name and writes a `.user` link through `GraphEditor.addName`, the same path as Add a
   name.
5. `#word` becomes a user-created tag (a `.user` link to a tag entity), not literal text.
6. The formatting bar hides while a recording shows in the accessory.
7. Cleanup may turn dictation into structure ("first, second" as a numbered list), within the
   cleanup rules: transcribed entries only, only the exact text it was made from, revert still
   works.

## Storage: plain text plus a formatting record, not Markdown

Revision 1 recommended Markdown inside `Entry.text`, on the grounds that the syntax was the
feature. Decision 1 removed that ground, and with it the reason to put syntax in the string. The
built design keeps **`Entry.text` exactly the words the user sees** and stores the layout beside
it: `Entry.formattingRaw` holds `EntryFormatting` as JSON (`Models/EntryFormatting.swift`), a
list of paragraphs by ordinal (block: heading1, heading2, bullet, number, check, checked, quote;
indent 0 to 3) and inline spans by UTF-16 range (bold, italic, strike). `nil` when plain. Both
new columns (`formattingRaw`, `originalFormattingRaw`) are optional, so
`CloudKitSchemaRulesTests` passes unchanged.

Why this beats hidden Markdown markers: with markers in the string, every offset (parts,
name ranges, the caret) is an offset in a string the user cannot see, the caret can land inside
a hidden `**`, and Backspace has to know that deleting one asterisk unbalances a pair. That is
the hairy case the owner named. With attributes, bold is an attribute UITextView already knows
how to type into and delete across, and the string is the plain string. It also means every
downstream consumer is untouched, which the map in revision 1 was mostly about:

- **Insights, title, Ask, search, index, sanitizer, digests, snippets, `previewText`,
  `displayTitle`, `CreativeSignals`, `NameMatching`, `TextHash`, Reflect's fingerprint**: read
  `text`, which has no markers. Nothing to strip anywhere. Formatting-only edits (bolding a word)
  change no hash, so they never make insights stale or rewrite a week's summary.
- **Parts offsets** (`EntrySection.offset`, `GraphServices.analyzedText`): counted in `text`,
  which is what the view shows and what the model read. Unchanged.
- **Transcription** (`applyGeneratedText`, `replaceWithPageTranscription`, `restartPages`): sets
  plain text and clears the formatting.
- **Cleanup** (decision 7): the prompt now asks for Markdown lists where the author spoke one
  (`- `, `1. `, `- [ ] `, `## ` only for a heading the author said, nothing else).
  `Entry.parseCleanup` reads it through `MarkdownCodec.parse` into words plus formatting;
  `applyCleanedText` compares the words against the entry (the same hash rule as before) and
  writes both, keeping `originalText` and `originalFormattingRaw` for revert. The review sheet
  diffs the words, so an added list shows as the same words; the entry draws the list once
  applied. Plain cleanups parse to themselves, so the old tests hold.
- **Export**: `JournalExport.markdown(for:)` renders through `MarkdownCodec.render`, so the `.md`
  file shows the layout; `journal.json` carries `text` and `formatting` separately.
- **Loose ends** (decision 3): the insights prompt reads plain lines and asks for at most
  `maxNewLooseEnds` (2) new threads per run, "usually empty", so a checklist of ten cannot fan
  out. No guard added; noted here.

Markdown exists only in `MarkdownCodec` (render for export, parse for cleanup), a subset that
round-trips: `#`/`##`, `- `, `1. `, `- [ ]`/`- [x]`, `> `, two spaces per indent, `**`, `*`,
`~~`. `[illegible]` from the page transcriber is not a checkbox.

## Editor: one UITextView, attributes and text lists

Phase 0 (hosted spike, deleted): TextKit 2 in `UITextView` draws `NSTextList` markers in the
gutter with no characters in the string (120 marker pixels measured), continues decimal
numbering across paragraphs that share one `NSTextList` object, and renders a custom marker
string (a checkbox glyph). A custom `NSTextLayoutFragment` through the layout manager delegate
was called but painted nothing in the gutter, so text lists it is.

`FormattingStyle` (`Views/Editor/`) is the codec: a character carries the paragraph's block and
indent and its own inline mask as custom attributes, and `formatting(of:)` reads them back to
store. Paragraph styles hold the text list (disc, `{decimal}.`, a box or ticked box, a bar for
quotes) and indents (`indentStep` 22 pt per level, `markerGap` 26 pt). Consecutive numbered
items at one indent share one list object; a bar action re-applies paragraph styles over the
whole text so runs recount, which is attributes only and never moves the selection.

One measurement changed the coordinator's shape (`GrowingTextEditorTests`, a hosted test on a
real `UITextView`): typing attributes keep only `NSFont`, `NSColor`, and `NSParagraphStyle`. A
custom key never reaches typed text on its own, and the empty paragraph after the last newline
has no character to carry one, so a first draft that leaned on UIKit propagating the keys lost
the bullet on the line after Return. The coordinator now applies Return by hand, holds the
trailing paragraph's block itself, and after each edit re-marks the touched paragraph from any
character that still carries the key and gives the inserted characters the caret's inline marks.

`ListEditing` is the pure rule set: Return continues a list (a ticked box continues as an empty
one, a heading gives body), Return on an empty item leaves the list, Backspace at the start of
an item takes the marker before it takes a character, then one indent level. The text view
applies it in `shouldChangeTextIn`. `FormatBar` is the `inputAccessoryView`: Title, Heading,
Bold, Italic, Strikethrough, Bulleted, Numbered, Checklist, Quote, Outdent, Indent, and hide
keyboard, with the paragraph under the caret highlighted. It is dropped while
`RecordingSession.showsAccessory` is true (decision 6).

The same view now reads: non-editable, with the names linked as `.link` attributes and their
kind's colour, opened through `textView(_:primaryActionFor:)`, and a tap anywhere else reported
as a UTF-16 offset from `closestPosition(to:)`, so the editor opens with the caret on that
character. That retires `ReadTapCaret` and the 150 ms link-versus-tap wait, and gives read mode
hanging indents and native selection. A tap in a checklist item's gutter ticks it in either mode.

The title field and read title use `.title2` semibold, the same as a heading 1 paragraph
(decision 2); heading 2 is `.title3` semibold. Typing shortcuts ("- " starting a list) were left
out: with attributes rather than syntax they are a small recogniser of their own, not free.

## Phases

- **Phase 1 (built).** Everything above, plus `EntryFormattingTests`, `ListEditingTests`,
  `MarkdownCodecTests`, `FormattingStyleTests`, export and cleanup coverage in the existing
  suites, and `FormattingUITests`.
- **Phase 2 (built, second commit).** `@` name completion writing a `.user` link, `#word` tags.
- **Later.** Highlight (one colour). The user's own prompts as templates. A horizontal rule.
  Collapsible headings only if entries grow long enough to need them. Tables, colours, fonts,
  code, embeds: no.

## Risks

- **Attribute writes that reset the selection.** Only `textStorage` attribute edits and
  `typingAttributes` are used for formatting; `attributedText =` is reserved for text pushed in
  from outside, under the same echo rule as before.
- **Dictation and marked text.** Nothing restyles while `markedTextRange` is set.
- **Old test element types.** Read mode is now a text view, not a static text, so UI tests
  that queried `staticTexts["entryReadText"]` moved to a type-agnostic query.
- **The custom checkbox marker's font.** Drawn in the paragraph's font; the glyph exists in
  every system design.
