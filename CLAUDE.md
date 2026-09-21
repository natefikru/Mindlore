# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Mindlore is a voice-first journaling app for iOS, built with SwiftUI and SwiftData. v1 is a local journal: write or record entries, get on-device text from recordings, and never lose anything. The long-term product (AI analysis, an entity knowledge graph, iCloud sync) is described in `docs/mindlore-build-plan.md`. Remaining work and the unrun device smoke steps live in `docs/remaining-work.md`. Finished plans, with the design decisions and review history behind them, are archived in `tasks/archive/`: `v1-capture-storage.md` for persistence, recording, and transcription, `ai-providers.md` for the AI layer, photo entries, drafts, and entry dates, and `knowledge-graph.md` for entities, resolution, merging, and the graph picture. The plan in progress is `tasks/todo.md`. Read the relevant "Key decisions" before changing those areas.

Deployment target iOS 26.5, Swift 5.0 language mode. The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency, so types are main-actor by default; mark work that must leave the main actor `@concurrent nonisolated`. The test targets do not default to MainActor, so test suites that touch app types are marked `@MainActor`.

The app signs with a free Personal Team. iCloud, CloudKit, key-value storage, and push are unavailable, and any CloudKit call without the entitlement fails at runtime. Sync is gated by `AppConfig.cloudKitContainerID`, which stays `nil` until the project moves to a paid team.

## Commands

Build and run only through Xcode (`Mindlore.xcodeproj`) or `xcodebuild`:

```bash
# Build for the iOS Simulator
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -destination 'platform=iOS Simulator,name=iPhone 17' build

# Unit tests only (the normal iteration loop)
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:MindloreTests -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 60

# Everything, including UI tests (several minutes)
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 120

# A single Swift Testing test. The trailing () is required; without it xcodebuild runs 0 tests and still reports success.
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -parallel-testing-enabled NO "-only-testing:MindloreTests/EntrySaverTests/flushWithNothingPendingDoesNotSave()"
```

Use a per-test time allowance: an awaited continuation that never resumes hangs the whole run silently. Disable parallel testing so xcodebuild doesn't open a "Clone N of iPhone 17" simulator per worker. The simulator can't run on-device speech models, so transcription can only be verified on a physical iPhone. There is no SwiftPM package, lint config, or CI.

## Device smoke testing

Anything the simulator can't show (recording, locking, force-quits, on-device speech) is verified on a physical iPhone with a feedback loop. The steps and the log events each one must produce are in `tasks/smoke-test.md`.

- `scripts/device/deploy.sh` builds Debug and installs on the first connected iPhone. App data is kept.
- `scripts/device/launch.sh <run-id>` relaunches the app with its console attached and streams `MINDLORE` diagnostics lines (run it under a monitor). Routine throttle saves are filtered out. Arguments for the app go after `--`, or `devicectl` reads them as its own flags.
- `scripts/device/pull-logs.sh <run-id>` copies `Library/Logs/Mindlore/diagnostics.jsonl` and Mindlore crash reports into `.smoke/<run-id>/` (git-ignored) and prints a timeline. Use it after any step that kills the app, since that ends the console stream.

Device builds go to `~/Library/Developer/Xcode/DerivedData/Mindlore-device`. Builds inside `~/Documents` pick up iCloud Drive file attributes and fail code signing.

`DiagnosticsLog` (`Mindlore/Diagnostics/`) writes those events in Debug builds only and is disabled under XCTest. Events carry IDs, counts, sizes, durations, and framework error descriptions, never entry text. Log save errors with `DiagnosticValue.errorCode`, because SwiftData errors can embed model values. `DiagnosticsPrivacyTests` runs real components against a sentinel string to enforce this. When adding behavior that only a device can show, add events for it so the loop can see it.

## Architecture

The project uses file-system synchronized groups, so new files under `Mindlore/`, `MindloreTests/`, or `MindloreUITests/` join their target without editing `project.pbxproj`.

