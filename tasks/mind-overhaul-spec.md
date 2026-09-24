# Mind overhaul spec: one meaning per channel, a time window, a drawer that says what changed

Branch `feature/mind-overhaul`, worktree `.claude/worktrees/mind-overhaul`, built on
`feature/story-seed-insights` (PR #51, the story seed regenerated through the real pipeline).
Rebase onto `origin/main` once #51 merges. Approved by the owner on 2026-09-23. Nothing is
implemented yet; start at Phase 1.

## Working notes for whoever picks this up

- Use the worktree's own simulator, `iPhone 17 mind` (UDID CEA2750E-3675-42AF-AAC8-A4EAD38645AA),
  and DerivedData at `~/Library/Developer/Xcode/DerivedData/Mindlore-mind`. The shared
  `iPhone 17` and `iPhone 17 fmt` belong to other sessions.
- `MindloreUITests/MindAuditScreenshots.swift` is an untracked scratch test that walks every
  current Mind state on the story journal and screenshots it (export with
  `xcrun xcresulttool export attachments`). Use it for before/after comparisons; never commit it;
  delete it in Phase 6.
- The owner wants questions asked, not assumed, and plans approved before code. Follow the
  dev-plan workflow: commit, push, CI green per phase; draft PR after Phase 1.
- Keep tool output small: filter xcodebuild to failures and summaries; never dump the chapter
  JSON in `Mindlore/Debug/DemoStory+Chapter*.swift`.

## What the audit found (2026-09-23)

Screenshots of every state on the old story seed, plus the owner's own journal:
- The owner's real map (with parts) is spread into meaningful topical islands; the "hairball" on
  the old seed was an artifact of a seed with no parts. Do not argue the redesign from clutter.
- Tags dominate the labels (in the owner's map about 10 of 12 labels are tags; in the regenerated
  story 82 of 158 names are tags).
- The "Mood around" lens painted nearly every node Calm, because it takes the mode and "content"
  (the most common mood) maps to calm. The real signal (Greg: 4 of 5 entries anxious or irritated;
  Kev: content or joyful) is only visible as a distribution against a baseline.
- Recency is encoded twice, area three times; color changes meaning behind a menu; "Group by
  area" barely moves the cluster; entry dots are invisible at this scale.
- The drawer leads with a data-cleanup question and nine area tiles over an alphabetical list.
- The entity page opens on Name/Kind/Contact/aliases and lists "Mentioned with" (84 rows for Maya
  on the old seed) with no counts.

Regenerated story (PR #51) numbers: 200 entries, all journal; 116 with two or more parts; 158
names (33 people, 15 places, 10 organizations, 5 projects, 6 events, 7 other, 82 tags); 73
threads (34 resolved, 32 faded, 7 open). Part-aware co-occurrence at most 1,057 pairs versus
1,925 entry-level; Maya's connections at most 73 versus 119.

## Research (summarized; the full report was a scratch file)

- Global force-directed graphs of personal notes draw the same "pretty but decorative" complaint
  in Obsidian, Logseq, and Reflect; Tana shipped without one. Every documented useful use narrows
  first (local graph around one node). Ghoniem, Fekete and Castagliola (2004): node-link loses to
  other forms past about 20 nodes except for path-finding.
- Journaling and self-tracking apps people praise surface patterns as lists, grids, and single
  resurfaced items: Day One On This Day, Daylio Year in Pixels, Apple Health "notable change"
  callouts with charts one tap deeper, Clay/Dex "you haven't mentioned X lately".
- Small multiples beat an animated single view on 7 of 9 mobile tasks (96-person study), which is
  the case against the replay.
- Personal informatics (Li, Dey, Forlizzi 2010): reflection fails when the view does not match the
  user's question. Baumer (2015): reflection needs a prompt to notice, which is what "what changed"
  is for.
- House rule carried over from Phase B: the app observes, never judges or advises; no number that
  can make the user feel they failed (no streaks, no "days missed").

## The change rules, measured

A draft of the Phase 1 rules run over the regenerated story:
- Month: "running" more lately (11 of 19 entries, up from 7 of 41); "therapy" quieter.
- 3 months: Greg, Priya, "job search", "Payouts v2" quieter (the Ledgerline chapter closing);
  "dating" quieter (after the breakup); "knee" new.
- Noise the tightened rules below remove: the author ("Teo") came up as New; tags produced most
  junk ("bears", "quiet evening", "coffee" back after 110 days).

## Context

The Mind tab works but grew by accretion: color swaps meaning behind a lens menu (kind, mood,
recent), recency is drawn twice (7-day halo, 30-day lens), life area three times (regions,
highlight tiles, grouping), a replay animates the year, a filter sheet holds kind toggles, a
minimum-mentions stepper, entry dots, and grouping, and the drawer mixes search, a data-cleanup
question, nine area tiles, and an alphabetical list. The peek card is mostly empty and the entity
page opens on admin rows (Name, Kind, Contact, aliases) with 84 "mentioned with" rows and no
counts. Nothing on the screen answers the questions the data can: who and what fills my life,
how it connects, and what changed.

Owner decisions (2026-09-23): the map stays the centerpiece. Color always means life area. Kind is
shape: tags are hollow rings with lighter labels, everything else filled. Time is a window control
(Month, 3 months, Year, All) that replaces the replay. The drawer holds search, a "what changed"
row, a ranked list with sparklines and kind chips, and a Tidy up row. In scope too: a richer peek
card and an entity page that leads with insight, with admin moved under Edit. Island labels are
deferred.

Branch `feature/mind-overhaul` from `main` after PR #51 (regenerated story seed) merges, so the
story journal used for screenshots has parts.

## Decisions made in planning (approved with the plan)

- Default window 3 months; the choice is remembered per launch only (not a setting).
- Size = entries mentioning the name inside the window (`GraphSimulation.radius(linkCount:)`
  unchanged, fed the window count). A name with no mention in the window leaves the map; search
  still finds it.
- Color = the name's primary area within the window (`EntityTally.primary` over windowed links);
  no area in the window = neutral grey.
- The kind chips (All, People, Places, Projects, Themes) filter both the list and the map. They
  replace the filter sheet's kind toggles; the filter sheet, minimum stepper, entry dots, and
  grouping go.
- Breadcrumbs (`FocusTrail`) and bloom for newly written names stay.
- The author is excluded from "what changed" by `SettingsStore.userName` (name or alias match).
- The chips keep today's segment mapping, with Tags renamed Themes: People, Places, Projects, and
  Themes each show one kind; organizations, events, and other show only under All (owner,
  2026-09-23, during Phase 2).
- A journal with 60 or more names keeps its automatic minimum of 2 mentions in the window before a
  name draws; the list still shows everyone (owner, 2026-09-23, during Phase 2).
- Phase 1 readings: changes rank by the shift in share times the larger of the two counts (a sum
  put Greg fifth behind a tag), "more lately" needs an earlier mention, and no changes show
  without a baseline.
- Phase 2: the map's edges come from the window's entries too, not only its sizes, so an old
  shared entry doesn't tie two names the window has apart. Map labels and the window control cap
  their text size (accessibility sizes truncated the control and buried the map in labels). The
  drawer's area tiles went with the area highlight they drove.
- The replay stays (owner, 2026-09-23, reversing its removal): a play button left of Month plays
  the whole journal, first mention to today, whatever the window, in the drawer's chosen kind,
  then returns to the window. Picking a window during a replay ends it there. `MindReplay`,
  `MindReplayTests`, and `mind.replayed` stay.
- Phase 4: "Often with" lists names only (people, places, projects, and so on) and themes get
  their own quieter line, on the card and the entity page alike, because tags share the most
  entries with anyone and crowded out the people (owner, 2026-09-23). "Last mentioned" is said in
  days ("today", "3 days ago"), never minutes.

## Phase 1: the numbers (pure, no UI)

New `Mindlore/Graph/MindWindow.swift`: `enum MindWindow { month, quarter, year, all }` with
`days` (30, 90, 365, nil) and `interval(endingAt:)`.

`MindMapSnapshot` gains `entryDates: [Date]` for every non-draft entry, linked or not.
`GraphServices.buildSnapshot` (`:374-390`) builds `entries` only from linked entry ids, so without
this no "N of your last M entries" denominator exists. One extra fetch per graph revision.

New `Mindlore/Graph/MindStats.swift`, `nonisolated`, no SwiftData, over `MindMapSnapshot`
(`Graph/MindMap.swift:7`), the same split `EntityGraph` keeps:
- `counts(_:window:asOf:) -> [UUID: Int]`: entries per entity in the window, each entry once.
  Generalizes `MindMap.recentMentions` (`MindMap.swift:105`), which it replaces.
- `areas(_:window:asOf:) -> [UUID: LifeArea]`: `EntityTally.primary` over windowed links.
- `series(_:entity:window:asOf:buckets:) -> [Int]`: the sparkline, covering the window plus the
  three windows before it (Month: 16 weekly buckets; 3 months: 16 buckets of about 3 weeks; Year:
  16 of about 3 months; All: 16 across the journal's span).
- `changes(_:window:asOf:excluding:) -> [Change]`, `Change { id, kind: new|back|more|quieter,
  inWindow, before, windowEntries, beforeEntries, lastMentioned }`. Rules, by share of entries
  (so writing less never makes everyone "quieter"): baseline is the three windows before.
  New = first mention ever inside the window, at least 2 mentions, not a tag. Back = mentioned in
  the window after a silence of at least max(2 windows, 45 days) with at least 3 mentions before,
  not a tag. More lately = at least 3 in the window (tags 4) and at least double its earlier share.
  Quieter = at least 2 per window before (tags 3), now at half its share or less. Ranked by size
  of the shift weighted by count, capped at 4, none for `.all`. Excluded ids are dropped.
- Shared-entry counts are not computed here. There is one source for "often with":
  `GraphServices.mentionedWith` (`:589-634`), which today returns only `EntityGraph.build`'s
  decayed `weight`. `EntityGraph.Edge` gains `entries: Int` (the entries whose placement produced
  the edge, counted where `build` already decides placement), `CoOccurrence` carries it, and
  `mentionedWith` ranks by it (weight breaks ties). The peek card and the entity page both read it,
  so they never disagree, and it matches the map's edges by construction.
- Mood mix is computed where it is shown (Phase 5), from the page's own entries.

Performance: `MindView` computes counts, areas, series, and changes once per
(graph revision, window, chip) key and holds them in state; nothing runs per frame. Measured on
`-seedDemoJournal 300` and the large-journal case in `DemoJournalTests.theLargeSeedStillMakesABusyMap`
(`MindloreTests/DemoJournalTests.swift:84`), not only on the story.

Tests `MindloreTests/MindStatsTests.swift`: window bounds, share-based rules on fixtures for each
change kind and each exclusion (author, tag thresholds, cap, `.all` empty, a month with half the
entries not making everyone quieter), series bucket edges, windowed area. `EntityGraphTests` gains
edge entry counts under part placement; `GraphServicesTests` gains `mentionedWith` ordering by
count. One test runs `changes` over the seeded story and
asserts the headline arc (for 3 months: running more lately; Greg quieter).

## Phase 2: the map

`Views/Graph/GraphCanvasModel.swift`, `GraphCanvasView.swift`:
- Fill by area: `GraphFill` gains `.area(LifeArea)`; `GraphDrawCache.makePlan` (around line 251)
  takes `areaOf: [UUID: LifeArea]` in place of `GraphPaint` and keys its cache on an area
  generation. `color(_:)` resolves through `LifeArea.color`.
- Tags as rings: the node loop (`GraphCanvasView.swift:356-391`) buckets tag nodes separately and
  strokes them (fill for everything else), keeping the per-bucket path discipline. Tag labels
  draw at secondary opacity.
- Labels: keep `rankedLabels` ordering (by the node's count, now the window count), add a
  screen-space overlap check in the label loop (`:410-420`) so a label that would collide is
  skipped rather than drawn over another.
- Focus: keep `litNodes`/`litEdges` dimming as the single highlight. Delete `highlightedIDs`,
  `highlightGroup`, `flyToHighlight`, halo rings and the 12 fps breathing interval, regions and
  `fitRegions`, entry dots (`isEntry`, `onOpenEntry`, `entryDot`), and `GraphPaint`.

`Graph/GraphSimulation.swift`: drop `regions` from `init`/`update` and `applyRegions`; drop
`isEntry` and `entryRadius`. `update()` already carries surviving nodes and drops departed ones.

`Views/Mind/MindView.swift`: the top bar becomes the window control (a glass segmented control in
the existing `GlassEffectContainer`) plus breadcrumbs. `Frame` is built from `MindStats.counts`
and `.areas` for the window and the chip filter. The replay task, lens menu and legend, filters
sheet, area highlight, and halo state go. Empty state gains "Nothing in this stretch" with a
"Show all time" action when the window is empty but the journal is not.

Deleted with their tests: `MindLens.swift`, `MindRegions.swift`, `MindReplay.swift`,
`MindFilters.swift`, `MindMap.haloed`/`entryNodes`/`moodAround`; `MindRegionsTests`,
`MindFiltersTests`, `MindReplayTests`, `MindHaloTests`, and the matching cases in `MindMapTests`,
`GraphCanvasModelTests`, `GraphSimulationTests`.

Diagnostics (`Graph/GraphServices.swift:481-573`): remove `mind.filtersChanged`,
`mind.lensChanged`, `mind.replayed`, `mind.entryOpened`; `graph.rendered` drops `lens`, `replay`,
`entryNodes` and gains `window`. Add `mind.windowChanged {window: MindWindow raw, nodes: Int}` and
`mind.changeTapped {change: Change.kind raw (new|back|more|quieter), kind: EntityKind raw}`, never
an id or a name. Update `AIDiagnosticsPrivacyTests`
(`MindloreTests/DiagnosticsLogTests.swift:322-376`) and `docs/privacy-coverage.md:27`.

## Phase 3: the drawer

`Views/Mind/SearchPanel.swift` keeps its stops, drag, keyboard handling, and material rules.
Header: search field, then the kind chips (replacing the segmented picker; identifiers
`mindKindChip-<kind>`). Content when not searching:
- "What changed" (`MindChangesRow`): up to 4 compact cards, each a name, the change word, and the
  numbers as words ("in 11 of your last 19 entries, up from 7 of 41"; "once in 3 months, down from
  22"). Tap = focus the node, as a row tap does, and records `mind.changeTapped`. Identifier
  `mindChange-<name>`. Hidden when there are none.
- The ranked list (`MindRankedRow`): area dot, kind glyph, name, `Sparkline`, count in the window,
  the change word when the name is in the changes, and "N open". Ordered by count, then most
  recent. Keeps `mindRow-<name>` and `mindRowOpen-<name>`.
- Tidy up row at the end (`mindTidyUp`, "Tidy up · N to check"), shown when there is a review
  question or a hidden name. Opens `TidyUpView` (sheet): the `ReviewQueue` questions one at a time
  with the existing `ReviewCard` and its identifiers, then hidden names (`mindHiddenSection`).
Searching shows `EntitySearch.rank` over every name (unchanged), windows ignored.

`Graph/MindDirectory.swift` stays the fetch for names, open threads, and hidden rows; windowed
numbers come from `MindStats` over the same snapshot Mind already holds.

New `Views/Design/Sparkline.swift` (no Swift Charts in the app today; a small `Canvas` of bars,
the window's bars at full strength and the earlier ones muted, accessibility value as words).

Tests: `SearchPanelTests` unchanged; a `MindDrawerTests` for row ordering, chip filtering, and
change wording.

## Phase 4: the peek card

`Graph/EntityPeekPresentation.swift`: `Summary` gains `series` (26 weekly buckets, since the card
also appears outside Mind with no window), `lastMentioned`, `connections` (top 3 from
`graph.mentionedWith(..., limit: 3)`, with shared-entry counts), and `openThreads` (count plus the
most recent text). `load` keeps its own narrow fetch (the subject's links and entry dates it
already gathers, `:60-64`) rather than reading Mind's snapshot, because the card also opens from
the editor (`EntryEditorView.swift:259`) and Ask (`AskView.swift:113`), where Mind may never have
built one. `mentionedWith` is the query the entity page already runs, so its cost is known.
`Views/Graph/EntityPeekCard.swift` lays them out: name and kind, the sparkline with "last
mentioned 3 days ago", "Often with Danny (14), Mom (9), Omar (6)", open threads, bio line. The
height math in `MindView.cardHeight` and `EntityPeekSheet`'s detent grows to fit. Existing identifiers (`entityPeekCard`, `entityPeekOpen`,
`entityPeekLooseEnd`, `entityPeekBio`) stay. `EntityPeekPresentationTests` extended.

## Phase 5: the entity page

`Views/Graph/EntityView.swift` stays a `Form` (swipe actions and disclosures, per CLAUDE.md).
Order: header (avatar, name, kind, area, bio text), Presence (a monthly bar row across the
journal's span with "87 entries · Oct 2025 to Sep 2026 · busiest in November"), Feeling (mood mix
beside your usual, 5 or more entries with a mood only, stated as counts), Loose ends (unchanged),
Often with (partners with shared-entry counts from `mentionedWith`, 8 inline, "Show all"),
Entries (unchanged), the place map preview for places, and a Manage section at the bottom.

Presence and Feeling are computed by `EntityPagePresentation` from the entries the page already
fetches for its Entries section, and "your usual" from one fetch of every entry's primary mood,
counted with `ReflectAggregator.aggregate` (`Reflect/ReflectAggregator.swift:54`).
`EntityPagePresentation.coOccurrenceRows` keeps the count instead of dropping it.

Admin splits by whether it navigates. A toolbar Edit button (`entityEdit`) opens
`EntityEditView`, a `Form` sheet with the admin that does not: rename and kind, bio edit and
redraft, contact link, place link, aliases, Hide; identifiers unchanged. Everything that pushes an
`EntityRoute` stays on the page, because those `NavigationLink(value:)` rows resolve only through
the enclosing stack's `navigationDestination` (`MindView.swift:98`, `EntryInsightsView.swift:88`,
`EntityPeekCard.swift:17`) and a merge must keep `entityRouteReplacer` working: "Merged into this"
(with undo), Merge into, and Show in Mind, in the Manage section.
`EntityPagePresentationTests` extended for the new sections' gating.

## Phase 6: UI tests, screenshots, docs

- `GraphUITests`: delete `testAreaTileHighlightsItsEntities`, `testMindLensesEntriesAndRegions`,
  `testMindReplayRunsAndEnds`. Rewrite `testMindFocusesATappedNodeAndKeepsResponding` to change
  the node count with the window control and a kind chip. Rewrite
  `testReviewCardNotTheSameRemovesThePair` through Tidy up. Adjust the bio and alias steps to open
  Edit first; the merge and unmerge steps stay on the page, so `testMindSearchOpenMergeAndUnmerge`
  keeps its `goBack()` flow. Add `testWindowChangesTheMapAndTheList` and `testWhatChangedFocusesAName`.
- `GraphScreenshotTests.testDemoJournalMind` rewritten for the new states (map per window, focus,
  drawer, Tidy up, peek, entity page, Edit), light and dark.
- `scripts/ci/ui-test-seconds.txt`: drop removed tests, time the new ones.
- `CLAUDE.md` Graph/Mind section rewritten (removing lens, regions, replay, halo, filters, area
  tiles; adding window, stats, drawer, peek, entity page). `docs/privacy-coverage.md` updated.
- The untracked `MindAuditScreenshots.swift` is deleted.

## Verification

- Each phase: its unit tests, then the full unit suite on the worktree's own simulator
  (`iPhone 17 mind`); UI tests only for the phase's own screens (owner rule), the full Graph UI
  set in Phase 6.
- Screenshots on the regenerated story journal (`-seedStoryJournal -resetStoryJournal`) for every
  window and both appearances, at the default text size; looked at before calling a phase done
  (lessons.md rule). No accessibility-size pass (owner, 2026-09-23).
- Frame p95 from `graph.rendered` and refresh time on the story journal and on
  `-seedDemoJournal 300`, compared with today's.
- Device: deploy and look at your own journal only after asking first.

## Workflow

Phase 1 commit, push, draft PR, CI green; each later phase commit, push, CI green. Review
sub-agent (read-only) over the full diff, fixes as separate commits, then `gh pr ready`. No AI
attribution in commits or the PR.

## Follow-up PR, planned separately (owner, 2026-09-23)

Reflect becomes one screen with two sides, Recaps (today's summaries) and Numbers (a new overview:
totals and a year grid of days written, the cast of all time, areas and mood month by month,
threads opened and closed). The week strip opens it on Recaps; a chart button in Mind's top bar
opens it on Numbers; each side links into the other for the same stretch. It reuses this PR's
`MindStats` and `ReflectAggregator`. This PR only leaves room for that button in the top bar.

## Not in scope

- The Reflect Recaps and Numbers screen (the follow-up above).
- Island labels for clusters (deferred by owner).
- Today, Reflect, Ask, and the journal list.
- New AI calls (all of this reads stored data).
- A mood color on the map; mood appears only on the entity page.
- Persisting the chosen window as a setting.
