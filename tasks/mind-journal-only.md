# Mind: journal entries only, tags as pins

Owner, 2026-09-23: the map shows journal entries only. Notes and creative pieces put nothing on
it, and an entry switched away from journal takes every trace off: its names, tags, edges, its
share of a name's size and area, any halo. Switching back brings them back. Tags draw as small
filled pins instead of hollow rings, since a tag carries less weight than a name.

## Base

The Mind overhaul (PR #55, with the rings, `MindStats`, and the snapshot's `entryDates`) merged to
main at `60270e9`. New branch `feature/mind-journal-only` from `origin/main`, in its own worktree
`.claude/worktrees/mind-journal-only`. Draft PR targets main.

## Phase 1: the snapshot reads journal entries only

`Mindlore/Graph/GraphServices.swift`, `buildSnapshot` (~364-410):

- Filter `fetched` in memory to `entry.kind == .journal` right after the fetch. The existing
  `guard let entry = entries[entryID]` in the `inputs` map already drops every link whose entry is
  missing, so links, parts, areas, moods, halos, bloom, replay, and `MindMap.primaryAreas` all
  follow with no other change. (`kind` is computed, so no `#Predicate`; the fetch is already
  bounded by `entryIDs`.)
- `entryDates` (the "of your last M entries" denominator `MindStats` measures shares against):
  journal entries only, so a week of grocery lists doesn't dilute a name's share.
  Predicate `!$0.isDraft && !$0.isNote && !$0.isCreative` (both stored `Bool = false`).
- `entities` (browsable): only roots that have at least one input link, plus the author's
  entity whatever its links. Today it holds every browsable entity, which feeds
  `MindMap.minimumMentions(browsableCount:)` (`MindMap.swift:58`, read at `MindView.swift:352`)
  and the empty state's `browsableCount` (`MindView.swift:164-192`); a journal of only notes
  would otherwise show "Nothing matches" instead of the empty journal state. The author stays in
  because `MindStats.authorIDs` (`MindStats.swift:179-184`) finds the author by scanning
  `entities`; without it an author first named in a note would show as New in the drawer. Nodes are already built only from link counts, so nothing drawn changes.
  Check before changing: every reader of `snapshot.entities` (namer, crumbs, drawer rows, search
  on the map) must cope with an entity it can't find; `MindView.focus` already fills a missing
  name from `EntityDirectory`.

Revision: `setKind(_ kind: EntryKind…)` already bumps `revision` unconditionally, so the cached
snapshot rebuilds on a kind change; the AI setting a kind bumps it through `insightsWritten`.
Nothing new needed.

`Mindlore/Views/Capture/KeepSnapshot.swift` / `KeepCard.swift`: after a note or creative entry,
the Keep card must not say "N names on your mind map" or offer Show in Mind for a name that isn't
on it. `KeepSnapshot.make` fetches no `Entry` today; add one fetch of the linked entries' kinds,
count `namesOnTheMap` over journal entries' links only, and show the map line only when this
entry is journal. The card refreshes on `graph.revision`, so a recording the AI files as a note
drops the line once insights land (a brief flash first is acceptable).

Peek card: `EntityPeekCard.swift:130` says "Not on the map in this stretch", which is false for a
name only in notes (no window will show it). The snapshot knows the difference (no journal link
at all vs. none in the window), so pass a reason and say "Only in notes, so not on the map" for
that case.

Comments: `EntryKind.swift` (header, the `keeps*` comment), `Entry.swift` near `isNote`,
`EntryKindTests.swift:56` ("a note's names reach the map").

### Tests (MindMapSnapshotTests, store-backed, `GraphHarness`)

- A note and a creative entry naming the same people as a journal entry: the snapshot's links
  and entries hold only the journal entry; an entity named only in the note is not in `entities`.
- A shared name's count (node size) and primary area come from its journal entries only.
- Switching kind through `graph.setKind(_:on:in:)`: journal to note removes the entry's links,
  entry, and names from the next `mapSnapshot`; note to journal brings them back (links survive a
  switch to note, since notes keep mentions); journal to creative removes them and a switch back
  leaves them off until insights rerun (mentions were cleared), tags back at once. Also proves the
  cache invalidates (compare `snapshotBuildCount`).
- `entryDates` excludes notes and creative entries.
- `MindStats` share over a journal with notes in it measures against journal entries only.
- The author named first in a note, later in a journal entry, is not reported as New.
- The peek reason: a note-only name gets the notes wording, a name outside the window keeps
  "in this stretch".
- Keep: a note's snapshot has `namesOnTheMap == 0` / no map line.

## Phase 2: tags as small filled pins

- `GraphSimulation.radius(for:)`: a tag gets `tagRadius`, 3pt fixed (a name starts at 5pt and
  grows to 16), so a tag reads as a pin at any mention count. Collision and label offset already
  read the per-node radius. The tap target already has a minimum (`GraphHitTest.minimumNodeRadius
  = 12`, `GraphCanvasModel.swift:243,274`), so small pins stay tappable.
- The focus stroke (`GraphCanvasView.swift:312`) is a fixed 2.5pt line on the node's own circle,
  which on a 3pt pin is a blob. Draw it around the node with a gap: circle radius
  `max(r * 1.4, r + 3)` and 1.5pt for a tag.
- `GraphCanvasView` node loop: drop the ring bucket and the stroke branch; tags fill like
  everything else. Keep the lighter tag label (`ringLabelOpacity` becomes `tagLabelOpacity`).
- `GraphDrawPlan.ringNodes` becomes `tagNodes` (it still drives the label opacity). Drop
  `ringWidth`.
- The canvas accessibility value says `rings=`; rename to `tags=` and update
  `GraphUITests.swift:224`.
- Comments: `MindView.swift:5` ("a tag is a ring"), `GraphCanvasModel.swift:127`, the canvas
  comments.

### Tests

- `GraphSimulationTests`: a tag's radius is `tagRadius` at 1 and at 80 mentions and is smaller
  than any name's.
- `GraphCanvasModelTests.swift:103`: `tagNodes` holds the tag.
- UI: run only `GraphUITests` (the phase's own UI tests).

## Phase 3: docs, review, phone

- CLAUDE.md: Mind is "a map of every browsable entity a journal entry names"; Entry kinds says a
  note keeps its names for search, entity pages, and Ask but not the map, and creative puts
  nothing on it; the Life areas line that says "the entries it appears in" reads "the
  journal entries" (the Life areas line, CLAUDE.md ~447). `tasks/mind-overhaul-spec.md`: the ring line (81, 175) becomes pins, plus a
  line for journal-only.
- Code review by a Sonnet sub-agent over the whole diff, read-only tools, tree baselined first.
- Phone: deploy with `-seedStoryJournal` (it seeds no notes or creative pieces), switch one entry
  with a distinctive name to a note by hand, screenshot the map before, after, and after
  switching it back, and confirm tags draw as pins.

## Not in scope

- The entity page, search panel, directory rows, Today, merge suggestions, and Ask keep counting
  every kind. A name's page is about the name, and a meeting note about Sarah belongs there.
  (`Entity.linkCount`, `mentionedWith`.) If the owner wants "Mentioned with" journal-only too,
  it's a one-line filter in `mentionedWith`, done separately.
- A Creative or Notes view of the map (owner: not planned).
- Rewriting stored links on a kind change: the filter is at read time; nothing stored changes.
- Which labels tags get (tags still compete for label slots).
