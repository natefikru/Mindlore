# B2: Journal rows and Today

Branch: `feature/phase-b2` from `feature/phase-a` at `dc81233` (PR #13, Phase B part 1, merged),
in `.claude/worktrees/phase-b` on the `iPhone 17 phase-b` simulator.

Status: revision 2, approved by the owner on 2026-09-19. Revision 2 folds in the four owner
decisions and a read-only sub-agent review of revision 1 (19 findings; see "Review log"). Nothing
below is built.

Covers `tasks/phase-b-ux.md` sub-phases B2a (Journal rows) and B2b (Today). They ship together
because Today is a header section of the same `List` whose rows B2a restyles, and splitting them
means designing one screen twice and updating the same UI tests twice.

## What the research found

Three read-only surveys of the code (2026-09-19). Four findings change the plan as written in
`tasks/phase-b-ux.md`:

1. **B2a is smaller than the plan assumes.** `EntryRow` (`EntryListView.swift:249-329`) already has
   the serif title (`:272`), the area dots (`:302-311`), the date, the source glyph, and the
   preview. B0 got there. What is left is the row surface itself: there is no `.listRowBackground`,
   so the system row material draws over Paper, and separators are still on.
2. **There are no swipe actions to keep.** `tasks/phase-b-ux.md:191` says "Keep `List` (swipe
   actions...)". Deletion is SwiftUI's `.onDelete` on the per-section `ForEach`
   (`EntryListView.swift:47`), routed through `JournalGroups.ids(at:in:)`. Any change to row
   structure has to keep that offset mapping exact, or a swipe deletes the wrong entry.
3. **B1 did not pull shared pieces out of `InsightCards.swift`.** B0 moved the two colour switches
   to `Palette.swift`; that was all. `KeepCard` inlined its own `.chip()` rows rather than reuse
   `LifeAreaChips` and `WrappingChips`, which still carry the old `.quaternary` capsule. `.card()`
   in `Design/CardStyle.swift:12` has **zero call sites**, and `Motion.stagger` is declared and
   unused. Today's cards are the first consumer of both.
4. **The merged-walk is copied inline five times**, not four: `GraphServices.buildSnapshot`
   (`:302-308`), `GraphServices.mentionedWith` (`:488-494`), `KeepSnapshot.make`
   (`KeepSnapshot.swift:42-49`), `EntityPeekPresentation.load` (`:46-53`), plus the id-only
   `EntityDirectory` (`AI/Insights/LooseEndWriter.swift:110-143`), which already does exactly what
   `TodaySource` needs. `TodaySource` reuses `EntityDirectory` rather than adding a sixth copy, and
   moves it to `Graph/EntityDirectory.swift` on the way (see Phase 4).

## Owner decisions (2026-09-19)

1. **All five card kinds ship.** The cost is in the composer and its tests either way.
2. **"It's been a while" is on by default**, with the Settings switch and the per-person mute.
   Judged against the owner's own journal after it lands.
3. **The stale-insight sparkles is removed entirely.** The `analyzingBadge` progress view stays.
4. **Reuse the `phase-b` worktree and simulator.** Avoids a fourteenth device and the fresh-simulator
   `AskIndexLemmaTests` failures (`tasks/lessons.md`).

## Ground rules carried from Phase B

- No backwards compatibility. No migrations.
- CloudKit rules: every new stored property optional or defaulted, nothing `@Attribute(.unique)`.
- Diagnostics carry ids, counts, and durations only. Every new event gets a privacy test case.
- No advice. Today's cards state facts and quote the user. They never suggest.
- No new AI calls. Every card is a query over data Phase A already stores.
- Text styles only, never point sizes. Reduce Motion goes through `Motion.resolve`.
- No CI. The gate after every push is the unit run from `CLAUDE.md`, on the `phase-b` simulator.

## Phase 1: Journal rows (B2a)

One commit. `Mindlore/Views/EntryListView.swift` only.

- **Row surface.** Each entry row gets `.listRowBackground` drawing `Palette.card` in a
  `RoundedRectangle(cornerRadius: Corner.card, style: .continuous)` with a `Palette.hairline`
  stroke, `.listRowSeparator(.hidden)`, and row insets that give the cards air over Paper. The row
  content keeps its current structure, so `.accessibilityIdentifier("entryRow")` stays exactly
  where it is (`:328`), on the VStack inside the `NavigationLink`.
