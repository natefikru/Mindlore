# Mindlore Phase A: an app a journaler would actually use

Branch: `feature/phase-a` from `main` at `1e87b05` (PR #3, the knowledge graph, merged). The graph
plan and its review history are archived in `tasks/archive/knowledge-graph.md`.

Status: revision 2, awaiting the owner's approval. Nothing below is built. Revision 2 folds in
the sub-agent review of revision 1 (12 findings; see "Review log").

## Why

The engineering under the app is sound. Entries, transcription, insights, entity resolution,
merges, and co-occurrence all work and are tested. The app on top of them still feels like a
developer's test bench. The graph is five taps deep and barely reacts once it's open. Themes are
unique to each entry, so they never connect to anything. Loose ends get generated and then nobody
reads them again. There's no way to ask the journal a question.

Phase A rebuilds the experience around three moments: capturing an entry, wandering through your
life on a map, and asking your journal something.

## Ground rules

- **No backwards compatibility.** Nothing has shipped. Old fields, enum cases, and screens get
  deleted outright, with no migration code. The phone gets a fresh install (delete the app first)
  before the first Phase A build, which wipes the entries on it.
- **CloudKit rules still apply** to every new model: every stored property optional or defaulted,
  nothing `@Attribute(.unique)`. `CloudKitSchemaRulesTests` covers each new model.
- **Privacy rules still apply.** Diagnostics carry IDs, counts, and durations only. Every new event
  gets a case in `DiagnosticsPrivacyTests`.
- **No advice.** Ask answers and loose-end prompts observe and quote. They never counsel.
- **There's no CI.** The check after every push is the local unit test run (the CLAUDE.md command),
  plus the UI tests for the sub-phase being built.

## Owner decisions (2026-09-17 brainstorm)

1. **Themes are removed.** Nine fixed **life areas** replace them: Work, Money, Health, Mind,
   Family, Love, Friends, Play, Home. The model picks one or two per entry from that closed list.
   Areas are not entities or graph nodes. The user can rename or hide an area but can't add one.
2. **Loose ends persist.** An open thread lives across entries and closes when a later entry
   settles it. It fades if it goes quiet. The generation bar is high: few threads, concrete ones.
3. **Tabs: Journal, Mind, Ask.** Record lives in the bottom accessory above the tab bar, reachable
   from every tab. Settings is a gear on Journal.
4. **Mind is the graph plus a search panel.** The graph fills the screen, and the panel (people,
   places, projects, tags, the area tiles, search) is a panel dragged up from the bottom, like
   Apple Maps. Connections, the global graph screen, and the local graph sheet go away.
5. **One shared peek card.** Tapping a name anywhere (a graph node, a search result, a name in an
   entry) shows the same small card. Swiping up opens the full page.
6. **Entries open for reading.** Past entries open read-only with names highlighted and tappable.
   Edit switches to typing. New entries and drafts open straight into typing.
7. **The graph has to feel alive** or the Mind tab fails. The simulation stays warm while touched,
   dragging pulls neighbours along, focus dims everything else, and labels respond to zoom.
8. **Ask combines search and chat.** Typing shows instant matches. Asking sends the relevant
   entries to the AI, and the answer cites them.
9. **Reflect comes later** (weekly recaps, area balance, mood over time) as its own phase after A.
10. **3D gets a spike** at the end of Phase A, judged on the device against the improved 2D graph.

## What the research found

Three read-only surveys of the code (2026-09-17). The findings that shape the plan:

- **Themes** reach about 57 test references and these code paths: `EntityKind.theme`
  (`Entity.swift:7`), the tag/theme label rule (`EntityResolver.swift:74,91`,
  `GraphEditor.swift:54-58`, `EntityMatcher.swift:59-73`, `RepointView.swift:139-140`), the indexer
  (`GraphIndexer.swift:255-266,407`), the prompt (`InsightsPromptBuilder.swift:7,16,40,49,60,62,73,
  118-123,192,265`), settings (`SettingsStore.swift:24,126,178`, `AIServices.swift:66`,
  `AIFeatureSettingsViews.swift:180`), storage (`EntryInsights.swift:17,27`), the coordinator
  (`InsightsCoordinator.swift:159,199,207`), views (`EntryInsightsView.swift:197-206,259,311-319,
  340`, `InsightCards.swift:34,48,62,77`), and the UI stub (`UITestingHTTPClient.swift:29`).
- **Open threads** are plain strings (`EntryInsights.swift:20`) with no cap and no quality bar
  (`InsightsPromptBuilder.swift:156-158`). Each regeneration overwrites them
  (`InsightsCoordinator.swift:202`), and one card reads them (`EntryInsightsView.swift:222-226`).
- **The insights request** sends the entry text plus a system prompt with the mood list, known
  tags and themes, and up to 50 known names (`InsightsPromptBuilder.plan`, vocabulary from
  `GraphIndexer.vocabulary`, wired at `RootView.swift:52`). The write path calls
  `onInsightsWritten` (the graph indexer) before its save at `InsightsCoordinator.swift:232`.
  Moods are the closed-vocabulary pattern to copy (`Mood.swift`, parsed at
  `InsightsPromptBuilder.swift:258-264`).
- **The graph goes still** because `GraphSimulation.tick()` stops once `alpha` decays
  (`GraphSimulation.swift:123,143`). Pins never reheat it, and `TimelineView(.animation(paused:
  settled))` stops redrawing (`GraphCanvasView.swift:34`). Repulsion and collision are O(n²) and
  run on the main actor inside the draw closure. Node and edge sets are `let`, so every filter
  change rebuilds from scratch. Edges are one uniform grey path. Labels are a fixed top 12.
  Selection adds a thin stroke only.
- **The shell.** `RootView.swift:85` shows `EntryListView()` with all environment and lifecycle
  modifiers on it, so a `TabView` can take its place. `RecordingView` owns its `AudioRecorder`
  (`RecordingView.swift:13`) and blocks dismissal while recording, so recording across tabs needs
  a session object owned by `RootView`. The editor is always editable, and its close rules run in
  `onDisappear` unless `isPresentingOverEditor` (`EntryEditorView.swift:162-165,300`). Entity chips
  live only in the insights sheet (`InsightCards.swift:243`).
- **UI tests tied to today's navigation:** `GraphUITests` and `GraphScreenshotTests` (the
  Connections button). `newEntryButton`, `newVoiceEntryButton`, `newPhotoEntryButton`, and "No
  entries yet" are used across most UI tests and must keep their identifiers.
