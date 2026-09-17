# A6 build spec: read mode and tappable names

Lane 3, branch `feature/phase-a-shell`. Implements the "Read mode" key decisions and the A6
checklist in `tasks/todo.md`, plus review finding 11. Builds on A4 (`AppRouter`, `EditorLifecycle`).

## The peek card dependency

A6 taps a name and "shows the peek card", but `EntityPeekCard` is an A5 item and A5 hasn't been
built. A6 builds the card's **sheet form** now, to the "Peek card" key decisions:

- name and kind, the bio's first line, last mentioned, entries in the last 30 days, an Open button
- a sheet with `.height(220)` and `.large` detents, its own `NavigationStack`, and its own
  `entityRouteReplacer`; Open pushes `EntityView` inside it
- the card never calls `pageOpened`; only the pushed `EntityView` does

A5 later adds the overlay form in Mind and reuses the same card view and data. The "most recent
open loose end" line joins the card when A2's `LooseEnd` lands, the same rule as the recorder's
prompt line.

## Which entries open for reading

`EntryReadMode.opensForReading(_:automationStartedAt:) -> Bool`, a pure static function in
`Mindlore/Views/Shell/EntryReadMode.swift`. It returns false (open for typing) when any of these
holds:

- there is no entry yet (a new route)
- `isDraft`
- `awaitingText`
- `textReviewPending`
- a photo entry whose pages aren't confirmed
- `AIPassTrigger.offersDone(entry, automationStartedAt:)` is true
- the route asked for typing (`JournalRoute.opensForTyping`, set by a finished recording's jump,
  so a live-text recording always lands in the editor, even with automation off)
- the text is empty after trimming

The mode is decided when the editor is created (`@State`) and only ever flips automatically one
way: if the entry starts awaiting text, needs page review, becomes a draft, or its text empties
while reading (Edit pages, Replace with page transcription), it switches to typing. Done on a
finished entry doesn't flip it to reading, so the insights UI test that keeps typing after Done
still works.

## Read mode in `EntryEditorView`

- `@State private var isReading` from the rule above.
- The header is unchanged (banners, player, page strip, date suggestion), except the title
  `TextField` becomes `Text(entry.displayTitle)` (`entryTitleText`).
- The body is `Text(linkedText)` (`entryReadText`), with `.textSelection(.enabled)`, in the same
  scroll view, instead of `GrowingTextEditor` and the tap-below-text area.
- Toolbar: an Edit button (`editEntryButton`) while reading. Edit sets `isReading = false`; the
  `GrowingTextEditor`'s own `onAppear` then bumps `focusAtEndToken` (a token bumped in the same
  update as its creation is treated as already handled), so the caret lands at the end. While typing an entry that opened for
  reading, a Done button (`doneEditingButton`) resigns the keyboard, flushes the saver, and
  returns to reading, unless the text is empty. If `offersDone` is also true at that moment, only the existing
  `finishEntryButton` shows, and finishing also returns to reading. Insights, More, Edit pages, and
  Entry date stay in both modes.
- Saving is unchanged. Typing still goes through `textBinding` and `EntrySaver.noteChange()`.

## Name links

### `EntityNameRanges` (`Mindlore/Graph/EntityNameRanges.swift`, `nonisolated`, no SwiftData)

```swift
struct Candidate { let entityID: UUID; let names: [String] }   // entityID is already the root
struct Match { let range: Range<String.Index>; let entityID: UUID }
static func matches(in text: String, candidates: [Candidate]) -> [Match]
```

- Every name of every candidate is found with `NameMatching.ranges` (case-insensitive, word
  bounded; "Sarah's" matches "Sarah").
- Ranges are converted with `Range<AttributedString.Index>(_:in:)`, and one that doesn't land on
  character boundaries (a decomposed accent after the match) is dropped.
- Overlaps resolve longest first, then earliest, then the smaller entity UUID string, so "Sarah Kim" beats "Sarah" and a name is never
  linked twice. Results are sorted by position.
- Empty and one-character names are skipped.

### `EntryNameLinks.candidates(forEntry:in:)` (`Mindlore/Graph/EntryNameLinks.swift`)

- Takes `GraphIndexer.allLinks` filtered to the entry in memory (never a `#Predicate` on the
  optional `entryID`), and fetches every `Entity` once into `[UUID: Entity]`.
- Walks `mergedIntoID` to the root with a cycle guard, the pattern in
  `GraphServices.resolvedLinks`.
- Drops links whose root is missing or not `isBrowsable`, and tag links: tags are common words
  ("river") and would turn ordinary prose into links. Guessed and unsure links stay, as their
  chips do.
- Names per root, in this order: each link's `writtenSurface`, its `surface`, then the root's
  `name` and `aliases`. Grouped by root, so two links to merged entities become one candidate.
- A new file, not a `GraphServices` method, so it stays clear of A5's graph work.

### Rendering

- `AttributedString(entry.text)`, with `.link = mindlore-entity://<root uuid>` on each match. The
  first build step checks on the simulator whether a per-run kind colour renders, whether link
  taps work with `.textSelection(.enabled)`, and whether XCUITest sees the links; the fallback is
  the app tint plus underline, and no text selection.
