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
  comment carries the measurement.
- **`AskRetrievalQuery` gives retrieval the conversation.** The last three questions contribute terms
  decayed 1, 0.5, 0.25, highest weight winning rather than the sum, so "Why do you think that
  started?" stays about whoever the turn before was about. A range the question names filters; a range
  an earlier question named carries one turn, only boosts, and is dropped once the new question names
  someone. Nothing about this is stored: a reopened conversation rebuilds it from the messages.
- **`AskRetrieval.plan` decides, `AskContextBuilder` renders.** The plan takes a top k (15, or 5 on
  device) and divides the budget into four absolute slices (about, rollups, continuity, ranked),
  reading no entry text, which is what makes the cost line under the field free. The renderer holds
  the real budget slice by slice, so nothing can eat the room the entries needed. `matchedCount` is
  how many matched before the cut; a question naming a stretch of time is measured against that
  stretch, which is what stops a year being answered from two weeks. A question matching nothing
  falls back to the newest entries rather than failing.
- **The index rebuilds on a fingerprint**, not a timer: entry, link, and entity counts plus three
  monotonic counters (`EntrySaver.revision`, `GraphServices.revision`, `JournalSaves.revision`).
  Ordinals, never dates, so a clock stepping back cannot hide a change. `JournalSaves` sits inside
  `saveStampingEntries` because the transcription and title coordinators save straight through it:
  without it a recording's text never reached the index.
- **Prompt safety is unchanged from A7.** Journal text is data inside `<<<entry` fences, delimiters
  and handle-shaped text are stripped, citations are enumerated from the handles this request
  actually carried, and answers render with `Text(verbatim:)`.
- **Diagnostics** (`ask.indexed`, `ask.retrieved`, `ask.answered`, `ask.failed`) carry counts,
  durations, bools, and rounded scores. Never a term, a tag, a name, a question, or a handle map.
- **Measured, not assumed.** `AskRetrievalQualityTests` is a fixed 25-entry corpus and 15 questions
  whose expected answers were written from the entry text before retrieval ran once, asserted per
  question, with follow-ups scored with the continuity slice disabled so they cannot pass on what the
  last turn was already holding. Two known misses are asserted as misses: a synonym ("burnt out"
  against "running on empty") and morphology ("ran" against "run"). Those are the argument for
  embeddings, and they stay measured rather than argued.