- **The sparkles badge goes** (`:283-298`), per owner decision 3. The `analyzingBadge` identifier
  and its `ProgressView` stay, because an entry mid-analysis is a live state the user needs.
- **Filter chips.** `areaFilterRow` (`:180-209`) drops its hand-rolled capsule and calls
  `.chip(tint: area.color, selected: selected)` from `Design/ChipStyle.swift:25`, which already
  handles the selected white-text case. `Haptics.selected` fires on tap. The
  `areaFilter-<rawValue>` identifiers and the `.isSelected` trait stay. It keeps its existing
  `.listRowBackground(Color.clear)` (`:39`).
- **Toolbar: unchanged.** `tasks/phase-b-ux.md:196` wants a gear plus one compose menu. Deferred,
  because 11 UI test files tap `newEntryButton` directly and a `Menu` means every one of them has
  to open the menu first, for no behaviour the user gains. Owner decision 9 in the parent plan
  already says the toolbar mic goes "once the accessory is proven", which is a separate moment.
  The gear gains an identifier (`settingsButton`) it has never had.
- **Leaves alone:** `JournalGroups`, `JournalFilter`, `.onDelete` and its offset mapping, the two
  `ContentUnavailableView` overlays, every sheet and cover.

**Tests.** `JournalGroupsTests` and `JournalFilterTests` are untouched and must stay green.
The three cell-counting assertions must stay green without editing them:
`JournalNavigationUITests.swift:30-31,62,93` and `RecordingUITests.swift:67`. Checked during the
review: no test anywhere in `MindloreUITests/` asserts a bare `app.cells.count`, only the
`entryRow`-filtered query, so a new header section cannot shift a count. Run those two UI classes
on the `phase-b` simulator before the commit, because they are the only proof the rows are still
cells.

## Phase 2: the model and settings Today needs

One commit, no UI.

- `Entity.resurfacingMuted: Bool = false` (`Models/Entity.swift`, beside `hidden` at `:47`),
  non-optional with a default to match every other flag on the model. `CloudKitSchemaRulesTests`
  covers it with no edit.
- **`resurfacingMuted` joins the `recount` keep-list**, parallel to `hidden`
  (`Graph/GraphIndexer.swift:326-329`). Revision 1 left this alone and was wrong: an entity with
  no links is *deleted*, not merely unmuted, and the code's own comment on `hidden` says it is kept
  "or it would come back the next time it is mentioned". Without this, a muted person who goes
  quiet is pruned, then reappears under a fresh id the next time they are mentioned, with the mute
  forgotten. That is the one thing this feature must never do.
- `SettingsStore`: `Key.todayDismissed` holding JSON `Data` (the existing idiom, five keys already
  do it: `lifeAreaNames`, `hiddenLifeAreas`, `userName`, `providerAccounts`,
  `customInsightPrompts`), decoded with the existing `json(_:_:)` helper (`:248`) and written with
  `writeJSON` (`:318`), which logs the key and never the value. The value is a small `Codable`
  struct: a day stamp plus the dismissed card keys.
- `SettingsStore`: `Key.resurfacingEnabled`, a `Bool` defaulting to **true** (owner decision 2),
  read through `bool(_:_:)` (`:245`) so a missing key means the default.
- A row for it in the existing Settings form, next to the life-area settings.

**Tests.** `SettingsStoreTests`: the dismissal value round-trips through `FakeKeyValueStore`;
`initDoesNotWriteDefaultsBack` still passes with both new keys; a corrupt blob falls back to
"nothing dismissed" rather than throwing. A `GraphIndexer` test proving a muted, unlinked entity
survives `recount` and keeps its mute. `CloudKitSchemaRulesTests` green.

## Phase 3: `TodayComposer`, pure (B2b, the substance)

One commit, no UI. This is where the function lives, and all of it is testable without a simulator.

`Mindlore/Views/Today/TodayComposer.swift`, `nonisolated`, no SwiftData import, following
`EntityGraph`'s shape (`Graph/EntityGraph.swift:7`) and `EntityPeekPresentation.summary`'s
pure/impure boundary (`Graph/EntityPeekPresentation.swift:24`).