- **AI calls are single-turn.** `TextRequest` carries one system and one user message, has no
  streaming, and supports strict JSON schemas on OpenAI. Foundation Models ignores schemas and has
  about 4k tokens. There's no search over entry text anywhere. `BioExcerpts`,
  `GraphServices.resolvedLinks`, `mentionedWith`, and `NameMatching` are the retrieval building
  blocks.

## Key decisions

### Life areas

- `LifeArea` is a `nonisolated enum: String, CaseIterable, Codable, Sendable` in `Models/`, built
  like `Mood`. Cases: `work, money, health, mind, family, love, friends, play, home`. Each has a
  default name, a one-line meaning (used in the prompt and in Settings), an SF Symbol, and a
  colour.
- Stored as `EntryInsights.areasRaw: [String] = []` with a computed `areas`. Parsing drops unknown
  values, removes duplicates, and caps at 2.
- **Prompt:** a required array field with `enumeration(LifeArea.allCases)`, and guidance listing
  each area's meaning. Two rules:
  - Pick one, or two only when the entry is clearly about both.
  - Pick Mind only when the entry is about the writer's inner life itself, not because it's
    written reflectively.
  The model always sees the raw values, never the user's renames.
- **Settings:** a `lifeAreas` insights section toggle, plus per-area `displayName` and `hidden`
  stored through `SettingsStore`. A hidden area is left out of filters and chips. The model still
  gets asked for it, so un-hiding an area brings back its old assignments.
- **Distribution check:** a Debug-only Settings row, "Life areas: distribution", shows the
  percentage per area. A Debug-only "Regenerate insights for every entry" action exists so the
  owner can run the split/merge test (above ~40% split, below ~3% merge) on a real journal. It
  runs oldest `entryDate` first, so loose ends are created before later entries resolve them.
- **Old stores:** no compatibility. `SchemaMigrationTests` and its v1/v2 fixture stores are
  deleted in A1, since opening old stores is no longer a goal.

### Loose ends

A new model, `LooseEnd`. "Loose end" is the user-facing name, and code uses the same name.

```swift
@Model final class LooseEnd {
    var id: UUID = UUID()
    var text: String = ""
    var createdAt: Date = Date.distantPast       // the source entry's entryDate, not the clock
    var sourceEntryID: UUID?          // the entry whose insights created it
    var sourceEntryDate: Date = Date.distantPast
    var entityIDs: [UUID] = []        // as resolved at write time; read through mergedIntoID
    var dueDate: Date?                // "interview on Friday"
    var statusRaw: String = "open"    // open, resolved, faded, dismissed
    var resolvedByEntryID: UUID?
    var statusChangedAt: Date?
    var lastMentionedAt: Date = Date.distantPast // entryDate of the latest entry that mentioned it
    var promptedAt: Date?             // last time the recorder asked about it
    var userTouched: Bool = false     // dismissed or resolved by hand
}
```