**Graph** (`Mindlore/Graph/`, `Mindlore/Views/Graph/`). Turns the mentions and tags `EntryInsights`
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
  several (recorded in `unsureAmong`, surfaced by Connections' "Which one?"), or creates one.
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
  Connections' review list. Resolving a merged or hidden entity to what a screen should actually
  show is the same shape everywhere: fetch every `Entity` once, build an in-memory
  `[UUID: Entity]`, and walk `mergedIntoID` with a cycle guard (`root(of:)` in `GraphEditor`,
  repeated inline wherever a read-only query needs the same resolution without a full editor,
  e.g. `GraphServices.mentionedWith`/`resolvedLinks`) rather than re-fetching per id.
- **`GraphServices`** is the one shared graph object (`RootView` builds it, `.environment(graph)`),
  parallel to `EntrySaver` for persistence: every edit method flushes the saver first, saves through
  `context.saveStampingEntries()`, and bumps `revision`, which every graph-reading view keys a
  `.task(id:)` refresh off rather than a plain computed property. It also fronts the read-only
  queries no single model owns: `chipIndex` (an entry's links, for the editor's chips),
  `unsureLinks`/`repoint` (5c.4's "Which one?"), `mentionedWith` (one entity's co-occurring
  partners), and `localGraph`/`globalGraph` (below).
- **Co-occurrence and the picture.** `EntityGraph` (no SwiftData import, `nonisolated`) turns a
  caller-resolved `[LinkInput]` into weighted `Edge`s: two entities sharing an entry get an edge,
  weighted by a 90-day half-life so a recent shared entry counts for more (`EntityGraph.build`),
  with `neighbourhood(of:in:depth:)` and `filtered(edges:nodes:kinds:minimumLinkCount:)` for the
  local and global graph's node sets. `GraphSimulation` (also `nonisolated`, a plain class, not
  `@Observable`, since the canvas ticks it every frame from inside its own draw closure) is the
  force layout: phyllotaxis initial placement, many-body repulsion, link springs, centre gravity,
  and collision, each with a deterministic zero-distance fallback; sticky `pin`/`unpin` for a
  user's drag, a permanent `anchor` for a local graph's centred subject. `GraphCanvasView` is the
  shared `Canvas`/`TimelineView` drawing surface both `LocalGraphView` (a sheet from the entity
  page, its own `NavigationStack` and `entityRouteReplacer`) and `GlobalGraphView` (pushed onto
  Connections' own stack via `ConnectionsPathItem`, inheriting its replacer) embed. `graph.rendered`
  logs node/edge counts and actual settle time once per appearance, never per frame.
- **Navigation.** `EntityRoute` carries an id, never an `Entity`, so a merge or prune while a page
  is on the stack doesn't invalidate what's pushed; `EntityView` resolves it fresh
  (`EntityPagePresentation.resolve`). A screen that owns its own `NavigationStack` over entity pages
  (`ConnectionsView`, `EntryInsightsView`'s chips, `LocalGraphView`) must set
  `.environment(\.entityRouteReplacer, ...)` itself, or a merge made from inside it leaves a stale
  loser id on that stack's own path instead of redirecting to the winner; a view pushed into an
  existing stack (`GlobalGraphView` into Connections', `EntityView` itself) inherits the enclosing
  stack's replacer for free.
- **Diagnostics and privacy.** Every graph event (`graph.indexed`, `graph.merged`, `graph.rendered`,
  etc.) carries only ids, counts, and durations, never a name, alias, bio, or surface string;
  `DiagnosticsPrivacyTests`/`AIDiagnosticsPrivacyTests` run real graph components, including a
  local/global graph render, against a sentinel string used as every one of those fields and assert
  it never reaches the log.

**Entry dates.** `createdAt` is when the entry reached the app and drives every automation rule. `entryDate` is where it belongs in the journal, editable; a picked day is noon with `entryDateIsDayOnly`, and `EntryDateRepair` fixes any entry whose untouched date drifted.

**Settings** (`Mindlore/Settings/`). `SettingsStore` reads through a `KeyValueStore` protocol using `object(forKey:)`, so a missing value means "use the default" rather than `false`. `PrivacyInfo.xcprivacy` declares the UserDefaults reason.

**Views** (`Mindlore/Views/`). `RootView` owns the saver, ingestor, the four coordinators, `EditorPresence`, and `NetworkMonitor`, and passes them through the environment; it runs transcription in one lane and titles plus insights in another, and resumes both when the network returns. `EntryListView` lists entries and opens `EntryEditorView` or `RecordingView`. The editor is one scroll view: header (banners, player, page strip, title) above a `GrowingTextEditor` (a UITextView that grows with its text and never ends shorter than the screen, so a tap below short text puts the cursor at the end). `EntryInsightsView` is a sheet over the editor, never a push, because the editor's `onDisappear` runs its close rules.

**Adding a provider.** Conform to the capability protocols, add a `ProviderKind` and preset, and resolve it in `AIServices`. The coordinators, settings shape, and views don't change.

**Tests.** Fakes to reuse: `FakeHTTPClient`, `FakeSecretStore`, `FakeKeyValueStore`, `FakeTranscriber`, `FakeTextGenerator`, `FakePageTranscriber`, and the harnesses in `TranscriptionCoordinatorTests`, `PageTranscriptionTests`, and `InsightsTests`. `OpenAILiveTests` and the AI UI tests run against real OpenAI when `TEST_RUNNER_MINDLORE_OPENAI_KEY` is set, and against the app's stub (`-uiTestingFakeAI`, `UITestingHTTPClient`) otherwise; UI tests isolate settings and Keychain per `UITEST_STORE_NAME`, and `-uiTestingFakePages` replaces the camera. `MindloreTests/` uses Swift Testing (`import Testing`, `@Test`, `#expect`). For async code, inject dependencies and await the real task (for example `EntrySaver.scheduledSave`) rather than polling with `Task.yield()`, which can starve the main actor. `MindloreUITests/` uses XCTest and relaunches the app against a named file store to prove data survives.