**Input**, plain `Sendable` structs with explicit memberwise inits, entities already resolved
through merges and already filtered for hidden and muted by the caller:

- `EntryFacts`: `id`, `entryDate`, `entryDateIsDayOnly`, `title`, `summary`, `areas: [LifeArea]`,
  `createdAt`.
- `LooseEndFacts`: `id`, `text`, `status`, `sourceEntryID`, `sourceEntryDate`, `dueDate`,
  `resolvedByEntryID`, `entityIDs` (roots), `lastMentionedAt`.
- `EntityFacts`: `id`, `name`, `kind`, `linkCount`, `lastLinkedAt`.
- `now: Date`, `calendar: Calendar`, `dismissed: Set<TodayCardKey>`, `resurfacingEnabled: Bool`,
  `latestEntryID: UUID?`.

**Output**: `Today` (`Equatable`): a `greeting`, `week: [WeekDay]` (seven, oldest first: `date`,
`hasEntry`, `tint: LifeArea?`), and `cards: [TodayCard]` capped at three.

**Card priority**, exactly `tasks/phase-b-ux.md:150-156`:

1. `.closed(LooseEndFacts)` if the latest entry closed one, else `.dueToday(LooseEndFacts)`.
2. `.onThisDay(EntryFacts, span)`: prior years first (most years ago wins), then a month ago, then
   six months ago.
3. `.stillOpen(LooseEndFacts)`: the oldest open loose end, quoted.
4. `.beenAWhile(EntityFacts)`: the highest `linkCount` whose `lastLinkedAt` is more than 30 days
   before `now`. Not a candidate at all when `resurfacingEnabled` is false.
5. `.latestSummary(EntryFacts)`.

**Rules the composer owns**, each one a named test:

- **Nothing backs two cards.** One entry, one loose end, and one entity each appear at most once
  across the whole of `cards`. Revision 1 stated this for loose ends only; in a one- or two-entry
  journal the same entry would otherwise back both `.onThisDay` and `.latestSummary` and read as a
  bug. Tested with a one-entry journal, asserting exactly which card shows.
- **One `.onThisDay` card, chosen once.** Several spans can match the same day (last year, a month
  ago, and six months ago at once, or two anniversaries from different years). The highest-priority
  span wins, the rest are dropped, and dismissing it does not promote another anniversary of the
  same day into the slot. Tested with two same-day anniversaries.
- A card whose `TodayCardKey` is in `dismissed` is skipped and the next *kind* takes its slot, so
  dismissing one card does not leave a hole.
- **Disabled is not dismissed.** `resurfacingEnabled == false` removes `.beenAWhile` from
  consideration; a dismissal removes one specific card for the day. Separately tested, because a
  bug that treats them the same passes either test alone.
- Future-dated entries are excluded from every card and from the week strip, the way
  `EntityGraph.build` filters `$0.entryDate <= asOf` (`EntityGraph.swift:54`). A clock stepping
  back must not produce "0 years ago" or a negative span.
- On this day compares calendar days through `EntryDates.isSameDay` with the injected calendar
  (`Models/EntryDates.swift:22`). A day-only entry is stored at noon (`:6`), so the comparison is
  on components, never on a 24-hour window.
- 29 February: an entry from 29 Feb 2024 surfaces on 28 Feb in a non-leap year, not silently never.
  Asserted both ways (a leap-day entry on a non-leap anniversary, and a 28 Feb entry not
  duplicating onto a leap day).
- "A month ago" and "six months ago" are calendar arithmetic (`calendar.date(byAdding:)`), not
  30 or 180 days. `Calendar` clamps 31 March minus one month onto the last day of February, which
  can collide with a different candidate for the same day; asserted, including which card wins.
- The 30-day staleness boundary is exclusive and asserted at exactly 30 days, 30 days minus a
  second, and 30 days plus a second.
- An empty journal produces a greeting, an empty week strip, and no cards, never a placeholder.

