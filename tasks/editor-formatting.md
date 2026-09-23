# Editor formatting: a plan

Branch `claude/editor-formatting`, off `claude/journal-app-improvements-o5kfzx` at `766c69c` (the
commit with `JournalFont`, parts offsets, and the first-keystroke fix; `main` at `ead7a53` has none
of them). Status: proposal, nothing built. Research on 2026-09-23 against Apple Notes (iOS 18 and
26), the iOS 26.5 SDK, Obsidian and its plugin download counts, Day One, Bear, and Apple Journal.

## What the editor has today

`Entry.text` is a plain `String`. `GrowingTextEditor` is a `UITextView` that grows with its text,
set in one font (`UIFont.journal(.body, design:)`), with no attributes, no toolbar above the
keyboard, and no typing shortcuts: "- " and "1. " are just characters. Read mode
(`EntryEditorView.readBody`) shows the same string in a SwiftUI `Text` built with
`AttributedString(entry.text)`, a literal init that parses nothing; the only attributes it carries
are the entity links `EntryNameLinks.attributed` lays over name ranges. A tap on the read text is
turned into a caret position by `ReadTapCaret`, which lays the raw string out again with TextKit
and returns a UTF-16 offset. Everything downstream (insights, cleanup, parts, Ask, search, export,
previews, titles) reads the raw string as prose.

## Findings

**Apple Notes** is the benchmark on the phone. The Aa panel has five paragraph styles (Title,
Heading, Subheading, Body, Monospaced), bold/italic/underline/strikethrough, three list kinds
plus checklists, block quote, indent, tables, five highlight colours (iOS 18), and collapsible
headings (iOS 18). Typing "* ", "- ", or "1. " starts a list; "#" does not make a heading, it
makes a tag. Return on an empty list item leaves the list. Checked items sort to the bottom only
if a setting says so. iOS 26 added Markdown import and export (never shown while editing) and a
swipeable format toolbar. Notes stores rich text; Markdown is a border format.

**Obsidian** stores Markdown and renders it in place (Live Preview: syntax shown on the line the
cursor is on, hidden elsewhere; users report the reveal shifting line height and jumping the
cursor mid-typing, which matters for dictation landing mid-line). Its mobile toolbar is a
configurable row above the keyboard, defaulting to link and tag. The plugin counts say what
people bolt on: Excalidraw 8.1M, Templater 5.7M, Dataview 5.0M, Tasks 4.3M, Advanced Tables
3.2M, Calendar 3.1M, Outliner 1.4M, Editing Toolbar 1.9M, Highlightr 0.7M, Periodic Notes 0.8M,
Various Complements 0.6M, Natural Language Dates 0.5M. The ones that shape the editor: Tasks
(due dates and recurrence on a checkbox), Editing Toolbar (heading levels, indent, colours),
Outliner (Tab moves a subtree, fold, drag), Various Complements (`[[` autocomplete), Natural
Language Dates (`@today` inserts a dated link), Highlightr (writes `<mark>` because `==` can't
carry a colour).

**Day One and Bear** are the closest cousins. Both keep Markdown underneath and render it live in
one editor with no separate raw mode. Day One's iOS keyboard bar is an Aa button (headers, bold,
italic, highlight, numbered, bullets, checklist, quote, rule, indent, outdent) and a paperclip;
selecting text floats link/highlight/bold/italic. Bear hides the syntax once you leave the line
and shows it when you tap back in ("Hide Markdown", a setting), links notes with `[[ ]]`, and
tags with `#tag`. Apple Journal, Apple's own journal, shipped with bold/italic/underline/strike
only and added flat lists and quotes in iOS 18, still no headings: a signal that a journal needs
far less than a notes app.

**What fits Mindlore.** Headings, bold, italic, strikethrough, bullets, numbers, checklists, a
block quote, and a bar above the keyboard, with the Notes typing shortcuts and Return
behaviour, rendered in place like Bear. Checklists tie to loose ends, and names typed with an
`@` tie to the graph, which is Obsidian's `[[` and Tasks ideas landing on systems that already
exist. **What is notes-app scope creep**: tables, per-character colours and fonts, code blocks,
embeds, callouts, footnotes, frontmatter (insights already are the metadata), collapsible
sections, drawing, kanban, Dataview-style queries (Reflect and Ask are the queries).