- Computed in `.task(id: LinksKey(text, graph.revision, isReading))`, and skipped while typing.
  Until the result for the current text arrives, the body shows the plain text.
- The read `Text` alone carries `.environment(\.openURL, OpenURLAction { ... })`: a
  `mindlore-entity` URL sets the peek target and returns `.handled`, anything else
  `.systemAction`. Sheets the editor presents don't inherit it.

## `EntityPeekCard` (`Mindlore/Views/Graph/EntityPeekCard.swift`)

- `EntityPeekSheet(entityID:)` owns `NavigationStack(path: [EntityRoute])`, the
  `navigationDestination` for `EntityRoute`, and the `entityRouteReplacer` that rewrites its own
  path, the same as `EntryInsightsView`. Its root is `EntityPeekCard`.
- `EntityPeekCard` reads the data below through `EntityPagePresentation.resolve` (following a merge
  to the winner), refreshed on `graph.revision`. It never calls `graph.pageOpened`.
- `EntityPeekPresentation.summary(entity:linkDates:now:) -> Summary` (pure): the display name and
  kind, the first line of the bio (nil when there is none), the last mentioned date, and the count of
  distinct entries in the last 30 days.
- Link dates: links whose root (same walk) is the entity, by `entryID`, with each entry's
  `entryDate`. A merge already moved the loser's links, so this is one pass.
- The sheet starts at the 220pt detent and switches to `.large` when Open pushes (detent
  selection binding). The sheet item is an `Identifiable` wrapper around the id.
- Identifiers: `entityPeekCard`, `entityPeekOpen`, `entityPeekBio`.
- A merged-away or deleted entity shows "No longer in your journal".

Editor wiring: `.sheet(item: $peekEntityID)` with the detents. The router's
`dismissPresentationsToken` also clears it. Presenting it doesn't touch `EditorLifecycle`: close
rules only run when the route leaves Journal's path (A4).

## Tests

Unit (Swift Testing):

- `EntryReadModeTests`
  - a finished typed entry reads
  - drafts, awaiting text, page review pending, unconfirmed pages, and empty text type
  - an entry still offering Done types
  - a live-text recording before its pass types, including with automation off; after its pass it
    reads
- `EntityNameRangesTests`
  - longest overlapping name wins
  - aliases and `writtenSurface` match
  - a possessive matches only the name
  - several occurrences all link
  - one-character names skipped
  - results are sorted and never overlap
- `EntryNameLinksTests` (in-memory store)
  - a merged entity's link points at the winner and carries the winner's aliases
  - a hidden root is dropped
  - a cycle doesn't hang
  - another entry's links are ignored
- `EntityPeekPresentationTests`
  - bio first line
  - last mentioned
  - 30-day count with duplicates and older entries
  - a merged entity summarises the winner with the loser's links included
- The card and `pageOpened`: covered by the UI test below, since the stub drafts a bio the moment
  the page opens.

UI (lane simulator):

- New `ReadModeUITests` (stub AI):
  - finish an entry naming Sarah, go back, reopen: `entryReadText` shows, no `entryEditor`
  - tap the Sarah link: `entityPeekCard` shows with no drafted bio after a short wait (the card
    didn't start one)
  - Open: the entity page shows its drafted bio
  - close the sheet, tap Edit, type, tap Done: the read text has the addition, and after going
    back the list row does too
- No existing UI test types into an entry that opens for reading (the reopened entries are drafts
  or awaiting review), so none change.
- The A6 checklist's "peek doesn't run the close rules" is covered by A4: close rules run only when
  a route leaves Journal's path (`AppRouterTests`, `JournalNavigationUITests`).
- Phase-scoped run: the same set as A4 plus `ReadModeUITests`.

## Review fixes (sub-agent review, "approve with fixes", 15 findings)

Folded in above: stale read text (keyed on the text itself), Edit's focus token, live-text
recordings via the route instead of a flag that never clears with automation off, the one-way flip
to typing, the in-memory link filter and `isBrowsable`, the rendering spike, the scoped `openURL`,
the detent switch, tags excluded, index conversion and tie-break, one-pass peek counts, Done on an
empty body, and the test notes. Open: `EntityPeekCard` is also an A5 item, so whoever builds A5
builds on this file instead of a second card.

## Units and commits

1. `JournalRoute.opensForTyping`, `EntryReadMode`, read and edit modes in the editor, UI test updates. Unit and UI tests.
2. `EntityNameRanges`, `EntryNameLinks`, links in the read text. Unit tests.
3. `EntityPeekPresentation`, `EntityPeekCard` and sheet, `OpenURLAction`. Unit tests and
   `ReadModeUITests`.
4. Code review and fixes, then tick the plan, log it, and land.

## Not in scope

- The Mind overlay form of the card and its swipe-up (A5).
- The loose-end line on the card (after A2).
- Names in the list preview and in Ask answers.
- A long-press fallback on names in the editable view.
