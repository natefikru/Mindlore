# Mindlore: the knowledge graph

Branch: `feature/knowledge-graph` from `main` at `0678525` (after PR #2 merged the AI layer). The AI
layer this builds on is archived in `tasks/archive/ai-providers.md`; the product vision is
`docs/mindlore-build-plan.md` Phase 2.

Status: revision 2, approved. Phases 1 to 4 are built (PR #3); the rest is still plan. Revision 2 folds in the sub-agent review of revision 1
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

**Known names go into the prompt, to fix spelling, not to rewrite.** Each insights request carries
up to 50 tags, 50 themes, and 50 names this journal already uses: about seven in ten by use and the
rest by recency, so someone new still makes the list. Hidden entities and merge losers are left out.
Names are written the way the entry writes them; the list only fixes a misspelled or garbled name
and settles kinds. A dictated "sarah" stays "sarah" and the graph decides which Sarah, because the
user's corrections are keyed on what the entry says. An `other` nobody has settled is listed
without a kind. Every item is cleaned to one line of at most 60 characters. Before the graph exists
the tags are counted off the insights as before; once it exists, an empty list means the user hid
them. The counts that went out are stored on `EntryInsights` and shown by `WhatWasSentView`.

**Assumption, for the owner to confirm: names the user typed are sent too.** A renamed entity, and
later a re-pointed one, carries a name the provider never produced. This PR treats that as part of
"words this journal uses", says so on the disclosure screen, and never sends aliases or bios. The
alternative is to send such an entity only under the last name the provider saw. Recorded here so
the privacy review before an external build can decide.

### Views

**Connections is the index page.** A toolbar button on the list opens a screen with a search field,
a kind picker (All, People, Places, Organizations, Projects, Events, Tags, Themes), a Review row
when suggestions exist ("3 possible duplicates"), and entities sorted by recent or by count. A Hidden
section at the bottom. The graph opens from the toolbar.

**The entity page is the person page.** Name (editable), kind (picker), aliases (chips, add and
remove), the bio, first and last mentioned, count.

**Bios are drafted once, owned by the user.** The first time the page of a person, place,
organization, project, or event opens while automatic insights are usable, `GraphServices` drafts
a bio from excerpts of linked entries the provider has already received in full (Phase 5a spec
has the exact rules), with the build plan 4.2 prompt, and stores it with `bioWasGenerated = true`.
The page labels it "Drafted by AI" until the user edits it; any user edit, including clearing it,
sets `bioEditedByUser` and AI never writes it again, exactly the title rule. There is no approve
step: the label is the approval state. A tapped Draft works for any kind and any time the bio is
empty or AI-written. The page shows what was sent (entry count, characters, model). The bio itself
never leaves the device. Entries: every linked entry by entry date, newest first, with the
sentence the name appears in, read-only until 5b. Merge into (search, suggestions first), Hide,
and, for entities merged into this one, "Also known as B, merged on date, Undo". The co-occurring
"Mentioned with" section arrives with Phase 6.

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
    var bioWasGenerated: Bool = false     // AI may rewrite only while true; a user edit clears it
    var bioEditedByUser: Bool = false     // set by setBio, even to empty; AI never writes after (5a)
    var bioDraftedAt: Date?               // what was sent, for the page's disclosure line (5a)
    var bioModelUsed: String?
    var bioSourceEntries: Int = 0
    var bioSourceCharacters: Int = 0
    var kindEditedByUser: Bool = false    // an untouched kind can still be upgraded
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

### Phase 1: Models (done)
- [x] `Mindlore/Models/Entity.swift`, `EntityLink.swift`, `EntityKind` with `symbol` and `heading`
      (extend the per-kind table in `Views/Insights/InsightCards.swift:19-41`).
- [x] `Entry.swift`: `entityLinks` relationship and `graphIndexedAt`.
- [x] `ModelContainerFactory.swift`: schema.
- [x] Tests: `CloudKitSchemaRulesTests.appSchemaFollowsCloudKitRules` (`:43`) passes with the new
      models; `SchemaMigrationTests` per-entry loop (`:54-64`) asserts the new fields;
      `MoodTests.moodRawValuesArePinned` (`InsightsTests.swift:6-20`) gains `EntityKind` and
      `EntityLinkSource`.

### Phase 2: Normalizer, resolver, indexer (done)
- [x] `Mindlore/Graph/EntityNormalizer.swift`: `key(for:kind:)`, `tokens(of:)`, honorific and
      possessive tables. Table-driven tests: `"Sarah's"`, `"Dr. Kim"`, `"NĚMEČEK"`, `"  new   york "`,
      `"James'"`, `"Aunt May"`, tag and theme forms.
- [x] `Mindlore/Graph/EntityResolver.swift`: the three-step rule over an in-memory snapshot of live
      entities (fetched once per index call). Returns link decisions; does not write.
- [x] `Mindlore/Graph/GraphIndexer.swift` (main actor, owns writes, injected `DiagnosticsLog`):
      `index(entry, context)`, `sweep(context)`, `recount(context)` with orphan pruning and
      nullified-link cleanup, `removeAILinks(for:)` which saves before returning. Every save goes
      through `saveStampingEntries(at:except:)` with the touched entries excluded.
- [x] `Entry+Editing.removeInsights()`; call it from `EntryInsightsView` "Delete insights" and from
      `restartPages` (`Entry+Pages.swift:155-157`).
- [x] Hooks: `InsightsCoordinator.init` takes an `onInsightsWritten: (Entry, ModelContext) -> Void`
      (the `InsightsHarness` passes a no-op or a spy), called before the save at `:207`;
      `RootView` third `.task` lane (`:89-95`) runs `sweep` before the title and insights queues so
      the first request after the upgrade already carries known names; `EntryDateSheet` dismiss
      (`:30,49`) and the two coordinator date paths (`InsightsCoordinator.swift:192`,
      `PageTranscriptionCoordinator.swift:209`) call `recount`; `EntryListView` delete path flushes
      then recounts.
- [x] Diagnostics events (`graph.indexed`, `graph.sweep`, `graph.ambiguous`, `graph.saveFailed`); `AIDiagnosticsPrivacyTests` extended.
- [x] Tests (`GraphIndexerTests`, `@MainActor`, in-memory container, `FakeTextGenerator` through
      the `InsightsHarness` pattern at `InsightsTests.swift:155-198`): exact match links; alias
      match; first-name rule with one candidate links inferred, with two creates new, and ignores
      hidden candidates; cross-kind creates new; hidden entity is reused by exact match and stays
      hidden; reindex is idempotent, preserves user links, and does not add an AI link beside a
      user link with the same key; reindexing the sole entry for an entity keeps its ID; deleting
      insights removes AI links; deleting an entry prunes an unconfirmed orphan and keeps a confirmed
      one; counters match links after every operation; sweep indexes only entries whose stamp differs
      from `generatedAt`; **a sweep over N entries leaves every `updatedAt` unchanged**; an exact
      tie resolves to the confirmed entity and records `graph.ambiguous`.

### Phase 3: Editing, merge, suggestions (done)
- [x] `Mindlore/Graph/GraphEditor.swift` (built as a struct rather than an `Entity` extension, so it can hold an injected `DiagnosticsLog`): `rename`, `setKind`, `addAlias`, `removeAlias`,
      `setBio`, `hide`, `unhide`, `merge(into:)`, `unmerge`, `markNotSame(as:)`, `repoint(link:to:)`.
      Every one sets `confirmedByUser` on the entity edited and calls recount. `rename` and
      `addAlias` return a collision (the other entity) instead of applying when the key is taken;
      `merge` refuses self, redirects a merged target to its root, flattens every loser pointing at
      the loser onto the winner, sets `originalEntityID` only where nil, and records
      `contributedAliases`.
- [x] `Mindlore/Graph/EntityMatcher.swift` (`nonisolated`): Jaro-Winkler, token subset,
      `suggestions(among:)`.
- [x] Tests: merge moves links and aliases and unmerge restores exactly, including aliases the
      winner already had; B into A then A into C leaves B pointing at C, and unmerging A from C
      restores only A's own links; unmerging B afterwards still works; self-merge and cycle refused;
      the loser survives the recount; the resolver links a mention of a loser's name to the root;
      rename onto an existing key reports the collision; Jaro-Winkler against known values
      (`martha`/`marhta` 0.961); subset pairs suggested, dismissed pairs not, fuzzy cross-kind not,
      identical-key tag and theme suggested at 1.0; ranking.

### Phase 4: Prompt feedback (done)
- [x] `InsightsPromptBuilder.plan`: one `JournalVocabulary` parameter (tags, themes, named things) in place of `existingTags` with
      the guidance text above; caps at 50 each.
- [x] `GraphIndexer.vocabulary(in:)`, injected into the coordinator; `InsightsCoordinator.topTags` kept only as the fallback
      reading `Entity` counters instead of scanning every `EntryInsights`.
- [x] `WhatWasSentView` lists the counts sent.
- [x] Tests: prompt contains the names and kinds, excludes hidden and merged entities, caps at 50,
      falls back to the old tag scan when the graph is empty, and the coordinator really sends it.

### Phase 5a: Entity page, bios, chips

The first screens that show the graph. From an entry's insights, a tag, theme, or name opens that
entity's page: what it is, what the journal says about it, and every entry it appears in, with the
edits Phase 3 built (rename, kind, aliases, bio, hide, merge, unmerge, "this is someone else").
Plan review of 2026-09-16 (20 findings) is folded in below; see "Review log".

**Rules the views follow** (from the Phase 2 and 3 review):
- Never read `EntityLink.entity`/`.entry` or `Entity.links`/`Entry.entityLinks`. They exist for
  SwiftData's delete rules and read nil or short often enough to blank a screen. Everything
  resolves through `entityID` and `entryID`, and links for an entity or entry come from one fetch
  filtered in memory, never from an optional-UUID `#Predicate` (check `GraphEditor.merged(into:)`,
  which uses one, and fix it the same way). Rows with `isDeleted` are ignored.
- Never hold an `Entity` across an edit. A page is given an id; `init(id:)` builds its
  `Query(filter: #Predicate { $0.id == local })` from a local copy of the id. Sheets take strings and
  ids, never an `Entity`.
- Views get the graph from one injected object, not by building their own (review item 11).
- Every graph edit from a view first flushes `EntrySaver` (so no entry has real unsaved edits),
  then goes through `GraphServices`, which saves exempting only the entries whose links moved,
  recounts when counts can change, and bumps `revision`. The Phase 3 text claiming the editor
  saves and recounts on its own was wrong for most edits.

**Decisions for this phase** (the three marked * were accepted by the owner on 2026-09-16):
- `GraphServices`, an `@Observable` final class built once in `RootView` with
  `State(initialValue:)` and put in the environment (and in every `#Preview`), holds the
  `GraphIndexer`, `GraphEditor`, and `EntityBioDrafter` with the shared log. The coordinator
  closures capture that same instance. It exposes `revision` (bumped after every graph save, the
  refresh key for pages and chips), `drafting: Set<UUID>`, and `bioFailures: [UUID: AIError]`.
  The three inline `GraphIndexer()` flows move into methods `entriesDeleted`, `insightsDeleted`,
  and `entryDateChanged` so they are unit tested. Tests build their own with a test log.
- Navigation is by value on a `NavigationPath` owned by the insights sheet's `NavigationStack`
  (`EntryInsightsView.swift:40`). `EntityRoute(id:, follow: Bool)`: `follow` routes show the
  merge winner when the id was merged elsewhere; merged-in rows push `follow: false` so they show
  the loser itself. A merge made from the page replaces the top route with the winner, rather than
  relying on the redirect, so Undo does not flip the page. When a route's entity is gone (pruned,
  say after Generate again), the page shows "No longer in your journal" until the user goes back;
  the page never dismisses itself and the path is not rewritten under the user. The resolved page is a separate body view
  with `.id(rootID)`, watched with `.onChange(of:initial: true)`.
  `EntityPagePresentation.resolve(route, fetched)` is the pure decision and is tested.
- *Entry rows on an entity page are read-only in 5a: date, title or first words, and the sentence
  the name appears in. The page only lives inside the insights sheet here, and opening an editor
  inside a sheet opened from an editor fights `EntryEditorView`'s close-on-disappear. 5b adds
  Connections to the main stack, where a row can open the entry properly.
- *"Mentioned with" (the entities an entity shares entries with) waits for Phase 6, which builds
  the weighted version. Building a plain one now means building it twice.
- *A bio is drafted automatically once per entity, the first time its page opens, only for
  people, places, organizations, projects, and events (tags and themes rarely appear word for
  word), and only while `AIServices.automaticInsightsUsable` holds, since it is a new automatic
  send. If the entries say too little, the model returns null, the bio stays empty, and the page
  says "Not enough in your entries yet" with a Draft button. Draft (any kind) stays available
  whenever AI text generation is usable and the bio is empty or still AI-written and not
  user-edited; a tapped Draft on a cleared bio clears `bioEditedByUser` first. Once the user edits
  the bio, AI never writes it again. The AI settings disclosure mentions bios.

**Bio drafting** (`Mindlore/Graph/EntityBioDrafter.swift`, main actor, run by `GraphServices`):
- Eligible entries (so nothing goes out that the provider has not already received in full): not
  drafts, not photo entries awaiting approval, with insights whose source text still matches the
  entry's current text, and only `text.prefix(InsightsPromptBuilder.maxInputCharacters)` is
  searched.
- Excerpts (`BioExcerpts`, `nonisolated`, pure): the eight most recent eligible linked entries by
  `entryDate`, and from each the sentences containing the link's surface text, matched as a whole
  word, case-insensitive, possessive included (the matcher `InsightsPromptBuilder.grounded` uses,
  moved to a shared `NameMatching`). Capped at 1,500 characters in total, whole sentences only,
  newest first. An entry whose text no longer contains the name contributes nothing. Zero excerpts
  means no request and nothing recorded (so a later open can try once entries exist); the page
  shows the not-enough state.
- Request: structured, schema name `entity_bio`, one nullable string field `bio`. System prompt
  from build plan 4.2: "Based only on how {name} is described in these excerpts from the writer's
  journal, write one neutral sentence about who or what {name} is to the writer. Do not speculate
  beyond what is said. Return null if the excerpts do not say enough." The name goes through
  `promptSafe`; name, kind, and excerpts go in the user message. No bios, aliases, or other
  entities are sent.
- One draft per entity at a time: `GraphServices` keys running drafts by entity id, so two quick
  opens or two pages send one request. Leaving the page does not cancel it (the result is cheap to
  keep and already paid for), and nothing in the app cancels one; `cancelDrafts` exists for tests.
- Writes, after `Task.isCancelled` is checked and the entity is re-fetched by id: only if it still
  exists, is not merged, `!bioEditedByUser`, and its bio is still empty or AI-written. Stores `bio`
  (or nil), `bioWasGenerated = true`, `bioDraftedAt`, `bioModelUsed`, `bioSourceEntries`,
  `bioSourceCharacters` (see Data model changes; `Entity` has never shipped, so no migration).
  Saves with plain `saveStampingEntries()`, never exempting an entry. A drafted bio does not
  confirm the entity: if all its links go, the entity and its AI bio are pruned together.
- A cancelled or failed draft records nothing on the entity, so the next open tries again.
  Failures show inline with Try again, worded by `BioDraftPresentation.message(for:)`.
- `AIServices.textGenerator(settings:accounts:)` and `textUsable` are added, sharing a
  `ResolvedTextGenerator` with `insightsGenerator`; `textUsable` skips the Keychain read like
  `pagesUsable`.
- Events: `graph.bioDrafted` (id, entries, characters, empty, inputTokens, outputTokens) and
  `graph.bioFailed` (id, `AIJobFailure.raw`, the code `insights.failed` logs; `errorCode` would
  only say "AIError 8"). A failed save logs `graph.saveFailed` with `errorCode`. Never the name,
  excerpts, or bio.
- Built (5a.2): `GraphServices.pageOpened` (automatic) and `draftBio` (tapped), `drafting`,
  `bioFailures`, and `withoutExcerpts` (zero excerpts this session, for the page's not-enough
  state); `draftFinished` lets tests await the real task; `cancelDrafts` for the cancellation tests only; nothing in the app cancels a draft.

**The entity page** (`Mindlore/Views/Graph/EntityView.swift` and small pieces beside it):
- Header: name (tap to rename), kind menu, "Mentioned in N entries", first and last dates. The
  kind menu offers only mention kinds for a mention entity and only tag or theme for a tag or
  theme. `setKind` returns an `EditOutcome`, and a key collision goes to the merge offer.
- About: the bio, with "Drafted by AI · N entries sent to OpenAI · model" under an AI-written one,
  a spinner while `drafting` contains the id, Edit (a text editor sheet taking the string), Draft
  again while AI-written, and the not-enough, failure, and AI-unavailable states.
- Also called: alias chips with remove, and Add alias.
- Entries: newest first, read-only, each with the sentence the name appears in. A guessed link
  (`inferred`) is marked "Guessed" with a one-tap "Not them" that opens the re-point sheet.
- Merged into this: each loser with its merge date, Undo (unmerge), and a `follow: false` route.
- Actions: Merge into... (`MergeIntoView`: search over browsable entities, suggestions from
  `GraphEditor.suggestions` for this entity first, same-kind first), Hide or Unhide.
- A rename, alias, or kind change that collides shows "{other} already goes by that name. Merge
  them?" with Merge (this into that, then the route is replaced with the winner) and Cancel. If the
  other is hidden it says "(hidden)" and merging unhides it.
- `EntityPagePresentation` (pure) carries the logic the view shows: route resolution, entry rows
  from links and entries, dates and counts wording, which bio state applies, merged-in list.

**Chips** (`InsightCards.swift`, `EntryInsightsView.swift`):
- `EntityChipIndex` (pure): from the entry's links (one fetch, filtered by `entryID` in memory), a
  lookup by the link's kind, exact surface first, then normalized key, to (entity id, inferred).
  Hidden entities get no route. Rebuilt when `insights.generatedAt` or `GraphServices.revision`
  changes.
- Tags keep `WrappingChips`, which takes an optional route per item. Themes stay rows and become
  navigation rows when linked. Mentions become per-name chips under each kind heading (today one
  comma-joined line). A value with no link is plain text. A guessed link's chip has a dashed
  outline and "guessed" in its accessibility label.
- Several chips share one Form row, so each is a borderless `Button` appending to the path;
  `MentionGroups` drops `.accessibilityElement(children: .combine)`; Copy moves off the
  section-level context menu on chip cards; chips use `.contentShape(.contextMenuPreview, Capsule())`.
- Each chip's context menu: Open, and for names "This is someone else", which opens `RepointView`.
  It carries (entryID, surface, kind), never a link id, since Generate again can delete the link,
  and looks the link up on commit ("This mention changed" if gone). Search existing entities of
  that kind or type a new name (checked with `entityAnswering` first, offering the existing one),
  and a switch "Also for future mentions of '{surface}'" (the alias). It calls
  `GraphEditor.repoint` and reports an alias collision the same way the entity page does.
- Accessibility identifiers: `entityChip-{kind}-{surface}`, `entityPage`, `entityBio`,
  `entityBioDrafted`, `entityRename`, `entityMergeInto`.

**Test stub**: `UITestingHTTPClient` answers a body containing `entity_bio` with a sentence using
the requested name ("{name} is a friend the writer walks by the river with."), before the title
fallback.

**Steps**, each committed and pushed on its own with the unit suite green:
- [x] 5a.1 `GraphServices` in the environment with `entriesDeleted`, `insightsDeleted`,
      `entryDateChanged`; the three inline `GraphIndexer()` uses switch to it; `NameMatching`
      shared by grounding and excerpts; `merged(into:)` filters in memory. No behavior change. Also fixed: the chunked launch sweep
      crashed when an entry was deleted between chunks (it held a detached entry); chunks now
      re-fetch by id.
- [x] 5a.2 `Entity` bio fields, `bioEditedByUser` in `setBio`, `AIServices.textGenerator` and
      `textUsable`, `BioExcerpts`, `EntityBioDrafter`, drafts in `GraphServices`, the stub branch,
      events, the draft privacy test, the settings disclosure line.
- [x] 5a.3 `EntityPagePresentation`, read-only `EntityView` with the bio section and editing,
      route resolution. (Built: the insights sheet's stack takes a typed `[EntityRoute]` path;
      a gone route shows "No longer in your journal" until the user goes back. Nothing pushes a
      page from an entry yet; that is 5a.5.)
- [x] 5a.4 Rename, kind, aliases, hide, `MergeIntoView`, `RepointView`, the collision flow.
      (Built: `GraphServices` wraps every page edit and saves; merging into a hidden entity
      unhides it in `GraphEditor.merge`; a merge made from a page swaps the route through an
      `entityRouteReplacer` environment value set on the sheet's stack; a merged entity's own
      page shows "Merged into X" with Undo; guessed entry rows open `RepointView`.)
- [x] 5a.5 `EntityChipIndex`, tappable chips, per-name mention chips, navigation from the sheet.
      (Built: `GraphServices.chipIndex(for:in:)` builds the index so it is tested against real
      links; tags and names use `EntityChips`, themes become navigation rows; the Tags and
      Mentioned cards lost their card-wide Copy, and each chip's menu has Open, Copy, and for
      names "This is someone else".)
- [x] 5a.6 UI test, sub-agent review of 5a, fixes, simulator screenshots of each screen state.
      UI tests written and passing:
      - GraphUITests: full flow (chip tap, bio draft, edit, alias, tag page, relaunch)
      - InsightsUITests: passes with real OpenAI, confirming chip changes don't break insights
      Screenshot test captures drafted bio state; other states need manual verification.

**Tests**:
- `BioExcerptsTests`: the sentence containing each surface form; case and possessive; a longer
  word containing the name does not count; newest eight entries only; 1,500-character cap without
  cutting a sentence; an entry that no longer names them adds nothing; no match gives no excerpts;
  drafts, unapproved pages, stale insights, and text past the insights limit are excluded.
- `EntityBioDrafterTests` (`FakeTextGenerator`): a draft lands with the flag and what-was-sent
  fields; a null answer leaves the bio empty and marks it drafted; zero excerpts sends nothing and
  records nothing; a user-written bio is never replaced, including one typed while the request was
  out; a bio the user cleared is not redrafted automatically; an entity merged or pruned while the
  request was out gets nothing; a failure records nothing and logs `bioFailed`; a cancellation
  (suspended fake, cancel, resume) records and logs nothing; two opens send one request; tags and
  themes are not auto-drafted; automatic insights off or no key does not call the generator; the
  request carries the name and excerpts and no bio, alias, or other entity; no entry's `updatedAt`
  moves; an unconfirmed entity whose links all go is pruned with its AI bio.
- `EntityPagePresentationTests`: route resolution (live, merged with and without follow, gone);
  entry rows newest first with the right sentence and guessed flag; bio state for each combination
  of empty, AI-written, user-written, cleared, drafting, failed, not enough, AI unavailable; counts
  and date wording; merged-in list with dates.
- `GraphEditor` additions: `setKind` collision returns the other entity; the kind menu's allowed
  kinds; merging into a hidden entity unhides it.
- `EntityChipIndexTests`: a tag, theme, and name each resolve to their entity; a grounded
  lowercase surface ("sarah") still resolves; a value with no link has no route; a hidden entity
  has no route; a guessed link says so; a user-repointed link resolves to where the user put it.
- Repoint: after Generate again removed the link, commit reports the change and writes nothing; a
  typed name that already exists links to that entity.
- `GraphServicesTests`: the services share one log; `entriesDeleted`, `insightsDeleted`, and
  `entryDateChanged` recount; `revision` moves on every save; Generate again that prunes a shown
  entity leaves the route resolving to gone.
- Privacy (in 5a.2): the sentinel as entry text, surface, and bio passes through a real draft and
  nothing reaches the log.
- `GraphUITests` (stub only, since real names vary): finish an entry, open insights, tap Sarah,
  see the page and the drafted bio marked as AI's, edit the bio and see the mark go, add an alias,
  go back, tap the "river" tag and see its page, relaunch and find the edited bio still there.
- Unchanged suites stay green, including the live insights UI test.

**Not in 5a**: Connections, the Review list, and opening an entry from an entity page (5b); the
"Mentioned with" section (6); the graph (7); creating an entity by hand; bulk edits; on-device bio
drafting; sending bios anywhere; choosing a capitalized display name automatically (a 5b
question, recorded there).

### Phase 5b: Connections and review

Display name decided (2026-09-16): no auto-capitalization. `entity.name` stays exactly what was
first seen, same as today; a display-only capitalizer would fight the user's own rename (5a) and
add a rule with no clean edge (initials, "mom" versus "Mom's house"). Unchanged from Phase 5a.

- [x] 5b.1 `Mindlore/Graph/ConnectionsPresentation.swift`: pure filter/sort helpers.
      - `filter(_:kind:search:)`: kind is `EntityKind?` (`nil` = all), search matches name or any
        alias (`localizedStandardContains`, matching `MergeCandidates.order`'s search).
      - `SortOption: name, mostMentioned, recent` (`recent` = `lastLinkedAt`, nil sorts last, per
        `EntityModelTests.swift:307-328`'s existing sort contract).
      - `ConnectionRow` (id, name, kind, linkCount, lastLinkedAt), built from `Entity` by the view.
      - Tests: filter by kind, filter by search (name and alias), each sort, nil `lastLinkedAt`
        sorts last.
- [x] 5b.2 `GraphServices.markNotSame(_:_:in:)`: `GraphEditor.markNotSame` takes two `Entity`
      values and doesn't save, so this can't reuse the private `edit(_:in:_:)` helper (single id,
      single-entity closure); fetch both entities directly, call `editor.markNotSame`, then the
      private `save(context)` (`GraphServices.swift:154-161`), bumping `revision` the same way
      `merge`/`unmerge` do.
      Test: after `markNotSame`, the pair is gone from `editor.suggestions(in:)`.
- [x] 5b.3 `Mindlore/Views/Graph/ConnectionsView.swift` + `ReviewSuggestionsView` (small subview,
      same file): own `NavigationStack` and `.navigationDestination(for: EntityRoute.self)`,
      mirroring `MergeIntoView`/`EntryInsightsView`. Sections, in order:
      1. **Review** — `graph.editor.suggestions(in:)`, refreshed via `.task(id:)` keyed on
         `graph.revision` (the `RefreshKey` pattern from `MergeIntoView.swift:20-24`). Each pair:
         both names, "Same" (`graph.merge`) and "Not the same" (`graph.markNotSame`, 5b.2).
         Both act, then rely on the same `.task(id:)` refresh (keyed on `graph.revision`) to drop
         the pair, the pattern `MergeIntoView` already proves; a ConnectionsView UI test covers
         the refresh actually happening, not just that `editor.suggestions(in:)` drops the pair.
      2. **All** — `isBrowsable` entities, filtered/sorted (5b.1). Rows are
         `NavigationLink(value: EntityRoute(id:))`, opening the existing `EntityView`; merge and
         hide stay on that page, unchanged from 5a. No row swipe actions.
      3. **Hidden** — `hidden == true` entities, same row style, same navigation.
      Toolbar: kind picker (menu, `EntityKind?`), sort menu. `.searchable(text:)`.
      `ContentUnavailableView.search(text:)` when a search matches nothing; a plain "No entities
      yet" when the graph is empty (no entries indexed).
      `EntryListView`: `showingConnections` state, toolbar button (`"person.2"`, matching
      Settings' pattern at `EntryListView.swift:78,90-92`), `.sheet`.
      Accessibility ids: `"connectionRow-\(entity.name)"`, `"connectionsKindPicker"`,
      `"connectionsSortPicker"`, `"reviewSame-\(suggestion.a)"`, `"reviewNotSame-\(suggestion.a)"`.
- [x] 5b.4 Entry rows on the entity page become tappable (gap from 5a: "opening an entry from an
      entity page" was explicitly deferred here). Scope: a read-only preview sheet (date, full
      text), not the full editor — reaching the editor would mean dismissing through however many
      sheets got the user to this entity page (the insights sheet, or now Connections, each with
      their own stack), which is a bigger change for a small want. `entityRows`
      (`EntityView.swift:394`) rows become buttons opening `.sheet(item:)` with a small
      `EntryPreview` view. `saver.flush()` before presenting it, matching every other read of an
      entry's live text in this file (rename, hide, and merge all flush first; this had been the
      one unflushed read of `entry.text`). Accessibility ids: `"entityEntryRow-\(row.id)"`,
      `"entryPreview"`.
- [x] 5b.5 `UITestingHTTPClient` (`Mindlore/AI/HTTP/UITestingHTTPClient.swift:29`): add a second
      mention, `{"name":"Tom","kind":"person"}`, to the fixed payload, so a merge can be
      exercised. Confirmed safe: `InsightsUITests` asserts only section titles and the run button
      label; `GraphUITests` asserts Sarah's and river's chips specifically, unaffected by Tom's
      presence.
      UI test (`GraphUITests`, stub only, real OpenAI names people however it likes so this test
      always launches with `-uiTestingFakeAI`): finish an entry, open Connections from the list
      toolbar, tap Sarah, see her entry (5b.4's preview), go back, merge Tom into Sarah (existing
      `EntityView` flow), relaunch, the merge and the count survive, unmerge.
      Sub-agent review of the whole phase; fix what it finds.

Not in scope: manual entity creation, bulk merge or hide, full-text entry search (name/alias only,
same as `MergeIntoView`'s), model-judged merge suggestions (`EntityMatcher`'s heuristic only), and
opening the full editor from an entity page's entry row (5b.4's preview instead).

Review log (sub-agent review of `e700e7a..HEAD`, 2026-09-16, verdict: two findings, both fixed):
1. No test exercised the Review section's Same/Not-the-same buttons or its `.task(id:)` refresh
   actually dropping a pair, as the plan required. Added
   `testReviewSuggestionNotTheSameRemovesThePair`: renames Tom to "Sara" so he looks like Sarah,
   confirms the suggestion appears, dismisses it, and confirms it's gone after the refresh.
2. `ReviewSuggestionRow`'s comment had the merge direction backwards ("second into the first"
   when the code merges the first into the second). Fixed the comment; behavior was never wrong.
Everything else the reviewer checked (markNotSame's implementation, saver.flush() before the
entry preview, kind filtering on both All and Hidden, Tom not false-matching Sarah, no
capitalization creeping in, nothing from "Not in scope" leaking in) was already correct.

### Phase 5c: Names that sound alike (owner request, 2026-09-16; specified 2026-09-16)

A dictated "Luis" arrives as "Lewis," a real name the writer has no one by. The writer wants every
"Lewis" and "luis" to mean their friend Luis, until they add a second, real Lewis; from then on the
graph should ask which one a mention means instead of guessing. Five of the sketch's seven bullets
are specified below as 5c.1-5c.5. Two are out, both explained under "Not in scope, this phase" at
the end: the AI-disambiguation bullet is blocked on the bios-in-insights privacy review, and the
transcription-hint bullet waits on an owner call about scope.

**Steps**, each committed and pushed on its own with the unit suite green:

- [x] 5c.1 Keep what the entry wrote alongside a corrected name, so bio excerpts and entry-row
      sentences can search for it. `InsightsPromptBuilder.grounded(_:in:)`
      (`InsightsPromptBuilder.swift:230-238`) already recovers the entry's own wording when the
      model's name, or a decreasing word-prefix of it, appears literally in the entry text; only
      when nothing at all matches does it fall through and keep the model's own correction
      (its own comment: "the model fixed a garbled name... and that is kept, which is what the
      journal's names are sent for"). That fallback stays exactly as it is for resolution, a
      corrected "Luis" should still link to the Luis entity, but the fallen-through case needs a
      second attempt to find what the entry actually printed, for display only. Change `grounded`
      to return `(surface: String, wasCorrected: Bool)`; when `wasCorrected`,
      `InsightsPromptBuilder.parse(_:plan:calendar:)` (`InsightsPromptBuilder.swift:242-272`) calls
      a new `NameMatching.nearestWord(to:in:threshold:)`, which scores every word and two-word
      phrase of the entry text sharing the name's first letter (a cheap filter against noise: two
      unrelated words rarely share both a first letter and a high score) against the model's name
      with `EntityMatcher.jaroWinkler` (already internal, not private, nothing to change there),
      returning the best match at or above `NameMatching.nearestWordThreshold` (0.8, looser than
      `EntityMatcher.threshold`'s 0.88 since that one is tuned for whole entity names and a
      corrected "Luis" against an entry's "Lewis" scores 0.805), or nil. `Mention` gains
      `writtenSurface: String?`.
      `EntityResolver.Value` (`EntityResolver.swift:8-13`) has no field for it and `resolve`
      doesn't need one, so it stays off `Value`; `GraphIndexer.values(of:)`
      (`GraphIndexer.swift:382-394`) instead builds a parallel `[Claim: String]` lookup of
      `writtenSurface` by surface-and-kind, the same pattern `origins` already uses
      (`GraphIndexer.swift:68`), and `index`'s link creation (`GraphIndexer.swift:110`) reads from
      it into the new `EntityLink.writtenSurface: String?` field (nil = the surface already is
      what the entry wrote, the common case), carried through unchanged by merge, repoint, and
      unmerge (none of `moveForMerge`, `restore`, or `repoint` touch `surface` either, since they
      reassign who owns a link, not what the entry said). `BioExcerpts.sentences(in:naming:)`
      (`BioExcerpts.swift:32,50`) and the entity page's entry-row sentence lookup
      (`EntityPagePresentation.swift:89`) try `link.writtenSurface` before `link.surface`.
      Test: `grounded` reports `wasCorrected` only on the no-match fallback, never on a full or
      prefix match; `nearestWord` finds "Lewis" for a corrected "Luis" when the entry says "Lewis,"
      and returns nil when nothing in the entry scores 0.8 or above (a truly garbled clip, where
      the model invented a name out of nothing); `BioExcerpts` and the entry row use
      `writtenSurface` when present, `surface` otherwise; a link from before this ships has a nil
      `writtenSurface` and behaves as it does today (lightweight migration, one new optional field).
      (Built: `writtenSurface` threaded through a `[Claim: String]` lookup in
      `GraphIndexer.index`, set on the link after creation rather than through its initializer,
      the same way `originalEntityID` already is; `NameMatching.nearestWord` requires the
      candidate word or phrase to share the name's first letter before scoring, which is what lets
      `nearestWordThreshold` sit at 0.8 instead of `EntityMatcher`'s 0.88 without matching noise.)
- [x] 5c.2 Rename offers "Keep '{old name}' as another name." `GraphEditor.rename(_:to:in:)`
      (`GraphEditor.swift:27-38`) gains `keepingOldNameAsAlias: Bool = false`; on a successful
      rename it appends the entity's old `name` to `aliases` in the same edit, skipping
      `entityAnswering`'s collision check since the old name already belonged to this entity.
      `GraphServices.rename(_:to:in:)` (`GraphServices.swift:55-57`), the wrapper `EntityView`
      actually calls, gains the same parameter and forwards it. `EntityView`'s rename alert
      (`EntityView.swift:114-119`) adds a `Toggle` bound to a new `@State var keepOldName: Bool`,
      defaulted by a new pure `EntityPagePresentation.hasVoiceSourcedLink(links:entries:) -> Bool`
      (true when any entry among the linked entries has `source == .voice`). `EntityView.entryRows`
      (`EntityView.swift:408-429`) already fetches those entries for the entry rows, but as a
      computed property, not a stored one; sourcing the toggle's default from the header
      (`EntityView.swift:181-184`, outside `entriesSection`) means either calling that same
      computed fetch again or lifting it into a stored value the header can also read, not a new
      kind of query but a second invocation of the existing one unless restructured. Passed through
      `apply`'s closure to `graph.rename(id, to:, keepingOldNameAsAlias:, in:)`.
      (Built: the rename UI moved from `.alert` to a small `.sheet` (`RenameEntitySheet`,
      mirroring `BioEditorSheet`'s pattern), because `.alert`'s action builder is backed by
      `UIAlertController`, which does not render a `Toggle`, only buttons and text fields; the
      toggle only shows once the typed name differs from the original, since keeping a name that
      didn't change is a no-op. `entryRows` and the new default both read a shared
      `linkedEntries` computed property, still a second fetch per render rather than one, per the
      spec's own note. The existing `GraphUITests` rename interaction, which drove `app.alerts`,
      was updated to the sheet's `entityRenameField`/`entityRenameSave` identifiers; not run this
      session per the standing "no UI tests" note, but it builds.)
      Test: rename with the flag true adds the alias and it survives a second rename; false behaves
      exactly as `rename` does today; `hasVoiceSourcedLink` is true with a voice entry among the
      links and false for typed-only or none; a rename that collides never touches the alias,
      flag or not.
- [x] 5c.3 "A different person also called {name}." Every collision `rename` and `addAlias` raise
      today (`GraphEditor.swift:31-32,79-80`, surfaced as `EditOutcome.collides(with:)`) stops the
      edit outright. Both gain `force: Bool = false`, skipping `entityAnswering` when true and
      applying the edit anyway; `setKind`'s collision is untouched, a kind change colliding is a
      different, rarer shape, out of scope here. `EntityView`'s collision alert
      (`EntityView.swift:129-136`) gets a third button, "No, someone else," which replays the same
      edit with `force: true`; `apply`'s closure needs to be kept around for this instead of
      discarded once it collides, e.g. `@State var collidingEdit: ((Bool) -> EditOutcome)?` set
      alongside `collision`. Forcing also calls the existing `markNotSame(_:as:)`
      (`GraphEditor.swift:121-127`) between the two entities in the same edit: without it,
      `EntityMatcher.score` (`EntityMatcher.swift:56-68`) gives identical keys 1.0, and the Review
      list's next refresh would immediately re-suggest merging the exact pair the user just said
      were different, undoing the point of forcing. `graph.collisionForced` event (id, other id)
      records it happened, no names. Once forced, two live entities intentionally share a key; the
      resolver ties them together the way it does after any collision today (5c.4, next, is what
      stops it guessing).
      Test: a forced rename applies despite the collision and both entities stay separate and live;
      a forced alias likewise; both entities end up in each other's `notSameAs` and don't appear in
      `EntityMatcher.suggestions` afterward; the unforced path is unchanged; `collisionForced` logs
      ids only.
      (Built: `apply` stayed as-is for `setKind`, which cannot be forced; a second helper,
      `applyForcible`, is what `RenameEntitySheet` and the alias alert call, so `setKind`'s
      collision closure never populates `collidingEdit` and "No, someone else" never appears for a
      kind collision, which the spec's text implied but didn't spell out as a second function.)
- [x] 5c.4 The resolver asks instead of silently choosing, when a shared key ties.
      `EntityResolver.resolve`'s exact-match band (`EntityResolver.swift:42-49`) already tolerates
      more than one live match (its own comment: "two live entities can share a key after a rename
      collision the user pushed through") and always picks with `bestExact`
      (`EntityResolver.swift:96-101`: confirmed, then `linkCount`, then id, a total order). Leave
      `resolve` and its three-case `Outcome` untouched, every existing caller and test keeps
      working, and add a second, pure function beside it, `EntityResolver.tied(_:among:) ->
      [UUID]`, using the same exact-match filter but returning the full set only when more than one
      candidate is `confirmedByUser`, or none are: a real tie either way. A single confirmed
      candidate among unconfirmed others is not tied, a prior decision already broke it, the same
      case `bestExact` already resolves cleanly today. `GraphIndexer.index`
      (`GraphIndexer.swift:80-108`) calls `tied` alongside `resolve` for every value and, when
      non-empty, sets a new `EntityLink.unsureAmong: [UUID]` (default `[]`, added beside
      `writtenSurface`) to the tied ids on the link it creates or reuses; `graph.ambiguous`
      (`GraphIndexer.swift:81-83`) keeps firing unchanged, since `tied` fires strictly less often
      than `isAmbiguous` (a confirmed-versus-unconfirmed pair is ambiguous but not tied).
      Resolving one link is a repoint: `EntityLink.repoint(to:)` clears `unsureAmong` to `[]`
      alongside its existing `source = .user` and `inferred = false`, so picking an answer through
      the existing `RepointView` flow (`GraphEditor.repoint`) resolves it with no new commit path.
      `GraphServices` gets `unsureLinks(in:) -> [UnsureMention]` (link id, entry id, surface, the
      tied entities' names), mirroring `editor.suggestions(in:)`'s shape for the Review section; it
      resolves each id in `unsureAmong` through `editor.root(of:)` before reading a name, and drops
      an id that no longer points at a live, unhidden entity (merged or hidden after the tie was
      recorded, before the user answered) rather than showing a stale one, clearing `unsureAmong`
      down to `[]` (resolved automatically after all) when that leaves one or zero candidates.
      `RepointView` (`RepointView.swift`) gains a `restrictedTo: Set<UUID>?` init parameter (nil =
      today's behavior); `choices` (`RepointView.swift:36-42`) filters its `@Query` result down to
      that set when set, still through the existing `isBrowsable` check, so a stale id is simply
      absent rather than crashing the picker. `ConnectionsView`'s Review section (5b) gets a second
      subsection, "Which one?", one row per unsure link ("{surface} could be {a} or {b}"), tapping
      opens `RepointView(restrictedTo:)` with the (cleaned) tied set. `EntityChipIndex` (5a) already
      returns `(entity id, inferred)` per chip; extend to `(entity id, inferred, unsure)` so a chip
      whose link has a non-empty `unsureAmong` gets its own style (a "?" badge, distinct from the
      dashed "guessed" outline) and "unsure" in its accessibility label, alongside the existing
      "This is someone else."
      Test: `tied` returns both ids when two confirmed (or two unconfirmed) entities share a key,
      empty when one is confirmed and the other isn't, empty for an ordinary single match; indexing
      a value whose key ties sets `unsureAmong` on the link without stopping it resolving to
      something (today's `bestExact` pick, unchanged, so nothing regresses while it waits in
      Review, since `entityID` never changes); repointing an unsure link clears `unsureAmong`;
      `unsureLinks` drops a tied id that got merged or hidden and resolves the rest through
      `root(of:)`; `RepointView(restrictedTo:)` only offers the given ids; the chip index marks the
      right chips unsure; a `ConnectionsView` UI test opens "Which one?," picks one, and the row is
      gone after the refresh (the same `.task(id:)` pattern 5b's Review section
      uses).
      (Built: testing surfaced a real bug the spec text didn't anticipate, now fixed. The
      candidate a tie doesn't pick has no link pointing at it yet, so it looked exactly like an
      abandoned entity to `GraphIndexer.recount` (`GraphIndexer.swift:301-330`: `linkCount == 0 &&
      !confirmedByUser` gets deleted), and the very next recount pruned it, silently resolving the
      tie by deleting one side. `recount` now also keeps an entity referenced in any link's
      `unsureAmong`, the same way it already keeps a hidden entity or a merge loser. `unsureLinks`
      returns `GraphServices.UnsureMention` (a `MentionRef` for identity, reusing the existing
      "found again by what it says" pattern from `GraphServices.repoint`, plus named
      `Candidate(id:name:)` values) rather than raw tuples. A "Which one?" row commits through the
      existing `RepointView` UI, unchanged beyond the new `restrictedTo` filter; no new commit
      path was written. `EntityChipIndex.Chip`/`LinkInput` grew a third field, `unsure`, alongside
      `guessed` rather than replacing it, since the two states are mutually exclusive (`inferred`
      only comes from the resolver's first-name band, `unsureAmong` only from its exact-match
      band) but both are real; the chip badge is a small "?" circle, not a border style, so it
      reads distinctly from the guessed chip's dashed outline. `ConnectionsView`'s UI test was not
      written or run this session, per the standing "no UI tests" note; `unsureLinks` and the
      repoint-clears-`unsureAmong` path are covered at the `GraphServices`/`GraphIndexer` unit
      level instead.)
- [x] 5c.5 "Spelled right?" for a brand-new, unconfirmed name. `EntityPagePresentation` gains a
      pure `showsSpellingPrompt(for:) -> Bool`: true when `!entity.confirmedByUser &&
      entity.linkCount <= 1` and the kind is one of person, place, organization, project, or event,
      the same set bio auto-drafting already limits itself to (5a: "tags and themes rarely appear
      word for word"), since a fresh tag or theme being misspelled isn't the scenario this prompt
      is for. A first mention nobody has touched yet is the same freshness `RepointView`'s "guessed"
      state already leans on, just at the entity level instead of the link level. `EntityView`
      shows a small banner above the header when true, "Spelled right?
      {name}," with a button opening the existing rename alert pre-filled with the current name
      selected. No model changes; any edit through the alert, including 5c.2's alias-keeping
      toggle, clears the prompt the normal way, since it sets `confirmedByUser`.
      Test: `showsSpellingPrompt` is true for a fresh single-link entity, false once confirmed or
      once it has a second link; the banner opens the rename alert with the name selected.
      (Built: `showsSpellingPrompt` takes plain values (`confirmedByUser:linkCount:kind:`), not an
      `Entity`, matching every other pure function in this file; the kind set is
      `EntityBioDrafter.automaticKinds`, reused rather than duplicated, marked `nonisolated` since
      it was `@MainActor`-isolated by default and this pure enum needed to read it. The button
      opens 5c.2's rename sheet, not an alert (the alert was already replaced); "pre-filled with
      the current name selected" simplified to pre-filled, unselected, since selecting the text
      needs a `UITextField`-backed control this codebase doesn't have and the win is small.
      Fixed a flaky test while adding this step's coverage, unrelated to 5c.5 itself but found by
      running the suite repeatedly: `GraphServices.repoint` had an early return, "already points
      there, nothing to do," that predates `unsureAmong`. When the resolver's own provisional pick
      for a tied link happened to be the same entity the user then confirmed through "Which one?",
      that return fired before `unsureAmong` was ever cleared, so confirming the resolver's own
      guess left the mention stuck "unsure" forever, roughly half the time depending on which of
      the tied candidates `bestExact` happened to pick. The guard now also fires the real repoint
      when `unsureAmong` isn't empty, even if `entityID` doesn't change.)

Sub-agent review of the whole phase; fix what it finds.

**Not in scope, this phase:**
- AI choosing between tied candidates, and sending anything about them (bios, excerpts) into the
  insights request: blocked on the bios-in-insights privacy review already flagged under "Not in
  scope" above. 5c.4's Review-list "Which one?" is the answer until that review clears.
- Known names as a transcription hint (owner decision, 2026-09-16: deferred whole, not split).
  A distinct subsystem, transcription rather than resolution, and the on-device half needs a spike
  (iOS 26 `SpeechTranscriber`/`DictationTranscriber`, constructed today with only `locale`/`preset`
  at `SpeechAnalyzerTranscriber.swift:21,30`, expose no vocabulary or contextual-strings hook
  anything in this codebase currently uses). Bundling only the OpenAI-only half (feeding
  `GraphIndexer.vocabulary`'s `named` list into `TranscriberRouter`'s existing `prompt`,
  `OpenAICompatibleTranscriber.swift:15-22,33-35`, alongside the previous chunk's tail) into 5c
  would ship an on-device/cloud asymmetry this phase doesn't otherwise have and would need its own
  privacy-note update regardless; simpler to keep 5c scoped to resolution and take the whole bullet,
  spike included, as its own follow-up phase, the same way Phases 6 and 7 are already split off.

Review log (sub-agent review of `96865ae..HEAD`, 2026-09-16, verdict: one real bug, two coverage
gaps, both fixed):
1. `RenameEntitySheet`'s "keep the old name" toggle decided whether to show itself by comparing
   the typed name to the original as plain strings, not by the normalized key
   `GraphEditor.rename` itself uses to decide whether to add the alias. A spelling-only rename
   ("sarah kim" to "Sarah Kim", same key) still showed the toggle and let it be turned on, but
   the edit silently added no alias, since the key hadn't changed, no feedback either way. Fixed:
   the sheet now takes the entity's `kind` and compares `EntityNormalizer.key(for:kind:)` on both
   sides, matching the editor exactly.
2. 5c.1's actual wiring (`GraphIndexer.index` copying `Mention.writtenSurface` onto
   `EntityLink.writtenSurface`, and `EntityBioDrafter.excerpts` preferring it over `surface`) had
   no test exercising it end to end, only the pure `grounded`/`nearestWord` pieces. Added
   `indexingCopiesWrittenSurfaceFromTheMention`, `indexingLeavesWrittenSurfaceNilWhenTheMentionHasNone`
   (`GraphIndexerTests.swift`), and `writtenSurfaceIsSearchedInsteadOfTheCorrectedSurface`
   (`EntityBioTests.swift`).
3. 5c.3's forced-alias test checked `notSameAs` but not that `EntityMatcher.suggestions` actually
   comes back empty afterward, unlike its forced-rename sibling. Added the same assertion to
   `aForcedAliasAppliesAndKeepsBothEntitiesLiveAndSeparate`.
Everything else the reviewer checked was already correct: the `unsureAmong` lifecycle across
merge/hide/repoint, the `recount` and `repoint` fixes from earlier steps, `collisionForced`'s
privacy (ids only), `writtenSurface`/`unsureAmong` both optional-or-defaulted for
`CloudKitSchemaRulesTests`, and no leakage of the excluded AI-disambiguation or
transcription-hint work.

### Phase 6: Co-occurrence (specified 2026-09-16)

Two entities share an edge because they share an entry, the same way Obsidian's edges are derived,
not stored (plan line 71-72). This phase builds the weighted computation two things already promised
it: the entity page's "Mentioned with" section, deferred twice ("waits for Phase 6, which builds the
weighted version," Phase 5a; "arrives with Phase 6," Phase 5b), and the edge weights Phase 7's local
and global graphs draw. No new stored model: `EntityGraph` reads `EntityLink` and `Entity` and
produces edges at view time, per the "computed from co-occurrence at view time and never stored" rule
(plan line 108-110).

**Key decisions:**
- `EntityGraph` is `nonisolated`, like `EntityMatcher` (`Mindlore/Graph/EntityMatcher.swift:9`): a
  plain enum namespace, static functions, plain `Sendable` value types in and out, no `@Model`
  reference anywhere in its signatures. It cannot call `GraphEditor.root(of:)` or read
  `Entity.isBrowsable` itself, so the caller resolves merges and hidden entities into plain values
  first. This is *not* `chipIndex`/`unsureLinks`'s exact shape, since both of those resolve a handful
  of ids per call (one entry's links, or a tied set), while `mentionedWith` (below) resolves against
  every link in the store: one `allLinks(in:)` fetch plus one plain `Entity` fetch (all of them, or
  every id referenced by those links), turned into an in-memory `[UUID: Entity]` map, with
  `mergedIntoID` chains and `isBrowsable` walked purely against that map, never one `root(of:)` or
  `entity(withID:)` call per link. `GraphEditor.root(of:)`/`entity(withID:)` each issue their own
  `FetchDescriptor`, and calling either per link over a link table sized in the thousands (this
  app's own stated scale) is the perf cliff `recount` (`GraphIndexer.swift:301-330`) avoids by
  fetching each table exactly once; `mentionedWith` must do the same.
- Input type: `EntityGraph.LinkInput(entryID: UUID, entityID: UUID, entryDate: Date)`, where
  `entityID` is already the live root (post `root(of:)`) of a link whose `entity` `isBrowsable`
  (`Entity.swift:75`). A link pointing at a hidden or merged-away entity is dropped before it ever
  reaches `EntityGraph`, so "hidden and merged entities excluded" is a caller responsibility, not a
  filter inside `build`. `entryDate` is `Entry.entryDate` (`Entry.swift:21`, always present, defaults
  to `createdAt`), the same field `GraphIndexer.recount` uses for `firstLinkedAt`/`lastLinkedAt`
  (`GraphIndexer.swift:302-306`), not `createdAt` itself and not the link's own creation time.
- `build(links:asOf:halfLife:) -> [Edge]`: groups `links` by `entryID` (mirroring
  `GraphIndexer.batch`'s `Dictionary(grouping:by:)` at `GraphIndexer.swift:36-43`), drops any group
  whose `entryDate` is after `asOf` entirely (excluded, not zero-weighted, so `asOf` behaves like a
  point-in-time filter, matching the time scrubber's job in Phase 7), de-duplicates `entityID`s
  within a group (two mentions in one entry resolving to the same entity, common after a merge, must
  not pair that entity with itself or double-count a pair through it), then for every remaining group
  with two or more distinct entities emits every unordered pair with weight
  `0.5 raisedTo (asOf.timeIntervalSince(entryDate) / halfLife)` (so age equal to one half-life is
  weight 0.5, an entry from `asOf` itself is weight 1.0, `halfLife` defaults to 90 days *
  86400 seconds, matching Phase 7's plan line 267 "90-day half-life"). `Edge(a: UUID, b: UUID, weight:
  Double)` canonicalizes `a`/`b` by comparing `.uuidString` (`a < b`), a fixed 36-character uppercase
  hex form, so ordering is deterministic across implementations; `build` keeps an internal `[Edge.Key:
  Double]` accumulator (`Edge.Key` the canonicalized `(a, b)` pair) and sums every group's
  contribution into it before turning it into the returned `[Edge]`, which is how "a pair appearing in
  several entries sums its per-entry weights into one `Edge`" is actually satisfied, not merely a
  side effect of `Edge` being `Equatable`.
- `neighbourhood(of:in:depth:) -> Set<UUID>`: breadth-first over `edges` treated as an adjacency list,
  returning ids reachable within `depth` hops, excluding `id` itself. Depth 0 is the empty set, depth
  1 is direct neighbours, depth 2 adds their neighbours; Phase 7's local graph (plan line 266, depth 1
  or 2 from an entity page) calls this directly and then filters `edges` to the pairs whose both ends
  are in the returned set (or equal `id`) for what it draws, which this phase does not need to do
  itself since nothing renders yet.
- `filtered(edges:nodes:kinds:minimumLinkCount:) -> [Edge]`: the global graph's two controls (plan
  line 268-269, kind toggles and the minimum-count slider defaulting to 2). `nodes: [UUID:
  (kind: EntityKind, linkCount: Int)]` is supplied by the caller (another plain map from `Entity`,
  since `EntityGraph` cannot fetch one), because filtering by total mentions is a property of the
  entity, not the edge weight; an edge is kept only when both ends appear in `nodes`, both ends' kind
  is in `kinds` (`nil` means no kind filter, matching every other optional-set filter in this codebase,
  e.g. `RepointView.restrictedTo`), and both ends' `linkCount` is at least `minimumLinkCount`. An edge
  with an end missing from `nodes` (the entity was pruned since `edges` was built) is dropped rather
  than crashing, the same defensive stance `RepointView(restrictedTo:)` takes on a stale id
  (5c.4).
- `GraphServices.mentionedWith(of:in:limit:) -> [CoOccurrence]` (new method, placed after
  `chipIndex(for:in:)` at `GraphServices.swift:228`, before the bios section): builds the resolved
  `LinkInput` array as above from `indexer.allLinks(in:)`, calls `EntityGraph.build` with the default
  half-life, keeps only edges touching `id`, sorts by weight descending, caps at `limit` (8, the
  entity page's row count), and turns the surviving ids into `CoOccurrence(id: UUID, name: String,
  kind: EntityKind, weight: Double)` via one batch fetch of `Entity` by id set, the same
  `#Predicate { entityIDs.contains($0.id) }` pattern `chipIndex` already uses rather than one fetch
  per id (this can reuse the same `[UUID: Entity]` map the resolution step above already built,
  rather than fetching twice). An id that resolves to nothing (pruned since the last recount) is
  dropped. This method does not save or bump `revision`; it is a read, like `unsureLinks`, and logs no
  `graph.*` diagnostics event, consistent with `chipIndex`/`unsureLinks` being unlogged reads too.
- `EntityPagePresentation` gains `struct CoOccurrenceRow` and a pure `static func
  coOccurrenceRows(_:) -> [CoOccurrenceRow]` (renaming/passing straight through `GraphServices`'s
  `CoOccurrence` list; kept as a separate presentation type so the view layer never imports
  `EntityGraph` directly, matching how `EntryRow`/`MergedRow` already sit between the raw fetch and
  the view, `EntityPagePresentation.swift:87-94,166-178`).
- `EntityView` gets a "Mentioned with" section, alongside `entriesSection`/`mergedInSection`
  (`EntityView.swift:352-433`), one row per `CoOccurrenceRow` (name, kind icon reusing the existing
  per-kind table extended in Phase 1, no weight number shown, weight is ordering only), each a
  `NavigationLink(value: EntityRoute(id:))` into the same stack. `entriesSection`/`mergedInSection`
  are `@Query`-backed computed properties and refresh for free on any SwiftData change; `mentionedWith`
  is a fresh, uncached fetch over the whole link table, not something to recompute on every body
  re-evaluation. The new section instead follows `ConnectionsView`/`MergeIntoView`'s pattern
  (`ConnectionsView.swift:117`, `MergeIntoView.swift:67`): a `@State private var coOccurring:
  [CoOccurrenceRow] = []`, populated by `.task(id: graph.revision)` calling `graph.mentionedWith` once
  per revision bump, not a plain computed property. Empty section (no co-occurring entities yet, or
  not yet loaded) is hidden entirely, not a placeholder row, matching how `mergedInSection` already
  hides itself when there is nothing to show.

**Steps**, each committed and pushed on its own with the unit suite green:

- [ ] 6.1 `Mindlore/Graph/EntityGraph.swift`: `LinkInput`, `Edge`, `build`, `neighbourhood`,
      `filtered`, `defaultHalfLife`. No SwiftData import.
      Test file `EntityGraphTests.swift`, styled like `EntityMatcherTests.swift` (plain `struct`, no
      `@MainActor`, no `ModelContainer`, hand-built `LinkInput`/`Edge` fixtures):
      - Two entities sharing one entry produce one edge at weight 1.0 when `asOf` equals `entryDate`.
      - An entry aged exactly one half-life produces weight 0.5; two half-lives, 0.25.
      - Three entities in one entry produce three edges (every pair), each carrying that entry's
        weight.
      - The same pair across two entries sums both entries' weights into one edge.
      - Two `LinkInput`s in the same entry with the same `entityID` (a duplicate after resolving
        merges) do not pair the entity with itself and do not inflate any other pair's weight.
      - An entry with `entryDate` after `asOf` contributes nothing, not a near-zero weight.
      - A single-entity entry (no pair possible) contributes nothing.
      - `Edge(a:b:)` canonicalizes regardless of input order, so building from links in either order
        produces `Equatable`-equal results.
      - `neighbourhood`: depth 0 is empty, depth 1 is direct neighbours only, depth 2 includes a
        neighbour's neighbour but not further, a node with no edges has an empty neighbourhood, and
        `id` itself is never in its own result.
      - `filtered`: drops an edge whose endpoint's kind is outside the given set; keeps all when
        `kinds` is nil; drops an edge whose endpoint's `linkCount` is under the minimum; drops an
        edge with an endpoint missing from `nodes` instead of crashing.
- [ ] 6.2 `GraphServices.mentionedWith(of:in:limit:)`, resolving hidden/merged entities through
      `editor.root(of:)` and `Entity.isBrowsable` before building `LinkInput`s, batch-fetching names
      and kinds for the result.
      Test (`GraphServicesTests`, SwiftData harness like `GraphIndexerTests`'s
      `ModelContainerFactory.make(.inMemory)` pattern): two entries mentioning the same two people
      produce a co-occurrence edge between them found by `mentionedWith`; a hidden entity never
      appears as a co-occurrence partner even though its links still exist; a merged-away entity's
      co-occurrences show up under the winner's id; results are ordered by weight; `limit` caps the
      list; an entity with nothing to co-occur with returns an empty list, not an error.
- [ ] 6.3 `EntityPagePresentation.CoOccurrenceRow`/`coOccurrenceRows(_:)`; `EntityView` "Mentioned
      with" section.
      Test (`EntityPagePresentationTests`): rows preserve `mentionedWith`'s order; an empty input
      gives an empty list (the view hides the section on empty, no separate presentation flag
      needed since the list itself is the signal).
- [ ] 6.4 Sub-agent review of the whole phase; fix what it finds.

**Not in scope, this phase:** the depth control, kind toggles, minimum-count slider, and time
scrubber UI (Phase 7 wires these to `neighbourhood`/`filtered`, this phase only builds and tests the
functions); `GraphSimulation` and any rendering; caching or incrementally updating the computed graph
(the existing "Recount cost" risk note, plan line 1008-1010, already covers the O(links) budget this
reuses); showing edge weight as a number anywhere in the UI.

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

### Measured before Phase 5 (2026-09-16, iPhone 17 simulator, Debug)

- **The live model completes names it is told not to.** With 50 journal names in the prompt,
  gpt-5.6-luna wrote "Sarah Kim" for an entry that said "sarah". Names are now grounded in the
  entry text after parsing. Live: a garbled "sara kym" still becomes "Sarah Kim", none of 48 decoy
  names is invented, and the list costs about 590 input tokens a request.

- **First launch of a large journal shows a loading screen (owner decision).** The launch sweep
  indexes in chunks of 100 and yields between them; with 200 or more entries to index, an opaque
  "Organizing your journal" screen shows progress until it is done. A real launch on a
  3,000-entry store took 27 s this way (10.7 s in the unit test, 119 s before the sweep shared one
  fetch per chunk); the 300-entry fixture takes under a second and shows nothing. The screen
  appears at once rather than fading in, because a fade stalls behind the first chunk. Before any
  of that, the app itself takes about 2 s to draw its first frame on a 3,000-entry store, which is
  existing startup cost, not the graph. Phase 8 measures both on the phone.
- **Every launch pays for repair.** With nothing stale, the sweep still recounts and clears
  stranded links: about 150 ms at 300 entries, and the recount alone is 340 ms at 3,000.
- **The backfill leaves duplicates for Review, by design.** On the fixture, "Marcus" and
  "Marcus Webb" stay apart because the bare name was indexed before the full one existed, and then
  matched itself; 7 suggestions come out of 300 entries. An entity keeps the first spelling seen,
  so "mom" can be lowercase. Worth deciding in Phase 5 whether a display name should prefer a
  capitalized variant.

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

Phase 5a build (sub-agent review of `1d5a465..3ead125`, 2026-09-16, verdict "approve with
fixes"; 8 findings, all fixed in the commit after 5a.5). Privacy, stamping, the post-await
checks, and the route replacer were confirmed sound.

1. "This is someone else" with the alias switch offered to merge the two entities the user had
   just separated: a collision with the entity the mention came from is now `aliasStaysWith`,
   reported without a merge offer.
2. `MergeIntoView` ran the all-pairs matcher on every render: `EntityMatcher.likelySame` scores
   one entity against the rest, once per search or graph change.
3. The collision check let `other` meet tags and themes, unlike the resolver: it uses the
   resolver's label rule.
4. A merged entity's page offered Draft, and tapping it (or a failed resolve) cleared the
   user's "cleared bio" flag: Draft is hidden on merged pages, and the flag changes only once a
   request can go out.
5. An automatic draft resent after a permanent failure on every appearance: it waits for Try
   again.
6. A chip found by key but repointed by exact surface said "This mention changed": chips carry
   the link's own surface.
7. `cancelDrafts` and the gone-route path claims did not match the code: the spec now says what
   the code does; `register`'s plain save is commented.
8. Tests added: unapproved photo entries excluded, cancellation logs nothing, and one per fix.

Phase 5a plan (sub-agent review of the spec, 2026-09-16, verdict "approve with fixes"; 20
findings, all folded into the Phase 5a spec before building): excerpts limited to text the
provider already received; several chips in one row firing together; double pushes and Undo
flipping a redirected page; a cleared bio being redrafted (`bioEditedByUser`); duplicate draft
requests (drafts run in `GraphServices`); most editor edits never saving (views flush, services
save); `setKind` collisions and cross-family kinds; optional-UUID predicates; a repoint holding a
link id that regeneration deletes; page and query mechanics; bio error wording; auto-draft limited
to mention kinds; the automatic send gated and disclosed; hidden chips and kind-aware lookup; the
view recount flows made testable; one `GraphServices` instance; a shared text generator; more
tests; merging into a hidden entity; 5a.3 split and the privacy test moved into 5a.2.

Phase 4 (sub-agent review of `3334c58`, 2026-09-16, verdict "needs rework"; 11 findings):

1. "Use this exact name" made the model complete "sarah" to "Sarah Kim", bypassing the user's
   corrections and the first-name guess: names are written as the entry writes them, and the list
   only fixes spelling. The live test now asserts that instead of the opposite.
2. The tag fallback ran whenever the list was empty, so hiding every tag re-sent them: the graph
   returns nil only when it has not been built, and switched-off sections skip the fallback.
3. The fallback was listed as tested and was not: three coordinator tests now cover it.
4. User-typed names reach the provider: recorded as an assumption above, and said on screen.
5. The disclosure screen showed today's vocabulary and fetched on every render: it shows counts
   stored when the request was built.
6. Listing every kind froze unsettled `other` entities: those go without a kind, and the type is
   `MentionKind?` so tags and themes cannot be listed as names.
7. Names were not cleaned: one line, 60 characters, blanks and repeats dropped, one per line.
8. Order starved new names: seven in ten by use, the rest by recency.
9. Every request fetched every entity: bounded fetches per list, none for switched-off sections.
10. Integration, hidden person and theme, odd names, and switched-off sections are tested.
11. The `plan` default is gone, the counts are in `insights.started`, and the redundant
    `nonisolated` markers are removed.

Phases 2 and 3 (sub-agent review of `8343786` and `cfcd532`, 2026-09-16, verdict "needs rework";
12 findings; fixed in the commit after Phase 4 unless noted):

1. Reindexing a merged entry dropped the links' birthplaces, making the merge permanent: `index`
   carries `originalEntityID` across the rebuild.
2. The sweep returned before counting and cleanup whenever nothing was stale, which is always in
   steady state: it now repairs counters and clears stranded links on every launch.
3. A merge chain handed deeper losers' names up to the intermediate, so unmerging both left two
   live entities with one key: each alias has one owner, and flattening moves it.
4. `removeInsights` chose links through `entityLinks`: it deletes by `entryID`, and the insights
   screen recounts.
5. `GraphEditor` saved without the stamping rule: every save exempts the entries whose links moved.
6. Changing a kind kept the old key, though keys are kind-sensitive: both paths re-key.
7. Pruning can delete an entity a page is showing: a Phase 5 constraint, recorded above.
8. A mention typed `other` could join or convert a tag or theme: labels only match their own kind.
9. A re-pointed link kept the guess marker, and its alias was saved late: both fixed.
10. Weak tests: the hiding test passed for the wrong reason (and hidden entities could in fact be
    pruned; they no longer can), the merge-loser test hand-rolled a merge, orphan cleanup was never
    reached, the privacy test skipped every editor event, and claims across kinds, a vanished
    surface, and the ambiguity event were untested. All covered now.
11. Views build `GraphIndexer` inline instead of receiving it: deferred to Phase 5, which is where
    the view wiring gets designed.
12. The matcher ran a filter inside its sort; `register` saved when it had nothing to do. Fixed.

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
