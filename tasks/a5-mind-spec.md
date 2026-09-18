# A5 build spec: the Mind tab, search panel, and peek card

Branch `feature/phase-a`. Implements the "Mind tab" and "Peek card" key decisions and the A5
checklist in `tasks/todo.md`. Builds on A3 (`GraphSimulation.update`, `GraphCanvasView`'s
`focusedID` binding), A4 (`AppRouter`, tabs), and A6 (`EntityPeekCard`, `EntityPeekSheet`).

## What exists today

- `MindPlaceholderView` (`Views/Shell/PlaceholderTabs.swift`) opens `ConnectionsView` as a sheet.
  `GlobalGraphView` is pushed from Connections, `LocalGraphView` is a sheet from the entity page's
  Graph button.
- `ConnectionsView`'s path is `[ConnectionsPathItem]`, so every `NavigationLink(value: EntityRoute)`
  inside `EntityView` ("Mentioned with", "Merged into this") pushes nothing there. That is the
  whole of the old unmerge failure: the test could never reach Tom's page to unmerge. The list
  itself refreshes through `@Query` and `graph.revision`, so nothing suggests a data problem;
  a unit test below pins it (unmerge makes Tom browsable again with his link count back).
- `AppRouter` has no Mind path yet (A4's spec mentioned one; it wasn't added).
- `EntityPeekCard` shows name, kind, details, the open loose end, and the bio line, and takes an
  `open` closure. It hides the navigation bar and has no background of its own.
- `EntityView` has no loose-ends section. Its actions section has "Graph", which opens
  `LocalGraphView`.

## Router

`AppRouter` gains:

```swift
var mindPath: [EntityRoute] = []
private(set) var mindFocusRequest: MindFocusRequest?   // struct { id: UUID; token: Int }
func showInMind(_ entityID: UUID)   // dismiss token += 1, tab = .mind, mindPath = [], request = (id, next token)
func replaceInMind(_ loser: UUID, with winner: UUID)   // EntityPagePresentation.replacing on mindPath
```

- `showInMind` waits for covers the same way `showEntry` does (`pendingRoute` becomes an enum
  `PendingJump { entry(JournalRoute), mind(UUID) }`).
- `consumeMindFocus() -> UUID?` returns the pending request and clears it. Mind calls it after its
  first refresh (a jump can arrive before Mind was ever built, and `onChange` never fires for the
  value a view appears with) and in `onChange(of: router.mindFocusRequest?.token)`, so asking twice
  for the same entity still refocuses and a request is used exactly once.
- Journal's path is untouched by `showInMind`, so an open editor stays open on its tab and no close
  rules run.

## `MindView` (`Views/Mind/MindView.swift`)

```
NavigationStack(path: $router.mindPath)
  ZStack
    MindGraph            full screen, ignores the top safe area
    breadcrumb row       top, below the status bar
    filters button       top trailing
    peek card overlay    above the panel, only while something is focused
    SearchPanel          bottom, three stops
  .navigationDestination(for: EntityRoute.self) { EntityView(route: $0) }
  .toolbar(.hidden) on the root only
  .environment(\.entityRouteReplacer) -> router.replaceInMind + refocus
```

State (`@State` on `MindView`, or one `@Observable MindModel` if the view gets heavy; decided
while building, tests target the pure types either way):

- `simulation: GraphSimulation?`, `version`, `names: [UUID: String]`
- `filters: MindFilters` (kinds, minimum mentions)
- `trail: FocusTrail`, with `focusedID` a binding onto `trail.current`
- `highlightedArea: LifeArea?`
- `panelStop: SearchPanel.Stop`

Refresh is `.task(id: RefreshKey(filters, graph.revision))`, the same build-once-then-`update`
shape `GlobalGraphView.refresh()` has today (that body moves here). `onRendered` still goes to
`graph.recordGraphRendered`.

### Default minimum mentions

A fresh journal with ten entries has almost nothing at two mentions, and the phone has a fresh
install. `MindFilters.defaultMinimum(browsableCount:)` is 1 below 60 browsable entities, 2 from 60
on. It's applied once, on the first load, and never overrides a value the user picked in this
session. At the 300-entry seed that's still 2, so the A3 gate numbers stay comparable.

### Focus loop

`FocusTrail` (`Views/Mind/FocusTrail.swift`, pure, `nonisolated struct`):