**If a boundary test fails when it first runs on a real calendar**, diagnose which day it actually
landed on before touching the assertion or the arithmetic (`tasks/lessons.md`, "measure a failing
assertion before loosening it").

**Copy** lives in a `TodayCopy` enum beside the composer, the way `KeepCopy`
(`Views/Capture/KeepCard.swift:235-271`) does, so every string and every diagnostics field builder
is unit-testable without a view. Copy states facts: "Maya last appeared 12 August", never
"You should call Maya".

**Tests**: `MindloreTests/TodayComposerTests.swift`, built on plain structs with a fixed gregorian
UTC calendar and a fixed `now`, following `LooseEndTests.swift:10-14`. No container needed.

## Phase 4: `TodaySource`, main actor

One commit, no UI yet.

`Mindlore/Views/Today/TodaySource.swift`, `@MainActor`, the only part that touches SwiftData.

- **`EntityDirectory` moves to `Graph/EntityDirectory.swift`** from `AI/Insights/LooseEndWriter.swift`,
  unchanged, with its existing callers repointed. Merge resolution belongs in `Graph/` beside
  `GraphEditor.root(of:)`, not in an AI helper file a Views type has to reach into.
- One `Entity` fetch into `EntityDirectory`, reused rather than re-copied.
- Resolves every `LooseEnd.entityIDs` through `root(of:)`, then **drops a loose end if any entity
  it names is hidden or muted**, not only if all of them are. A loose end's text is one sentence
  about all of its subjects ("call Sarah and Tom back"), so a bystander being hidden is enough to
  suppress it. Privacy wins over completeness. Tested with one hidden and one visible subject.
  This is the first place loose-end entities get resolved and hidden-filtered together (the
  insights sheet shows them raw).
- Drops `Entity` rows that are hidden, merged, muted, or not `kind.isAName`
  (`Views/Capture/KeepSnapshot.swift:95-104`).
- **Every entry fetch filters `entryDate <= now` itself.** The newest-entry query sorts by
  `entryDate` descending, the same way `EntryListView`'s `@Query` does (`:10-11`), so without the
  filter a future-dated entry becomes "the latest" upstream and the composer's own exclusion never
  sees it. The pure side cannot catch this.
- Anniversary candidates come from date-range fetches, not from fetching the journal.
- Builds the plain facts and calls `TodayComposer`. Holds nothing across an await, re-derives on
  every refresh, exactly like `KeepCard.refresh()` (`Views/Capture/KeepCard.swift:222-231`).

**Tests**: `MindloreTests/TodayTests.swift`, `@MainActor`, on `ModelContainerFactory.make(.inMemory)`
with the seeding helpers from `KeepTests.swift:7-42`. A merged entity resolves to the winner and
the winner's mute wins; a hidden entity produces no card; a loose end with one hidden subject
produces no card; a faded, resolved, or dismissed loose end never reads as open; a future-dated
entry is never "the latest".

## Phase 5: the views

One commit. `Mindlore/Views/Today/TodayCards.swift`, `WeekStrip.swift`, and the header section in
`EntryListView`.

- Today is **a header section of the existing `List`**, above `JournalGroups`' sections, carrying
  no `entryRow` identifier, and with its own `.listRowBackground(Color.clear)` and hidden
  separators, so it does not inherit the card background Phase 1 gives entry rows and draw a seam
  under its own `.card()` surfaces.
- Cards use `.card()` (its first call sites), `Motion.settle` to arrive, `Motion.stagger` between
  them, and `.chip()` for any area or mood. Quoted user words use `.journalText()`; everything the
  app says is SF Pro. Dismissal is a per-card control writing the day-scoped settings key, with
  `Haptics.selected`.
- The week strip is seven dots, filled where a day has an entry, tinted by that day's first visible
  area (`settings.isHidden`), ink where there is none. No count, no streak, no label that can read
  as a target.
- "It's been a while" carries a per-person "Don't show" writing `Entity.resurfacingMuted`.
- Identifiers: `todayHeader`, `todayCard-<key>`, `todayDismiss-<key>`, `weekStrip`.
- **Refresh**: the header recomputes in `.task(id:)` keyed on `graph.revision`, `saver.revision`,
  and `JournalSaves.revision`, the same three monotonic counters `AskIndexStore.Revisions` uses
  (`AskIndexStore.swift:36`, built at `RootView.swift:99`), plus the current calendar day. Revision
  1 said `entries.count`, which is not an ordinal: an add and a delete return it to the same value,
  so the header would silently miss a change. Not keyed on every `@Query` update, or a keystroke
  elsewhere recomposes it.

**Tests**: a `today` shot added to `DesignScreenshotTests.testTour` in both appearances (the dark
run needs `simctl ui <udid> appearance dark`, per `DesignScreenshotTests.swift:7-10`). **Both
attachments get opened and looked at before this phase is done**, per `tasks/lessons.md`: a
screenshot's filename is not evidence of its contents. One UI test dismisses a card and relaunches
against the same `UITEST_STORE_NAME` store to prove it stays gone within the day; the day-*change*
case is a composer unit test, because the view reads `Date.now` and there is no launch-argument
clock to inject.

## Phase 6: diagnostics, privacy, review

One commit.

- `today.shown`: card count, the card kind keys as fixed rawValues, week-strip filled count,
  compose duration. `today.dismissed`: the kind key and its rank. Never a name, a quote, a
  loose-end text, or a title.
- A sentinel test in `TodayTests` following `KeepTests.swift:215-235`: put
  `DiagnosticsPrivacyTests.sentinel` in the entry text, the entity name, and the loose-end text,
  then assert it reaches **the composed `Today.cards` copy strings**, not merely the facts fed in,
  so the check exercises the copy path that could leak it. Then assert the written log never
  contains it.
- Record the test count and `git status` baseline, then a read-only sub-agent review over the whole
  diff (`tasks/lessons.md`: a reviewer with write tools reviews its own edits). Fixes in separate
  commits, never amended.

## Not in scope

- Reflect: recaps, charts, mood over time, any generated narrative about a period.
- The daily reminder and App Intents (B6).
- The toolbar compose menu and removing the toolbar mic (owner decision 9, separate moment).
- The Settings "Your journal" totals row.
- Any change to `JournalGroups`, `JournalFilter`, the coordinators, the graph simulation, retrieval,
  or `GrowingTextEditor`.
- Consolidating `LifeAreaChips` and `WrappingChips` onto `.chip()`. Left for B5, which restyles the
  insights sheet that owns them.
- Consolidating the four remaining inline merge-walk copies onto `EntityDirectory`. Phase 4 moves
  the type and adds one caller; the rest is a separate pass.
- iPad layouts, localisation, user-picked accents.

## Review log

Revision 1 (read-only sub-agent review, 2026-09-19; 19 findings, the factual ones re-checked
against the code before folding in):

1. Two cited line numbers were wrong (`areaFilterRow` is `:180-209`, `json(_:_:)` is `:248`), from
   a copy-paste between files during research. Fixed and spot-checked the rest.
2. The refresh fingerprint used `entries.count`, which round-trips on an add plus a delete: changed
   to `JournalSaves.revision`, the counter `AskIndexStore` actually uses.
3. `resurfacingMuted` was left out of `recount`'s keep-list, so a muted person would be pruned and
   come back under a new id with the mute forgotten. Now in the keep-list, with a test.
4. A loose end can name several entities; the hidden rule was undefined for a partial match. Now:
   any hidden or muted subject suppresses it.
5. Nothing stopped one entry backing two cards in a small journal. Added as an explicit rule.
6. Several spans can match one day; whether a dismissal promotes another anniversary was undefined.
   Now: one `.onThisDay`, chosen once.
7. The future-date filter lived only in the pure composer, which cannot stop `TodaySource` fetching
   a future entry as "the latest". The filter is now named on the fetches.
8. "Disabled" and "dismissed" shared a test that either bug would pass. Split.
9. `Calendar` clamps 31 March minus a month onto February; now a named test.
10. The privacy sentinel could have passed while only proving the sentinel was in the input.
    It now asserts against the composed card copy.
11. The UI test for "stays gone for the day" had no clock to advance; the day-change case moved to
    a unit test.
12. `EntityDirectory` sat in `AI/Insights/` while being a graph concern; it moves to `Graph/`.
13. The merge-walk is copied five times, not four (`EntityPeekPresentation.load` was uncounted).
14. No UI test asserts a bare `app.cells.count`, only the `entryRow`-filtered query. Checked, and
    recorded here so the next person does not have to re-derive it.
15. Added the pre-review baseline and the "look at both screenshots" step from `tasks/lessons.md`,
    and a note to diagnose a failing boundary test before loosening it.
