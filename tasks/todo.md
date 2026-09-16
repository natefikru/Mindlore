# Mindlore: the knowledge graph

Branch: `feature/knowledge-graph` from `main` at `0678525` (after PR #2 merged the AI layer). The AI
layer this builds on is archived in `tasks/archive/ai-providers.md`; the product vision is
`docs/mindlore-build-plan.md` Phase 2.

Status: revision 2, awaiting owner approval. Revision 2 folds in the sub-agent review of revision 1
(17 findings, all addressed; see "Review log"). Nothing below is implemented.

## Goal

Every entry already carries AI-extracted tags, themes, moods, and mentions of people, places,
organizations, projects, and events. Today those are strings on one entry: "Sarah" in Monday's entry
and "Sarah" in Friday's are two unrelated values. This PR turns them into a graph the user can browse,
correct, and look at.

1. Entities. One record per person, place, organization, project, event, tag, and theme, with a
   canonical name, aliases, and a bio: drafted by AI the first time the user opens the entity,
   theirs the moment they edit it.
2. Resolution. Tags, themes, and mentions are matched to entities when insights land, exact matches
   automatically, near matches as suggestions the user confirms. "Mom" becomes a person because the
   user says so, once, and it stays resolved forever after.
3. Correction. Rename, merge, unmerge, hide, re-point a single mention, add an alias. Every automatic
   decision is reversible and none is silent.
4. Feedback. Known names and themes go into the insights prompt so the model reuses them instead of
   inventing near-duplicates.
5. Views. A Connections screen listing entities by kind, an entity page (the "person page" journalers
   build by hand in Obsidian), tappable chips on every insights card, and a force-directed graph:
   local around one entity, or global with filters and a time scrubber.

Moods stay attributes on the entry, not nodes; they colour and filter the graph. Open threads stay
per-entry text; a resolvable OpenThread model is next-PR work.

## How it fits the existing models

Entities are not a new source of data. They are an index over what `EntryInsights` already stores:

- **Input.** `EntryInsights.tags`, `EntryInsights.themes`, and the mentions in
  `EntryInsights.mentionsData` are the only things that create entities and links. When an insights
  run finishes, the indexer reads those three fields off that entry's insights and writes one
  `EntityLink` per value: `entry` is this entry, `entity` is the matched or newly created `Entity`,
  `surface` is the string exactly as the AI wrote it. Every link traces back to one value in one
  entry's insights.
- **Existing entries.** On the first launch after the update, every entry that has insights has a
  nil `graphIndexedAt`, so the launch sweep indexes all of them in one pass. That sweep is the
  backfill; there is no separate import. The journal comes out with its people, places, tags, and
  themes as entities and every entry linked.
- **Staying in sync.** Run AI again and the insights are regenerated, the stamp no longer matches,
  and the entry is re-indexed from the new values. Delete insights and the entry's AI links go with
  them. Delete an entry and its links cascade away.
- **Unchanged.** `EntryInsights` keeps its raw strings and the insights view keeps reading them.
  The graph is a layer over the insights, not a replacement. The one feedback path is the prompt:
  known names and themes go into the next insights request so the model reuses them.

## Owner decisions (2026-09-15)

- The graph is the product. Insights over the stored data are what makes the app worth using.
- Obsidian Dataview is inspiration for the metadata layer, Obsidian's graph view for the picture.
  Neither is copied.
- Themes, people, tags, keywords, and organizations all belong in the graph. Keywords are covered by
  tags plus mentions of kind `other`.
- Entity creation must be as simple as possible. Entities are created with nothing to confirm; bios
  are drafted by AI when the user first looks at an entity, and the user edits from there. Same
  rule as titles: AI writes only while the bio is empty or still AI-written.

## Research summary

Three sub-agent reports on 2026-09-15 (codebase, Dataview, Obsidian graph plus entity resolution).
What shaped the plan:

- **Obsidian's edges are derived, not stored.** Two notes are linked because a note links both. The
  graph view runs d3-force on PixiJS, sizes nodes by inbound links, colours by search-query groups,
  and offers a local graph with a depth slider. Users say the global graph is a hairball past 200
  nodes and what they keep using is the local graph at depth 1 or 2, colour groups, orphan finding,
  and the time-lapse. Rule from the hairball literature: never put the whole graph in the UI; start
  from the question the user has.
- **Dataview's lesson is the index, not the language.** Journalers build the same handful of
  dashboards (person page, on this day, mood over time, open tasks, tag counts). Obsidian's own
  first-party answer, Bases, dropped the query language and kept typed fields with editable views.
  Two model rules follow: entities are rows with identity so "everything about Sarah" is a
  relationship traversal, not a text search; and an absent field must drop out of a view, never sort
  first.
- **Entity resolution** is blocking, pairwise scoring, then clustering. For a single user with a
  confirmation UI, auto-link only exact matches, never merge across a chain (one bad link merges
  three real people), and surface the middle band as pairs. Wikidata's merge model: the loser becomes
  a redirect and keeps its history, so undo is clearing one pointer. Kinship words ("Mom", "my boss")
  are roles, not names; they become aliases only when the user binds them.
- **No shipping journal app does this.** Apple Journal takes people from Contacts and Photos, Day One
  has no people feature, Reflect adds backlinks with AI but has no merge. Open ground.
- **Rendering.** Grape is the only force-directed SwiftUI package; it has an open "Canvas never
  redraws on the 26 SDKs" report and an unmerged fix for an iOS 27 SDK compile break, with the
  maintainer silent since May 2025. Swift Charts has no network mark. Recommendation: about 300 lines
  of hand-rolled `Canvas` plus `TimelineView` with d3's force constants, O(n^2) is fine under 500
  nodes, stop the timeline when alpha settles, resolve labels once.
- **NaturalLanguage on iOS 26.** `NLTagger.nameType` misses lowercase names, which is what dictation
  produces; `NLEmbedding` sentence vectors cluster relevant and irrelevant text alike. Neither earns a
  place in this PR. `NLGazetteer` over confirmed names is the useful follow-up once entities exist.
- **SwiftData limits that decide the model.** No GROUP BY (aggregate in memory), `[String]`
  attributes are blobs (never in a `#Predicate`), optional to-many relationships crash in most
  predicate forms, so every query runs from the link side or in memory. Denormalized counters on the
  entity are the only way to sort by count.

## Key decisions

### Data model

**Two models, one edge type.** `Entity` is a node of any kind. `EntityLink` is the only stored edge:
an entry mentions an entity. Entity-to-entity edges are computed from co-occurrence at view time and
never stored, so they cannot go stale, which is the failure mode build plan section 4.4 warns about.
At journal scale (thousands of links, hundreds of entities) the computation is milliseconds.

**Tags and themes are entities too.** One node type keeps the graph uniform, lets a person and a theme
share an edge ("Sarah" with "career anxiety" is the most interesting edge in the graph), and gives
every kind the same page, merge, and rename. Kind-specific rules live in the resolver, not the model.
Moods are not nodes: they are a closed vocabulary already on `EntryInsights`, and as an attribute they
colour and filter the graph.

**Every rule from `CloudKitSchemaRulesTests` holds.** Every property optional or defaulted, no unique
attributes, every relationship optional with an inverse. The self-reference for merges is a
`mergedIntoID: UUID?`, not a relationship, so `#Predicate { $0.mergedIntoID == nil }` selects live
entities without relationship gymnastics.

**Links move on merge; undo moves them back; chains are flattened, never followed.** Merging B into
A re-points B's links to A, sets `originalEntityID` on each moved link only if it is still nil (so a
link remembers where it was born, not its last stop), records on B exactly which aliases A did not
already have (`contributedAliases`), unions B's name and aliases into A's aliases, and sets
`B.mergedIntoID = A.id` with `mergedAt`. B stays in the store and leaves every list through
`isBrowsable` (`!hidden && !isMerged`); merging never writes `hidden`, or unmerge could not tell a
loser the user had hidden beforehand from one it had not. When A is later
merged into C, every entity whose `mergedIntoID == A.id` is rewritten to C, so `mergedIntoID` is
always one hop from a live root and unmerge of X restores exactly the links with
`originalEntityID == X.id` and removes exactly X's `contributedAliases`. Merge refuses self-merge,
and merging into an entity that is itself merged redirects to its root. Merge is allowed across
kinds (a tag and a theme with the same words, a mention typed `other` and a person); the winner's
kind stands.

