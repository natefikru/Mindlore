# A5b build spec: map extras

Branch `feature/phase-a`. Implements the A5b checklist in `tasks/todo.md` (lenses, replay,
entries as nodes, area regions). Builds on A5's `MindView`, `MindFilters`, `GraphCanvasView`
(`highlightedIDs`, `visibleInsets`, `clearsMissingFocus`), `GraphDrawCache`, and
`GraphSimulation.update`. No second canvas, no second card.

## What exists today

- `MindView.refresh()` calls `graph.globalGraph(kinds:minimumLinkCount:in:)` and
  `graph.primaryAreas(in:)`. Both run `GraphServices.resolvedLinks`, which is one `Entity` fetch,
  one `EntityLink` fetch, and one `Entry` fetch. `primaryAreas` then fetches the entries a second
  time for their areas. It's cached per `revision`. `globalGraph` isn't.
- `globalGraph(asOf:)` filters edges by date, but its standalone-node clause reads the all-time
  `Entity.linkCount`. `GraphServicesTests.globalGraphStandaloneNodeIgnoresAsOfScrubbing` pins that
  quirk. Replay can't live with it: an entity whose later mentions clear the minimum would sit on
  the map from the first frame.
- The canvas fills nodes by `EntityKind` only. Only the focus and its biggest neighbours glow, at
  most 1 + 24 of them.
- `GraphSimulation.Node` is `(id, kind, linkCount)`. The forces are repulsion, springs, gravity
  toward the origin, and collision. `anchor(_:at:)` and the canvas's `anchoredID` have no caller.
  They were built for the deleted local graph's centred subject.

## One snapshot, pure builders

`GraphServices.mapSnapshot(in:) -> MindMapSnapshot` replaces the `primaryAreas` cache. It's
cached per `revision` and built from one `resolvedLinks` pass plus the entry fetch that pass
already makes, extended to read each entry's areas and primary mood. A debug counter,
`snapshotBuildCount`, lets tests count the builds.

```swift
nonisolated struct MindMapSnapshot: Sendable {
    struct EntityInfo: Sendable { let id: UUID; let name: String; let kind: EntityKind }
    struct EntryInfo: Sendable { let id: UUID; let date: Date; let areas: [LifeArea]; let mood: MoodCategory? }
    let entities: [UUID: EntityInfo]          // browsable roots only
    let links: [EntityGraph.LinkInput]        // resolved to roots, browsable only (today's rule)
    let entries: [UUID: EntryInfo]            // every entry some link points at
}
```

`MindMap` (`Graph/MindMap.swift`, `nonisolated enum`) is pure over the snapshot. No builder takes
a `ModelContext`, so a replay step can't fetch.

- `graph(_ snapshot:, filters:, asOf:) -> GraphData`: today's `globalGraph` rules, with one
  change. A node's mention count is the number of its links dated on or before `asOf`, and that
  count feeds both the minimum filter and `Node.linkCount` (the radius). Nodes grow during replay,
  and an entity with no mentions yet isn't on the map. The live map passes `asOf: now`, which is
  what `globalGraph` does today. `globalGraph` becomes a thin wrapper over it, so the existing
  `GraphServicesTests` keep covering these rules. The quirk test is rewritten to expect the node
  gone. The one visible change on the live map: a mention in an entry dated in the future doesn't
  count until that day. Its edges already didn't.
- `primaryAreas(_ snapshot:, asOf:)`: `EntityAreas.primaryAreas` over the links up to `asOf`.
  `GraphServices.primaryAreas(in:)` stays as a wrapper over the snapshot.
- `moodAround(_ snapshot:, asOf:) -> [UUID: MoodCategory]`: see Lenses. `EntryInfo.mood` is
  `insights.primaryMood?.category`.
- `recentMentions(_ snapshot:, asOf:, days: 30) -> [UUID: Int]`: see Lenses.
- `entryNodes(_ snapshot:, onMap: Set<UUID>, asOf:, cap:) -> (nodes, edges)`: see Entries as
  nodes.