## The storage decision

Three options were weighed.

1. **Markdown in `Entry.text`** (recommended). One canonical string, a small CommonMark subset,
   rendered live in the editor and in read mode.
2. **An `AttributedString` persisted beside `text`** (an `NSAttributedString` archive or a JSON
   run list), with `text` kept as a plain projection.
3. **A block model** (an array of typed paragraphs), like Notes internally.

Option 1 is what Bear, Day One, and Obsidian do and it is the one that leaves every existing
consumer working. Option 2 keeps two truths for one entry: every write path (transcription,
cleanup, revert, page replace, the first-keystroke create) has to update both, and the hash and
offset rules that assume `text` is the entry would need a second set for the styled twin. Option 3
is a rewrite of the model, the editor, and every reader for no gain a phone journal can feel.

The subset: `#`/`##` headings, `**bold**`, `*italic*`, `~~strike~~`, `- ` and `1. ` lists with
two-space nesting, `- [ ]`/`- [x]` checklists, `> ` quotes, and later `==highlight==`. Nothing
else parses; a stray `#` mid-line or an underscore in a word stays literal.

**The one rule that keeps offsets true: nothing ever mutates the string to render it.** Markers
are hidden or dimmed with attributes (a zero-width or clear font on the marker range), never
removed, so a character offset in the styled text is the same offset in `Entry.text`. That is
what keeps `EntrySection.offset`, `ReadTapCaret`, `EntityNameRanges`, and the UITextView
selection rule untouched.

Consequences for each consumer (the file map is in the Explore pass, summarised here):

- **Insights prompt** (`InsightsPromptBuilder.plan`, raw `prefix(inputCharacters)`): sends
  the markdown as is. Models read it well, and a list is a better hint about a Note than prose
  would be. Cost: a few tokens per marker. `grounded(_:in:)` matches names with `NameMatching`,
  whose regex treats `*` as a non-letter, so `**Sarah** Kim` fails the full-name match and
  falls back to "Sarah"; the parser strips inline markers from its match text before grounding.
- **Hashing and staleness** (`TextHash`, `sourceTextHash`, `cleanupAppliedHash`,
  `ReflectSummaryStore.fingerprint`): unchanged. Making a line a heading is an edit like any
  other and makes insights stale, which is right.
