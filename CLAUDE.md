# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Mindlore is a voice-first journaling app for iOS, built with SwiftUI and SwiftData. v1 is a local journal: write or record entries, get on-device text from recordings, and never lose anything. The long-term product (AI analysis, an entity knowledge graph, iCloud sync) is described in `docs/mindlore-build-plan.md`. Remaining work and the unrun device smoke steps live in `docs/remaining-work.md`. Finished plans, with the design decisions and review history behind them, are archived in `tasks/archive/`: `v1-capture-storage.md` for persistence, recording, and transcription, `ai-providers.md` for the AI layer, photo entries, drafts, and entry dates, and `knowledge-graph.md` for entities, resolution, merging, and the graph picture. The plan in progress is `tasks/todo.md`. Read the relevant "Key decisions" before changing those areas.

Deployment target iOS 26.5, Swift 5.0 language mode. The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency, so types are main-actor by default; mark work that must leave the main actor `@concurrent nonisolated`. The test targets do not default to MainActor, so test suites that touch app types are marked `@MainActor`.

The app signs with team `7DZBU56KUA`, a paid Individual team since 2026-09-23 (it was the free Personal Team before, same ID). The app's own journal mirrors to `iCloud.com.natefikru.mindlore` (`AppConfig.cloudKitContainerID`) through SwiftData's CloudKit store; only `StoreLocation.default` does, so tests and demo journals never touch iCloud. A store that fails to open with CloudKit reopens on the device alone (`sync.storeFailed`). `SyncStatusMonitor` (`Mindlore/Sync/`) reports the account and the mirroring's own events to the iCloud section at the top of Settings' General screen; `SyncStatus` holds every sentence it can say. Xcode builds talk to CloudKit's Development environment and TestFlight to Production, and nothing copies data between them. Production only accepts fields its schema already has, and Development only learns a field once a record carrying it syncs, so after any model change: launch a Debug build on a signed-in phone with `-initializeCloudKitSchema` (`scripts/device/launch.sh schema -- -initializeCloudKitSchema`, `CloudKitSchemaInitializer`), which writes every field to Development; check it with `xcrun cktool export-schema --team-id 7DZBU56KUA --container-id iCloud.com.natefikru.mindlore --environment development` (a management token saved with `cktool save-token --type management`); then press Deploy Schema Changes in CloudKit Console, which no API can do (cktool answers "endpoint not applicable in the environment 'production'"). Do it before the merge whose TestFlight build writes the new field. Core Data's mirroring deletes synced data on sign-out or an account change, so every save also writes the entry's words to `Application Support/EntryBackups/` (`EntryBackups`, registered to the journal's container only, so tests never write there), and `JournalRecovery` offers them back through `RestoreBanner` once sync settles after such an event. A save path that bypasses `saveStampingEntries` and `EntrySaver` skips the copy until the next launch fills it in. The plan and its remaining phases are `tasks/icloud-sync.md`.

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

Use a per-test time allowance: an awaited continuation that never resumes hangs the whole run silently. Disable parallel testing so xcodebuild doesn't open a "Clone N of iPhone 17" simulator per worker. The simulator can't run on-device speech models, so transcription can only be verified on a physical iPhone. There is no SwiftPM package or lint config.

## CI

`.github/workflows/ci.yml` builds once (`scripts/ci/build-for-testing.sh`, about three minutes) and then runs `unit` on every pull request and push to `main`, the only required check; a new push cancels the run in flight for the same event and ref. Everything slow runs nightly at 07:00 UTC (skipped when `main` hasn't moved since the last passing nightly run), and there `live` and `ui` are not `continue-on-error`, so a failure turns the run red and GitHub emails about it. `ui` (three shards) and `live` also run on a PR carrying the `ui` or `live` label, and by manual dispatch, advisory both ways. `ci.yml` has no `labeled` trigger, because a label-only run would skip its jobs and a skipped job counts as a passed required check; `ui-label.yml` (Ubuntu, outside the macOS limit) dispatches `ci.yml` on a labeled PR's branch with `skip_unit` only when the label is added; every later push runs `ui` or `live` inside the PR's own run, which reads the labels, so one push never starts two runs building the same commit (owner, 2026-09-24). The fourteen slow unit tests (300-node simulations, demo and story seeds, timing budgets, the paraphrase rate; 125 of the unit job's 175 seconds of tests) are `.enabled(if: TestHost.runsSlowTests)`: they skip on CI unless `TEST_RUNNER_MINDLORE_SLOW=1`, which the nightly run sets, and always run on a Mac. Building in each job while its simulator booted was tried and was slower: the boot fought the compiler, and builds took 6.5 to 11.5 minutes. A manual run with the `only` input runs just the named UI tests (`Class` or `Class/testMethod`) on one runner. On CI a UI test gets five minutes instead of two and one retry: a runner is two to three times slower than a Mac, and a relaunch test killed at two minutes also broke the next test's launch ("Failed to terminate"). `test.sh` ends with what the result bundle says failed or was retried, because xcbeautify printed a green check for a test the allowance had killed. Runners have no NLTagger lemma assets (and `NLTagger.requestAssets` hangs there), so lemma-dependent tests are `.enabled(if: LemmaAvailability.isAvailable)`. The on-device model reports itself available in a runner's simulator but gives no meaningful quality reading there, so its quality tests are `.enabled(if: TestHost.canMeasureOnDeviceModel)`; `test.sh` sets `TEST_RUNNER_MINDLORE_CI=1` on GitHub. Both run on every Mac and show as skipped on CI. The suites that call real OpenAI (`OpenAILiveTests`, `CreativeOpenAIQualityTests`, `LifeLiveTests`) judge a live model's answers, which vary call to call, and each failed a CI run with no code change, so on CI the unit job leaves them out (`-skip-testing`) and the `live` job runs them with the key (`scripts/ci/test.sh live`). Locally `test.sh unit` still runs them when the key is set. `scripts/ci/ui-shards.sh` splits by test method, not class (each UI test launches the app anyway), weighting each by its measured seconds in `scripts/ci/ui-test-seconds.txt` (60 if missing) so the shards finish together; a new test needs nothing registered, and `scripts/ci/ui-test-seconds.sh <run-id>` refreshes the timings. The class name must match the file name. `scripts/ci/test.sh unit` and `scripts/ci/test.sh ui <Class> ...` are the same commands locally (they build first if nothing is built; local products go to `~/Library/Developer/Xcode/DerivedData/Mindlore-ci`, since builds under `~/Documents` fail signing). Signing stays at the project's defaults: `CODE_SIGNING_ALLOWED=NO` fails `KeychainSecretStoreTests` with `errSecMissingEntitlement`. The scheme is shared (`xcshareddata/xcschemes/Mindlore.xcscheme`); keep it that way or CI has nothing to build. `release.yml` archives and uploads to TestFlight after every push to `main` whose CI run passed (a `workflow_run` trigger), on a `v*` tag, and by hand; it signs manually on the runner (a distribution p12 and an App Store profile from secrets) while the project stays automatic, because automatic signing archives with a development identity the runner doesn't have. It is gated by the `RELEASE_ENABLED` variable; the one-time setup is in `docs/remaining-work.md` and `scripts/release/set-secrets.sh` loads the secrets. The plan and its measurements are in `tasks/ci-plan.md`, and the cut from twenty minutes a run in `tasks/ci-speed.md`.

## Device smoke testing

Anything the simulator can't show (recording, locking, force-quits, on-device speech) is verified on a physical iPhone with a feedback loop. The steps and the log events each one must produce are in `tasks/smoke-test.md`.