`EntityAreas`' tally (the most common value, a tie to the most recent entry, then case order)
becomes a generic
`EntityTally.primary<V: CaseIterable & Hashable>(links:values: [UUID: (values: [V], date: Date)]) -> [UUID: V]`.
Each entry counts each of its values once. Areas pass up to two values per entry, and moods pass
one.

**Revision bumps.** `mapSnapshot` is cached per `revision`, so every change the map shows has to
bump it. Today a mood edit doesn't: `MoodPickerView` saves without telling the graph. It gains a
`graph.moodsEdited()` call that bumps `revision`, and a test covers it. Entries dated in the future
are left out of the snapshot's links.

## Lenses

`MindLens: String, CaseIterable { kind, mood, recency }` is `@State` on `MindView`, not part of
`MindFilters`: a lens changes paint, never the node set, so it never runs `refresh()` or
`update`. It's picked from a menu button in the top bar, left of the filters button
(`mindLens`, items `mindLens-<raw>`, labels "Kinds", "Mood around", "Recent").

The canvas gets one new input, `paint: GraphPaint?` (nil is today's kind colours):

```swift
nonisolated struct GraphPaint: Equatable, Sendable {
    var generation: Int               // the only field the cache key compares
    var palette: [Color]              // at most 9 entries
    var slotByID: [UUID: Int] = [:]   // ids missing here use the neutral grey
    var faded: Set<UUID> = []         // drawn at 35%
    var glowing: Set<UUID> = []       // glow while nothing is focused
}
```

- `GraphDrawCache`'s key gains `paint?.generation`, not the paint itself, so a frame never
  compares a dictionary with up to 300 entries. `MindView` holds the paint in `@State` and bumps
  the generation only when it builds a new paint (on a lens change, a refresh, or a replay step). The plan gains per-index `fillSlots: [Int]`,
  `fadedNodes: Set<Int>`, and, with no focus, `glowNodes` from `glowing`: the 25 with the most
  mentions, the same cap A3 set. It's computed with the plan, never per frame.
- Draw: node fills are bucketed by slot instead of by kind, still one path per bucket. At most
  9 colours times 3 strengths is 27 fills a frame, where today it's 21.
- Focus and area highlight keep working on top of any lens. Faded, focus-dimmed, and
  highlight-dimmed multiply.
- **Kind**: `paint == nil`.
- **Mood around**: each entity's most common primary-mood category across its entries up to
  `asOf`. A tie goes to the most recent entry, then to `MoodCategory`'s order. "Average" of a
  category means this mode. Averaging valence would blur Anxious and Low into one colour.
  Entities with no moods are grey. The palette is `MoodCategory.color`.
- **Recent**: kind colours. Entities with a mention in the 30 days up to `asOf` glow. The rest
  are faded.
- **Legend**: under the top bar while the lens isn't Kind (`mindLensLegend`). Mood around shows a
  dot and name for each category present on the map. Recent shows "Glowing: mentioned in the last
  30 days". Colour is never the only carrier: the legend names every colour, and the peek card
  already names the entity.
- The canvas accessibility value gains `lens=<raw>`.
- Diagnostics: `mind.lensChanged` with `lens`.

## Entries as nodes

`MindFilters.showsEntries` (default off) is a toggle in the filters sheet ("Entries",
`mindShowEntries`), so it goes through `refresh()` and `update`.

- `GraphSimulation.Node` gains `isEntry: Bool = false`. An entry node's id is the entry's id. Its
  `kind` is `.other`, which nothing reads for an entry, and its `linkCount` is its number of
  links on the map. Its radius is a fixed 2.5 pt.
- `MindMap.entryNodes` makes one node for each entry that has a link, dated up to `asOf`, to an
  entity on the map, keeping the newest `MindMap.entryCap = 100`. Each such link becomes an edge
  entry to entity, with weight 1 (a 40 pt spring) and recency from the 90-day decay. Entries with
  no entity on the map are left out.
- Canvas rules for entry nodes:
  - fill neutral grey in every lens, including Kind: `draw` checks `isEntry` before it looks at
    the kind or the slot
  - left out of `rankedLabels`, `head`, and `glowNodes` in `makePlan`
  - never dragged or unpinned: the drag gesture pans when it starts on an entry, and a long press
    ignores entries
  - no repulsion between two entry nodes (collision still separates them)
  - never labelled, never glowing
  - their edges always draw in the thinnest, faintest bucket
  - a focused entity's entry neighbours light up with it, but they don't count toward the label
    or glow caps
  - area highlight includes entries filed under the area
- **Tapping.** `GraphHitTest.node` looks for an entity first, using today's 12 pt minimum. Only if
  nothing is found does it look for an entry within 8 pt, so a dot beside a person never steals
  the person's tap. A hit entry calls the canvas's new `onOpenEntry(id)` and never takes focus.
  An edge hit on an entry edge focuses its entity end.
- `MindView` handles `onOpenEntry` with `router.showEntry(id, forReading:)`, where `forReading`
  is `EntryReadMode.opensForReading` for the fetched entry. Journal's path is replaced. That's
  the existing jump.
- **Performance.** At the 300-entry seed this adds up to 200 nodes to 170, and repulsion and
  collision are O(n²): about 2.6× the pair work. The cap is a constant, and the device step
  measures with entries on. From 170 nodes to 270 is about 2.5× the pair work, and skipping
  entry-to-entry repulsion takes some of that back. If p95 goes over 20 ms, the cap drops to 50,
  since A3b is out of scope here.
- The accessibility value's `nodes=` keeps counting entities only, so existing UI tests hold, and
  it gains `entries=<count>`. New fields (`entries`, `lens`, `replay`, `entryDot`) go between
  `highlighted=` and `focused=`, because the tests match `BEGINSWITH 'nodes=N '` and
  `ENDSWITH 'focused=X'`.

## Area regions

`MindFilters.groupsByArea` (default off) is a toggle in the filters sheet ("Group by life area",
`mindGroupByArea`).

- **`GraphSimulation`**:
  - Regions come in through `update(nodes:edges:regions: [UUID: SIMD2<Double>] = [:])`, so there
    is no second call to order. The points are stored per index as `SIMD2<Double>?`.
  - An update whose nodes, edges, and regions all match changes nothing. When only the regions
    change, it reheats to 0.3 and bumps `topologyVersion`.
  - `applyRegions()` runs after gravity. For each unpinned node with a point:
    `velocity += (point - position) * regionStrength * alpha`, where `regionStrength = 0.06`,
    six times gravity, so area clusters form while springs still pull cross-area pairs toward
    each other.
  - There's no randomness and the iteration order is fixed, so determinism holds.
- **`MindRegions.points(visible: [LifeArea], entityCount: Int) -> [LifeArea: SIMD2<Double>]`**
  (pure):
  - Every visible area (`settings.visibleLifeAreas`) gets a fixed spot on a circle, in
    `LifeArea.allCases` order, whether or not it has entities.
  - The radius is `max(120, 22 * sqrt(entityCount))`, where `entityCount` is the snapshot's total
    number of entities. That number doesn't change during a replay or when Entries is toggled, so
    the points stay put.
- Entities take their `primaryAreas` point. Entry nodes take the point of their first area.
  Anything with no area gets no point and stays under gravity alone, near the middle.
- **Drawing.** The canvas gets `regions: [GraphRegion]` (`id`, `name`, `point`, `color`). Each
  area's display name is drawn at its point in world space, beneath the nodes, in its colour at
  35%, through the existing symbols mechanism. Hidden areas: their entities get no point, so
  they drift to the middle, and they get no label.
- **Tile fly-to.** A tile tap now flies the camera to the centroid of the highlighted nodes,
  keeping the current zoom (`GraphCamera.fly(to:zoom:)` gains an optional zoom). This is useful
  with or without regions. The centroid is taken only over the highlighted ids that are on the
  map. With none on the map, or while something is focused, the camera stays put.
- **Deleted.** `GraphSimulation.anchor`, the `anchored` array, the canvas's `anchoredID`, and
  their tests (`GraphSimulationTests` near lines 171 and 349). The comments on `applyGravity` and
  the canvas that mention the local graph are updated, and so is the "anchor pull" wording in
  `tasks/todo.md`. Their only caller was the deleted local graph, and regions don't need a pinned
  subject.

## Replay

A play button in the top bar (`mindReplay`) animates the map from the first mentioned entry's
date to now in 10 seconds.

- **`MindReplay`** (pure, `nonisolated struct`):
  - `init(start: Date, end: Date, duration: 10)`
  - `asOf(elapsed:)` is linear and clamped
  - `isFinished(elapsed:)`
  - `start` is the earliest link dated on or before now. With no such link, or with
    `start >= end`, the button is disabled.
- **`MindReplayPlayer`** (`@MainActor final class`, owned by `MindView` in `@State`):
  - `init(fetch: () -> MindMapSnapshot, frame: (MindMapSnapshot, Date) -> Void)`
  - `start(now:)` fetches exactly once and keeps the snapshot
  - `step(elapsed:)` calls `frame` with the held snapshot and that step's `asOf`
  - `refetch()` fetches again and keeps the elapsed time, for a `revision` change during a replay
    (a merge, for example, so a focus that moved to the winner is on the map)
  - `stop()` drops the snapshot
- **Driving.** `MindView` runs a `Task` that steps every 100 ms (about 100 steps) off a
  `ContinuousClock`, then stops. Each frame builds `MindMap.graph` plus the lens, area, and entry
  data for that `asOf`, and calls `simulation.update`. Each step changes the edge weights, so
  every step bumps `topologyVersion` and the plan recomputes about 10 times a second. That's a
  sort of about 170 nodes per step, not per frame.
- **Keeping steps cheap.** A step writes `names` only when they change. The replay controls and
  their date live in a child view (`MindReplayControls`), which reads the player, so a step
  doesn't re-render `SearchPanel`. `mind.replayed` reports `stepP95Milliseconds`, so the device
  step can tell step cost apart from draw cost.
- **While replaying:**
  - the top bar shows the replay date ("Mar 2026", `mindReplayDate`) and a stop button in place
    of play
  - focus and taps keep working
  - `refresh()` is skipped. A `graph.revision` change calls `player.refetch()`
  - changing filters or the lens applies from the next step
- **Ending.** A replay ends when:
  - it finishes
  - the user taps stop
  - the Mind tab goes away (`onDisappear` on the `NavigationStack` itself, so a pushed entity
    page doesn't end it; a pushed page stops it through `onChange(of: router.mindPath)`, since
    nobody watches a replay under a page)
  - a focus jump arrives from elsewhere, which stops the replay, refreshes, and then focuses, in
    that order

  Every way out calls `player.stop()` and a live `refresh()`, which returns the map to today
  through `update`. Nodes that survive the whole replay keep their place. Everything else, pins
  included, was dropped at step 0 and grows back beside its neighbours, so the map after a replay
  isn't the map before it. That's accepted: the replay is the story of the layout.
- **Canvas.** It gains `animating: Bool`, which feeds `GraphRedraw.isActive`.
  - Turning it on calls `wake()`, and starts a fresh sample (it resets the sampler and
    `activity.reported`), so a replay is measured even after earlier touches were already
    reported.
  - While it's on, frames count as interaction.
  - `graph.rendered` gains a `replay` bool.
- Accessibility value gains `replay=on|off`.
- Diagnostics: `mind.replayed` with `steps`, `durationMilliseconds`, `finished` (bool), and
  `nodes` at the end.

## Diagnostics and privacy

- New events: `mind.lensChanged`, `mind.replayed`, and `mind.entryOpened` (no fields).
- `mind.filtersChanged` gains `entries` and `regions` (bools).
- `graph.rendered` gains `entryNodes` (int), `lens` (the raw value, a fixed vocabulary), and
  `replay` (bool).
- `mind.replayed` has `steps`, `durationMilliseconds`, `stepP95Milliseconds`, `finished`, and
  `nodes`.
- `DiagnosticsPrivacyTests` extends the Mind case. It builds a snapshot, a mood lens, the entry
  nodes, and the regions, runs a replay player, and records each event, with the sentinel as
  every entity name, alias, entry title, entry text, and area display name. It asserts the
  sentinel never reaches the log.

## Tests

Unit (Swift Testing, `iPhone 17 graph-unit`):

- **`MindMapTests`** (pure snapshots):
  - `asOf` drops later links from counts, minimum, and radius, and removes a node whose mentions
    are all later (replacing the quirk test)
  - kinds still filter standalone nodes
  - entry nodes: only entries linked to on-map entities, the newest 200 kept, edges only to
    on-map entities, `asOf` respected
  - `recentMentions` window edges: exactly 30 days is in, 31 is out
  - a future-dated entry isn't in the snapshot's links
- **`MindMapTests`** (in-memory store): `mapSnapshot` resolves a merged loser's links to the
  winner and skips hidden entities. It's built once per revision (`snapshotBuildCount`) and again
  after a revision bump. `moodsEdited()` bumps the revision, and the mood lens then reads the new
  mood.
- **`EntityTallyTests`**: the `EntityAreasTests` cases move here. Plus: mood around picks the
  mode, a tie goes to the most recent, entries without a mood are skipped, and an entity with no
  moods has none.
- **`GraphSimulationTests`**:
  - the region force brings a node closer to its point than the same run without regions
  - two identical runs with regions end in identical positions
  - `update` keeps a surviving node's region and gives a new node its point
  - an update with equal regions doesn't reheat, and one that changes only regions does
  - a replay-like update with the same node set and new weights reheats only for resizing
  - a pinned node ignores its region
  - `setRegions([:])` clears them
  - entry nodes have the fixed radius
  - the anchor tests are deleted
- **`GraphCanvasModelTests`**:
  - paint slots and faded nodes land in the plan
  - the plan recomputes on a paint change and not on an identical paint
  - recency glow is capped at 25 and gives way to focus glow
  - entry nodes are never labelled or glowing, and their edges use the faint bucket
  - focus lights entry neighbours
  - hit-testing prefers an entity over an overlapping entry, and an entry is hit only within 8 pt
  - an edge hit on an entry edge returns the entity end
  - `fly(to:zoom:)` keeps the zoom
- **`MindRegionsTests`**: the points are deterministic and distinct, don't depend on which areas
  have entities, and spread out as the entity count grows. A hidden area has no point.
- **`MindReplayTests`**:
  - `asOf` is linear and clamped, and `isFinished` is right
  - no links disables replay
  - a player over 100 steps calls `fetch` exactly once, and every frame gets the same snapshot
  - `stop` drops the snapshot, and a new `start` fetches again
  - `refetch` fetches once more and keeps the elapsed time
- **`MindFiltersTests`**: the new toggles default off.
- **`DiagnosticsPrivacyTests`**: as above.

UI (`iPhone 17 phase-a-ai`, stub AI), in `GraphUITests`:

- **`testMindLensesEntriesAndRegions`**:
  1. Finish the Sarah entry, open Mind, and pick Mood around. The canvas reports `lens=mood`
     and the legend shows.
  2. Pick Recent, then Kinds.
  3. In filters, turn on Entries (the canvas reports `entries=1`, still `nodes=3`) and Group by
     life area. The canvas stays.
  4. Tap the entry dot at the point the canvas reports, `canvas.coordinate(withNormalizedOffset:)`.
     The Journal tab opens the entry for reading.
- **`testMindReplayRunsAndEnds`**: tap play. The canvas reports `replay=on` and then `replay=off`
  within 20 s, with the node count back to where it was.
- **Finding the entry dot.** Under `-uiTesting` only, the canvas adds `entryDot=<x>,<y>` to its
  accessibility value: the newest entry node's normalized screen position, written when the
  layout settles. The tap then goes through the real hit rule. If this proves flaky, the tap step
  is dropped, and the unit tests on the hit rule and the router cover it.
- **`GraphScreenshotTests.testDemoJournalMind`** adds a screenshot for each lens, one with
  entries, one with regions, and one mid-replay.
- **Phase-scoped run**: `GraphUITests`, `GraphScreenshotTests`, and `ReadModeUITests` (the entry
  jump lands in read mode).

Device (ask before deploying), with `-seedDemoJournal 300`:

- replay start to finish, and a stop partway through
- each lens
- entries on, and tap a dot
- regions settling into a readable layout, with a tile fly-to
- `graph.rendered` p95 for:
  - the default map
  - entries on
  - regions on
  - a replay

The gate is the same as A3's: p95 under 20 ms at 60 Hz.

## Units and commits

1. `MindMapSnapshot`, `MindMap`, and `EntityTally`, with `globalGraph` and `primaryAreas` as
   wrappers. `MindView.refresh` uses the snapshot. Unit tests.
2. Lenses: `GraphPaint`, the plan and draw changes, the lens menu, and the legend.
3. Entries as nodes: the `Node` flag, radius, hit priority, plan rules, the filter toggle, and
   the router jump.
4. Regions: the force, `MindRegions`, the toggle, region labels, and the tile fly-to. The anchor
   code is deleted.
5. Replay: `MindReplay`, the player, the top bar UI, and the canvas `animating` flag.
6. Diagnostics and the privacy case. The UI tests and screenshots, and the phase-scoped UI run.
7. Sub-agent review of the A5b diff, with fixes in separate commits. The device step, the review
   log, and ticking the plan.

For each unit: build, run the unit suite, commit, push.

## Not in scope

- a time scrubber beyond play and stop
- replay speed or loop options
- saving the lens, filters, or regions across launches
- per-entry mood colours on entry dots
- labels for entry dots
- regions for entities with no area
- A3b's performance steps, and 120 Hz
- CLAUDE.md's Graph section (A9)

## Review fixes (sub-agent review of this spec, verdict "approve with fixes", 16 findings)

Folded in above:

1. **Region points moved on every replay step and every Entries toggle.**
   - Fixed spots for every visible area, sized by the snapshot's entity count.
   - Regions come in through `update`, and an equal map is a no-op.
2. **The entries cost estimate was wrong.** The cap is now 100, with a fallback of 50, and there's
   no repulsion between two entry nodes.
3. **The UI test expected an unchanged node count.** `nodes=` now counts entities only.
4. **An invisible overlay button can't test the canvas tap.** The canvas reports the dot's point,
   and the test taps that coordinate.
5. **Entry dots would have taken the Other colour under the Kind lens.** `draw` now checks
   `isEntry` first. `makePlan`, the edge hit, and the drag and long-press gestures now handle
   entry nodes.
6. **A mood edit didn't bump the revision.** `graph.moodsEdited()` now bumps it, and the spec
   notes that mood maps through `.category`.
7. **Replay steps re-rendered all of Mind.** Names are written only when they change, the
   replay controls are their own view, and `stepP95Milliseconds` is logged.
8. **Replay might never be sampled.** `animating` feeds the redraw rule, wakes the canvas, and
   starts a fresh sample, and `graph.rendered` gains `replay`.
9. **Races while replaying.** A push or leaving the tab ends a replay, a revision change fetches
   again, and a jump stops, refreshes, then focuses.
10. **A replay loses the layout.** Stated and accepted.
11. **The paint was compared every frame.** The cache now keys on `paint.generation`.
12. **Signatures.** The spec now gives `EntityTally`'s generic shape, and a replay starts at the
    earliest link dated on or before now.
13. **Tile fly-to edge cases.** Only on-map ids count, and there's no fly with none or with a
    focus.
14. **Missing tests.** Added for equal regions, resize-only reheat, future-dated entries, the
    mood edit, and refetch.
15. **Deleting the anchor code.** Agreed. The stale comments and the plan's wording get updated
    too.
16. **Privacy.** The review found no problems.