```swift
private(set) var ids: [UUID]       // capped at 8, oldest dropped
var current: UUID? { ids.last }
mutating func focus(_ id: UUID)    // already in the trail: truncate back to it; else append
mutating func back(to id: UUID)    // truncate to id
mutating func clear()
mutating func replace(_ loser: UUID, with winner: UUID)   // merge; collapses a duplicate
mutating func normalize(root: (UUID) -> UUID, exists: (UUID) -> Bool)   // after every refresh
```

- Tapping a node: `trail.focus`, the canvas flies there (it already does on `focusedID` change),
  the panel drops to `.peek`, the card shows.
- Tapping a neighbour while focused moves focus the same way, so the trail grows.
- Tapping the focused node again opens its page: `GraphCanvasView.onNavigate` pushes
  `EntityRoute` onto `router.mindPath`.
- Tapping empty space: the canvas sets `focusedID` to the edge hit there (a tap near an edge focuses
  its better-connected end) or nil; nil calls `trail.clear()` and hides the card.
- Breadcrumbs: a horizontal chip row of the trail's names (`mindCrumb-<name>`), the current one
  filled. Tapping one calls `back(to:)`. Hidden when the trail has one or no entries.
- A focused id that the graph doesn't contain (a search result under the minimum, or filtered out)
  still shows its card; the card adds "Not on the map with these filters". The canvas's existing
  "clear focus when the node leaves the simulation" rule would fight this, so it moves behind a
  flag: `GraphCanvasView(clearsMissingFocus: Bool = true)`, false in Mind.
- After every refresh, Mind normalises the trail against one `EntityDirectory`:
  `trail.normalize(root:exists:)` maps each id through `root(of:)` (a merge made anywhere, including
  the review card, becomes the winner, and duplicates collapse) and drops ids whose entity is gone.
  A focused entity that becomes hidden keeps its card, with the "Not on the map" line, since hiding
  happens from its own page.
- After a merge from a pushed page, the replacer also calls `trail.replace(loser, with: winner)`,
  so popping back lands on the graph focused on the winner.

### Canvas additions

- `highlightedIDs: Set<UUID>?` on `GraphCanvasView`, fed into `GraphDrawCache`'s key. When set and
  nothing is focused, nodes outside the set draw at 30% and their edges at 15%. Focus still wins
  when both are set. `GraphDrawPlan` gains `highlightedNodes: Set<Int>?`, computed with the plan,
  never per frame.
- The accessibility value gains `highlighted=<count>` so a UI test can see an area tile work.
- The canvas's identifier in Mind is `mindGraphCanvas`. With nothing highlighted the value reports
  `highlighted=0`.
- The canvas also flies to `focusedID` in `onAppear`, so a canvas built with focus already set (a
  Show in Mind jump into a Mind tab never opened) centres it.
- `visibleInsets: EdgeInsets` shifts the fly-to target to the centre of the part of the canvas the
  panel and card don't cover. Mind passes the panel height plus the card when one shows.

## Search panel (`Views/Mind/SearchPanel.swift`)

A custom view, not a sheet, laid out inside Mind's content (A4's check showed the tab's bottom
safe area already clears the tab bar and the accessory).

**Stops.** `.peek` (grabber and field, about 76 pt), `.half` (45% of the available height), `.full`
(the available height minus 60 pt). `SearchPanel.height(for:available:)` is pure and tested.

- The drag gesture lives on the header (grabber and field row) only. The list below scrolls on its
  own and never moves the panel, which avoids scroll-handoff bugs. At `.half` and `.full` the list
  is visible; at `.peek` it isn't built.
- Release snaps to the nearest stop, with a velocity term (`SearchPanel.snap(from:translation:velocity:available:)`, pure).
- Focusing the field moves the panel to `.full`. Submitting or tapping a result resigns the
  keyboard.
- The graph and the panel container both use `.ignoresSafeArea(.keyboard)`, so the keyboard never
  moves the map or changes `available` (measured once, without the keyboard). Only the list takes
  the keyboard's height, as a bottom `.safeAreaInset`, so at `.full` the panel keeps its top edge.
- The panel starts at `.half`, so the tiles and rows are visible on first open.
- Tapping a result (or submitting) clears the query as well as resigning the keyboard, so the
  tiles and the review card come back when the panel is raised again.