- **Cleanup** (`applyCleanedText`, voice and photo only): the cleanup prompt says nothing about
  formatting, so a model could drop markers; add one sentence ("keep any Markdown marks as they
  are") and reject a cleanup that changed the line count of a formatted entry. Transcribed text
  arrives as plain paragraphs, so this only bites an entry the user formatted after transcription
  and before applying cleanup, which the hash check already refuses.
- **Parts offsets** (`parseSections`, `EntrySection.offset`, `GraphServices.analyzedText`,
  `EntryParts.Context`): offsets are counted in the raw string and the raw string stays
  canonical, so spans survive. The model's "first words of the part" may omit a leading `- ` or
  `## `; the lookup falls back to the same words after skipping line-leading markers. The
  prompt's instruction "exactly as the entry writes them" already tells it to keep them.
- **Ask** (`AskSources`, `AskContextBuilder.sanitized`, `AskDigests`, `AskIndex`): the index
  tokenises `.byWords` and drops punctuation, so markers never become terms. Blocks go raw
  inside the `<<<entry` fence; the sanitizer strips only the fence and `[E12]` handles, and `[ ]`,
  `[x]`, `==` survive (they are harmless; `[[E3]]` would already reduce to `[]`). The 90-character
  digest line and `JournalSearch.snippet` go through a plain-text projection so a line reads
  "milk, eggs" and not "- milk - eggs".
- **`displayTitle`, `previewText`, `JournalSearch.displayTitle`,
  `EntityPagePresentation.heading`, `KeepCard`, Today's `EntryFacts.title`**: all show markers
  today. One `MarkdownText.plain(_:)` (markers removed, a checkbox as a glyph or nothing, lists
  joined with ", ") behind every one of them. `displayTitle` from a `# ` first line drops the `#`.
- **Export** (`JournalExport.markdown(for:)`): already writes `.md` with the text verbatim under
  YAML front matter, so a formatted entry exports right for the first time; `journal.json`
  carries the raw string.
- **Transcription** (`applyGeneratedText`, `joinedPageText`): unchanged; nothing formats what a
  model transcribed. The page transcriber writes `[illegible]`, which the parser must not read as
  a checkbox (`- [ ]` is line-leading and has a space or x; `[illegible]` matches neither).
- **`contentRevision`**: unchanged; only page restarts bump it, and text edits are caught by hash.
- **`CreativeSignals`** (on-device kind heuristics over lines): strip markers first. Today a `#`
  counts as a word and a poem written as a bulleted list can never be verse; both go away.
- **Entity name links in read mode**: `EntityNameRanges.matches` runs on the raw string and the
  ranges map straight onto the styled text, since no character moved.
- **CloudKit rule**: no new stored property. If a format version is ever wanted it is
  `var textFormatRaw: String?`, optional, passing `CloudKitSchemaRulesTests` as is.
- **Diagnostics**: new events carry counts and kinds only (`editor.formatted` with the mark's
  kind and a bool for toolbar versus typed), never a run of text; one more case in
  `DiagnosticsPrivacyTests`.

## Editor implementation

**Stay on `GrowingTextEditor` (UITextView) and add a TextKit styler. Do not move to the iOS 26
SwiftUI `TextEditor`.**

What the SDK says (typechecked against iOS 26.5 on 2026-09-23, spike deleted):
`TextEditor(text: Binding<AttributedString>, selection:)`, `AttributedTextSelection.indices(in:)`,
`AttributedTextFormattingDefinition`, `AttributedTextValueConstraint`, and
`textInputFormattingControlVisibility` all exist and compile. But `AttributeScopes.SwiftUIAttributes`
holds only inline attributes (font, colours, kern, strike, underline, alignment, line height); no
`presentationIntent`, so headings, lists, and checklists have no editing affordance and no
renderer in SwiftUI, in `Text` or `TextEditor`, and Apple's WWDC25 sample builds them by hand.
Selection is `AttributedString.Index`-based, so `ReadTapCaret`'s UTF-16 offsets and the whole
first-keystroke fix (the echo rule in `updateUIView`, `lastReportedText`, `markedTextRange`)
would have to be re-proven on a view we cannot reach into. There is no `inputAccessoryView`, no
container inset control, and no evidence it grows without scrolling. Whether it keeps its
selection when a binding pushes text in was not measured; it does not need to be, because the
block-level gap decides it.

The UIKit route: `UITextView` has run TextKit 2 since iOS 16, the app can add a keyboard bar
through `inputAccessoryView`, and the styler works entirely in attributes:

- `MarkdownStyler` (nonisolated, no UIKit types in its output, testable): given the string and
  the journal font, returns runs of attributes (heading font at `title2`/`title3` in the journal
  design, bold and italic traits, strikethrough, a `NSParagraphStyle` with `headIndent` and
  `firstLineHeadIndent` so a wrapped list item aligns under its text, a dimmed colour on marker
  ranges, `.link` on a checkbox so a tap toggles it). Applied in `NSTextStorageDelegate
  .textStorage(_:didProcessEditing:...)` to the edited paragraphs only, by `setAttributes`,
  which never touches the string or the selection. Marker hiding is an attribute too (a
  near-zero font on the marker range in read mode, dimmed in edit mode), never a deletion.
- `ListEditing` (pure): what Return, Backspace, and Tab do on a list line. Return on
  "- item" inserts "\n- "; on "1. item" inserts the next number and renumbers the run; on an
  empty "- " removes the marker (Notes' leave-the-list); Backspace at a marker's end removes
  it; Tab and the bar's indent buttons add and remove two spaces. Applied through
  `textView(_:shouldChangeTextIn:replacementText:)` so the change goes through the text view's
  own undo and `textViewDidChange` still reports it once.
- Typing shortcuts fall out for free: in Markdown "- " already is a list. "[] " at a line start
  becomes "- [ ] " so Notes users get their checklist.
- The keyboard bar (`FormatBar`, SwiftUI hosted in a `UIInputView`): Heading, Bold, Italic,
  List, Numbered, Checklist, Quote, Indent, Outdent, and a keyboard-down button; the current
  line's state highlighted from the styler's parse of the paragraph under the caret. Toggling
  bold on a selection wraps it; on a caret it inserts `****` with the caret inside. The system
  `UITextFormattingViewController` (iOS 18) was looked at: it offers styles and lists in its UI
  but only reports the choice, and applying attributes, list continuation, and renumbering stay
  the app's, so it buys a panel we would then have to constrain to our subset; a five-button bar
  is smaller and matches Day One's.
- Read mode: keep the SwiftUI `Text`, now built by `MarkdownStyler` too (the same runs as
  `AttributedString` attributes, markers hidden) with `EntryNameLinks` laid over it, and
  `ReadTapCaret` given the same attributed runs so its layout matches what is drawn. Because
  no character moves, the offset it returns is still a `Entry.text` offset. If SwiftUI `Text`
  proves unable to draw a hanging indent (it cannot take `NSParagraphStyle`), read mode becomes
  a non-editable `UITextView` sharing the styler, which also makes the tap-to-caret native and
  retires the 150 ms link-versus-tap wait. That is measured in phase 0, not decided here.
- The font-change branch in `updateUIView` (`view.font = ...`) goes away: the styler owns every
  attribute and re-styles on a `journalFont` change, keeping the selection as it does now.

## Phases

**Phase 0, measure (half a day).** A styler over the story journal's longest entries and a
40,000-character one, typed into on the phone: keystroke-to-paint under 16 ms with per-paragraph
restyling, or the styler needs to be lazier. Whether SwiftUI `Text` honours a hanging indent.
Both results go in this file.

**Phase 1, the journal's formatting.** `#`/`##` headings (Title and Heading; Notes' third level
and Monospaced are not offered), bold, italic, strikethrough, bullets, numbers, checklists,
quotes, nesting by two spaces, the keyboard bar, Notes' Return and Backspace rules, read mode
rendering with markers hidden, `MarkdownText.plain` behind every preview and title, the cleanup
prompt line, the `CreativeSignals` strip, the parts fallback lookup. Undo through the text
view's own manager. `EntryKindPicker` unchanged: a checklist entry is still whatever kind the
user or insights say.

**Phase 2, ties to what exists.**
- **Checklists and loose ends.** A `- [ ]` line in a finished entry is offered to
  `LooseEndWriter.candidates` as a user-written thread (the entry's own first, as today), and
  ticking it in the editor resolves the loose end through the same path Today's Done uses;
  resolving on Today ticks the box. Never automatic in the other direction for AI-found threads,
  which have no line to tick.
- **`@` names.** Typing `@` opens a small completion over `EntityDirectory` (Various Complements'
  idea); picking inserts the plain name and writes a `.user` link through `GraphEditor.addName`,
  so the text stays prose, the map gets the name, and read mode links it. No `[[ ]]` syntax: the
  graph already links names without one, and brackets in the text would reach Ask and export.
- **Highlight** `==text==`, one colour (`Palette` accent), no picker; Highlightr's five-colour
  `<mark>` is HTML in the journal and gets no.
- **Prompts as templates.** Reflect cards already seed `startingText`; add a Settings list of the
  user's own prompts (three by default) offered on a new typed entry, in the Templater spirit
  without its language. Daily notes are what the journal is.

**Phase 3, maybe.** A horizontal rule `---` as a visual break between parts of a day. Links to
another entry (`>>` in Notes) via the search panel. Collapsible headings only if entries grow
long enough to need them, which the story journal does not suggest. Tables, colours, fonts,
code, embeds: no.

## Risks

- **Restyling on every keystroke.** A 40,000-character entry restyled whole per key would drop
  frames; per-paragraph restyling in `didProcessEditing` is the design, and phase 0 measures it.
- **The first-keystroke bug's family.** Any attribute write that goes through `attributedText =`
  resets the selection the way `text =` does. Only `textStorage.setAttributes` inside the
  editing transaction is allowed; `GrowingTextEditorTests` gets a test that types, styles, and
  asserts the selection never moved.
- **Dictation and marked text.** The styler must not run while `markedTextRange` is set, the
  same rule the push-in path keeps, or a dictated list marker restyles mid-composition.
- **Cleanup dropping markers** on an entry formatted after transcription: the line-count guard
  and the prompt line; if a model still strips, the hash check leaves the user's text alone.
- **Old entries with accidental syntax.** A past entry that began a line with "- " now renders
  as a bullet. The story journal has none (checked); a real journal may. Acceptable, since it
  is what the user typed and Obsidian and Bear would show it the same way.
- **Read-mode caret drift** if the read text's layout diverges from the styler's: guarded by
  building both from one set of runs, and by `ReadTapCaretTests` over formatted fixtures.

## Test plan

Unit (`MindloreTests`, Swift Testing):
- `MarkdownStylerTests`: a fixture set of entries to expected runs (heading, nested list,
  checklist, quote, inline marks, a mid-line `#`, `[illegible]`, an underscore in a word); every
  run's range is a valid range of the raw string and the string is unchanged.
- `ListEditingTests`: Return, Backspace, Tab on every list kind, renumbering, leaving a list.
- `MarkdownTextTests`: `plain` for previews, titles, digest lines, search snippets, headings.
- Existing suites extended with formatted fixtures: `TitleTests` (`# ` first line),
  `EntryKindTests` (preview), `AskDigestsTests`, `JournalSearchTests`, `InsightsTests` (a
  section whose opening words omit the marker still gets an offset), `EntityNameRangesTests`
  (`**Sarah Kim**`), `ReadTapCaretTests` (formatted layout), `CreativeClassificationQualityTests`
  (a bulleted poem is still verse on device), `TrustTests` (export round trip).
- `GrowingTextEditorTests` (hosted): selection survives a restyle; no restyle under marked text.
- `DiagnosticsPrivacyTests`: the sentinel typed as a heading, a list, and a checkbox never
  reaches the log.

UI (`MindloreUITests`, XCTest, `FormattingUITests` to match the class-name rule):
- Type "- " then words then Return: the next line starts with a bullet; Return again leaves the
  list. Relaunch against the named store: the text is `- ...` verbatim.
- Bar: Heading on the first line, Bold on a selection, Checklist, tick it in read mode.
- Read mode: a heading renders larger, markers absent from `entryReadText.label`, a name inside
  a list item still a link, a tap on the second list item opens the editor with the caret there.
- The list row's `entryPreview` shows no markers.
Registered in `scripts/ci/ui-test-seconds.txt` after the first CI run.

## Open questions for the owner

1. Bear or Obsidian on markers while editing: dimmed and always visible (simpler, no cursor
   jumps, what phase 1 proposes), or hidden except on the current line?
2. Two heading levels (Title, Heading) or one?
3. Should a ticked checklist item resolve a loose end, and an open one create a candidate, or
   do checklists stay purely visual?
4. Does `@` name completion write a graph link, or only insert the name and let insights link it?
5. `#tag` in the text: Notes and Bear both read it as a tag. Tags in Mindlore are the AI's;
   leave `#word` literal (proposed), or make it a user tag?
6. Should the format bar hide while a recording is up in the accessory, since the two stack?
7. Any appetite for the cleanup pass adding structure to a dictated entry (a spoken "first,
   second, third" becoming a list)? Proposed no: cleanup fixes punctuation and paragraphs only.