**Creating fewer** (the owner's favourite part):
- New loose ends must be concrete and something a later entry could settle: waiting on someone,
  an unmade decision, an upcoming event. Feelings and "think more about X" never qualify.
- At most 2 per entry, and the prompt says zero is the normal answer.
- The request includes **known open loose ends** as short handles (`L1`...`Ln`, mapped to IDs
  locally, never sent as UUIDs), capped at 15:
  - open loose ends linked to any entity whose name or alias appears in the entry text
    (`NameMatching`, before the request)
  - then the most recently mentioned open ones, to fill the cap
- **Schema:**
  - `looseEnds`: `[{text, about: [name], due?: date, sameAs?: handle}]`
  - `resolved`: `[handle]`
  - Unknown handles are dropped, the same way unknown moods are.
  - `sameAs` never creates a new loose end. It bumps the existing one's `lastMentionedAt`.

**Which loose ends go in the request:**
- Only loose ends whose source entry is dated earlier than this entry, so an old page can't settle
  a newer loose end.
- This entry's own earlier loose ends (any status) are sent as `sameAs` candidates only. The
  parser never accepts them in `resolved`. Regenerating an entry then reuses its loose ends
  instead of duplicating them, and can't resolve itself.
- The model gets the entry's `entryDate` as the reference date for `due`.
- The request records `sentLooseEndCount` next to the other `sent*Count` fields, and "What was
  sent" shows it, since this is text from other entries.
- Foundation Models gets at most 5 candidates.

**Writing:** `LooseEndWriter` runs inside `InsightsCoordinator`'s write path, right after
`onInsightsWritten` (so the entry's links exist), in the same save.
- **After the await, every handle is fetched again by ID.** Missing ones are skipped. A loose end
  that is `userTouched` or no longer open is never changed.
- `about` names map to entity IDs through a fetch of `EntityLink` by `entryID` that skips deleted
  links (the `GraphIndexer.allLinks` pattern), never through the relationship. Names are matched
  against surface, `writtenSurface`, and aliases. Names that don't match are dropped.
- **Dates:** `createdAt`, `sourceEntryDate`, and `lastMentionedAt` come from the entry's
  `entryDate`. A loose end written from an entry older than 42 days is created already faded, so
  photographing an old journal never produces stale prompts.
- **Rollback** is one function, `LooseEnd.rollback(forEntryID:)`:
  - loose ends the entry resolved (not `userTouched`) reopen
  - loose ends it created that are still open and not `userTouched` are deleted
  - loose ends it only bumped keep their date, which is harmless
- **Rollback runs at the two choke points** every path already goes through:
  - `Entry.delete`, which covers the list, `editorDidClose` on a blank entry, and
    `PageOrderView`
  - `removeInsights`, which covers deleting insights and `restartPages`
- Regeneration calls rollback first, then applies the new result.

**Merges and pruning:** `entityIDs` is never rewritten. Every reader (search panel counts, the peek card,
the `EntityView` section, prompt candidates) resolves each ID through `mergedIntoID` with the
cycle guard, using the one in-memory entity map the Graph section of CLAUDE.md describes. IDs
with no `Entity` are ignored for grouping, but the loose end still shows on its source entry's
card.

**Fading** (`LooseEndLifecycle`, a pure function over `now`):
- An open loose end not mentioned for 42 days becomes faded.
- A dated one becomes faded 7 days after its due date if still open.
- Runs in the launch lane after the graph sweep, and before a prompt is picked.
- Faded is a normal outcome. Nothing is deleted.

**Closing:**
- A later entry's `resolved` closes a loose end and sets `resolvedByEntryID`.
- Swiping on a loose end offers "Done" (resolved by hand) and "Let go" (dismissed).
- There are no badges and no counts on tabs.

**Prompting:** `LooseEndPrompter.next(now:)` picks at most one:
- first, a dated loose end that is past due and never prompted
- otherwise, the most recently mentioned open one not prompted in the last 3 days

The recorder shows it as one line. Showing it sets `promptedAt`. Recording after a prompt changes
nothing on its own; the next insights run decides whether the loose end got settled.

**Settings:** the `insightOpenThreads` key becomes `looseEnds`, and `EntryInsights.openThreads` is
deleted.

### Graph engine

The goal is a graph that stays warm and changes in place. At 300 nodes, all-pairs physics costs
about 45k pair checks per tick, well under a millisecond. The likelier frame cost is label and
symbol work in the draw closure. So the simulation stays on the main actor until a device
measurement says otherwise.

- **`GraphSimulation`:**
  - gains `alphaTarget` (default 0, so today's settle tests still hold) and `reheat(to:)`
  - dragging sets `alphaTarget = 0.3` and releasing sets it back to 0, which is d3's pattern and
    how Obsidian's graph feels
  - `update(nodes:edges:)` replaces the sets in place: surviving IDs keep position and velocity,
    new nodes start near a linked neighbour (phyllotaxis only when they have none), and it reheats
    to 0.3
- **Redraw:** `TimelineView` stays unpaused while `alpha` is above the minimum or a gesture is
  active, and pauses 2 seconds after both stop.
- **Canvas drawing:**
  - focus dims non-neighbours to 15% and brightens the focused edges
  - edge width comes from weight, and opacity from recency (the 90-day decay already in
    `EntityGraph`)
  - glow is a pre-rendered symbol, not a blur filter
  - the label budget scales with zoom (12 at 1x, more when zoomed in, fading by rank)
  - the neighbourhood and label set are computed when focus or zoom changes, never per frame; this
    also removes the `@State` write inside the draw closure
- **Camera:**
  - animated `flyTo(id)` centres a node at a readable zoom, used by focus, and search results
  - edge hit-testing uses distance to the segment, with a 10pt tolerance
  - haptics on focus
- **Measurement gate:**
  - `graph.rendered` becomes "first settle", with a frame-time sample (p50 and p95 over 5 seconds
    of interaction) and the node count, logged once per appearance
  - if p95 is above 20 ms at 300 nodes on the iPhone 17 Pro, sub-phase A3b runs (below)
  - otherwise the simulation stays on the main actor and Canvas stays
- **A3b, only if the gate fails, in this order, measuring after each step:**
  1. A deterministic Barnes-Hut quadtree (theta 0.9). Convergence tests are re-tuned if the
     forces shift.
  2. A `GraphEngine` `actor` that owns the simulation, with the latest positions in a `Mutex`
     that the Canvas reads without observation. Pushing 60 Hz snapshots through an
     `@Observable` would invalidate every view that watches it. Tests step it with an injected
     clock, and only the simulation itself is claimed to be deterministic.
  3. A SpriteKit (`SpriteView`) renderer reading the same positions.
- **Region force** (the optional anchor pull for area regions) moves to A5b along with the other
  map extras.
- **Demo journal:** a Debug-only launch argument `-seedDemoJournal <n>` builds `n` entries with
  hand-written insights (moods, areas, tags, mentions) and runs them through the real
  `GraphIndexer`. It calls `LooseEndWriter` directly for loose ends. It always uses its own named
  file store (`StoreLocation.file`, the `-uiTesting` mechanism), so the owner's real journal and
  the 300-node seed can live on the same phone. Every UI sub-phase and the 300-node measurement
  use it.

### Shell and tabs

- **`RootView`:**
  - shows a `TabView` with `Tab("Journal")`, `Tab("Mind")`, `Tab("Ask")`
  - every existing environment, lifecycle, and lane modifier moves onto the `TabView` unchanged
  - `GraphIndexingOverlay` stays on top
- **`AppRouter`** (new, `@Observable`, owned by `RootView`) owns the selected tab, Journal's path,
  and Mind's path. Every cross-tab jump goes through it: a finished recording, an Ask citation,
  "Show in Mind", and a peek card's entry link. A jump dismisses any open sheet first, then
  replaces the target path instead of appending, so a finished recording never lands on top of
  another open editor.
- **The editor's close rules move off `onDisappear`.** Today `EntryEditorView` runs `close()`
  whenever it disappears (`EntryEditorView.swift:162-165`). A tab switch, the expanded recorder,
  and "Show in Mind" would all trigger that while the entry is still open: presence closes, a
  blank entry is deleted, and the AI pass fires. Instead, the rules run when the entry leaves
  Journal's path. `AppRouter` observes the path, and the editor's own Done and back actions go
  through the same call. `isPresentingOverEditor` stays for sheets. `EditorPresence` stays open
  while the entry is on the path, even on another tab, so cleanup and `onTextReady` still defer
  to it.
- **`RecordingSession`** (new, `@Observable`, owned by `RootView`, in the environment):
  - owns `AudioRecorder`, the live transcription session, the feed task, the start task
    (including today's `CancellationError` handling in `RecordingView`'s `.task`), and the level
    meter the waveform draws
  - `AudioRecorder` gets a small protocol so tests can drive the session with a fake
  - exposes start, stop, discard, elapsed time, levels, live text, and state
  - `RecordingView` becomes a view of the session, and closing it while recording minimizes it
    instead of blocking; discard stays reachable from the minimized state
  - finishing still ingests through `RecordingIngestor`, then routes to the entry through
    `AppRouter`
- **Bottom accessory** (`tabViewBottomAccessory(isEnabled:)`, iOS 26.1+):
  - idle: a Record button, keeping the `newVoiceEntryButton` identifier
  - recording: a live timer and level tick, and tapping expands the recorder
  - it holds no state of its own, because the system can render it in both the inline and
    expanded placements
  - the recorder shows `LooseEndPrompter`'s line above the record button when there is one
  - **A4 opens with a device check** of the accessory's behaviour under sheets, full-screen
    covers, and a custom bottom panel, before anything is built on it
- **Journal tab:**
  - keeps today's list, the Settings gear, `newEntryButton`, and `newPhotoEntryButton`
  - the Connections button is removed
  - rows show area chips
  - a filter row of area chips sits above the list, using hidden areas and display names from
    settings

### Mind tab

- **`MindView`:**
  - the warm global graph, full screen
  - a custom draggable bottom panel (not a system sheet, which would cover the tab bar and the
    accessory) with three stops: peek (search field only), half, and full
- **The search panel** (no brand name; its field reads "Search people, places, tags"):
  - search field, filtering and flying to the first match on submit
  - the nine area tiles (a tap highlights that region and dims the rest; a second tap clears it)
  - segments: All, People, Places, Projects, Tags (All also includes organizations and events)
  - rows show the name, last mentioned, and open loose-end count
  - one review question card at most, above the rows, taken from today's "likely the same" and
    "Which one?" sources and answered with one tap
  - a Hidden section at the bottom
- **Focus loop:**
  - tapping a node or a search result focuses it (fly-to, dimming, panel drops to peek) and shows the
    peek card
  - tapping a neighbour moves focus, and a breadcrumb chip row lets you step back
  - tapping empty space clears focus
- **Lenses** (a toolbar menu):
  - kind colours (default)
  - mood tint: the average mood category of linked entries, labelled "Mood around"
  - recency: glow for mentions in the last 30 days
- **Controls:** a filters menu (kinds, minimum mentions, show entries as nodes) that calls
  `update`, so there's no rebuild.
- **Replay:** a play button animates `asOf` from the first entry to today over about 10 seconds,
  calling `update` per step. Links are fetched once when replay starts and filtered by date in
  memory, never through `globalGraph`'s full fetch on every step.
- **Split:** the focus loop, the search panel, and the peek card are A5. Lenses, replay, entries as nodes, and
  area regions are A5b, built once A5 feels right on the phone.
- **Entries as nodes:** small grey dots linked to their entities. Tapping one opens the entry in
  read mode.
- **Deleted:** `ConnectionsView`, `GlobalGraphView`, `LocalGraphView`, and
  `ConnectionsPathItem`. `ConnectionsPresentation`'s name filter moves to an `EntitySearch` type
  that the search panel and Ask's entity search both use. The entity page's Graph action becomes "Show in Mind" (switch tab,
  focus). The `entityRouteReplacer` pattern stays for the Mind tab's own stack.

### Peek card

- **`EntityPeekCard`**, one view used everywhere:
  - name and kind
  - the bio's first line
  - last mentioned
  - entries in the last 30 days
  - the most recent open loose end
  - an "Open" affordance
- It reuses `EntityPagePresentation.resolve` and the bio state from `EntityView`. It never
  triggers an automatic bio draft; only the full page does.
- **Presentation:**
  - in Mind, it's an overlay above the panel, and swiping up pushes `EntityView` onto Mind's stack
  - elsewhere, it's a sheet with `.height(220)` and `.large` detents. The sheet has its own
    `NavigationStack` and sets `entityRouteReplacer`, per the CLAUDE.md rule, and "Open" pushes
    `EntityView` inside it
  - only a pushed `EntityView` calls `pageOpened`, so the card alone never starts a bio draft
- **`EntityView`:**
  - gains a "Loose ends" section (open first, then resolved and faded, collapsed)
  - "Mentioned with" stays
  - the Graph action becomes "Show in Mind"

### Read mode

- `EntryEditorView` opens in **read mode** unless the entry is new, a draft, awaiting text,
  waiting for page text review (`textReviewPending`), still offering Done
  (`AIPassTrigger.offersDone`, which covers a recording with live text), or has an empty body.
- **Read mode:**
  - shows the title, header, and a `Text(AttributedString)` of the body
  - entity names get link attributes (`mindlore-entity://<uuid>`), handled by an `OpenURLAction`
    that shows the peek card
  - name ranges come from the entry's links (surface, `writtenSurface`, and the entity's
    aliases) found with `NameMatching.ranges`, preferring the longest match when ranges overlap
- **Edit** (a toolbar button) switches to `GrowingTextEditor` with the cursor at the end, and Done
  returns to read mode. Nothing about saving changes: typing still goes through
  `EntrySaver.noteChange()`.
- The peek sheet is added to `isPresentingOverEditor`, so it never triggers the close rules.
- The UI tests that type into existing entries tap Edit first. New-entry tests are unchanged.

### Ask tab

- **Search as you type** (no AI), grouped results for entries, entities, and tags:
  - entries: `#Predicate` with `localizedStandardContains` on `text` and `title`, newest first,
    capped at 30
  - entities: the name and alias match from today's Connections search
  - tags: exact tag values
  - tapping an entry opens it in read mode, and tapping an entity shows the peek card
- **Ask** (the send button):
  - `AskContextBuilder`, a pure function over fetched values, fills a character budget (24k, a
    constant) in priority order:
    1. entities named in the question (`NameMatching` against names and aliases): their bio, open
       loose ends, and `BioExcerpts` sentences from their 10 most recent linked entries
    2. entries matching the question's keywords (stop words removed), most recent first
    3. entries from a date range named in the question ("last week", "in March", via
       `NSDataDetector` plus a small relative-date parser)
    4. the 5 most recent entries, if room remains
  - each entry is sent as `[E1] <date> <title>` followed by its text inside a delimited block,
    with handles mapped locally
- **What Ask may send:** only entries that pass `InsightsCoordinator.canRunAI` (never drafts,
  entries awaiting text, or unapproved page text). By default, entries created before
  `aiEnabledAt` are not sent either, which is the same boundary transcription keeps
  (`TranscriberRouter.swift:35`). A switch in Ask's settings ("Include entries from before AI was
  on") lifts that, with a line saying what it means.
- **Journal text is data, not instructions.** The system prompt says so, and entries sit inside
  delimiters. Answers render with `Text(verbatim:)`, so an injected markdown link can never reach
  an `OpenURLAction`. Only citations handed out in this conversation are accepted.
- **Multi-turn:**
  - `TextRequest` gains `messages: [TextMessage]` (role and content), defaulting to empty, and
    `OpenAICompatibleTextGenerator` sends it between the system and the new user message
  - history keeps only question and answer text, capped at the last 6 turns
  - handles stay stable for the whole conversation (entry ID to handle), so `[E3]` means the same
    entry in every turn
  - Foundation Models ignores `messages`, so its request folds the previous question and answer
    into the user prompt
  - a context overflow maps to `AIError.contextTooLong` with its own message
- **Saved conversations, like Claude** (owner decision, 2026-09-17):
  - the Ask tab always opens on a new, empty conversation
  - a history button lists past conversations, newest first, titled by their first question;
    tapping one reopens it and you can keep asking
  - swipe to delete a conversation
  - a conversation is saved once its first answer arrives, so an empty chat never clutters the
    list
  - models: `AskConversation` (`id`, `createdAt`, `updatedAt`, `title`) and `AskMessage` (`id`,
    `conversationID`, `index`, `roleRaw`, `text`, `citedEntryIDs`, `handleMapData`), linked by
    ID like `EntityLink`, all properties defaulted, with `CloudKitSchemaRulesTests` cases
  - the handle map is stored with the conversation, so a reopened conversation keeps `[E3]`
    pointing at the same entry
  - a citation whose entry was deleted shows as "Entry deleted" and can't be tapped
  - the stored text stays on the phone; diagnostics still log counts only
- **Answer schema:**
  - `{answer: string, citations: [handle]}`
  - unknown handles are dropped
  - Foundation Models gets the same prompt, asking for `[E3]` inline markers, which are parsed out
  - Foundation Models is used only when it's the selected text provider, with a 6k-character
    budget
- **System prompt:**
  - answer only from the provided entries
  - say so when they don't cover the question
  - quote briefly
  - no advice, no diagnosis
- **UI:**
  - message bubbles
  - citation chips under each answer, opening the entry in read mode
  - "What was sent" per answer, showing counts and the entry list
  - errors use the existing `AIError` wording
- **Diagnostics:** `ask.answered` with entry count, citation count, character count, duration, and
  provider kind. Never the question or the answer.

### 3D spike

- A Debug-only `Mind3DSpikeView` reached from Settings: a `RealityView` with sphere entities,
  billboard text labels, one-finger orbit, pinch zoom, and idle auto-rotate, fed by a 3D variant
  of the engine (`SIMD3`).
- It's time-boxed to the sub-phase. The deliverable is a device comparison written into the
  review log, and the spike's code is deleted unless the owner picks 3D.

## Phases

Each sub-phase is one logical unit:
1. build it
2. add tests
3. run the unit tests (plus that sub-phase's UI tests)
4. commit with `gh`
5. push

The draft PR opens after A0 is pushed. Sub-phases that change a prompt run `OpenAILiveTests` with
the real key.

### A0: Groundwork
- [x] Merge PR #3, branch from main, archive the graph plan.
- [x] `-seedDemoJournal <n>` (Debug only): a deterministic generator of entries with insights,
      indexed through the real `GraphIndexer`, always in its own named store. Tests: it creates
      `n` entries, indexing produces links for them, and it never opens the default store.
- [x] Carry the unrun graph device steps into A9's checklist (below).

### A1: Life areas replace themes
- [x] Delete `EntityKind.theme` and every theme path listed in the research summary. The label
      rule becomes tag-only.
- [x] Delete `EntryInsights.themes` and `sentThemeCount`, `InsightSections.themes`, the
      `insightThemes` setting and toggle, the theme card, and the stub value.
- [x] Add `LifeArea`, `EntryInsights.areasRaw`, the prompt field and guidance, parsing, the
      `lifeAreas` section toggle, and the area card on the insights sheet.
- [x] Settings: area rename and hide. Debug only: distribution readout and "Regenerate insights
      for every entry" (oldest first).
- [x] Delete `SchemaMigrationTests` and the v1/v2 fixture stores.
- [x] Fix the tests that assume eight kinds (`entityKindColorsAreEightDistinctValues`) and the
      graph privacy case.
- [x] The seeder writes areas.
- [x] Tests:
  - theme tests removed or rewritten as tag-only
  - `LifeAreaTests` (list pinned, parsing drops unknowns, dedupes, caps at 2)
  - prompt includes the enumeration and the Mind rule
  - rename and hide persist
  - hidden areas are left out of display
  - privacy test unchanged
  - `OpenAILiveTests` asserts 1 to 2 valid areas

### A2: Loose ends
- [x] `LooseEnd` model, registered in the container, plus a `CloudKitSchemaRulesTests` case.
- [x] Prompt: the known loose-ends block with handles, the quality bar, the cap of 2, and the
      `looseEnds` and `resolved` schema. Settings key renamed to `looseEnds`.
      `EntryInsights.openThreads` deleted.
- [x] `LooseEndWriter` in the insights write path: create, `sameAs`, resolve, re-fetch after the
      await, entity mapping through a link fetch, and dates from `entryDate`.
- [x] `LooseEnd.rollback(forEntryID:)` in `Entry.delete` and `removeInsights`. Regeneration calls
      it first.
- [x] Read-time resolution of `entityIDs` through `mergedIntoID`. `sentLooseEndCount` and "What
      was sent".
- [x] `LooseEndLifecycle` (fading) in the launch lane. `LooseEndPrompter`.
- [x] Insights sheet: the loose-ends card shows status and offers Done and Let go.
- [x] Diagnostics: `looseEnds.written` (created, sameAs, resolved counts), `looseEnds.faded`
      (count). Privacy test cases.
- [x] The seeder writes loose ends across entries, including resolved ones.
- [x] Tests:
  - handles never leak UUIDs
  - unknown handles are dropped
  - cap of 2 enforced even when the model returns more
  - `sameAs` bumps without creating
  - resolve sets `resolvedByEntryID`
  - regenerate reopens and replaces, sparing `userTouched`, and never duplicates a loose end
    that a later entry already resolved
  - an entry never resolves its own loose ends, or loose ends from later-dated entries
  - a handle deleted or marked Done during the request is left alone
  - deleting an entry reopens what it resolved and removes what it created, in the list delete,
    the blank-entry delete, and `removeInsights`/`restartPages`
  - a backdated entry (older than 42 days) creates loose ends already faded, with dates from
    `entryDate`
  - after a merge, the winner's loose-end count includes the loser's, unmerge splits them again,
    and a pruned ID still shows on the entry's card
  - fading at 42 days and due+7
  - prompter order and the 3-day rule
  - candidate selection prefers name matches, capped at 15
  - `OpenAILiveTests`: an entry that settles a known loose end returns its handle in `resolved`

### A3: A warm graph
- [x] `GraphSimulation`: `alphaTarget`, `reheat`, `update(nodes:edges:)`.
- [x] Canvas: the redraw rule, focus dimming, weighted and recency edges, the glow symbol, the zoom
      label budget, the precomputed focus and label sets (no `@State` write in the draw closure),
      edge hit-testing, `flyTo`, and haptics.
- [x] `graph.rendered` redefined (first settle plus frame-time p50/p95).
- [x] `GlobalGraphView` stays wired for now, so the graph can be measured before Mind exists.
- [x] Tests:
  - existing settle, determinism, pin, and spring tests still pass
  - drag reheat keeps alpha above the minimum while pinned and settles after release
  - `update` keeps surviving positions exactly and places new nodes near a neighbour
  - focus and label sets change only on focus or zoom changes
  - edge hit-testing geometry
- [x] **Device gate:** seed 300 nodes and record `graph.rendered` p95. Write the result in the
      review log and decide on A3b.

### A3b (only if the gate fails): performance
- [ ] The three steps from Key decisions, in order, measuring after each: Barnes-Hut, the
      `GraphEngine` actor, then SpriteKit. Stop at the first step that passes.

### A4: Tabs and the record accessory
- [x] Device check first: the accessory under sheets, full-screen covers, and an overlay panel.
      Write the result in the review log.
- [x] `AppRouter` (tab, Journal path, Mind path, jumps). Editor close rules move to "left
      Journal's path".
- [x] `RecordingSession` extracted from `RecordingView` (start task, levels, recorder protocol),
      owned by `RootView`. The recorder minimizes while recording, and discard works from there.
- [x] `TabView` (Journal, Mind placeholder, Ask placeholder). Record accessory with idle and
      recording states.
- [x] The loose-end prompt line in the recorder (after A2's `LooseEndPrompter`).
- [x] Journal: remove the Connections button. Add area chips on rows and the area filter row.
- [x] Tests:
  - `RecordingSession` start/stop/discard with a fake recorder
  - minimizing keeps recording
  - finishing ingests once and routes to the entry, replacing the path
  - switching tabs with an entry open calls neither `presence.close` nor the AI pass
  - popping the entry runs the close rules exactly once
  - the area filter predicate
  - UI tests: recording still produces an entry through the accessory
  - existing identifiers still pass
- [x] Device: record, switch tabs, lock the phone, come back, finish. Siri interruption while
      minimized.

### A5: Mind tab, search panel, peek card
- [ ] `MindView` with the engine, the draggable panel, and the focus loop with breadcrumbs.
- [ ] Search panel: search and fly-to, area tiles with region highlighting, segments, rows, the
      single review card, and the Hidden section.
- [ ] `EntityPeekCard` (overlay in Mind, sheet with its own stack elsewhere), the loose-ends
      section on `EntityView`, and "Show in Mind" through `AppRouter`.
- [ ] The live filters menu (kinds, minimum mentions) through `update`.
- [ ] Delete the Connections, GlobalGraph, and LocalGraph views. Move the name filter to
      `EntitySearch`. Rewrite `GraphUITests` and `GraphScreenshotTests` against the Mind tab.
      `testConnectionsBrowseOpenAnEntryMergeAndUnmerge` already fails before Phase A (checked on
      `6d0735b`): after unmerging Tom from Sarah's page, Tom's row doesn't come back in
      Connections. Find out whether it's a refresh or a data problem, and make the Mind version
      of the test cover unmerge.
- [ ] Tests:
  - search result row data (last mentioned, loose-end count through merges)
  - the review card picks one question and advances after an answer
  - peek card data for merged and hidden entities
  - the card never calls `pageOpened`
  - UI tests: open Mind, search "Sarah", the card shows, open the page, merge from there, and
    the graph refocuses on the winner
- [ ] Device: smoothness by eye with the 300-node seed, focus and breadcrumbs, a filter change
      without a jump, the panel's three stops with the keyboard up.

### A5b: Map extras
- [ ] Lenses: kind (default), mood around, recency.
- [ ] Replay, with links fetched once.
- [ ] Entries as nodes.
- [ ] Area regions: the anchor force in `GraphSimulation`, the area-of-entity rule, and area tiles
      highlighting a region.
- [ ] Tests:
  - the area-of-entity rule (most common area, ties broken by recency)
  - the mood-around average
  - the anchor force pulls toward its point and leaves determinism intact
  - replay issues no fetch per step
- [ ] Device: replay, a lens switch, regions settling into a readable layout.

### A6: Read mode and tappable names
- [x] Read and edit modes in `EntryEditorView`. Name ranges from links. The `OpenURLAction` and
      the peek sheet. Peek added to `isPresentingOverEditor` (moot since A4: nothing closes the
      editor on disappear).
- [x] Tests:
  - name ranges (overlaps, aliases, `writtenSurface`, possessives, a merged entity resolves to
    the winner)
  - which entries open in read mode, including page review and live-text recordings, which don't
  - opening and closing the peek card doesn't run the close rules (the `EditorPresence` and
    `aiPass` fakes see nothing)
  - UI tests: edit an existing entry via Edit, and tap a name to see the card

### A7: Ask
- [ ] Search as you type (entries, entities, tags).
- [ ] `TextRequest.messages` and its OpenAI encoding. `AskContextBuilder` (with the `canRunAI`
      and `aiEnabledAt` filters), `AskService`, the answer parsing for both providers, the chat
      UI with `Text(verbatim:)`, and "What was sent".
- [ ] `AskConversation` and `AskMessage`, the history list, new conversation by default, reopen
      and continue, and swipe to delete.
- [ ] `ask.answered` diagnostics and a privacy test case (sentinel in the question, entries, and
      the answer).
- [ ] Tests:
  - search predicates
  - context budget order and truncation
  - drafts, unapproved pages, and pre-AI entries are never sent unless the switch is on
  - handles stay stable across turns and across a reopen, and only handed-out handles are
    accepted
  - date phrase parsing
  - unknown citations dropped
  - FM marker parsing and the folded previous turn
  - multi-turn encoding
  - a conversation is saved only after its first answer, and a deleted cited entry shows as
    deleted
  - empty journal gives "nothing to go on" without a request
  - `OpenAILiveTests`: a question about a seeded fact cites the right entry
  - UI test with the stub: ask, open history, reopen, and ask a follow-up

### A8: 3D spike
- [ ] `Mind3DSpikeView` (Debug only) with the 3D engine variant.
- [ ] Device comparison against A5's 2D (label readability, tap accuracy, frame time, feel)
      written in the review log. The owner decides. Delete the spike unless 3D wins.

### A9: Privacy, review, device, docs
- [ ] Privacy test covers every new event.
- [ ] Sub-agent code review over the whole diff. Fixes go in separate commits.
- [ ] Device steps, run on a fresh install:
  - Carried from the graph plan:
    - a new voice entry links to an existing person
    - merge two entities and relaunch
    - hide a tag
    - the graph stays responsive at 300 nodes
    - the time scrubber (now replay)
  - New:
    - a real week of entries produces few loose ends
    - a later entry closes one
    - the recorder prompt appears once
    - fading after a clock change
    - the area distribution on the owner's journal
    - Ask with real questions
- [ ] `CLAUDE.md` (Graph section rewritten for Mind, the search panel, the engine, loose ends, areas, Ask),
      `docs/remaining-work.md` (Reflect listed next), and `tasks/smoke-test.md` steps.
- [ ] PR description, marked ready only after the device steps run.

## Not in scope

- **Reflect:** weekly and monthly recaps, area balance charts, mood over time. That's the next
  phase.
- **Semantic search and embeddings.** Ask uses names, keywords, and dates only.
- **Streaming answers**, and searching inside past Ask conversations.
- **Typed relationships between entities** ("works with") and the build plan's weekly bio
  maintenance pass.
- **User-added life areas.**
- **iCloud sync.**
- **The deferred items in `docs/remaining-work.md`** (voice chunk saving, `retryAfter`, and the
  rest).

## Risks and open questions

- **A custom bottom panel** has to handle drag, scroll handoff, and keyboard avoidance for search.
  It's the fiddliest view in the phase. A5 budgets for it.
- **A recording that keeps running while the user browses** exercises interruption and
  route-change handling in new states. A4's device step covers it.
- **Barnes-Hut determinism** depends on a stable insertion order. The tests lock it.
- **Read mode changes a habit.** Tapping an old entry no longer puts a cursor in it. If that feels
  wrong on the phone, the fallback is a long press on names in the editable view.
- **Owner answers (2026-09-17):**
  - The tab is called Mind.
  - A fresh install that wipes the phone is fine.
  - Ask saves conversations and opens a new one by default.
- The pull-up panel in Mind has no name. It's a plain search bar ("Search people, places,
  tags") over the directory.

## Review log

Revision 1 (sub-agent review of the plan, 2026-09-17, verdict "approve with fixes"; 12 findings,
all folded into revision 2):

1. A tab switch, the expanded recorder, and "Show in Mind" would run the editor's close rules on
   an entry still open: close rules now run when the entry leaves Journal's path, and
   `AppRouter` owns cross-tab jumps and replaces paths.
2. Loose-end rollback was hooked to `graph.entriesDeleted`, which takes no IDs and misses two
   delete paths and `removeInsights`: rollback now sits in `Entry.delete` and `removeInsights`.
3. Loose ends used the clock, so an old photographed page would create fresh prompts: dates come
   from `entryDate`, old entries create faded loose ends, and only earlier entries can be
   resolved.
4. Regeneration could duplicate or self-resolve, and the write could race a user's Done: own loose
   ends are `sameAs`-only, handles are fetched again after the await, and links are fetched, not
   walked.
5. `entityIDs` had no merge or prune rule: resolved at read time through `mergedIntoID`.
6. Privacy: loose-end text from other entries is counted in "What was sent", Ask filters with
   `canRunAI` and `aiEnabledAt`, journal text is delimited, and answers render verbatim.
7. Multi-turn Ask: stable handles, text-only history, and a folded turn for Foundation Models.
8. The engine was over-built for 300 nodes: A3 keeps the simulation on the main actor and
   measures first. Barnes-Hut, an engine actor, and SpriteKit are A3b steps, only if needed.
9. `RecordingSession` needed the start task, levels, a recorder protocol, and discard while
   minimized; the accessory uses `tabViewBottomAccessory(isEnabled:)` and is checked on the
   device first.
10. The seeder would write into the real journal: it uses its own named store.
11. Read mode missed page review and live-text recordings, `writtenSurface`, the peek sheet's own
    stack, and the card starting bio drafts: all fixed.
12. Sequencing: the name filter survives Connections' deletion as `EntitySearch`, the
    migration tests go, "Regenerate every entry" runs oldest first, and the map extras moved to
    A5b. The review also suggested cutting the 3D spike, replay, lenses, and area rename/hide;
    they stay, since the owner asked for them, but the map extras now come after the core Mind
    tab works.

A1 build (sub-agent review of the working tree, 2026-09-17; 10 findings, no data or build
bugs). Fixed: tag examples no longer name areas and tags are told not to repeat one; a tag's page
shows its kind as text instead of a one-option picker; area renames save as they're typed and
skip no-op writes; the Debug regenerate waits for its own entries; a real drifted-date repair
test replaces the fixture one; the queue's entryDate order is pinned by a test; CLAUDE.md no
longer mentions themes. Not changed: old theme rows (a fresh install covers them); rename privacy
(the privacy test already renames an area to the sentinel). The Debug distribution lives on the
Life areas screen, reached from the insights settings while areas are on. Also fixed after the
owner saw it on the simulator: the area chip rendered as a tall empty yellow capsule; it's now a
grey capsule with a coloured icon, like the tag chips. `OpenAILiveTests` later ran with the real
key (2026-09-17): areas came back valid, but the model also tagged the entry `friends` next to the
Friends area despite the prompt, so the parser now drops any tag that is an area's name while
areas are on.

A2 build (sub-agent review of the working tree, 2026-09-17; 12 findings, one data bug).
Fixed: rerunning an entry reopened everything it had settled, since settled loose ends weren't
offered back; they now are, right after the entry's own. "Reopen" no longer marks a loose end as
the user's, so a later entry can still settle it. Rollback has three modes: deleting an entry
removes everything it made, touched or not; removing insights removes only what is open and
untouched; regenerating keeps what the new answer still means and what another entry settled.
An empty `sameAs` counts as null. A dated loose end waits for its day before the silence rule
applies. Changing an entry's date re-dates its loose ends. The card saves without stamping
entries. Insights holding only a loose end aren't "empty". "What was sent" counts only other
entries' loose ends. The demo seeder cycles its templates. Not changed: the Foundation Models
cap of 5 (insights only ever run through OpenAI today; add the cap if that changes); the
read-time `mergedIntoID` resolution exists as `EntityDirectory.root` and is used for candidate
ranking, and its other readers (search panel counts, peek card) arrive in A5. The live OpenAI
test `looseEndsAreSettledAndMentionedByHandle` passed against gpt-5.6-luna: the strict schema with
a nullable handle enum was accepted, the settled loose end came back in `resolved`, the ongoing
one as `sameAs`, and the unrelated one was left alone. `InsightsUITests` passed with the real key. The loose-end row's
identifier moved from the row to its label: on the row it overrode the menu button's own.

A3 build (2026-09-17, lane `feature/phase-a-graph`). Built to a spec the owner approved after a
sub-agent review (15 findings folded in). The draw cache keys on the simulation's own
`topologyVersion`; the canvas also takes a `version` argument only so an in-place update
re-renders it. The glow is a radial-gradient fill rather than a symbol (no blur, fewer moving
parts). A tapped edge focuses its better-connected end, a placeholder for A5's shared-entries card.

The demo journal found a bug that predates Phase A: at 225 nodes and 1897 edges the layout flew
to a 2.5 million point extent (a blank screen), because every spring pulled at full strength on
nodes with dozens of edges. Springs now use d3's `forceLink` defaults (strength 1 / min degree,
split by degree), and repulsion falls off with distance like d3's `forceManyBody` instead of
distance squared, which had left the settled graph packed into one blob. A unit test settles the
real demo graph. `-seedDemoJournal 300` means 300 entries: the global graph at its default
minimum of 2 mentions has 225 nodes, and that is the node count the gate reads.

Code review (sub-agent, 10 findings, no crash paths). Fixed: a cancelled drag or pinch left the
simulation warm and the canvas redrawing (cleanup now keys off `@GestureState`); pan and a
simultaneous pinch overwrote each other; settle time was reported as about 0 on a return visit;
glow was drawn for every neighbour of a hub (now capped at 25); a shaky tap pinned the node it
focused (8pt drag threshold); a node that grew didn't make room (0.05 reheat); the sampler kept
growing after reporting; the graph UI test raced the fly-to. Not changed: nothing covers a gesture
cancel in a test, since XCUITest can't cancel a gesture.

`GraphUITests.testConnectionsBrowseOpenAnEntryMergeAndUnmerge` failed at `entityMergeInto` on
this branch and on A0 (`6d0735b`) alike. A1 added a scroll there; it now fails later, at
`entityUnmerge`, on the landed A3 commit (`65cb856`) as well: after a relaunch, tapping Tom under
"Merged into this" highlights the row and pushes nothing. That's a real Connections bug, left
for A5, which deletes Connections and rewrites the test. For A9,
CLAUDE.md's Graph paragraph still describes a rebuild on every change and a settle-only
`graph.rendered`.

Device gate (2026-09-17, iPhone 17 Pro, run `a3-gate-1`, `-seedDemoJournal 300`, 223 to 224
nodes and 2770 to 2784 edges at the default minimum of 2 mentions). Nine `graph.rendered` events
from the owner's session of dragging, panning, pinching, and focusing:
- frame interval p50 16.7 to 17.4 ms, p95 17.6 to 18.3 ms (65 to 306 samples each)
- draw-closure work p95 9.0 to 11.1 ms
- first settle 1.1 to 5.0 s

p95 stays under the 20 ms gate on every sample, so **A3b is not needed** and the simulation stays
on the main actor with Canvas. One caveat: the app doesn't set
`CADisableMinimumFrameDurationOnPhone`, so iOS holds it to 60 Hz and the gate measured a 16.7 ms
budget. At ProMotion's 120 Hz the budget is 8.3 ms and today's ~9 ms of work would drop frames.
If the Mind tab should run at 120 Hz, that's the plist key plus A3b's first step (Barnes-Hut),
measured the same way.

Owner feedback from the same session, handled in this lane (`EntityView` is outside the lane's
file list; no other lane touches it before A5):
- The bubbles were too big to read the graph. Radius is now 3.5 + 1.4 sqrt(mentions), capped at
  16 (was 6 + 4 sqrt, capped at 28).
- The entity page's "Mentioned with" missed partners the graph showed: it listed the top 8 only.
  It now shows the top 8 and "Show all N", which expands in place.
- The entries list is now one "N mentioned entries" row (with a guessed count) that expands in
  place, which needs no new route type in the three stacks that push entity pages.
- Entries that didn't make sense under a tag: the demo seeder picks tags at random and never
  writes them into the text, so this is demo data, not the app.

A4 (lane 3, `feature/phase-a-shell`, build spec in `tasks/a4-shell-spec.md`):

- Accessory check, on the simulator rather than the phone: sheets and full-screen covers hide the
  accessory, pushed views keep it and the tab bar, and a panel inside a tab already lays out above
  it. The keyboard case is left for the phone.
- The spec review (17 findings) is folded into the spec. The main ones: start, finish, and discard
  guard each other with a generation number; a blank entry deleted while the editor animates out
  reads as no entry; `JournalRoute` compares by id alone.
- Deviations: `isPresentingOverEditor` is gone, since nothing closes the editor on disappear any
  more, so A6's "add the peek sheet to `isPresentingOverEditor`" has nothing to do. A jump waits for
  full-screen covers (`AppRouter.setCover`) instead of closing them, because the page screen has
  its own close rules. `LiveTranscriptionSession` didn't gain `Observable`; observation works
  through the concrete types. Moving the close rules also fixed presence counting twice after a
  cover over the editor, which left the entry "open" until relaunch.
- UI tests run against `-uiTestingFakeRecorder`, a recorder that writes a second of silence.
  Recordings share one folder across UI test stores, so a run killed mid-recording shows up as a
  recovered entry in the next test.
- Code review (10 findings, no crash paths), all fixed in "A4 review fixes".
- Found, not fixed (outside this lane, gone in A5): inside Connections the entity page's
  `EntityRoute` links push nothing, because Connections' path is typed `[ConnectionsPathItem]`.
  "Merged into this" is dead there, and `GraphUITests` marks that step as an expected failure.
  A likely cause of the unmerge item in A5's checklist. The
  test's `entityMergeInto` failure noted under A3 was a scroll issue and is fixed. The same run
  found `PageOrderUITests.testClosingWithNoPagesLeavesNothingBehind` never tapped Scan; fixed.
- Device steps passed on the phone (2026-09-17): recording across tabs and a lock, a Siri
  interruption while minimized, and A6's read mode and card. Owner change after using it: Record
  stays the microphone in Journal's toolbar, as before A4. The tab bar's accessory appears only
  while a recording runs, so a recording still follows the user across tabs.

A6 (lane 3, build spec in `tasks/a6-read-mode-spec.md`):

- The peek card is built here in its sheet form (owner's call), in `EntityPeekCard.swift`; A5 adds
  the Mind overlay on the same view instead of a second card.
- A simulator spike confirmed per-kind link colours render in `Text`, links tap with text
  selection on, and XCUITest exposes each name as a link.
- Spec review (15 findings) folded in. The main ones: read text keyed on the text itself, Edit's
  focus through the text view's own appearance, a finished recording lands for typing through its
  route, tags aren't linked, and the mode flips to typing one way only.
- "Opening and closing the peek card doesn't run the close rules" needs no test of its own: since
  A4, close rules only run when a route leaves Journal's path.
- Code review: one real bug (the editor re-decided its mode as the entry changed, so finishing a
  draft grew a second Done; the route now carries the decision), plus capitalised names linking
  only where capitalised ("I will call Will"), a card that spun forever for a missing entity, and
  two UI test waits. All fixed.
- The card's loose-end line and the recorder's prompt line landed after A2 (`looseEnds.prompted`
  logs the id only).

Owner answers after revision 1 (2026-09-17): the tab is Mind, a fresh install is fine, and Ask
keeps saved conversations and opens a new one by default. Folded in above.