**Models** (`Mindlore/Models/`). `Entry`, `EntryPage` (photographed journal pages), and `EntryInsights` (AI output, kept out of the entry's own text) are the persisted types. Its core field is `text`; audio is an optional attachment, and naming stays input-neutral (no voice-specific names like `transcript`). There is no status or commit step. `awaitingText` marks a voice entry whose text hasn't been generated, `textWasGenerated` and `textEditedByUser` record where the text came from. Rules that change an entry live in `Entry+Editing.swift` so every caller applies them the same way. Every stored property must be optional or have a default, and nothing may be `@Attribute(.unique)`, so CloudKit sync can be switched on later without a migration; `CloudKitSchemaRulesTests` enforces this. Store enums as raw strings with computed accessors.

**Persistence** (`Mindlore/Persistence/`). `ModelContainerFactory` builds the store: `.default` for the app, `.inMemory` when hosted unit tests run, `.file` named by `UITEST_STORE_NAME` when launched with `-uiTesting`. `EntrySaver` is the only thing that decides when the main context writes to disk. Autosave is off. Call `noteChange()` after edits (saves within one second, even during continuous typing) and `flush()` when leaving a screen or deleting. `RootView` flushes whenever the scene leaves `.active`.

**Audio** (`Mindlore/Audio/`). `AudioRecorder` captures 24 kHz mono 16-bit PCM into `Recordings/active/<uuid>.caf`, because PCM stays readable if the app is killed mid-recording and AAC does not. `stop()` moves the file to `finished/`. `RecordingIngestor` converts finished files to AAC, creates a voice entry whose `id` is the file's UUID, and deletes the file only after the save succeeds. `MindloreApp.init` moves leftover `active/` files to `finished/` before any UI exists, and `RootView` ingests them at launch.

**Transcription** (`Mindlore/Transcription/`). `TranscriptionCoordinator` processes `awaitingText` voice entries one at a time. `TranscriberRouter` picks per entry: OpenAI when AI is on with a key and the entry was created after `aiEnabledAt`, otherwise `SpeechAnalyzerTranscriber` (`SpeechTranscriber`, falling back to `DictationTranscriber`). A failed cloud call falls back to the phone and records why in `textFallbackReasonRaw`. Recordings longer than the provider's limit are split by `AudioChunker` at their quietest points, each chunk carrying the previous chunk's tail as context. After each await it re-fetches the entry, and `applyGeneratedText` refuses if the user has typed.

**AI layer** (`Mindlore/AI/`). One account (Keychain key, base URL) serves three capabilities: `TextGenerator`, `Transcriber`, and `PageTranscriber`. `OpenAICompatibleTextGenerator` covers any Chat Completions server; `FoundationModelsTextGenerator` is Apple's on-device model. Every failure becomes an `AIError` carrying codes only, never provider text. `AIJobPolicy` holds the shared rules for the three jobs (text, title, insights): attempts and the last failure live on the `Entry`, counted before the request, capped (text 3, title 2, insights 2), with permanent failures waiting for a manual retry and offline failures rolling the attempt back. `AIPassTrigger` gives each entry exactly one automatic pass, at the first of: the editor closing on a finished entry, a recording's text arriving, page text being approved, or a launch sweep. Drafts (`Entry.isDraft`, typed entries until Done) and unapproved photo entries are never eligible. Coordinators capture `contentRevision` and drop results if the entry changed underneath them.

**Photo entries** (`Mindlore/Pages/`). `PageOrderView` collects pages from VisionKit or Photos, saving each as it arrives; confirming locks the order. `PageTranscriptionCoordinator` sends one request per page and saves each page's text as it lands, so a failure resends only what is missing. The joined text waits for `approveText()` before any other AI runs on it. Editing pages afterwards works on a draft and, if it differs, restarts the entry through `restartPages(applying:)`.

**Insights** (`Mindlore/AI/Insights/`). One structured request per entry, with a field per enabled section (`InsightsPromptBuilder`), parsed tolerantly: unknown moods and mention kinds are dropped, tags normalized, lists capped. Cleaned-up text is offered for transcribed entries (voice and pages, never typed), applies only to the exact text it was made from, and keeps `Entry.originalText` plus `cleanupAppliedHash` so revert survives regenerating or deleting insights.

**Ask** (`Mindlore/AI/Ask/`, `Mindlore/Views/Ask/`). Questions answered from the journal, with every
answer citing the entries it used. `AskService` owns a conversation; `AskConversation` and
`AskMessage` persist it, linked by id like `EntityLink`. `askGenerator` in Settings picks who answers
(off, on-device, OpenAI), and on-device is a fallback: its whole prompt is about 3,300 characters
after the system prompt and the answer headroom come out.

- **`AskSources` is the single gate on what may leave the phone**, and the only thing that reads
  entry text for a prompt. `documents(in:)` gathers every non-draft entry and marks each `isSendable`
  from `InsightsCoordinator.canRunAI`; `blocks(for:)` fetches the text of just the entries a plan
  chose and re-checks eligibility, because the index is a snapshot. Entity bios and loose ends are
  written out of entry text, so an entity is only ever described when a *sendable* entry mentions it,
  checked in both places. Hidden entities are neither a term nor nameable. Age never excludes an
  entry: `aiEnabledAt` is transcription's rule, because that uploads recordings nobody asked it to,
  and a question is the opposite.
- **Retrieval is one ranked list, not tiers.** `AskIndex` is an immutable BM25 snapshot holding no
  entry text, built off the main actor behind `AskIndexBuilding`'s `@concurrent` requirement. A
  document is indexed twice: its own words (title weighted 2) and its context (entity names and
  aliases, tags, life areas, mood, month, weighted 1.5), scored apart with `contextFactor` so a body
  hit beats a context-only one. That is how a question about Maya reaches an entry that never spells
  her name, without forty linked entries scoring the same. Recency reuses `EntityGraph`'s 90-day
  half-life with a floor of 0.7, which breaks ties without overturning relevance; the constant's
  comment carries the measurement. A document also stores the **lemma** of anything it inflected,
  beside the word actually written, at `lemmaFactor` 0.4 and not counted in document length, so
  "run" finds "ran". Both weights matter: at 1.0 "read" and "reading" collapse into one term and
  questions that worked regress, and counting a shadow term would make every entry look more
  diluted than it is under BM25. `AskIndex.lemmas` drops stop words itself, because a surface stop
  word is harmless (no query asks for one) but "going" lemmatizes to the stop word "go".
  `AskRetrievalQuery.expanded` is the query half, and both the prompt and the panel go through it,
  or the panel would expand fewer words than the question did.
- **A date in the question is both a filter and a term.** `AskDates` parses today/yesterday, this
  and last week/month/year, "a week ago" and "the past six months", an explicit day, a month ("in
  April", "April 2025"), a bare year ("how was 2025"), a season (meteorological, winter straddling
  the new year, "last summer" meaning the one before this one while it is still running), and
  "since <month|year|season>", which runs to today rather than meaning that month alone. A parsed
  range filters, and every entry inside it counts as matched, which is what makes a year's question
  measured against the year. Separately every entry indexes its own "April 2025" as a context term,
  so a date still ranks when nothing parsed. Month and season names are fixed English, like the stop
  list: read from the calendar the caller passes, they came from the device's locale, and a phone
  set to French silently stopped understanding "in April".
- **`AskRetrievalQuery` gives retrieval the conversation.** The last three questions contribute terms
  decayed 1, 0.5, 0.25, highest weight winning rather than the sum, so "Why do you think that
  started?" stays about whoever the turn before was about. A range the question names filters; a range
  an earlier question named carries one turn, only boosts, and is dropped once the new question names
  someone. Nothing about this is stored: a reopened conversation rebuilds it from the messages.
- **`AskRetrieval.plan` decides, `AskContextBuilder` renders.** The plan takes a top k (20, or 5 on
  device) and divides the budget into five absolute slices (about, rollups, digests, continuity,
  ranked), reading no entry text. The renderer holds the real budget slice by slice, so nothing can
  eat the room the entries needed. `matchedCount` is how many matched before the cut; a question
  naming a stretch of time is measured against that stretch, which is what stops a year being
  answered from two weeks. A question matching nothing falls back to the newest entries rather than
  failing. `aggregateMatchCount` is absolute at 45, not a multiple of the ranked cap: raising the
  cap must not quietly turn rollups off for a fifty-entry question.
- **What didn't fit whole goes in as one line.** `AskDigests` renders up to 150 matched entries as
  a handle, a date, a title, and ninety characters, inside one fence, for about what seven whole
  entries cost; the OpenAI budget is 64,000 characters. That is what lets "what happened this year"
  see the year instead of whichever twenty entries ranked highest. The room is reserved before the
  ranked loop, from a count, or twenty whole entries eat the tail the lines exist to cover. A line
  is entry text leaving the phone, so it is fetched through `AskSources` under the same eligibility
  check and sanitized the same way; it carries a handle, so an answer can cite a day it only saw a
  line of. **The lines are spread evenly across the matched stretch, ends included, not taken newest
  first**: three hundred entries in 2025 with room for a hundred and fifty lines used to cover July
  to December and leave the rest to a number in a rollup, which answers a year from six months of it.
  The best matches are already in the prompt whole; what the lines are for is coverage, and coverage
  is measured along the calendar. `wasCut` counts a digest as having seen the entry, so a question whose whole matched set
  fit in lines has nothing to hedge about. On device there are no digests: one block is most of the
  budget. **The entries take their room first and the lines take what is left.** Held back in front
  of them, the reserve has to be charged at a line's worst case (160 characters, a true upper bound
  the slice is derived from) while a real line costs about sixty, and a question matching two
  hundred entries lost two of its twenty best-matching entries to room the lines then didn't use.