- The panel background is `.regularMaterial` with a 16 pt top corner radius. Identifier
  `mindSearchPanel`, value `stop=peek|half|full`.

**Contents, top to bottom:**

1. Field "Search people, places, tags" (`mindSearchField`). Submit focuses the first result.
2. Review card, at most one (below). Hidden while searching.
3. Area tiles, a 3-column grid of visible areas (`settings.visibleLifeAreas`, display names). A tap sets
   `highlightedArea` (`areaTile-<raw>`, selected trait); a second tap clears it. Hidden while
   searching.
4. Segments: All, People, Places, Projects, Tags (`mindSegment-<name>`). All is every kind.
5. Rows (`mindRow-<name>`): kind symbol, name, "last mentioned <relative date>", and "N open" when
   the entity has open loose ends. Tapping focuses it and shows its card.
6. Hidden, a collapsed section at the end (`mindHiddenSection`), rows open the page directly (a
   hidden entity isn't on the map, and its page is where you unhide it).

Empty states: "No people or places yet" with no entities; `ContentUnavailableView.search` with
no matches.

### `EntitySearch` (`Graph/EntitySearch.swift`, replaces `ConnectionsPresentation`)

```swift
nonisolated enum EntitySearch {
    struct Row: Equatable, Identifiable {
        let id: UUID; let name: String; let aliases: [String]; let kind: EntityKind
        let linkCount: Int; let lastMentioned: Date?; let openLooseEnds: Int
    }
    enum Segment: CaseIterable { case all, people, places, projects, tags }
    static func filter(_ rows: [Row], segment: Segment, query: String) -> [Row]
    static func rank(_ rows: [Row], query: String) -> [Row]
}
```

- `filter` keeps today's name-and-alias `localizedStandardContains` rule.
- `rank`: with a query, names that start with it first, then names with a word that starts with it,
  then alias-only matches; inside each group, most recently mentioned first, then name. Without a
  query, most recently mentioned first, never-mentioned last, then name.
- A7's entity search calls the same two functions.

### `MindDirectory` (`Graph/MindDirectory.swift`)

`static func rows(in context: ModelContext, now: Date) -> (visible: [Row], hidden: [Row])`:

- One `Entity` fetch, one `LooseEnd.all` fetch. Open loose-end counts go through
  `EntityDirectory.root(of:)`, each loose end counted once per root even when two of its
  `entityIDs` resolve to the same winner.
- `lastMentioned` is `Entity.lastLinkedAt` (the recount already covers a merge, since the links
  moved).
- Visible is `isBrowsable`; hidden is `hidden && !isMerged`. Merged losers appear in neither.
- Refreshed on `.task(id:)` keyed on `graph.revision` and on a `@Query` of loose ends reduced to
  `(id, statusRaw)` pairs, so marking one Done (which changes status, not the count, and doesn't bump
  `revision`) updates the counts. `MindDirectory.refreshKey(looseEnds:)` is the pure key and is tested.

### Review card (`Views/Mind/ReviewCard.swift`)

`ReviewQueue.next(suggestions:unsure:skipped:) -> ReviewQuestion?` (pure):

- `ReviewQuestion` is `.same(a, b)` or `.whichOne(UnsureMention)`.
- "Which one?" questions come first (they're about a specific sentence the user wrote), then
  "likely the same" pairs in `EntityMatcher`'s order.
- `skipped` is a session-only set of question keys, so "Skip" moves to the next one without
  writing anything.

The card:

- Same: "Are **A** and **B** the same?" with Same (merge A into B, the existing Connections
  behaviour), Not the same (`markNotSame`), Skip. Identifiers keep today's
  `reviewSame-<id>`/`reviewNotSame-<id>`.
- Which one: "“Sam” in your entry from <date>: which one?" with one button per candidate
  (`whichOneCandidate-<name>`), each calling `graph.repoint(mention, to: .existing(id),
  addingAlias: false)`, plus Skip. The full `RepointView` stays reachable from the entity page's
  "Not them".
- `graph.unsureLinks` can repoint and save a tie that has answered itself, without bumping
  `revision`. That's harmless (the question just disappears) and stays as is.
- Every answer flushes the saver first, the same as today. The graph bumps `revision`, which
  refreshes the queue, so the next question shows without extra state.

## Area highlighting

The area-of-entity rule moves up from A5b, since the tiles need it now. Regions (the anchor force)
stay in A5b.

`EntityAreas.primary(of:)` in `Graph/EntityAreas.swift`:

```swift
nonisolated static func primaryAreas(links: [(entityID: UUID, entryID: UUID)],
                                    areasByEntry: [UUID: (areas: [LifeArea], date: Date)]) -> [UUID: LifeArea]
```

- For each entity, count each linked entry's areas once. The most common area wins; a tie goes to
  the area of the most recent entry among the tied ones; still tied, `LifeArea.allCases` order.
- Entities whose entries have no areas get none.
- Links are the resolved ones `resolvedLinks` already builds (roots, browsable). `GraphServices`
  gains `primaryAreas(in:) -> [UUID: LifeArea]`, one `EntryInsights` fetch, cached on `revision`.
- A tile tap sets `highlightedIDs` to the entities whose primary area is that one. Hidden areas
  have no tile.

## Peek card in Mind

- `MindPeekOverlay` wraps `EntityPeekCard(route:open:).id(focusedID)` (so a new focus never shows
  the previous entity's summary while it loads) in a 180 pt `.regularMaterial` rounded
  rect, placed just above the panel's peek stop.
- `open` pushes onto `router.mindPath`. A drag up of more than 60 pt on the card does the same;
  a drag down clears focus.
- `EntityPeekCard` gains `var showsMapHint = false` for the "Not on the map" line. Its existing
  `.toolbar(.hidden)` stays; in the overlay it applies to Mind's root, whose bar is hidden anyway.
- The card still never calls `pageOpened`. Only a pushed `EntityView` does.
- Elsewhere nothing changes: the editor's `EntityPeekSheet` from A6 is the sheet form.

## Entity page

- **Loose ends section** (`entityLooseEnds`), after About: open loose ends about this entity
  (through `EntityDirectory.root`), newest mention first, each showing its text and the date of
  its source entry, with Done and Let go swipe actions through the same code the insights card
  uses (`LooseEnd` status setters, saved without stamping entries). Resolved and faded ones sit in
  a collapsed "Earlier" disclosure. The section is hidden when there are none. The data comes from
  `EntityPagePresentation.looseEnds(for:all:directory:)`, pure over fetched values.
- **Show in Mind** replaces Graph (`entityShowInMind`): `router.showInMind(id)`. From inside Mind's
  own stack that pops to the map and focuses; from a sheet (the editor's peek sheet, insights
  chips) it closes the sheet through the dismiss token first. Hidden entities don't show it.
- The `LocalGraphRoute` sheet is removed.

## Deletions

`ConnectionsView.swift`, `GlobalGraphView.swift`, `LocalGraphView.swift` (with
`ConnectionsPathItem`, `LocalGraphRoute`, `GlobalGraphFiltersView`), `ConnectionsPresentation.swift`,
`ConnectionsPresentationTests.swift` (its cases move to `EntitySearchTests`), and
`MindPlaceholderView`. `GraphServices.localGraph(around:depth:)` goes too, since nothing else calls it; its unit tests go,
but the local-graph privacy case in `DiagnosticsLogTests` moves onto `globalGraph` plus
`recordGraphRendered` rather than being dropped. `GraphCanvasView`'s `anchoredID` stays, with a
comment that it has no caller until A5b's regions.
`GraphServices.globalGraph(asOf:)` stays for A5b's replay. Comments that name the deleted views
are updated.

The filters sheet moves into Mind as `MindFiltersView` (kinds and minimum mentions, no "As of";
replay replaces it in A5b), opened from the filters button (`mindFilters`), with the existing
`globalGraphKind-*` identifiers renamed `mindKind-*` and the stepper `mindMinimumMentions`.
Changing a filter goes through the same `refresh()`, so the simulation updates in place.

## Diagnostics

- `mind.focused` with `source` (`node`, `search`, `crumb`, `showInMind`) and `onMap` (bool).
- `mind.filtersChanged` with `kinds` (count), `minimum`, and `nodes`.
- `mind.reviewAnswered` with `kind` (`same`, `notSame`, `whichOne`, `skip`).
- Never a name, a query, or loose-end text. `DiagnosticsPrivacyTests` gets a case that builds the
  directory, answers a review question, and logs a focus with the sentinel as every entity name,
  alias, and loose-end text.

## Demo seeder fix

Tags come from the text instead of a random pick. `DemoJournal` gains a list of about 30 topic
sentences, each written around one or two tag words that appear in it literally and are never a
life area's name (A1's parser drops those) ("Slept badly, and
the lack of sleep showed at work." → `sleep`). Each draft picks one to three topics, appends their
sentences, and takes its tags from them. The areas stay as they are but a topic can add its area
(`running` → Health), still capped at two. The tag pool no longer scales with the entry count; it's
the topics' tags. `DemoJournalTests` gains: every tag of every draft appears in its text
(`NameMatching`, word-bounded), and the 300-entry graph still has 150 or more nodes at minimum 2
(so the device gate stays meaningful).

## Tests

Unit (Swift Testing):

- `AppRouterTests`: `showInMind` selects Mind, clears Mind's path, bumps both tokens, leaves Journal's
  path and runs no close rules; it waits behind a cover; `replaceInMind` swaps the last loser.
- `AppRouterTests` also: a request made before Mind ever appeared is consumed exactly once.
- `FocusTrailTests`: append, truncate on refocus, `back(to:)`, cap of 8, `replace` collapsing a
  duplicate, `normalize` after a merge made outside a pushed page, and dropping a deleted id.
- `EntitySearchTests`: today's filter cases, segments (All includes organizations, events, and
  other), ranking with and without a query.
- `MindDirectoryTests` (in-memory store): last mentioned; open loose-end count through a merge
  (the winner's count includes the loser's, unmerge splits it, one loose end naming both counts
  once); resolved and faded aren't counted; hidden rows go to the hidden list; merged losers go
  nowhere; after unmerge Tom is visible again with his link count restored.
- `MindDirectoryTests` also: marking a loose end Done changes the refresh key.
- `ReviewQueueTests`: a tie that resolves itself inside `unsureLinks` yields no question; which-one before same, skip advances, nothing left returns nil, answering (a
  merge or a repoint through `GraphServices`) removes the question on the next call.
- `EntityAreasTests`: most common area, tie to the most recent, entries without areas, a merged
  entity counts the loser's entries.
- `GraphCanvasModelTests`: a highlight set dims the rest; focus beats highlight; the plan
  recomputes on a highlight change only.
- `SearchPanelTests`: stop heights and snapping, with velocity.
- `MindFiltersTests`: the default minimum below and above 60.
- `EntityPeekPresentationTests`: a hidden entity still summarises; a merged loser's route resolves
  to the winner's summary.
- `EntityPagePresentationTests`: the loose-ends split (open first, earlier collapsed, through a
  merge).
- The card never calls `pageOpened`: covered by the UI test below (the stub drafts a bio as soon as
  a page opens, and the card shows none).
- `DemoJournalTests` and `DiagnosticsPrivacyTests` as above.

UI (`iPhone 17 phase-a-ai`, stub AI), `GraphUITests` rewritten:

- `testOpenAPersonSeeTheDraftedBioEditItAndOpenATag`: unchanged.
- `testMindFocusesATappedNodeAndKeepsResponding` (replaces the global graph test): finish the Sarah
  entry, open Mind, the canvas shows at least 2 nodes without touching filters (default minimum 1),
  tap until focused, the card shows, tap an empty mid-left point (0.05, 0.35; the bottom is the
  panel and the top has the crumbs and filters button), focus clears, open filters and
  switch off People, the node count drops without the canvas disappearing.
- `testMindSearchOpenMergeAndUnmerge` (replaces the Connections test): search "Sarah", tap the row,
  the card shows with no drafted bio, Open, the page shows its drafted bio, tap
  `entityEntriesSummary` then an `entityEntryRow-`, the preview shows, Done, back to the map; search
  "Tom", Open, merge into Sarah, the page becomes Sarah's, back, the canvas reports
  `focused=Sarah`; relaunch; search "Tom" finds no `mindRow-Tom` (it does find `mindRow-Sarah`,
  since the merge made Tom her alias); open Sarah, "Merged into this" → Tom's page
  → Unmerge; back twice; search "Tom" finds the row again. No `XCTExpectFailure`.
- `testReviewCardNotTheSameRemovesThePair`: rename Tom to Sara from his page, back, raise the panel
  to half (the query was cleared by the result tap), the review card shows, Not the same, the card is gone and both rows remain.
- `testAreaTileHighlightsItsEntities`: tap the Friends tile (the stub files the entry under
  friends), the canvas reports a non-zero `highlighted=`, tap again, it reports 0.
- `testShowInMindFromTheEditor`: finish the Sarah entry, open the read view, tap the Sarah link,
  Open, Show in Mind: the Mind tab is selected with `focused=Sarah`, and the Journal tab still has
  the entry open.
- `GraphScreenshotTests.testDemoJournalGlobalGraph` opens the Mind tab directly and screenshots rest,
  focused, zoomed, and the panel at half.
- Phase-scoped run: `InsightsUITests` (the stub change below), `GraphUITests`, `GraphScreenshotTests`, `ReadModeUITests` (the peek sheet and its
  Open still work), `JournalNavigationUITests`, `RecordingUITests` (the accessory over the Mind
  panel).

Device (asks before deploying): launched with `-seedDemoJournal 300` (its own store; the owner has
no real journal on the phone yet, so this is fine for A5): smoothness by eye at 300 nodes, the
panel's three stops with the keyboard up, a filter change without a jump, focus and crumbs, Show in
Mind from an entry, and the recording accessory over the panel.

### Stub change

The stub's loose end gets `about: ["Sarah"]` (`UITestingHTTPClient`), so
`testMindSearchOpenMergeAndUnmerge` also checks "1 open" on Sarah's row, the card's loose-end line,
and the page's `entityLooseEnds` section. `InsightsUITests` joins the phase-scoped run.

## Units and commits

1. `EntitySearch` replaces `ConnectionsPresentation`; `MindDirectory`, `ReviewQueue`,
   `EntityAreas`, `FocusTrail`, `MindFilters`; `AppRouter.showInMind`. Unit tests only, no UI yet.
2. Canvas highlight and `clearsMissingFocus`. `MindView` with the graph, filters, focus loop,
   crumbs, and the peek overlay. Placeholder and Connections deleted, `GlobalGraphView` and
   `LocalGraphView` deleted, entity page gets Show in Mind. Diagnostics and privacy case.
3. `SearchPanel` with stops, rows, segments, tiles, review card, hidden section.
4. The entity page's loose-ends section.
5. `GraphUITests` and `GraphScreenshotTests` rewritten, phase-scoped UI run.
6. Demo seeder fix and its tests.
7. Sub-agent review of the A5 diff, fixes in separate commits, review log, tick the plan.

Each unit: build, unit suite on `iPhone 17 graph-unit`, commit, push.

## Not in scope

Lenses, replay, entries as nodes, area regions and the anchor force (A5b). Ask's entity search (A7,
which reuses `EntitySearch`). A 120 Hz frame rate. Sorting options in the panel (recency and the
query decide the order). Saving filters, the trail, or the panel stop across launches. CLAUDE.md's
Graph section (A9).

## Review fixes (sub-agent review of this spec, verdict "approve with fixes", 15 findings)

Folded in above:
1. A Show in Mind jump into a Mind tab never opened was lost: `consumeMindFocus()` on first refresh
   and on change, and the canvas flies to its focus on appear.
2. The keyboard would have moved the map: `.ignoresSafeArea(.keyboard)` on the graph and panel,
   and only the list takes the keyboard inset.
3. A merge made outside a pushed page (the review card) left the trail on the loser: the trail is
   normalised through `EntityDirectory.root` after every refresh; a hidden focus keeps its card.
4. Done on a loose end changes status, not the count: the refresh keys on `(id, status)` pairs.
5. The overlay card could show the previous entity while loading: `.id(focusedID)`.
6. UI test fixes: an empty-space tap point clear of the panel and crumbs, the panel starting at
   half, a result tap clearing the query, `highlighted=0`, the Tom alias after a merge, and a stub
   loose end about Sarah so the counts, card line, and page section are covered.
7. The local-graph privacy case moves onto `globalGraph` instead of being deleted.
8. Smoothness at 300 nodes: the owner approved seeding the demo store on the phone for A5.
9. `unsureLinks` saving a self-resolved tie during a read is noted and tested.
10. `visibleLifeAreas`, not `visibleAreas`.
11. `graph.rendered`'s `screen` field dropped; `anchoredID` commented as waiting for A5b.
12. Fly-to centres on the visible part of the canvas (`visibleInsets`).
13. Demo tags avoid area names.
14. Empty-space taps can focus an edge's end; the card's hidden toolbar note corrected.
15. The missing unit tests are added to the list.