**Denormalized counters, one recount function, run only at the end.** `linkCount`, `firstLinkedAt`,
`lastLinkedAt` (by the entry's `entryDate`, not the link's creation) let the Connections list sort
by count or recency with a `SortDescriptor`. `GraphIndexer.recount(in:)` recomputes them all from
the links in one pass, deletes any link whose entity or entry is nil, and is the only writer. It
runs at the end of `index` and `sweep` (never between removing and re-adding an entry's links, which
would prune and recreate an entity under a new ID), after merge, unmerge, hide, delete, and entry
date changes. Scattered increments are how counters drift.

**Unconfirmed orphans are pruned; confirmed and merged ones stay.** After a recount, an entity with
zero links that the user never touched (no rename, alias, bio, merge, or hide) and that is not a
merge loser (`mergedIntoID == nil`) is deleted. Anything the user touched (`confirmedByUser`)
survives with zero links, the way an Obsidian note with no links still exists, and merge losers
survive because they are the undo.

**The graph never stamps an entry.** `ModelContext+Stamping.swift:9-13` marks `updatedAt` on every
`Entry` in the changed set, and inserting or deleting an `EntityLink` whose `entry` is set, or writing
`graphIndexedAt`, puts the entry in that set. The archived rule is that `updatedAt` follows content,
not insights. So `GraphIndexer` saves its own work through `saveStampingEntries(at:except:)` with
every touched entry's `persistentModelID` in `except`, before control returns to any path that
flushes. Inside the insights coordinator the indexer runs before the coordinator's own save
(`InsightsCoordinator.swift:207`), which already excludes the entry. A test sweeps N entries and
asserts every `updatedAt` is unchanged.