- `scripts/device/deploy.sh` builds Debug and installs on the first connected iPhone. App data is kept.
- `scripts/device/launch.sh <run-id>` relaunches the app with its console attached and streams `MINDLORE` diagnostics lines (run it under a monitor). Routine throttle saves are filtered out. Arguments for the app go after `--`, or `devicectl` reads them as its own flags.
- `scripts/device/pull-logs.sh <run-id>` copies `Library/Logs/Mindlore/diagnostics.jsonl` and Mindlore crash reports into `.smoke/<run-id>/` (git-ignored) and prints a timeline. Use it after any step that kills the app, since that ends the console stream.

To look at the app with a believable journal, launch with `-seedStoryJournal` (for example `launch.sh story -- -seedStoryJournal`): 200 hand-written entries across a year, with a cast and a plot, whose insights, parts, and loose ends come from the real pipeline (`scripts/demo/regenerate-story.sh`), in their own store (`Mindlore/Debug/DemoStory.swift`, bible in `docs/demo-story.md`), on the real settings and key so Reflect and Ask answer it as they would the real journal. Add `-resetStoryJournal` to throw that store away and reseed it. `-seedDemoJournal <count>` is the generated journal the UI tests and performance checks use; don't use it for looking at the app. Its store outlives a run, dated from the day it was seeded, so a test that changes it or reads anything relative to today adds `-resetDemoJournal` to reseed it from today.

Device builds go to `~/Library/Developer/Xcode/DerivedData/Mindlore-device`. Builds inside `~/Documents` pick up iCloud Drive file attributes and fail code signing.

`DiagnosticsLog` (`Mindlore/Diagnostics/`) writes those events in Debug builds only and is disabled under XCTest. Events carry IDs, counts, sizes, durations, and framework error descriptions, never entry text. Log save errors with `DiagnosticValue.errorCode`, because SwiftData errors can embed model values. `DiagnosticsPrivacyTests` runs real components against a sentinel string to enforce this. When adding behavior that only a device can show, add events for it so the loop can see it.

## Architecture

The project uses file-system synchronized groups, so new files under `Mindlore/`, `MindloreTests/`, or `MindloreUITests/` join their target without editing `project.pbxproj`.