- **The index rebuilds on a fingerprint**, not a timer: entry, link, and entity counts plus three
  monotonic counters (`EntrySaver.revision`, `GraphServices.revision`, `JournalSaves.revision`).
  Ordinals, never dates, so a clock stepping back cannot hide a change. `JournalSaves` sits inside
  `saveStampingEntries` because the transcription and title coordinators save straight through it:
  without it a recording's text never reached the index.
- **The prompt owns up to what the answer is written from, and never says so out loud.** The
  answers used to read like search results, and they narrated their own retrieval because the
  prompt told them to: "say what you are looking at" went into every cut question. `AskPrompt.system`
  now opens with who is speaking, then one silence rule with its worked contrast attached ("you were
  fried the week of the deadline", never "your entry from 14 March says"), then two permissions:
  name a pattern you actually see, ask one short question back, nothing that steers a life. Handles
  are out of the prose; OpenAI returns citations in a field, and only the on-device model, which has
  no structured output, still writes `[E3]` inline for `AskAnswerParser` to strip. That split is why
  the prompt has a short form, since the whole on-device session is 6,000 characters.
  Ask takes no `PromptVoice`, unlike every other prompt: the setting decides how a written summary
  refers to the author, and a conversation is the one place that question doesn't arise, so Ask
  addresses them as "you" and never sends their name. Wired to the setting, the model half-obeyed and
  half-addressed, opening one answer "my life settled into a rhythm" and the next "you ran by the
  river". `AskPrompt.notes` still says "you can see 170 of the 213 entries that bear on this", says which
  days the entries came from, and says when nothing matched and these are simply the newest
  entries, but every note now carries its own gag order, because a note stated as a fact came back
  out inside the answer. `AskPromptToneTests` holds all of it, the old sentence asserted as absent.
  An inherited range reads differently from a named one, because it never filtered anything and entries outside it are in the prompt.
  `AskRollups` adds one fenced block of counts and coverage ("September 2026: 31 entries, 2 to 30
  September") for an aggregate question, counting **the matched set**, not the month: counting the
  month instead is the confident wrong answer the rollup exists to prevent. Counts and coverage
  only; mood, area, and tag distributions are Reflect's. Ask uses `PromptVoice` like every other
  prompt.
- **Prompt safety is unchanged from A7, with one hole closed.** Journal text is data inside
  `<<<entry` fences, delimiters and handle-shaped text are stripped, citations are enumerated from
  the handles this request actually carried, and answers render with `Text(verbatim:)`.
  `AskContextBuilder.sanitized` now strips to a fixpoint rather than once: a single pass is defeated
  by nesting, since `entrentry>>>y>>>` has its inner match removed and the outer halves close up into
  a live delimiter. In a digest block that would put every line after it outside the fence.
- **The search panel reads the same index.** `JournalSearch` ranks through `AskIndex` with the last
  word expanded by prefix, then fetches by id for titles and snippets, and falls back to the old
  substring predicate when the ranked path finds nothing (which also covers a query that is all stop
  words). Before this the panel could say "nothing matches that" about an entry the question then
  sent. A row that ranked on something invisible, a tag or a mood or a month, says which.
- **The chat shows no plumbing.** No cost line under the field, no sentence about what asking
  would send. The source chips under an answer stay, quiet and tappable, and "What was sent" is an
  icon on the footer row; that sheet is where the receipt lives, and it says how many entries were
  read in full against how many as one line.
- **The answer arrives as it is written.** Measured on the phone against 300 entries: 4.0 to 8.4
  seconds, every one of them a spinner on a blank screen, with the first sentence ready inside a
  second. `StreamingTextGenerator` is the opt-in, by conformance rather than provider name, and
  `OpenAICompatibleTextGenerator` is the only conformer; Foundation Models keeps the awaited path,
  since nobody watches a title or an insight being written either. The hard part is that Ask uses
  structured output, so a live answer means reading a half-written string out of a half-written
  object: `StreamingJSONString` does it **statelessly**, re-scanning the whole buffer each frame and
  carrying nothing across a chunk boundary, because a `\uXXXX` split across two network reads is
  the bug that passes every test and fails on the phone. Citations land when the object closes,
  which is when the handles exist, so the chips come last. `SSEParser` holds bytes until a line is
  whole for the same reason a character can straddle a read. A non-2xx status is not a stream: the
  body is collected and mapped by the code that maps a single-shot one, and `ProviderQuirks`
  remembers a server that rejects `stream` the way it already remembered one that rejects a strict
  schema. An idle watchdog fails a stream that goes 30 seconds without a frame, or a server that
  accepts and then stalls holds a half-written answer until the 300 second request timeout.
- **Cancellation is two things.** A cancelled task (the screen left, the conversation switched) and
  an explicit Stop. The stream is read in its own task so Stop can cut one that has gone quiet, and
  the flag is what tells them apart afterwards. **Stop keeps what arrived**, marked stopped, with no
  chips and nothing to retry, and it is saved, because a stopped answer is still an answer (owner,
  2026-09-21). A stream that *dies* halfway is the opposite: the partial goes and the ordinary
  failure turn arrives with Retry, exactly as a dropped request always did. The spinner shrank to
  what it should always have been, the wait before the first word, and the growing answer is
  followed on a 200 ms tick rather than per delta, which is the difference between following the
  text and fighting the thumb.
- **Diagnostics** (`ask.indexed`, `ask.retrieved`, `ask.answered`, `ask.stopped`, `ask.failed`) carry counts,
  durations, bools, and rounded scores, `ask.answered` including `streamed` and
  `firstChunkMilliseconds`, which is the number streaming exists to move. Never a term, a tag, a
  name, a question, a handle map, or a word of a delta.
- **Measured, not assumed.** Two suites, doing different jobs. `AskRetrievalQualityTests` is the
  regression guard: a fixed 25-entry corpus and 16 questions whose expected answers were written
  from the entry text before retrieval ran once, asserted per question, with follow-ups scored with
  the continuity slice disabled so they cannot pass on what the last turn was already holding. Its
  known misses are asserted *as* misses, so one starting to work goes red and has to be promoted
  rather than quietly enjoyed; that is how "How was the run?" moved into the fair set when lemmas
  landed, and how "Was I burnt out in the spring?" moved when seasons started parsing, since the
  date was doing the damage rather than the synonym. One miss remains, the synonym with no date to
  lean on ("Was I burnt out?" against "running on empty"), measured at 0.00.
  `AskRetrievalParaphraseTests` is the rate: 57 entries, 25 questions the journal answers in
  different words, sorted by why they are hard, against 8 control questions that share the entries'
  words. Control 1.00 at recall@5; paraphrases 0.20 before lemmas and 0.31 after, with morphology
  1.00 and **indirect description 0.00** over seven questions. That last class is what nothing
  lexical reaches ("Did my rent go up?" against "Ninety more a month"), and it is the argument for
  embeddings, measured rather than argued.

**Graph** (`Mindlore/Graph/`, `Mindlore/Views/Graph/`, `Mindlore/Views/Mind/`). Turns the mentions and tags `EntryInsights`
already stores into entities people, places, organizations, projects, events, and tags can share, resolve to, merge into, and see co-occurrence and a force-directed picture
of. `Entity` is the persisted node (name, `kindRaw`, `aliases`, `bio*`, `hidden`, `mergedIntoID`,
denormalized `linkCount`/`firstLinkedAt`/`lastLinkedAt` that `GraphIndexer.recount` owns); every
stored property is optional or defaulted and nothing is `@Attribute(.unique)`, the same CloudKit
rule as `Entry`, and `CloudKitSchemaRulesTests` checks both models. `EntityLink` is the only stored
edge (one entry mentions one entity); its `entity`/`entry` relationships exist solely for
SwiftData's cascade and nullify rules; nothing reads them; `entityID`/`entryID` are the truth, and
every view and service resolves an entity by fetching its id, never by walking the relationship.

- **Normalizer, resolver, indexer.** `EntityNormalizer` derives the matching `key` from a name and
  kind. `EntityResolver` decides, per mention, whether it lands on an existing entity, ties between
  several (recorded in `unsureAmong`, surfaced as Mind's "Which one?" review question), or creates one.
  `GraphIndexer` is the only thing that writes `EntityLink`s: `index(_:in:)` runs after an entry's
  insights are written, `recount(in:)` denormalizes `linkCount`/`firstLinkedAt`/`lastLinkedAt` and
  prunes an unconfirmed entity down to zero links, and `sweep(in:)` is the launch/upgrade pass over
  every entry `graphIndexedAt` doesn't yet cover. A counting pass never deletes on a transient nil;
  see `tasks/lessons.md`.
- **Editing, merge, matching.** `GraphEditor` is the only thing that changes an `Entity` afterwards:
  rename, kind, alias, hide, merge/unmerge, repoint a single mention (`EntityLink.repoint`), and
  "not the same" for the review list. A merge points the loser's id at the winner
  (`mergedIntoID`) rather than deleting it, so old references still resolve; unmerge reverses
  exactly the aliases and links that merge moved. `EntityMatcher` scores likely-duplicate pairs for
  Mind's review question. Resolving a merged or hidden entity to what a screen should actually
  show is the same shape everywhere: fetch every `Entity` once, build an in-memory
  `[UUID: Entity]`, and walk `mergedIntoID` with a cycle guard (`root(of:)` in `GraphEditor`,
  repeated inline wherever a read-only query needs the same resolution without a full editor,
  e.g. `GraphServices.mentionedWith`/`resolvedLinks`) rather than re-fetching per id.
- **`GraphServices`** is the one shared graph object (`RootView` builds it, `.environment(graph)`),
  parallel to `EntrySaver` for persistence: every edit method flushes the saver first, saves through
  `context.saveStampingEntries()`, and bumps `revision`, which every graph-reading view keys a
  `.task(id:)` refresh off rather than a plain computed property. It also fronts the read-only
  queries no single model owns: `chipIndex` (an entry's links, for the editor's chips),
  `unsureLinks`/`repoint` ("Which one?"), `mentionedWith` (one entity's co-occurring
  partners), and `mapSnapshot`/`globalGraph`/`primaryAreas` (Mind, below).
- **Co-occurrence and the picture.** `EntityGraph` (no SwiftData import, `nonisolated`) turns a
  caller-resolved `[LinkInput]` into weighted `Edge`s: two entities sharing an entry get an edge,
  weighted by a 90-day half-life so a recent shared entry counts for more (`EntityGraph.build`),
  (`EntityGraph.build`). `GraphSimulation` (also `nonisolated`, a plain class, not `@Observable`,
  since the canvas ticks it every frame from inside its own draw closure) is the engine:
  phyllotaxis initial placement, many-body repulsion, link springs, centre gravity, and collision,
  each with a deterministic zero-distance fallback; sticky `pin`/`unpin` for a user's drag. It
  stays warm on demand: a drag raises `alphaTarget` so alpha holds instead of decaying, and
  `update` swaps nodes and edges in place so a filter change moves the picture rather than
  restarting it. `GraphCanvasView` is the `Canvas`/`TimelineView` drawing surface Mind embeds;
  `FrameTimeSampler` (`GraphCanvasModel.swift`) measures frame p50/p95 and work p95, and
  `graph.rendered` logs them with node/edge counts once per appearance, never per frame.
- **Navigation.** `EntityRoute` carries an id, never an `Entity`, so a merge or prune while a page
  is on the stack doesn't invalidate what's pushed; `EntityView` resolves it fresh
  (`EntityPagePresentation.resolve`). A screen that owns its own `NavigationStack` over entity pages
  (`MindView`, over `AppRouter.mindPath`; `EntryInsightsView`'s chips; `EntityPeekCard`) must set
  `.environment(\.entityRouteReplacer, ...)` itself, or a merge made from inside it leaves a stale
  loser id on that stack's own path instead of redirecting to the winner; a view pushed into an
  existing stack (`EntityView` itself) inherits the enclosing stack's replacer for free.
- **Mind** (`Views/Mind/`) is the second tab: one full-screen map of every browsable entity.
  `GraphServices.mapSnapshot` reads the store once per `revision` into a `MindMapSnapshot`, and
  `MindView.frame` (static, pure) turns snapshot plus `MindFilters` into nodes, edges, entry dots
  and regions. `MindFilters` is kinds, a minimum mention count (1 below `largeJournal`, 60
  entities, then 2), entry dots, and grouping by area. `MindRegions` puts each visible life area on
  a fixed circle whose radius comes only from the snapshot's entity count, so it doesn't jitter
  during replay. A `MindLens` (kind, mood, recency) changes paint only, never which nodes are on
  the map. `MindReplayPlayer` plays first mention to now over 10 seconds in 100 ms steps and
  publishes every fifth step, because publishing each one pushed frame p95 to 32 ms.
  `SearchPanel` is Mind's own pull-up panel (not a system sheet, which would cover the tab bar and
  the record accessory): search, one review question from `ReviewQueue` ("Which one?" before
  "same person?", because it is about a sentence the user wrote; skips are session-only), the
  area tiles, and every entity via `MindDirectory`, which counts open loose ends through merges
  and keys its own refresh because closing a loose end doesn't bump `graph.revision`.
  `EntityPeekCard` is the shared card for any name. Tests: `MindMapTests`, `MindRegionsTests`,
  `MindFiltersTests`, `MindReplayTests`, `MindDirectoryTests`.
- **Diagnostics and privacy.** Every graph and `mind.*` event carries only ids, counts, kinds, and
  durations, never a name, alias, bio, or surface string; `AIDiagnosticsPrivacyTests` runs real
  graph components, including a Mind render with every lens and a replay, against a sentinel
  string used as every one of those fields and asserts it never reaches the log.
  `docs/privacy-coverage.md` maps every event in the app to the test that drives it, or says why
  none can.

**Loose ends** (`Models/LooseEnd.swift`, `AI/Insights/LooseEndWriter.swift`). Open threads an entry
leaves ("need to call the landlord") become `LooseEnd` records with a status (open, resolved,
faded, dismissed), subject `entityIDs`, an optional due date, and the entry that raised them; same
CloudKit rules as `Entry`. Insights writes them: `LooseEndWriter.candidates` sends the known ones
as handles (the entry's own first, so a rerun reuses them, then others dated before the entry,
never after, since an old page can't settle what hadn't happened yet), and `apply` records
mentions, resolutions, and new ones. The model's `sameAs` points a mention back at a known handle
instead of creating a duplicate. AI never resolves one the user touched (`userTouched`) or one
sourced from or dated after the entry itself. Nothing is deleted: `LooseEnd.fade` marks one faded
after 42 days of silence or a week past its due date, run in the launch sweep after the graph.
The recorder offers one at a time through `LooseEndPrompter` (overdue first, then the most recently
mentioned, never the same one within 3 days). Tests: `LooseEndWriterTests`, `LooseEndLifecycleTests`,
`LooseEndPromptTests`, `LooseEndCoordinatorTests`, `LooseEndBarTests`.

**Life areas** (`Models/LifeArea.swift`). Nine fixed areas (work, money, health, mind, family,
love, friends, play, home), at most two per entry, replaced per-entry themes because those never
connected anything. `EntryInsights.areasRaw` stores raw values, which is also what the prompt
sends; the user's renames and hidden set live in `SettingsStore` (`lifeAreaNames`,
`hiddenLifeAreas`, `visibleLifeAreas`) and only change display. An entity's area on the map is
computed, not stored: `MindMap.primaryAreas`, over the areas of the entries it appears in.

**Entry dates.** `createdAt` is when the entry reached the app and drives every automation rule. `entryDate` is where it belongs in the journal, editable; a picked day is noon with `entryDateIsDayOnly`, and `EntryDateRepair` fixes any entry whose untouched date drifted.

**Settings** (`Mindlore/Settings/`, `Mindlore/Views/SettingsView.swift`). `SettingsStore` reads through a `KeyValueStore` protocol using `object(forKey:)`, so a missing value means "use the default" rather than `false`. `PrivacyInfo.xcprivacy` declares the UserDefaults reason. Settings is the fourth tab, organised by what a setting touches rather than by subsystem: Your journal (life areas, how you're written about, keep recordings), Today, AI (use AI, the key, What AI does, with an Advanced screen for model fields, cloud fallback and custom prompts), and About (`JournalTotals`, counts only). Life areas and your name sit at the top level because both work with AI off. Seven keys are internal state, not settings, and never get a control: `aiEnabledAt`, `automationStartedAt`, `askGeneratorChosenByUser`, `todayDismissed`, `lifeAreaNames`, `hiddenLifeAreas`, `providerAccounts`; find every reader before touching one. UI tests reach settings through `app.tabBars.buttons["Settings"]`, never bare `app.buttons["Settings"]`, which matches a tab item and a toolbar button alike. `tasks/archive/settings-sprint.md` has the audit.

**Views** (`Mindlore/Views/`). `RootView` is a four-tab `TabView` (Journal, Mind, Ask, Settings; `AppTab` in `Views/Shell/AppRouter.swift`, which also owns each tab's path and cross-tab routes). Recording lives in the bottom accessory (`RecordAccessory`) and keeps going while tabs change. `RootView` owns the saver, ingestor, `RecordingSession`, the four coordinators, `AIPassTrigger`, `EditorPresence`, `NetworkMonitor`, `GraphServices`, `AskService`, and the router, and passes them through the environment. `EditorLifecycle` (`Views/Shell/`) is what runs when an editor opens and closes: presence, deleting a blank entry, discarding audio unless kept, and the `.editorClosed` AI pass. Past entries open in read mode (`EntryReadMode`) with tappable names. After a recording, `KeepCard` (`Views/Capture/`) shows what the journal noticed, from stored data only, no AI call. Colors, type, motion, and haptics come from `Mindlore/Design/`, and colors only from the asset catalog's light and dark variants. RootView runs transcription in one lane and titles plus insights in another, and resumes both when the network returns. `EntryListView` lists entries and opens `EntryEditorView` or `RecordingView`. The editor is one scroll view: header (banners, player, page strip, title) above a `GrowingTextEditor` (a UITextView that grows with its text and never ends shorter than the screen, so a tap below short text puts the cursor at the end). `EntryInsightsView` is a sheet over the editor, never a push, because the editor's `onDisappear` runs its close rules.

**Today** (`Mindlore/Views/Today/`). The header above the journal list: a greeting, a seven-dot
week strip, and at most three cards. `TodayComposer` is `nonisolated` and reads no SwiftData, the
same split as `EntityGraph`; `TodaySource` does the fetching, walks merges through
`EntityDirectory` (`Graph/`), and drops hidden and muted entities. Card order is fixed: a thread
the last entry closed or one due today, this day in an earlier year, the oldest thread still open,
a well-linked name whose `lastLinkedAt` is over 30 days old, the latest entry's summary. Nothing
backs two cards, there is one on-this-day card chosen once, and a dismissal is day-scoped
(`TodayDismissal` in `SettingsStore`, thrown away when the day changes). `Entity.resurfacingMuted`
is the per-name mute; it is in `GraphIndexer.recount`'s keep-list beside `hidden`, or a muted name
that loses its last link is pruned and returns under a new id. A loose end with any hidden or muted
subject never becomes a card. The header refreshes on `.task(id:)` over the three monotonic
revision counters, the day, and the two settings the composer reads, never on a count.

**Adding a provider.** Conform to the capability protocols, add a `ProviderKind` and preset, and resolve it in `AIServices`. The coordinators, settings shape, and views don't change.

**Tests.** Fakes to reuse: `FakeHTTPClient`, `FakeSecretStore`, `FakeKeyValueStore`, `FakeTranscriber`, `FakeTextGenerator`, `FakePageTranscriber`, and the harnesses in `TranscriptionCoordinatorTests`, `PageTranscriptionTests`, and `InsightsTests`. `OpenAILiveTests` and the AI UI tests run against real OpenAI when `TEST_RUNNER_MINDLORE_OPENAI_KEY` is set, and against the app's stub (`-uiTestingFakeAI`, `UITestingHTTPClient`) otherwise; UI tests isolate settings and Keychain per `UITEST_STORE_NAME`, and `-uiTestingFakePages` replaces the camera. `MindloreTests/` uses Swift Testing (`import Testing`, `@Test`, `#expect`). For async code, inject dependencies and await the real task (for example `EntrySaver.scheduledSave`) rather than polling with `Task.yield()`, which can starve the main actor. `MindloreUITests/` uses XCTest and relaunches the app against a named file store to prove data survives.