**Cascade goes one way.** `Entry.entityLinks` cascades: deleting an entry deletes its links.
`Entity.links` nullifies: nothing in this PR deletes a linked entity, and a cascade there would
silently delete links out of entries (and stamp them). Recount deletes nullified links.

### Resolution

**Normalize once, store both forms.** `EntityNormalizer.key(for:kind:)` folds case, diacritics, and
width, collapses whitespace, strips trailing possessives (`Sarah's`, `James'`), leading honorifics
(Dr, Mr, Ms, Mrs, Prof, Aunt, Uncle), and surrounding punctuation. The surface form stays on the
link and the display name stays what the user chose; only keys are compared.

**The automatic band is narrow.** In order, for each extracted value:
1. Exact key match against the name or an alias of a live, same-kind entity (or kind `other`, which
   is upgraded to the mention's kind if `kindEditedByUser` is false; `confirmedByUser` is too
   coarse, since writing a bio would otherwise freeze the kind): link. Hidden entities count
   here, so a hidden thing stays hidden instead of coming back under a new ID. If several live
   entities match exactly (possible after a user rename or alias collided; see below), prefer the
   confirmed one, then the highest `linkCount`, and record `graph.ambiguous`.
2. Person only: a single-token name that equals the first token of the name or an alias of exactly
   one live, unhidden person entity with a multi-token name: link, marked `inferred`. Hidden
   entities are excluded here, or a bare "Sarah" would vanish into a hidden "Sarah Kim" with nothing
   to show for it. Two or more candidates: no link, new entity.
3. Otherwise: create a new entity of that kind and link it.
Nothing else is automatic. A mention matching an entity of a different kind ("Paris" the place and
"Paris" the person) creates a second entity; the suggestion list is where they meet if that was wrong.

**Collisions are caught at the edit, not the read.** Renaming an entity or adding an alias whose key
equals another live entity's name or alias offers to merge the two instead, and the edit does not
go through until the user picks. The resolver tie-break above is the safety net, not the design.

**Suggestions are computed, not stored.** `EntityMatcher.suggestions(among:)` scores every pair of
live, unhidden entities of the same kind (or one of kind `other`) with the greater of Jaro-Winkler
on the keys and 0.9 when one key's tokens are a subset of the other's, keeps pairs at 0.88 or above,
drops pairs either side has marked "not the same" (`notSameAs: [UUID]` on both), and ranks by score
times the smaller link count. A tag and a theme with identical keys are suggested at score 1.0
(fuzzy tag-to-theme pairs are not). Hundreds of entities is tens of thousands of comparisons,
milliseconds, so the Review section is always current and there is no suggestion table to keep
consistent.

**Indexing is idempotent and keyed by insight time.** `Entry.graphIndexedAt` stores the exact
`insights.generatedAt` it indexed, and any inequality means stale (a clock that steps back cannot
fool it). Indexing an entry deletes its AI-sourced links and saves (SwiftData keeps deleted objects
in `entityLinks` until the save, and the resolver must not see them), then resolves every tag,
theme, and mention, skipping any value whose key and kind already has a user-sourced link on that
entry (so a re-pointed "Sarah" is not joined by a second, AI "Sarah"), then stamps the date. User
links whose surface no longer appears in the regenerated insights are kept; the entity page shows
the surface text, so nothing is hidden. `Entry+Editing.removeInsights()` is the one function that
deletes insights, removes the AI links, and clears the stamp; the view's "Delete insights" and
`restartPages` (`Entry+Pages.swift:155-157`) both call it. The launch sweep is the backfill: on
first launch after the update every entry with insights has a nil stamp and gets indexed in one
pass with one `graph.sweep` event. No separate migration step.

**Hidden entities keep resolving.** "Hide" on an entity ("Monday" tagged as an event, a tag the user
never wants to see) sets `hidden`; the resolver still links to it so the next run does not recreate
it, and every list, chip, and graph skips it. Hiding is undone from the Hidden section.

**Re-pointing one mention is the Limitless pattern.** On a chip or an entity page row: "This is
someone else" picks or creates the entity for that one link (source becomes `user`, so reindexing
keeps it) and asks whether to also add the surface form as an alias, which fixes every future
mention. One link or all of them; the user chooses.

### Feedback into the AI pass