**Models** (`Mindlore/Models/`). `Entry`, `EntryPage` (photographed journal pages), and `EntryInsights` (AI output, kept out of the entry's own text) are the persisted types. Its core field is `text`; audio is an optional attachment, and naming stays input-neutral (no voice-specific names like `transcript`). There is no status or commit step. `awaitingText` marks a voice entry whose text hasn't been generated, `textWasGenerated` and `textEditedByUser` record where the text came from. Rules that change an entry live in `Entry+Editing.swift` so every caller applies them the same way. Every stored property must be optional or have a default, nothing may be `@Attribute(.unique)`, every relationship needs an inverse, and no property may share a name with an `NSManagedObject` member (`EntityLink.entity` did, and CloudKit's exporter crashed on it); `CloudKitSchemaRulesTests` enforces all of it. The store has mirrored, so a property is added, never renamed: Core Data refuses a rename in a store CloudKit has touched (see `tasks/lessons.md`). Store enums as raw strings with computed accessors.

**Persistence** (`Mindlore/Persistence/`). `ModelContainerFactory` builds the store: `.default` for the app, `.inMemory` when hosted unit tests run, `.file` named by `UITEST_STORE_NAME` when launched with `-uiTesting`. `EntrySaver` is the only thing that decides when the main context writes to disk. Autosave is off. Call `noteChange()` after edits (saves within one second, even during continuous typing) and `flush()` when leaving a screen or deleting. `RootView` flushes whenever the scene leaves `.active`.

**Audio** (`Mindlore/Audio/`). `AudioRecorder` captures 24 kHz mono 16-bit PCM into `Recordings/active/<uuid>.caf`, because PCM stays readable if the app is killed mid-recording and AAC does not. `stop()` moves the file to `finished/`. `RecordingIngestor` converts finished files to AAC, creates a voice entry whose `id` is the file's UUID, and deletes the file only after the save succeeds. `MindloreApp.init` moves leftover `active/` files to `finished/` before any UI exists, and `RootView` ingests them at launch.

**Transcription** (`Mindlore/Transcription/`). `TranscriptionCoordinator` processes `awaitingText` voice entries one at a time. `TranscriberRouter` picks per entry: OpenAI when AI is on with a key and the entry was created after `aiEnabledAt`, otherwise `SpeechAnalyzerTranscriber` (`SpeechTranscriber`, falling back to `DictationTranscriber`). A failed cloud call falls back to the phone and records why in `textFallbackReasonRaw`. Recordings longer than the provider's limit are split by `AudioChunker` at their quietest points, each chunk carrying the previous chunk's tail as context. After each await it re-fetches the entry, and `applyGeneratedText` refuses if the user has typed.

**AI layer** (`Mindlore/AI/`). One account (Keychain key, base URL) serves three capabilities: `TextGenerator`, `Transcriber`, and `PageTranscriber`. `OpenAICompatibleTextGenerator` covers any Chat Completions server; `FoundationModelsTextGenerator` is Apple's on-device model, and a request with a schema goes through guided generation (the `JSONSchema` converted to a `DynamicGenerationSchema`), so its answer is JSON the same parsers read. Insights run on either, chosen by `insightsGenerator` (off, on device, OpenAI; defaulting like titles: OpenAI once a key is saved, else the phone), so a phone with no key still fills the map, Today, and Reflect. The on-device request uses `InsightsPromptBuilder.Budget.onDevice`: the first 4,000 characters, a short vocabulary, no cleaned text or custom prompts, no worked examples (the small model copied them into its answers), and the area list on the field itself. `OnDeviceInsightsLiveTests` runs a real entry through Apple's model when the machine has it; OpenAI remains the better reader, and its prompt is unchanged (`theCloudBudgetIsUnchanged`). Bios still need OpenAI (`automaticBiosUsable`). `aiEnabled` is the one gate every OpenAI path checks, and nothing in the app turns it on without `AIConsent` (`Views/AIConsent.swift`), an alert naming OpenAI and what it gets, shown by the Use AI switch and by saving a key; only Allow turns AI on, since App Review 5.1.2(i) wants an explicit yes before journal data reaches a third-party AI. Saving a key no longer turns AI on by itself. Every failure becomes an `AIError` carrying codes only, never provider text. `AIJobPolicy` holds the shared rules for the three jobs (text, title, insights): attempts and the last failure live on the `Entry`, counted before the request, capped (text 3, title 2, insights 2), with permanent failures waiting for a manual retry and offline failures rolling the attempt back. `AIPassTrigger` gives each entry exactly one automatic pass, at the first of: the editor closing on a finished entry, a recording's text arriving, page text being approved, or a launch sweep. Drafts (`Entry.isDraft`, typed entries until Done) and unapproved photo entries are never eligible. Coordinators capture `contentRevision` and drop results if the entry changed underneath them.

**Photo entries** (`Mindlore/Pages/`). `PageOrderView` collects pages from VisionKit or Photos, saving each as it arrives; confirming locks the order. `PageTranscriptionCoordinator` sends one request per page and saves each page's text as it lands, so a failure resends only what is missing. The joined text waits for `approveText()` before any other AI runs on it. Editing pages afterwards works on a draft and, if it differs, restarts the entry through `restartPages(applying:)`.

**Insights** (`Mindlore/AI/Insights/`). One structured request per entry, with a field per enabled section (`InsightsPromptBuilder`), parsed tolerantly: unknown moods and mention kinds are dropped, tags normalized, lists capped. Cleaned-up text is offered for transcribed entries (voice and pages, never typed), applies only to the exact text it was made from, and keeps `Entry.originalText` plus `cleanupAppliedHash` so revert survives regenerating or deleting insights. Format voice notes automatically (`autoApplyCleanedText`, off by default, on Settings' AI screen; owner 2026-09-24) applies a voice entry's cleanup as soon as insights produce it, through `Entry.applyCleanedTextAutomatically`, which is `applyCleanedText` (the Review button's own apply) behind `cleanupAppliesAutomatically` (voice only, never `textEditedByUser`, never a draft). A page's cleanup stays an offer, since its text was already approved. With the editor open the cleanup is held in `InsightsCoordinator.heldCleanups` (memory only; the editor hides its Review banner meanwhile) and applied at the next `processQueue`, which a close fires, after the same checks run again. Applying it never makes insights stale and flags no further pass. The cloud request also asks, with the moods, for `thinkingPatterns` (`ThinkingPattern`: six named habits of how the author talks about themselves, empty unless clearly there, at most three, dropped for notes and creative work as moods are, never on device). "loose ends" is never kept as a tag in any spelling (`InsightsPromptBuilder.isBlockedTag`: it had become a label on nearly every note), and `BlockedTagSweep` took it out of existing entries at launch. Settings, AI has Redo insights for every entry (`InsightsCoordinator.redoAll`, owner 2026-09-23): each entry `canRunAI` accepts gets Run AI's reset and goes through the same queue, oldest first, one at a time, with a count and Stop (which takes back what hasn't started). The queue is the entries' own `insightsPending` flags, so a run cut short finishes at the next launch without the count. Offline it waits for the network rather than failing every entry, and a mood the user picked by hand (`moodsEditedByUser`) survives it, since redoing a journal must not undo every correction in it.

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
- **The empty screen suggests three questions, from five kinds.** `AskSuggestions` decides and reads
  no SwiftData; `AskSuggestionSource` fetches, the `TodayComposer`/`TodaySource` split. A recent
  name (phrased for its kind), an open thread quoted in the user's words (loose-end text is an
  imperative, so it is quoted rather than grafted into a sentence), the area the last 30 days leaned
  on under the user's name for it, a question about time, and a second name. Which three turns with
  the day and holds still within it. The source applies Today's visibility rules, not `AskSources`':
  suggestions never leave the phone, so the promise is only that a hidden or muted name never
  renders, and a thread with any hidden or muted subject is dropped whole. They refresh on the
  graph and save revisions, never from the view body.
- **Chat writes notes, and only notes** (owner, 2026-09-24). OpenAI only. `AskPrompt.schema` adds
  nullable `noteTitle`, `noteText` (the whole note as Markdown) and `editNoteHandle`: a handle
  means change that note, none means make a new one, one per turn. `editNoteHandle` lists only
  notes the request carried whole (`Context.wholeEntryIDs`), and `AskAnswerParser` drops an edit
  aimed anywhere else rather than making a new note. `AskPrompt.noteRule` allows either only when
  the question itself asks, never because journal text does. Notes Chat made or changed in the
  conversation are pinned right after the focus entry by `AskRetrieval.plan(noteEntryIDs:)`, whole,
  within 8,000 characters, which is how "add butter to that" reaches the list; `AskSources` renders
  a note block as Markdown so a rewrite keeps its layout. `AskNoteWriter.insert` gives a new note
  the answer's own id (no second note for one answer, and a reopened conversation finds it with no
  `AskMessage` field), `setKindByUser(.note)`, not a draft, `textGeneratedBy` "chat:…".
  `AskNoteWriter.replace` re-checks at landing that the target is still a finished sendable note
  whose text is exactly what was sent; it never touches `contentRevision` (insights go stale by
  hash, as after typing) and keeps no old text. Only an answer that arrived whole writes. A new
  note gets its automatic pass through `AskService.onNoteCreated` (`AIPassTrigger.Moment.chatNote`);
  an edited one does not. `AskTurnView` shows "Note created" or "Note updated"; only "created"
  survives a reopen. `ask.noteCreated` and `ask.noteEdited` log counts only. Tests: `AskNoteTests`.
- **A conversation can be about one entry.** "Chat about this entry" in the editor's and the
  insights sheet's More menus (shown only when `canRunAI` allows the entry) jumps through
  `AppRouter.showAsk(aboutEntry:)` to a new conversation with `AskService.focusEntryID` set.
  `AskRetrieval.plan` takes the focus first, whole up to `maxFocusCharactersOpenAI` (24,000; the
  index's `textCharacters` is the uncapped length), before any slice divides the rest, so the
  journal is still searched; a question matching nothing keeps the focus instead of falling back
  to the newest five. It renders first with `AskPrompt.focusNote`. The tie is in memory only, by
  choice (owner, 2026-09-23): no model change, and a conversation reopened from History carries on
  through what it cited. `isRunning` belongs to the conversation that asked (`runningIn`), so an
  answer abandoned by the jump can't hold the new conversation's send button.
- **The field** is Liquid Glass over solid Paper with a short fade above, on the whole bottom stack
  so the fade never lands on the search panel's last row and catches its tap. Dragging the
  conversation or tapping empty space dismisses the keyboard (it covers the tab bar); not on the
  search results, which only show while the field is focused and would vanish mid-scroll.
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
edge (one entry mentions one entity); its `linkedEntity`/`entry` relationships exist solely for
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
- **Names added by hand.** The editor's More menu (and the insights sheet's) has Add a name
  (`AddNameView`), for a name the insights missed or an entry they never read. `GraphEditor.addName`
  writes a `.user` link, so a rerun keeps it and an AI mention of the same key is claimed by it; a
  new entity is left unclaimed, so removing the name (the "Added by you" card) prunes it.
  `GraphServices.addedNames` lists the user links no mention or tag accounts for.
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
  caller-resolved `[LinkInput]` into weighted `Edge`s: two entities sharing an entry get an edge
  (sharing a part of it, when the entry has parts; see Parts below),
  weighted by a 90-day half-life so a recent shared entry counts for more (`EntityGraph.build`),
  (`EntityGraph.build`). `GraphSimulation` (also `nonisolated`, a plain class, not `@Observable`,
  since the canvas ticks it every frame from inside its own draw closure) is the engine:
  phyllotaxis initial placement, many-body repulsion, link springs, centre gravity, and collision,
  each with a deterministic zero-distance fallback; sticky `pin`/`unpin` for a user's drag. It
  stays warm on demand: a drag raises `alphaTarget` so alpha holds instead of decaying, and
  `update` swaps nodes and edges in place so a window or kind change moves the picture rather
  than restarting it. `GraphCanvasView` is the `Canvas`/`TimelineView` drawing surface Mind embeds;
  `FrameTimeSampler` (`GraphCanvasModel.swift`) measures frame p50/p95 and work p95, and
  `graph.rendered` logs them with node/edge counts once per appearance, never per frame.
- **Navigation.** `EntityRoute` carries an id, never an `Entity`, so a merge or prune while a page
  is on the stack doesn't invalidate what's pushed; `EntityView` resolves it fresh
  (`EntityPagePresentation.resolve`). A screen that owns its own `NavigationStack` over entity pages
  (`MindView`, over `AppRouter.mindPath`; `EntryInsightsView`'s chips; `EntityPeekCard`) must set
  `.environment(\.entityRouteReplacer, ...)` itself, or a merge made from inside it leaves a stale
  loser id on that stack's own path instead of redirecting to the winner; a view pushed into an
  existing stack (`EntityView` itself) inherits the enclosing stack's replacer for free.
- **Mind** (`Views/Mind/`) is the second tab: one full-screen map where each channel means one
  thing (owner, 2026-09-23; the spec and its measurements are `tasks/mind-overhaul-spec.md`).
  Colour is kind (owner, 2026-09-24; `EntityKind.color`: blue person, green place, amber
  organization, violet project, coral event, stone other), each colorset with a light variant deep
  enough for Paper and a lighter dark one, and never a fixed system colour, which stays the same in
  both schemes; a tag is a 2pt dusty-mauve pin (`KindTag`, owner 2026-09-24: grey was dull and olive read wrong) (`GraphSimulation.tagRadius`, one size at any
  count, still tappable at `GraphHitTest.minimumNodeRadius`) with a lighter label, so the many tags
  read as weighing less than names; size is entries in the window; time is the window control at the top (`MindWindow`: Month, 3 months, Year, All;
  3 months by default, remembered per launch, never a setting). Edges come only from the window's
  entries. **The map reads journal entries only** (owner, 2026-09-23): `buildSnapshot` drops notes
  and creative pieces, so their names, tags, edges, and share of a shared name never draw, and an
  entry switched to either kind leaves at the next rebuild (`setKind` bumps `revision`); nothing
  stored changes, and search, entity pages, Today, and Ask still count every kind.
  `GraphServices.mapSnapshot` reads the store once per `revision` into a `MindMapSnapshot`, which
  also carries every non-draft journal entry's date (the denominator a share needs) and
  `linkedEntityIDs`, the names a journal entry has, which sizes the map and tells an empty map from
  a quiet stretch (`entities` keeps every browsable name, so the drawer finds the author by name); `MindView.frame` (static, pure) turns it into nodes, edges, and areas for the window and
  the drawer's kind segment. A journal of `MindMap.largeJournal` (60) names or more draws a name
  only with two mentions in the window; the drawer still lists it. The play button left of Month
  (`MindReplayPlayer`) plays the window on screen (owner, 2026-09-23), from its start (or the
  first mention, if the journal is younger) to today, over 6 seconds in 100 ms steps, publishing
  every fifth step (publishing each pushed frame p95 to 32 ms). The player trims the snapshot at
  the window's start (`MindMapSnapshot.since`, start-exclusive like the windows) and renders each
  step as all time, so the last step is the window's own map (`MindReplayTests`); the window stays
  selected while it plays, and picking any window ends it there. The date chip reads days for
  Month and 3 months, months for Year and All; the haptic ticks on a month change only.
- **`MindStats`** (`Graph/`, pure) is every number Mind shows for a window, computed once per
  (revision, window) by `MindView` into `MindDrawer.Stats`, never per frame: entries per name,
  its area (`EntityTally`), a 16-bucket sparkline over the window and the three before it, and
  "what changed". Changes are by **share** of entries against the three windows before, so a
  quiet month never makes everyone quieter: new (first mention inside the window, twice), back
  (three earlier mentions, then silence of two windows or 45 days), more lately (three in the
  window, tags four, double the earlier share, with an earlier mention), quieter (two a window
  before, tags three, half the share or less). Tags are never new or back; nothing shows for All
  or without a baseline; the author (`SettingsStore.userName`, by name or alias) is never listed.
  Ranked by the shift in share times the larger count, capped at four. On the story journal three
  months reads Greg quieter (1 of 42 entries, down from 22 of 155) and running more lately.
  Windows are start-exclusive, so a window and its baseline never share an entry.
- **The drawer.** `SearchPanel` is Mind's own pull-up panel (not a system sheet, which would
  cover the tab bar and the record accessory). It is dragged through `DrawerSurface`, which alone
  holds the drag state, so a tick re-renders neither the panel body nor the map: the panel is laid
  out once at full height and moved by offset, the list is skipped while its data is unchanged, the
  ends rubber-band, and release settles on a spring seeded with the finger's velocity (owner,
  2026-09-24: per-tick height changes re-laid out every row and made it jerky). The window
  buttons and the top bar's other buttons are 44pt targets. It holds the search field, kind chips (All, People,
  Places, Projects, Themes; Themes are tags, and organizations, events, and other show only under
  All) that filter the list, the cards, and the map, then `MindChangesRow` ("What changed", tap
  to focus, `mind.changeTapped`), `MindRankedRow` for every name the window holds (kind badge
  and `Sparkline` in the kind's colour, count, change word, open threads; by count, then most recent), and a
  Hidden names row when anything is hidden. The review questions are a `TidyUpButton` on the map's
  top bar with their count, shown only while there is one (owner, 2026-09-23: at the foot of the
  drawer nobody scrolled to it); `MindView` owns the count and the session's skips, which the
  drawer takes as a binding. Even at full the drawer sits below the top bar. A plain-style glass button on the bar needs `.contentShape` over its whole 44pt shape: glass doesn't take touches, so Tidy up once answered only on its glyph and badge and a tap between them cleared the map's focus. `MindDrawer` joins the window's numbers with `MindDirectory`'s rows, which count open
  loose ends through merges and key their own refresh because closing a loose end doesn't bump
  `graph.revision`. Searching ignores the window and ranks every name, hidden ones in their own
  section. `TidyUpView` holds the `ReviewQueue` questions one at a time ("Which one?" before
  "same person?", because it is about a sentence the user wrote; skips are session-only) and the
  hidden names.
- **The card and the page.** `EntityPeekCard` is the shared card for any name: half a year of
  weekly bars with "last mentioned" in days, "Often with" names with the entries each shares, a
  quieter themes line, open threads, and the bio's first line. It keeps its own narrow fetch,
  since it also opens from the editor and Ask. Names and themes come from one
  `GraphServices.mentionedWith` list split apart, because tags share the most entries with anyone
  and crowded the people out (owner, 2026-09-23); `mentionedWith` ranks by
  `EntityGraph.Edge.entries`, the entries whose part placement made the edge, so the card, the
  page, and the map agree. `EntityView` stays a `Form` and leads with insight: the header (kind,
  area, description), Presence (a bar per month across the journal, "87 entries · Oct 2025 to
  Sep 2026 · busiest in November 2025"), Feeling (the moods its entries carried beside the
  journal's usual, counted with `ReflectAggregator`, five or more entries with a mood only),
  loose ends, Often with, entries, the map for a place, and Manage. Admin that doesn't navigate
  (rename, kind, description, contact, place link, aliases, Hide) is behind the toolbar Edit in
  `EntityEditView`; what pushes a route (merged rows with undo, Merge into, Show in Mind) stays on
  the page, where the stack's destination and `entityRouteReplacer` are.
- **Mind's materials and motion.** Liquid Glass goes on what floats: the top bar (one
  `GlassEffectContainer`, a shared `glassEffectID` growing the play button into the replay's
  date chip) and `MindPeekOverlay`'s wrapper. Glass never goes inside `EntityPeekCard`, which is
  also presented as a partial-height sheet that iOS 26 already draws as glass. `SearchPanel` is
  glass at `.peek`, a field floating over the map, cross-fading to opaque Paper over the first 48pt as it opens and holds rows,
  because the house rule says never glass on list rows. Labels skip rather than print over a
  higher-ranked one (`GraphLabels.unobstructed`), and the map recentres when the window changes.
  `BloomCurve` is the sampled stand-in for `Motion.bloom`: a `Canvas` has no transition system.
  Bloom fires only for a name that was not on the map before an entry was written, never on the
  first build, a window or kind change, or a replay. The canvas pauses once the layout settles.
  Tests: `MindStatsTests`, `MindDrawerTests`, `MindMapTests`, `MindReplayTests`,
  `MindDirectoryTests`, `EntityPeekPresentationTests`, `EntityPagePresentationTests`.
- **Diagnostics and privacy.** Every graph and `mind.*` event carries only ids, counts, kinds, and
  durations, never a name, alias, bio, or surface string; `AIDiagnosticsPrivacyTests` runs real
  graph components, including a Mind frame, the stats, and a replay in every window, against a sentinel
  string used as every one of those fields and asserts it never reaches the log.
  `docs/privacy-coverage.md` maps every event in the app to the test that drives it, or says why
  none can.

**Entry kinds** (`Models/EntryKind.swift`, `Entry.kind` over the stored `isCreative` and `isNote`
flags, `AI/Insights/CreativeSignals.swift`). An entry is a journal entry, a note, or a creative
piece, and the kind decides what an insights run is allowed to say about the author's life
(`EntryKind.keeps*`, applied by `InsightsResult.restrict(to:)` before anything is written). A
poem, lyrics, or a story is work the author made, not an account of their life, so it keeps its
title, tags, and a line saying what it is, and gets no names, no area, no mood, no
loose ends, and no parts (owner, 2026-09-22). A note (a list, a plan, a recipe, notes from a
meeting) is kept for use rather than telling what happened: it keeps its names, area, loose ends,
and parts, and carries no mood, so a grocery list never colours Reflect's week (owner,
2026-09-23). Neither kind puts anything on Mind's map, which reads journal entries only (owner,
2026-09-23). The insights request asks `entryKind` (life, note, or creative) first. OpenAI's
answer is trusted; the on-device model's is not: prose is never creative on device, a line over
15 words means prose, only text laid out like verse gets a second single-question request, and
on device nothing is ever filed as a note (`CreativeSignals.decideKind`). The error that matters
is life filed as something less, which silently drops names, threads, or moods, so the bar is
zero of those: `CreativeClassificationQualityTests` holds a labeled set, 0/12 wrong on device with
the haiku and prose story as asserted misses, and 19/19 on OpenAI measured with the two-kind
request. The live OpenAI test now also fails an account of a day filed as a note
(`CreativeCorpus.mayBeNote` names the four lists that may be); that has not yet been measured
against the three-kind request. The user's pick is never
overridden: `EntryKindPicker` sits under the title in the editor (both modes) and on the insights
sheet, writes through `GraphServices.setKind`, which drops at once and with no AI call what the
new kind never keeps (the user's own loose ends stay theirs), and the caller reruns insights only
when the new kind keeps more than the old (`EntryKind.keepsMore(than:)`). Every row carries an
`EntryKindBadge`; the journal has a Notes chip and a Creative chip beside the area filters. Ask
and Reflect mark a creative or a note block so neither takes a lyric or a list as something that
happened.

**Parts** (`Models/EntrySection.swift`, `EntryInsights.sections`, `Graph/EntryParts.swift`). The
cloud insights request also asks for the entry divided by topic, only when it clearly moves
between things: each part has a topic, one sentence, its own areas, tags, and names, and the
first words of the part, which the parser looks up in the text to store a character `offset`
(nil when not found, never backwards). Nothing marks the text up. **What parts are for is the
map** (owner, 2026-09-23): two names in one entry connect only when they share a part, instead of
everything in an entry joining everything else because it was written at one sitting.
`EntryParts.Context` places each link at snapshot time, never stored, so older entries and names
added by hand need nothing migrated: by the part's own `names` or `tags` list, by the part's span
of text a name is written in, and a tag only by the lists. The span is read against the text the
offsets came from (`GraphServices.analyzedText`): the entry's own while it is still what was
analyzed, the original after a cleanup replaced it (cleanup drops fillers, so offsets would land
late in the cleaned text), and none after any other edit, when only the lists place names. Text
before the first placed part belongs to the opening part. A part's `names` are stored as written
and as grounded, like mentions, so "Sarah Kim" still places the entry's "Sarah". The map's
snapshot is cached per graph revision, so an edit's switch to list-only placement shows on the
map at the next graph change; `mentionedWith` reads fresh and places only the subject's entries. A name placed in no part connects to
nothing from that entry (owner, 2026-09-23: the map's problem was clutter) and stays on the map,
since a node shows for its mentions, not its edges, and other entries still link it. Only an
entry with fewer than two parts, which has nothing narrower to go on, connects everything in it
as before. `EntityGraph.LinkInput.parts` carries it (nil for an entry with no parts, empty for
a name placed in none); `EntityGraph.build` unions an entity's parts across its links and skips
a pair whose parts are disjoint. Both `mapSnapshot` and
`mentionedWith` read it. The parts' tags are also folded into the entry's own, after them and
under the same cap. Parts are metadata for the map, not something to read: the insights sheet
never shows them, since their tags and names are already on its own cards. Never asked of the on-device model (`Budget.sections`), and dropped for creative work.
`InsightSectionsTests` covers the schema, parsing, and storage; `PartAwareGraphTests` the edges.

**Loose ends** (`Models/LooseEnd.swift`, `AI/Insights/LooseEndWriter.swift`). Open threads an entry
leaves ("need to call the landlord") become `LooseEnd` records with a status (open, resolved,
faded, dismissed), subject `entityIDs`, an optional due date, and the entry that raised them; same
CloudKit rules as `Entry`. Insights writes them: `LooseEndWriter.candidates` sends the known ones
as handles (the entry's own first, so a rerun reuses them, then others dated before the entry,
never after, since an old page can't settle what hadn't happened yet), and `apply` records
mentions, resolutions, and new ones. The model's `sameAs` points a mention back at a known handle
instead of creating a duplicate. AI never resolves one the user touched (`userTouched`) or one
sourced from or dated after the entry itself. Done, Let go, and Reopen all go through
`LooseEnd.setByUser`, and all three mark it `userTouched` (owner, 2026-09-24): a reopened loose end
is the user's to close, so no entry's insights settle it again. A reopen also restarts the fade
clock: `LooseEnd.fadeDate` (read by the sweep and Today's card through
`LooseEndFading.date(…, reopenedAt:)`) gives it at least six weeks undated, or a week when dated,
from the reopen. `reopenedAt` is derived (open plus touched), not stored. Nothing is deleted: `LooseEnd.fade` marks one faded
after 42 days of silence or a week past its due date, run in the launch sweep after the graph.
The recorder offers one at a time through `LooseEndPrompter` (overdue first, then the most recently
mentioned, never the same one within 3 days). Tests: `LooseEndWriterTests`, `LooseEndLifecycleTests`,
`LooseEndPromptTests`, `LooseEndCoordinatorTests`, `LooseEndBarTests`.

**Life areas** (`Models/LifeArea.swift`). Nine fixed areas (work, money, health, mind, family,
love, friends, play, home), at most two per entry, replaced per-entry themes because those never
connected anything. `EntryInsights.areasRaw` stores raw values, which is also what the prompt
sends; the user's renames and hidden set live in `SettingsStore` (`lifeAreaNames`,
`hiddenLifeAreas`, `visibleLifeAreas`) and only change display. An entity's area is computed,
not stored (`MindStats.areas`, `MindMap.primaryAreas`); the map no longer colours by it.

**Entry dates.** `createdAt` is when the entry reached the app and drives every automation rule. `entryDate` is where it belongs in the journal, editable; a picked day is noon with `entryDateIsDayOnly`, and `EntryDateRepair` fixes any entry whose untouched date drifted. A date written at the top of a photographed page is the day the page was written, so a photo entry takes it without asking while it has no picked day (`!entryDateIsDayOnly`), from the page transcriber first and from the insights run's `writtenDate` (asked for typed and photo entries) as a second reading, whatever the typed-entry "use the suggested date automatically" setting says; once a day is picked, by the user or an earlier pass, a different reading is only offered. Turning "Suggest entry dates" off turns both off. Approving page text also asks for a title through `AIPassTrigger.requestTitle`, whether or not the entry's one automatic pass is already spent, so a photo entry is never left titled by its first line.

**Settings** (`Mindlore/Settings/`, `Mindlore/Views/Settings/`). `SettingsStore` reads through a `KeyValueStore` protocol using `object(forKey:)`, so a missing value means "use the default" rather than `false`. `PrivacyInfo.xcprivacy` declares the UserDefaults reason. Settings is a sheet from the gear at the top right of Journal (owner, 2026-09-24: it left the tab bar, and Journal's title went inline to give the room back), and its root is five rows, each its own screen with the one value worth seeing beside it (owner, 2026-09-23: one Form of eight sections ran past two screens): General (`SyncSettingsSection`, the `AppLock` Face ID lock in `AppLockSection`, whose cover is its own window above every sheet and can never become key, `AppearanceSection` for light, dark, or system, and `JournalDataSection`: `JournalExport` to a folder, `JournalImport` to put one back, and `JournalWipe`, the one delete with a confirmation dialog instead of Undo), AI (use AI, the key, What AI does, Format voice notes automatically, with an Advanced screen for model fields, cloud fallback and custom prompts), Your journal (life areas, how you're written about, the font, keep recordings, start recording right away), Today and reminders, and About (`JournalTotals`: whole-journal counts only, never averages or streaks, rows at zero left out). Life areas and your name sit under Your journal, not AI, because both work with AI off. Your journal also has What matters most (`lifePriorities`, up to three areas, read by Life). Eight keys are internal state, not settings, and never get a control: `aiEnabledAt`, `automationStartedAt`, `askGeneratorChosenByUser`, `todayDismissed`, `lifeAreaNames`, `hiddenLifeAreas`, `providerAccounts`, `lifePrioritiesAsked`; find every reader before touching one. UI tests reach settings through `app.openSettingsSheet()` (`MindloreUITests/NewEntryFanHelpers.swift`), which taps `settingsButton`. The "Open AI settings" buttons (the insights sheet, Mind's empty state) and the welcome screen's Add a key present `AISettingsSheet` themselves rather than routing, so nothing presents over a sheet that is still closing; from the insights sheet, closing Settings lands back on it. `tasks/archive/settings-sprint.md` has the audit.

**Export and import** (`Mindlore/Export/`, owner 2026-09-23: import reads only a Mindlore export). `journal.json` has two halves: readable fields for a person or a script, and `records` (`JournalRecords`, version 2), every stored property of every model named after the property it copies, with recordings and page photos as files in `media/`. `JournalRecordsCoverageTests` holds each record against SwiftData's schema, so a new model property fails it until it is carried or listed as left out (job bookkeeping and what `recount` derives). `JournalImport` restores records rather than re-analysing: no AI runs and the map comes back as exported. It keeps ids, never overwrites (an entry already here keeps its own copy whole, and the export's pages, insights, links, and loose ends for it are skipped with it), reuses a visible unmerged name the journal already has under the same key and kind and rewrites every entity id that named the imported one (`mergedIntoID`, `notSameAs`, `originalEntityID`, `unsureAmong`, loose-end subjects), sets `graphIndexedAt` equal to the restored `insights.generatedAt` so `GraphIndexer` doesn't re-resolve the links, saves in batches of 100 with imported entries unstamped, reads media per entry and only from inside the folder, and refuses a version 1 export (no records to restore from). `JournalImportTests` round-trips a journal with every kind of record through export, import, and export again and requires the same records.

**Views** (`Mindlore/Views/`). `RootView` is a five-slot `TabView`: Journal, Mind, +, Reflect, Chat (owner, 2026-09-24; Chat is Ask's tab and screen title, while the code keeps the Ask names; `AppTab` in `Views/Shell/AppRouter.swift`, which also owns each tab's path and cross-tab routes). The + (`AppTab.newEntry`) never becomes the selected tab: `NewEntryFan` draws its own ember + over the bar's middle slot (centred on the visible bar, whose frame `TabBarProbe` reads from UIKit, because the system bar reports a selection but never a press, a slide, or a release) and touching it pops Write, Record, and Pages out on a half circle (`NewEntryFanLayout`, pure and tested). Tap an option, or keep the finger down, slide onto one, and let go; letting go on the + leaves the fan open, anywhere else closes it. The tab underneath stays for VoiceOver: `AppRouter.select(.newEntry)` toggles the fan and writes `tab` back so the bar never shows the empty tab. Every jump closes the fan. Record in the fan starts recording at once; Write is `showNewEntry`; Pages is `showNewPages`, a one-shot Journal consumes because the page cover lives there. Journal's toolbar has only the Settings gear. The editor hides the tab bar while it has the keyboard (iOS 26's keyboard is glass and the bar showed through it), and `AppRouter.editorHasKeyboard` hides the + with it. Recording lives in the bottom accessory (`RecordAccessory`) and keeps going while tabs change. The empty states' Record opens the recorder **ready** (`RecordingSession.Status.ready`): nothing is captured until its own button is tapped, unless the `recordOnOpen` setting is on (off by default, owner 2026-09-23) or the fan or Siri asked (`begin(startsNow: true)`); the accessory shows only a real recording (`showsAccessory`), and closing or minimizing a ready recorder (the New Entry and Ask intents do the latter) discards it, since it has no accessory to come back through. Siri's Start Recording starts a ready recorder. `RootView` owns the saver, ingestor, `RecordingSession`, the four coordinators, `AIPassTrigger`, `EditorPresence`, `NetworkMonitor`, `GraphServices`, `AskService`, `DailyReminder`, and the router, and passes them through the environment. `EditorLifecycle` (`Views/Shell/`) is what runs when an editor opens and closes: presence, deleting a blank entry, discarding audio unless kept, and the `.editorClosed` AI pass. Past entries open in read mode (`EntryReadMode`): the same `GrowingTextEditor` made non-editable, with the names linked as `.link` attributes in their kind's colour (a tap opens the peek through `textView(_:primaryActionFor:)`), and a tap anywhere else reported as a UTF-16 offset so typing starts with the caret on that character. After a recording, `KeepCard` (`Views/Capture/`) shows what the journal noticed, from stored data only, no AI call. Deletes (an entry, a conversation, the key) go through `UndoQueue` (`Views/Shell/`): the item hides at once and the delete runs after five seconds, on the next delete, or when the screen or scene goes away, never deleted and rebuilt. The editor's Delete entry pops through `AppRouter.deleteEntry`, whose close rules skip the AI pass, and the list schedules it behind the same Undo a swipe gets. Colors, type, motion, and haptics come from `Mindlore/Design/`, and colors only from the asset catalog's light and dark variants. The user's own words take the `JournalFont` picked in Settings (serif by default, or sans, rounded, monospaced; `Design/JournalFont.swift`), carried through the `journalFont` environment value that `.journalText(_:weight:)` and the editor's `UIFont.journal(_:design:)` read; never set `design: .serif` directly. The app's own chrome stays SF. RootView runs transcription in one lane and titles plus insights in another, and resumes both when the network returns. `EntryListView` lists entries and opens `EntryEditorView` or `RecordingView`. The editor is one scroll view: header (banners, player, page strip, title, kind picker) above a `GrowingTextEditor` (a UITextView that grows with its text and never ends shorter than the screen, so a tap below short text puts the cursor at the end). The text view only ever takes text pushed from outside (a transcription, a cleanup, a revert): what it reported itself through the binding is never assigned back, because assigning a UITextView's text, even an equal string, resets its selection to the start, which is what put the second keystroke of a new entry in front of the first. Focus with the caret at the end is asked for from the text view's own `onAppear` for a new entry, and from `startEditing(at:)` for Edit and a read tap. If the app leaves while the text view is editing (a third-party keyboard's voice typing records in its own app and types in on return), the coordinator restores first responder and the caret when the app is active again, held back while `AppLock` is locked; only a user dismissal sets `resignedByUser`. System dictation must never see the storage change under it, or UIKit ends it at once (the dictation mic looked dead): plain words into a plain paragraph are left as UIKit wrote them, typing attributes are reset only when a kept key changes, and while the input mode reads `dictation` (a third-party keyboard's dictation bar) the coordinator only reports text and normalises what was dictated once it ends.

**Formatting** (`Models/EntryFormatting.swift`, `Views/Editor/`, plan in `tasks/editor-formatting.md`). The user never sees syntax. `Entry.text` stays the plain words every reader takes, and the layout lives beside it in `Entry.formattingRaw` (`EntryFormatting` JSON: a block per paragraph ordinal, heading1, heading2, bullet, number, check, checked, or quote, with an indent of 0 to 3, and bold/italic/strike spans by UTF-16 range; nil when plain). `FormattingStyle` is the codec to and from UITextView attributes: a character carries its paragraph's block and indent and its own inline mask as custom attributes, markers are `NSTextList`s on the paragraph style drawn by TextKit 2 in the gutter (never characters), and consecutive numbered items share one list object so TextKit counts them. UITextView's typing attributes keep only the font, colour, and paragraph style (measured in `GrowingTextEditorTests`), so typed characters arrive without the custom keys and the empty paragraph after the last newline has nothing to carry them: the coordinator applies Return itself, holds that trailing paragraph's block (`trailing`), and after every edit re-marks the touched paragraph from whichever character still has the key (`blockAndIndent`) and gives the inserted characters the caret's inline marks. `ListEditing` holds Notes' Return and Backspace rules (continue the list, an empty item leaves it, Backspace at the start takes the marker before a character); `FormatBar` is the `inputAccessoryView`, hidden while `RecordingSession.showsAccessory`. A tap in a checklist item's gutter ticks it in either mode. Heading 1 is the title's own style (`.title2` semibold), heading 2 `.title3` semibold. Markdown exists only at the edges, in `MarkdownCodec`: `JournalExport` renders it, and a cleanup comes back as Markdown (the prompt asks for lists where the author spoke one) that `Entry.parseCleanup` reads into words plus formatting, with `originalFormattingRaw` kept for revert. Text set from outside (`applyGeneratedText`, `replaceWithPageTranscription`, `restartPages`) clears the formatting. Formatting-only edits change no hash, so they never make insights stale. A list row shows the kind badge, the date the header leaves out, and two lines of `Entry.previewText`, never the day the entry was added: once its day is changed, the day it belongs to is the only date that matters. `EntryInsightsView` is a sheet over the editor, never a push, because the editor's `onDisappear` runs its close rules. It is a scroll of `InsightCard`s on Paper (not a `Form`), its scroll view named `insightsSheet` so UI tests scroll it rather than the editor underneath. The entity page stays a `Form` on purpose: its rows carry swipe actions, a disclosure, and links a hand-built card would lose, and an inset-grouped section already is a rounded card, so Paper behind and `Palette.card` rows are what make it match.

**Today** (`Mindlore/Views/Today/`). The header above the journal list: a greeting, a seven-dot
week strip, and one horizontal row of cards to page through each day ("2 of 9" under it).
`TodayComposer` is `nonisolated` and reads no SwiftData, the same split as `EntityGraph`;
`TodaySource` does the fetching, walks merges through `EntityDirectory` (`Graph/`), and drops
hidden and muted entities. The row opens on the open loose end that most needs attention (due
today, else fading soonest), then the day cards (a thread the last entry closed, this day in an
earlier year, a well-linked name whose `lastLinkedAt` is over 30 days old, rotating one name per
day, the latest entry's summary), then every other open loose end in the order they would fade.
Nothing backs two cards. A day card's X is day-scoped (`TodayDismissal` in `SettingsStore`,
thrown away when the day changes). A thread card has no X and no swipe-dismiss (the horizontal
swipe is paging): it stays until Done (resolved), Let it go (dismissed), or it fades, and it shows
the fade date from `LooseEndFading`, the one rule the fade sweep also reads. Reflect's Loose ends
tab lists every loose end, open or closed; Today shows only open ones. `Entity.resurfacingMuted` is the per-name mute; it is in `GraphIndexer.recount`'s
keep-list beside `hidden`, or a muted name that loses its last link is pruned and returns under a
new id. A loose end with any hidden or muted subject never becomes a card. The header refreshes on
`.task(id:)` over the three monotonic revision counters, the day, and the two settings the
composer reads, never on a count.

**Intents and the reminder** (`Mindlore/Intents/`, `Mindlore/Reminders/`). Start Recording, New
Written Entry, and Ask Your Journal are App Intents in the app target (no extension, no entitlement,
nothing the Personal Team can't sign), with Siri phrases in `MindloreShortcuts`. An intent can run on
a cold launch before `RootView` exists, so it only leaves a request in `IntentRequests.shared`, a
free-standing singleton; `RootView` takes it with `.onChange(of:initial: true)`, which covers a cold
launch and a warm one alike, exactly once. `IntentHandler` carries it out through the calls the
app's own buttons use. Record while recording brings the recorder back instead of a silent no-op.
A new entry or Ask puts the recorder away first (it can be closed from outside and keeps recording
in the accessory, unlike the editor and page-ordering covers the router waits behind), then jumps;
Ask only fills the field, never sends. `DailyReminder` is one local notification a day, off by
default, fixed neutral words, no badge. It schedules a week of single notifications rather than a
repeating one, because "skip today if you've written" can only be decided when scheduling; it
adds before it prunes, so a reschedule cut short by suspension keeps the old week; and a reminder
iOS won't show (permission withdrawn in Settings) switches off with the footer saying why. Settings'
Today and reminders screen says when the next one is and whether today went because you already
wrote (`DailyReminder.next`, `skippedToday`), since a skipped day looked exactly like a broken
reminder. `ReminderPresenter` shows it over the open app, which iOS otherwise drops; it is held by
a static because the centre keeps its delegate weakly. The
notification centre sits behind `NotificationScheduling`, faked in `DailyReminderTests`.

**Reflect** (`Mindlore/Reflect/`, `Mindlore/Views/Reflect/`). A week or month looked back on: where
the entries went, how they felt, and one generated paragraph about the stretch. The fourth tab
(owner, 2026-09-24), with three sides in a segmented control: Life, Recaps, and Loose ends
(`ReflectPage`). It opens on Life once Life has a reading and on Recaps until then; a jump that names
a side (`AppRouter.showReflect`, which Today's `WeekStrip` calls with Recaps) wins. An entry opened
from Reflect (a recap's question, a loose end, an area page) comes back to Reflect when it closes,
through `AppRouter.returnTab`, unless the user picked another tab meanwhile.

- **`ReflectAggregator` is the single source of these counts.** `nonisolated`, no SwiftData import,
  the same split `EntityGraph` keeps from `GraphServices`: given caller-resolved `EntryFact`s and
  `LooseEndFact`s and a `DateInterval`, it returns mood distribution, area split, top tags (capped,
  sorted by count then name), and loose-end opened/closed counts, always as one `Period` for the
  interval asked about, even an empty one, since a period the user is looking at needs an empty
  state, not a missing entry in a list. `AskRollups` reads it too, for mood and area lines on an
  aggregate question's month or year block; top tags stay out of that block, because a tag is
  closer to the entry's own words than a mood category or an area name.
- **`ReflectSource`** is the `@MainActor` fetching half, mirroring `TodaySource` against
  `TodayComposer`: it fetches `Entry`/`EntryInsights` for the period (bucketed by `entryDate`, not
  `createdAt`) and every `LooseEnd` (unfiltered, since one opened long before a period can still
  close inside it), and hands `ReflectAggregator` the facts.
- **`ReflectPeriodSelection`** is week or month plus an offset from now, clamped so Reflect never
  looks forward. `ReflectView` keys its refresh off the same three monotonic counters
  (`EntrySaver.revision`, `GraphServices.revision`, `JournalSaves.revision`) Today and Ask key off,
  never a count, in a `.task(id:)` over the selection and those counters together.
- **The narrative is new AI territory, not a Phase B "no new AI calls" surface.**
  `ReflectNarrator.narrate` asks for one paragraph per period the user actually opens: never
  persisted, never retried (reopening the period asks again), so it does not extend `AIJobPolicy`,
  which governs three per-entry jobs with counted attempts. The prompt carries only the aggregated
  facts already on the chart screen (mood distribution, area counts, top tags, loose-end
  opens/closes, entry count), never raw entry text. It resolves through the existing `AskGenerator`
  setting (`AIServices.askGenerator`) rather than a second AI toggle, and fails silently: the
  charts render on their own either way. `reflect.narrated` logs kind, entry count, duration, and a
  success bool, the same numbers-only rule as every other diagnostics event.
- **No advice, same rule as Ask and loose ends.** The narrative states what the numbers show and
  nothing else.
- **Loose ends** (owner, 2026-09-24). `ReflectLooseEndsView`: every open `LooseEnd` pinned on top,
  due soonest first (`ReflectLooseEnds.layout`), then the closed ones newest first by
  `sourceEntryDate` (the raising entry's journal day, so closing or reopening never moves a row),
  grouped by month, with All / Open / Closed chips.
  `ReflectLooseEnds` is the pure half (order, months, filter, row text); `ReflectLooseEndSource`
  fetches, walks merges, leaves out any loose end with a hidden subject whole (muted names stay,
  since muting is about Today resurfacing), and applies Done / Let it go / Reopen through
  `setByUser`, saving with `saveStampingEntries`. Open entry jumps through
  `router.showEntry(_:forReading: true)`. `reflect.looseEnd` logs the action and the previous
  status only. Tests: `ReflectLooseEndsTests`, `ReflectLooseEndSourceTests`.
- **No summary, no row** (owner, 2026-09-22). A week or month shows only once it has a generated
  summary; mood chips over nothing read as clutter, and "All caught up" must never appear. The
  running week gets one too, labelled "So far": `ReflectSummaryStore.generateIfNeeded` rewrites a
  week's summary whenever the fingerprint of its entries (ids, titles, text) changes, until a
  summary is written after the week ended, which is final. A failed rewrite keeps the old one.

**Life** (`Mindlore/Life/`, `Mindlore/Views/Reflect/Life/`, plan and decisions in
`tasks/reflect-tab-and-life.md`). Reflect's first side: what keeps happening and how it has felt,
the one part of the app allowed to suggest something (owner, 2026-09-24). Its rules hold for
everything on it: **code finds a pattern and a model may only word it**; every card shows what it
stands on and says nothing below its floor; mood is measured against the author's own baseline
(the year's mean valence), never absolutely, because journals over-represent bad days; it
describes situations, never traits, and never diagnoses.

- **`LifeSignals`** is the pure half (`nonisolated`, no SwiftData, the `ReflectAggregator` split),
  `LifeSource` fetches (non-draft entries with insights; mood only from journal entries; a loose
  end takes its raising entry's areas and date; hidden tags, areas, and names never show). No
  reading until 20 entries with insights span 21 days. Windows are Mind's (`MindWindow`, Month,
  3 months, Year; start-exclusive). It gives the headline (the biggest area, a twin within 80%,
  a tone only on 8 moods and 0.25 off the baseline), the areas (3 entries to show, 3 moods for a
  height; share is of entries, so two-area entries let shares pass a whole), recurring tags (3
  distinct months of a year or 4 weeks of 3 months; none for a month), what went quiet (10% and 6
  entries before, a third of that now), what changed (8 points of share or 0.3 of height), and
  follow-through by area (4 closed; `Contrast` when one area closes 30 points more than another
  lets fade). `LifeBubbleLayout` places the bubbles: size is share, height is feeling against
  usual, relaxed until none overlap, deterministic.
- **What matters most**: `lifePriorities` against the window's shares; under half an even spread
  is a gap and gets the sentence ("You said Friends matters to you right now...").
- **Words** (`LifePrompts` pure, `LifeWords` store). An area page opens with a paragraph and up to
  two quotes (OpenAI only: the phone's model wrote them in the author's first person and quoted
  paragraphs), rewritten when its entries change, at most weekly; quotes run six to thirty words; **a quote survives only if its
  words are in the entry its handle names** (`LifePrompts.verbatim`). About you is a portrait
  written once a month through OpenAI only (the on-device room is days, not a year): five parts,
  each line citing digest handles, from the numbers, the cached month summaries, and 150 digest
  lines spread over the year. "That's right" and "Not quite" (with a note) are sent to the next
  portrait. If the model sets `concern`, the portrait is replaced by `LifeConcernView` (988 in the
  US, findahelpline.com elsewhere) and nothing is suggested. Only entries `canRunAI` accepts are
  sent. `LifeLiveTests` judges both requests against the real model in the live job.
- **Something to try** (`LifeSignals.suggestion`, `LifeExperiments`). Weeks with two moods that
  sit 0.15 off the baseline are lighter or heavier; a tag or area in 3 or more lighter weeks and
  0.3 more often than in heavier ones is offered, a tag first (+0.2) since an experiment should be
  something to do. One at a time; declined and tried ones aren't offered again. Try it makes a
  loose end with **no source entry**, due Sunday (Today shows it, a later entry's insights can
  settle it, it fades like any other), and the card reports the weeks since.
- **How you talk to yourself** (`ThinkingPattern`). Counted from the insights field below, 3
  entries per pattern, with the area most of them were about.
- **Storage without a schema change.** Life's words, feedback, and experiments are `ReflectSummary`
  rows under `life.portrait`, `life.area.<area>.<window>`, `life.feedback`, and `life.experiment`
  (`periodKindRaw` is a free string; Reflect reads only `week` and `month`), and
  `ReflectQueueItem.entryIDs` carries a line's sources. Thinking patterns ride in
  `EntryInsights.customCardsData` under `ThinkingPattern.storageID`, which `customResults` never
  shows. Move either to fields of their own at the next deliberate schema change.
- Diagnostics: `life.rendered`, `life.areaOpened`, `life.areaWords`, `life.portrait`,
  `life.feedback`, `life.experiment`, counts and literals only
  (`LifeDiagnosticsPrivacyTests`). Tests: `LifeSignalsTests`, `LifeBubbleLayoutTests`,
  `LifePrioritiesTests`, `LifeSourceTests`, `LifePromptsTests`, `LifeWordsTests`,
  `LifeSuggestionTests`, `LifeExperimentsTests`, `LifeThinkingTests`.

**Adding a provider.** Conform to the capability protocols, add a `ProviderKind` and preset, and resolve it in `AIServices`. The coordinators, settings shape, and views don't change.

**Tests.** Fakes to reuse: `FakeHTTPClient`, `FakeSecretStore`, `FakeKeyValueStore`, `FakeTranscriber`, `FakeTextGenerator`, `FakePageTranscriber`, and the harnesses in `TranscriptionCoordinatorTests`, `PageTranscriptionTests`, and `InsightsTests`. `OpenAILiveTests` and the AI UI tests run against real OpenAI when `TEST_RUNNER_MINDLORE_OPENAI_KEY` is set, and against the app's stub (`-uiTestingFakeAI`, `UITestingHTTPClient`) otherwise; UI tests isolate settings and Keychain per `UITEST_STORE_NAME`, and `-uiTestingFakePages` replaces the camera. `MindloreTests/` uses Swift Testing (`import Testing`, `@Test`, `#expect`). For async code, inject dependencies and await the real task (for example `EntrySaver.scheduledSave`) rather than polling with `Task.yield()`, which can starve the main actor. `MindloreUITests/` uses XCTest and relaunches the app against a named file store to prove data survives.