**Known names go into the prompt.** `InsightsPromptBuilder` already sends the 50 most-used tags.
This adds the 50 most-linked themes ("Themes already used in this journal; reuse one when it fits")
and the 50 most-linked people, places, organizations, projects, and events with their kind ("Named
things already in this journal; use these exact names when the entry refers to them"). Hidden
entities are excluded. `WhatWasSentView` lists both. The names came from the provider in the first
place, so this is not a new disclosure category, but bios never go: sending the user's own words
about a person is a different decision and is left for the context-injection work in the next PR.

### Views

**Connections is the index page.** A toolbar button on the list opens a screen with a search field,
a kind picker (All, People, Places, Organizations, Projects, Events, Tags, Themes), a Review row
when suggestions exist ("3 possible duplicates"), and entities sorted by recent or by count. A Hidden
section at the bottom. The graph opens from the toolbar.

**The entity page is the person page.** Name (editable), kind (picker), aliases (chips, add and
remove), the bio, first and last mentioned, count.

**Bios are drafted lazily, owned by the user.** Opening an entity page whose bio is empty, with AI
on and a key present, drafts one: `EntityBioDrafter` gathers the sentences containing the surface
text from the eight most recent linked entries (capped at 1,500 characters), sends the build plan
4.2 prompt ("Based only on how X was described in these entries, draft one neutral sentence. Do not
speculate beyond what was said. If there is not enough information, say so."), and stores the
result with `bioWasGenerated = true`. The page labels it "Drafted by AI" until the user edits it,
which clears the flag; from then on AI never writes it, exactly the title rule. There is no approve
step: the label is the approval state. A "Draft again" action exists only while the bio is still
AI-written. Drafting is on demand, not queued, so it costs nothing for entities never opened and
never nags; a failure shows inline and the page stays usable. The excerpts sent are from entries
the provider already received in full for insights, so this is not a new disclosure category, and
the page's "What was sent" lists the entry count and characters. The bio itself never leaves the
device. Connected: the top co-occurring
entities with a "Show graph" button. Entries: every linked entry by entry date, newest first, with
the surface text as written. Merge into (search, suggestions first), Hide, and, for entities merged
into this one, "Also known as B, merged on date, Undo".

**Chips are links.** Tags, themes, and mentions on the insights cards resolve through the entry's
links and push the entity page inside the sheet's `NavigationStack`. A value with no link (insights
newer than the last index, which cannot happen after Phase 2 but is handled) shows as plain text.

**The graph starts local.** From an entity page, depth 1 (neighbours) or 2, edges weighted by
co-occurrence with a 90-day half-life, node size by link count, colour by kind, the centre pinned.
The global graph, from Connections, adds kind toggles, a minimum-count slider (default 2, which is
what keeps it from being a hairball), and a time scrubber that shows the graph as of a date, the
journal's version of Obsidian's time-lapse. Tap opens the entity page, drag pins a node, pinch zooms.
Labels draw for the largest nodes and on tap, so 300 nodes stay readable.

**Hand-rolled simulation.** `GraphSimulation` is a `nonisolated final class` over `SIMD2<Double>`
arrays with d3's constants (alphaMin 0.001, alphaDecay 1 minus 0.001^(1/300), velocityDecay 0.6):
centre, many-body repulsion, link springs, collision. It is deliberately not `@Observable`, so
ticking it inside the draw closure never trips "modifying state during view update".
`GraphCanvasView` draws links as one `Path` and nodes as circles inside
`TimelineView(.animation(paused: settled))`, with labels supplied through `Canvas(symbols:)` and
`resolveSymbol(id:)` (there is no once-only `Text` resolution; symbols are the supported way), and
pauses the timeline when alpha reaches its floor so the phone does not heat up drawing a still
picture. No dependency.

**Pure types are `nonisolated`.** `EntityNormalizer`, `EntityMatcher`, `EntityGraph`, and
`GraphSimulation` carry no model references and are declared `nonisolated` like `TextHash` and
`Mention`, so their table tests run without `@MainActor` and the simulation can move off the main
actor later. `GraphIndexer` and `Entity+Editing` touch `@Model` types, are main-actor, and take an
injected `DiagnosticsLog` so the privacy tests can see their events (`.shared` is disabled under
XCTest).

### Diagnostics and privacy

Events carry IDs and counts, never names, aliases, bios, or surface text: `graph.indexed` (id, links,
created), `graph.sweep` (entries, links, entities, duration), `graph.merged` (winner, loser, links),
`graph.unmerged`, `graph.entityEdited` (id, field), `graph.hidden`, `graph.repointed`,
`graph.suggestionDismissed`, `graph.rendered` (nodes, edges, ms). `DiagnosticsPrivacyTests` gets the
sentinel as an entity name, alias, bio, surface text, and inside a merge.

## Data model changes

```swift
@Model final class Entity {
    var id: UUID = UUID()
    var name: String = ""                 // display form, user's casing wins
    var key: String = ""                  // EntityNormalizer.key(for: name)
    var kindRaw: String = EntityKind.other.rawValue
    var aliases: [String] = []            // surface forms; keys computed in memory
    var bio: String?
    var bioWasGenerated: Bool = false
    var kindEditedByUser: Bool = false    // an untouched kind can still be upgraded     // AI may rewrite only while true; a user edit clears it
    var confirmedByUser: Bool = false     // any manual edit, merge, hide, or alias
    var hidden: Bool = false
    var mergedIntoID: UUID?               // always one hop from a live root
    var mergedAt: Date?
    var contributedAliases: [String] = [] // what this loser added to the winner, for unmerge
    var notSameAs: [UUID] = []            // dismissed suggestion partners
    var linkCount: Int = 0
    var firstLinkedAt: Date?
    var lastLinkedAt: Date?
    var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify, inverse: \EntityLink.entity) var links: [EntityLink]? = []
}

nonisolated enum EntityKind: String, CaseIterable, Codable, Sendable {
    case person, place, organization, project, event, other, tag, theme
}

@Model final class EntityLink {
    var entity: Entity?
    var entry: Entry?
    var surface: String = ""              // the value as extracted
    var kindRaw: String = EntityKind.other.rawValue
    var sourceRaw: String = EntityLinkSource.ai.rawValue   // ai | user
    var inferred: Bool = false            // linked by the first-name rule, not an exact match
    var originalEntityID: UUID?           // set by the first merge that moved this link, never overwritten
}

// Three ways a link changes hands, so a merge and a user re-point can never be confused:
// moveForMerge(to:) records the birthplace once, restore(to:) is unmerge, repoint(to:) is
// the user and clears the birthplace because it is a new birth.

// Entry gains:
@Relationship(deleteRule: .cascade, inverse: \EntityLink.entry) var entityLinks: [EntityLink]? = []
var graphIndexedAt: Date?                 // the exact insights.generatedAt that was indexed
```

`ModelContainerFactory.schema` grows to five models. `MentionKind` (`Mood.swift:109`) stays as the
per-insight type; `EntityKind` is a superset and `EntityKind(mention:)` maps one to the other.
Lightweight migration only: two new models, one new relationship and one optional date on `Entry`.
`SchemaMigrationTests` asserts the V1 fixture opens with `entityLinks` empty and `graphIndexedAt`
nil on every entry.

## Phases

Each phase is a commit or small series; unit tests pass before commit
(`-only-testing:MindloreTests`); push before the next. Draft PR against `main` after Phase 1.
Diagnostics events land with
the behaviour that produces them. Phases 6 and 7 (the graph picture, including the time scrubber
and node pinning) are the planned split point for a stacked PR if review of the first five gets
long.

### Phase 1: Models
- [ ] `Mindlore/Models/Entity.swift`, `EntityLink.swift`, `EntityKind` with `symbol` and `heading`
      (extend the per-kind table in `Views/Insights/InsightCards.swift:19-41`).
- [ ] `Entry.swift:53-56`: `entityLinks` relationship and `graphIndexedAt`.
- [ ] `ModelContainerFactory.swift:25`: schema.
- [ ] Tests: `CloudKitSchemaRulesTests.appSchemaFollowsCloudKitRules` (`:43`) passes with the new
      models; `SchemaMigrationTests` per-entry loop (`:54-64`) asserts the new fields;
      `MoodTests.moodRawValuesArePinned` (`InsightsTests.swift:6-20`) gains `EntityKind` and
      `EntityLinkSource`.

### Phase 2: Normalizer, resolver, indexer
- [ ] `Mindlore/Graph/EntityNormalizer.swift`: `key(for:kind:)`, `tokens(of:)`, honorific and
      possessive tables. Table-driven tests: `"Sarah's"`, `"Dr. Kim"`, `"NĚMEČEK"`, `"  new   york "`,
      `"James'"`, `"Aunt May"`, tag and theme forms.
- [ ] `Mindlore/Graph/EntityResolver.swift`: the three-step rule over an in-memory snapshot of live
      entities (fetched once per index call). Returns link decisions; does not write.
- [ ] `Mindlore/Graph/GraphIndexer.swift` (main actor, owns writes, injected `DiagnosticsLog`):
      `index(entry, context)`, `sweep(context)`, `recount(context)` with orphan pruning and
      nullified-link cleanup, `removeAILinks(for:)` which saves before returning. Every save goes
      through `saveStampingEntries(at:except:)` with the touched entries excluded.
- [ ] `Entry+Editing.removeInsights()`; call it from `EntryInsightsView` "Delete insights" and from
      `restartPages` (`Entry+Pages.swift:155-157`).
- [ ] Hooks: `InsightsCoordinator.init` takes an `onInsightsWritten: (Entry, ModelContext) -> Void`
      (the `InsightsHarness` passes a no-op or a spy), called before the save at `:207`;
      `RootView` third `.task` lane (`:89-95`) runs `sweep` before the title and insights queues so
      the first request after the upgrade already carries known names; `EntryDateSheet` dismiss
      (`:30,49`) and the two coordinator date paths (`InsightsCoordinator.swift:192`,
      `PageTranscriptionCoordinator.swift:209`) call `recount`; `EntryListView` delete path flushes
      then recounts.
- [ ] Diagnostics events; `AIDiagnosticsPrivacyTests` extended.
- [ ] Tests (`GraphIndexerTests`, `@MainActor`, in-memory container, `FakeTextGenerator` through
      the `InsightsHarness` pattern at `InsightsTests.swift:155-198`): exact match links; alias
      match; first-name rule with one candidate links inferred, with two creates new, and ignores
      hidden candidates; cross-kind creates new; hidden entity is reused by exact match and stays
      hidden; reindex is idempotent, preserves user links, and does not add an AI link beside a
      user link with the same key; reindexing the sole entry for an entity keeps its ID; deleting
      insights removes AI links; deleting an entry prunes an unconfirmed orphan and keeps a confirmed
      one; counters match links after every operation; sweep indexes only entries whose stamp differs
      from `generatedAt`; **a sweep over N entries leaves every `updatedAt` unchanged**; an exact
      tie resolves to the confirmed entity and records `graph.ambiguous`.

### Phase 3: Editing, merge, suggestions
- [ ] `Mindlore/Graph/Entity+Editing.swift`: `rename`, `setKind`, `addAlias`, `removeAlias`,
      `setBio`, `hide`, `unhide`, `merge(into:)`, `unmerge`, `markNotSame(as:)`, `repoint(link:to:)`.
      Every one sets `confirmedByUser` on the entity edited and calls recount. `rename` and
      `addAlias` return a collision (the other entity) instead of applying when the key is taken;
      `merge` refuses self, redirects a merged target to its root, flattens every loser pointing at
      the loser onto the winner, sets `originalEntityID` only where nil, and records
      `contributedAliases`.
- [ ] `Mindlore/Graph/EntityMatcher.swift` (`nonisolated`): Jaro-Winkler, token subset,
      `suggestions(among:)`.
- [ ] Tests: merge moves links and aliases and unmerge restores exactly, including aliases the
      winner already had; B into A then A into C leaves B pointing at C, and unmerging A from C
      restores only A's own links; unmerging B afterwards still works; self-merge and cycle refused;
      the loser survives the recount; the resolver links a mention of a loser's name to the root;
      rename onto an existing key reports the collision; Jaro-Winkler against known values
      (`martha`/`marhta` 0.961); subset pairs suggested, dismissed pairs not, fuzzy cross-kind not,
      identical-key tag and theme suggested at 1.0; ranking.

### Phase 4: Prompt feedback
- [ ] `InsightsPromptBuilder.plan` (`:59-144`): `existingThemes` and `knownEntities` parameters with
      the guidance text above; caps at 50 each.
- [ ] `InsightsCoordinator.topTags` (`:220-228`) replaced by `GraphIndexer.promptContext(in:)`
      reading `Entity` counters instead of scanning every `EntryInsights`.
- [ ] `WhatWasSentView` (`EntryInsightsView.swift:238-278`) lists the counts sent.
- [ ] Tests: prompt contains the names and kinds, excludes hidden and merged entities, caps at 50,
      falls back to the old tag scan when the graph is empty.

### Phase 5a: Entity page, bios, chips
- [ ] `Mindlore/Views/Graph/EntityView.swift`: the page as decided, with `MergeIntoView` (search,
      suggestions first) and the collision-to-merge prompt from rename and alias edits.
- [ ] `Mindlore/Graph/EntityBioDrafter.swift`: excerpt gathering (`nonisolated` sentence finder,
      tested on its own), the request, `draft(entity, context)` guarded by `bio == nil ||
      bioWasGenerated`, `graph.bioDrafted` (id, entries, characters, tokens) and `graph.bioFailed`
      (id, error code). `Entity+Editing.setBio` clears `bioWasGenerated`.
- [ ] Tests: the drafter refuses when the bio is user-written; the excerpt finder returns the
      sentence around each surface form and respects the caps; a `FakeTextGenerator` draft lands
      with the flag set; editing clears the flag; a failure leaves the bio nil; the sentinel never
      reaches the log through a bio or an excerpt.
- [ ] `InsightCards.swift`: `WrappingChips` and `MentionGroups` take an optional tap target;
      `EntryInsightsView` resolves chips through `entry.entityLinks`, filtering `isDeleted`. Chip
      context menu: "This is someone else". Inferred links show a small marker.
- [ ] Tests: presentation helpers (link lookup by surface, entry ordering, connected list) as pure
      functions over plain values.

### Phase 5b: Connections and review
- [ ] `Mindlore/Views/Graph/ConnectionsView.swift`: search, kind picker, Review row, sort, Hidden
      section. Toolbar entry from `EntryListView`.
- [ ] `ReviewSuggestionsView`: pairs with "Same" and "Not the same".
- [ ] `UITestingHTTPClient` (`:28-31`): the stub insights payload already names Sarah; add a second
      person and a tag so a merge can be exercised. `InsightsUITests` asserts section titles only
      (`:48-49`), so it is unaffected.
- [ ] Tests: sort and filter helpers as pure functions; UI test `GraphUITests`, stub only (real
      OpenAI returns whatever names it likes, so the test always launches with
      `-uiTestingFakeAI`): finish an entry, open Connections, tap Sarah, see the entry, merge the
      second person into Sarah, relaunch, the merge and the count survive, unmerge.

### Phase 6: Co-occurrence
- [ ] `Mindlore/Graph/EntityGraph.swift`: `build(links:asOf:halfLife:)` groups links by entry,
      emits weighted pairs with exponential decay from the entry date; `neighbourhood(of:depth:)`;
      filters by kind set and minimum count.
- [ ] Tests: weights for known link sets, decay at one half-life is 0.5, depth-2 neighbourhood,
      hidden and merged entities excluded, `asOf` excludes later entries.

### Phase 7: The picture
- [ ] `Mindlore/Graph/GraphSimulation.swift`: forces, tick, alpha schedule, pin and unpin.
- [ ] `Mindlore/Views/Graph/GraphCanvasView.swift`: `TimelineView` plus `Canvas`, gestures, labels,
      kind colours from `EntityKind`, stop when settled. `graph.rendered` event.
- [ ] `LocalGraphView` from the entity page (depth control); `GlobalGraphView` from Connections
      (kind toggles, minimum count, time scrubber).
- [ ] Tests (no `@MainActor`, the simulation is `nonisolated`): the simulation settles (alpha
      reaches the floor, every position finite, no two nodes coincident) for 1, 2, 50, and 300
      nodes, and 300 nodes settle within a fixed tick budget so a change to the constants is caught;
      a pinned node does not move; the layout is deterministic for a fixed seed. The picture itself
      is checked on the phone.

### Phase 8: Privacy, review, device, docs
- [ ] `DiagnosticsPrivacyTests`: sentinel as entity name, alias, bio, surface text, during merge and
      render.
- [ ] Sub-agent code review over the PR diff; fixes in separate commits.
- [ ] Device smoke steps in `tasks/smoke-test.md`: upgrade over real entries and watch the sweep
      index them (`graph.sweep` counts match); a new voice entry links to an existing person; merge
      two entities and relaunch; hide a tag; the global graph with the owner's real journal stays
      responsive (`graph.rendered` under 16 ms per frame at settle); the time scrubber.
- [ ] `CLAUDE.md`: Graph section (models, resolution rules, indexer hooks, how views query from the
      link side). `docs/remaining-work.md`: next projects updated.
- [ ] PR description; mark ready.

## Test plan

Unit tests carry the weight: the normalizer table, every resolver rule, indexer idempotence and
hooks, merge and unmerge round trips, matcher scores, co-occurrence weights, simulation
convergence, prompt contents, schema rules, and the V1 fixture. No test hits the network. One UI
test proves the browse-merge-relaunch loop against the stub and against real OpenAI when
`MINDLORE_OPENAI_KEY` is set. The graph's look, and its frame time on a real journal, are checked on
the phone.

## Risks and open questions

- **Fragmentation is the whole risk.** A graph of near-duplicates is worse than no graph. Three
  defences: exact-only automatic linking, prompt steering with known names, and a Review list that is
  always current. If the owner's real journal still fragments after the smoke test, the next lever is
  a nickname table (Bob, Robert) and a model-judged "same person?" with a one-line reason, both
  listed as follow-ups rather than guessed at now.
- **Themes may drift toward tags** once the prompt steers them to reuse. Acceptable: the difference
  the user sees is that themes are phrases and tags are labels, and both are mergeable.
- **The first-name rule can be wrong.** It links "Sarah" to "Sarah Kim" when she is the only Sarah.
  The link is marked `inferred`, the chip shows it, and re-pointing one mention is one tap. If it
  proves wrong often, drop the rule and let suggestions carry it.
- **Prompt length.** Up to 150 names and themes adds roughly 600 tokens per insights request. Cheap,
  but the cap is a constant and the smoke test records `inputTokens` before and after.
- **Recount cost.** Full recount after every index is O(links). At ten thousand links it is still
  milliseconds on the main actor, but it is measured in the sweep event and can become incremental
  if the number ever matters.
- **Entry date edits outside the three hooked paths** leave `firstLinkedAt` and `lastLinkedAt`
  stale until the next launch sweep recounts. The counts themselves cannot go stale that way.
- **Global graph size.** Minimum count 2 and kind toggles keep the default view small. A journal
  with thousands of entities is years away; the simulation is O(n^2) and would need Barnes-Hut
  around 1,000 visible nodes.
- **Canvas memory.** The first `Canvas` frame brings up Metal and about 90 MB that never frees. The
  graph views are pushed, not always resident, so this is paid once per session and only if opened.
- **Migration.** Two new models and two new fields on `Entry`, all lightweight. The V1 fixture test
  and the upgrade step of the smoke test gate the rest.
- **Sync later.** Every rule `CloudKitSchemaRulesTests` enforces holds. Merge pointers are UUIDs, so
  a merge on one device is a two-field write that syncs cleanly.

## Not in scope

- `NLTagger` extraction for entries without AI: not deferred, dropped (owner, 2026-09-15). This is
  an AI app; an entry with no insights has no graph presence and that is the intended behaviour. A
  second extraction path with worse precision (`nameType` misses the lowercase names dictation
  produces) writing into the same entity table is how the graph fragments. `NLGazetteer` over
  confirmed names stays a possible follow-up, as a precision hint on the AI path rather than a
  fallback, and it only helps once entities exist
- Embeddings of any kind; theme clustering; nearest-neighbour merge
- The new-entity prompt flow and the weekly graph maintenance pass (build plan 4.4); automatic bio
  drafting in the background for entities nobody has opened
- Sending bios into the insights prompt as context (next PR, with its own privacy review); the
  bio drafter sends entry excerpts out, never bios
- Explicit typed relationships between entities ("works with", "sister"); edges are co-occurrence
- A resolvable `OpenThread` model, mood over time, themes month over month, "on this day"
  (synthesis PR)
- Manual entity creation with no linked entry; bulk operations; export
- Nickname tables; model-judged merge suggestions
- Saved graph layouts, hierarchical layouts, clustering metrics
- Search across entry text (synthesis PR)

## Review log

Revision 2 (sub-agent review of revision 1, 2026-09-15, verdict "needs rework"; 17 findings, all
addressed; code claims verified against `ModelContext+Stamping.swift:9-13`, `EntrySaver.swift:52`,
`InsightsCoordinator.swift:207`, `Entry+Editing.swift:112-137`, `Entry+Pages.swift:155-157`,
`RootView.swift:89-95`, `CloudKitSchemaRulesTests.swift:43`, `InsightsTests.swift:6-20,155-198`):

1. Indexer writes would stamp `updatedAt` on every entry at the backfill sweep: every graph save goes
   through `saveStampingEntries(except:)`; the coordinator hook runs before its own save; a test
   asserts `updatedAt` unchanged across a sweep.
2. Merge losers pruned by the recount the merge triggers: pruning skips `mergedIntoID != nil`.
3. Chain merges broke unmerge and overwrote `originalEntityID`: chains flattened at merge time,
   `originalEntityID` set only when nil, `contributedAliases` recorded on the loser, self-merge and
   cycles refused.
4. Hooks placed where no context exists or after the save: `onInsightsWritten` injected into the
   coordinator; date recounts at the three call sites that have a context; one `removeInsights()`
   used by the view and `restartPages`.
5. Regeneration beside a user-repointed link made a duplicate: values with a user link for the same
   key and kind are skipped.
6. Deleted-but-unsaved links visible to the resolver and views: `removeAILinks` saves first; views
   filter `isDeleted`.
7. Mid-pass recount recreated entities under new IDs: recount only at the end of index and sweep.
8. `Entity.links` cascade would delete links out of entries: `.nullify`, recount cleans up.
9. First-name rule could link into a hidden entity: rule 2 excludes hidden, considers alias tokens.
10. Rename and alias collisions: caught at the edit with an offer to merge; resolver tie-break as the
    net, with `graph.ambiguous`.
11. Tag and theme with the same key never met: identical-key pairs suggested at 1.0; merge allowed
    across kinds, winner's kind stands.
12. `graphIndexedAt` compared as "older than": stores the exact `generatedAt`, inequality is stale.
13. Test isolation: pure types `nonisolated`; indexer and editing take an injected `DiagnosticsLog`.
14. Wrong names and lines fixed; sweep runs before the AI queues in the launch lane.
15. Canvas: `Text` cannot be resolved once; `Canvas(symbols:)`; `TimelineView(.animation(paused:))`;
    the simulation is a plain class, not `@Observable`; settle-within-N-ticks test.
16. UI test against live OpenAI cannot assert names: `GraphUITests` is stub only.
17. Phase 5 split into 5a and 5b; scrubber and pinning named as part of the stacked-PR split. (The
    branch was re-cut from `main` after PR #2 merged, so the draft PR targets `main` directly.)
