# Mindlore: what's left

The one ordered list of everything still open, rewritten on 2026-09-21 to replace five partial ones.
It says what to do and in what order. The reasoning behind each piece stays in its own spec, linked
where it matters: `tasks/todo.md` (Phase A), `tasks/phase-b-ux.md` (Phase B),
`docs/mindlore-build-plan.md` (the long-range product), `tasks/smoke-test.md` (device steps and the
events each must produce), and `tasks/archive/` for finished work. When something lands, tick it
here in the same commit.

## Where things stand

`main` is Phase A as of 2026-09-21 (PR #6). What it carries: all of Phase A, Phase B up to Today (B0 to B2b), the Ask conversation work
(#18), the settings sprint (#17, #19), and streaming Ask answers over SSE. Draft PR #6 carries it
to `main`. No other branch holds work phase-a doesn't.

The biggest risk on the list is not a feature. It is that phase-a keeps growing while it waits for
one device session, so every sprint added makes the final review bigger and the merge to `main`
harder. Section 1 is first for that reason.

## The order

1. **Get phase-a to `main`.** The no-phone half now, the device session the next time the iPhone is
   at hand, then merge #6.
2. **Finish Phase B**: B3 to B9, with B8 gated on a one-hour signing spike.
3. **Reflect**: weekly and monthly recaps, mood and area over time. Specced and built (R0-R3) on
   `feature/reflect`; the device pass and doc updates (R4) are what's left before it merges.
4. **Later**: text import, embeddings for Ask, typed relationships.
5. **iCloud sync, the rest** (section 6), and **blocked**: a paid tier.
6. **Other devices** (section 7): a watch sidekick, then a native Mac app, then a full native
   iPad app with Apple Pencil, all on the same iCloud journal. The Mac and iPad wait on sync phases
   3 to 5; the watch doesn't.

Reflect after Phase B is the owner's call from 2026-09-19 ("so it's built on the new cards"). It
can be pulled forward; nothing in B3 to B9 is a hard prerequisite for it.

## 1. Get phase-a to main

### Without the phone

- [x] **Privacy coverage.** Measured by instrumenting the log, not by grepping the tests: 70 of the
      131 events are driven by a sentinel test (11 of them by the new
      `AIEdgePathDiagnosticsPrivacyTests`), and each of the other 61 has a written reason. The
      table is `docs/privacy-coverage.md`.
- [x] ~~**Whole-branch review.**~~ Dropped by the owner on 2026-09-21: every sub-phase had its own
      review when it landed, and one over 160 commits is too big to be worth its cost.
- [x] **Docs.** `CLAUDE.md` checked against what shipped (the A10 list asks for the Graph section to
      cover Mind, the search panel, the engine, loose ends, areas and Ask). PR #6's description
      written for the whole branch.

### With the phone: one session

Run by the owner on the iPhone before 2026-09-21 ("I've already tested all of this stuff on my
iPhone, it works"). The list stays as the record of what the session covered.

Every device step from every plan, merged into one run and grouped so the phone is set up once per
group. Expected events for each are in `tasks/smoke-test.md` and `tasks/todo.md` (A10).

**Before starting: a fresh install deletes the journal.** There is no sync and no export yet, so the
steps that need one (the first-run model download, the recorder prompt appearing once) either run
last, after deciding the real journal can go, or run against `-seedDemoJournal 300`.

*Your journal and the graph* (A10)
- [ ] A new voice entry links to a person already in the journal.
- [ ] Merge two entities, relaunch, and the merge holds.
- [ ] Hide a tag.
- [ ] Mind stays responsive at 300 nodes, and the replay scrubber works.
- [ ] A real week of entries produces few loose ends, and a later entry closes one.
- [ ] Loose ends fade after a clock change.
- [ ] The life area distribution on your own journal.
- [ ] Today on your own journal, especially "Quiet lately" (decision 7 was to try it on real
      entries before trusting it).

*Ask* (A9b, A10, and `tasks/ask-conversation.md` phase 4, which are the same gap)
- [ ] Real questions on your journal: about a person, a broad one, and one with nothing on it.
- [ ] On the 300-entry seed: `ask.indexed` fetch time, and record-then-ask finds the new entry.
- [ ] A morphology question on a fresh install ("run" finding "ran"), since lemma assets load on
      first use (`tasks/lessons.md`).

*AI failure paths* (smoke-test steps 12, 15, 16, 20, 21)
- [ ] Bad key: `ai.invalidKey`, a fallback to the phone, no re-upload after relaunch.
- [ ] Pages offline: one `ai.offline`, then finishing on its own when the network returns.
- [ ] Edit pages and restart: `pages.restarted`, a fresh transcription, review again.
- [ ] Typing over a transcription in flight: typed text wins, and the page text can come back.
- [ ] Force-quit during insights: finishes after relaunch, one attempt counted.
- [ ] Lock for a minute, unlock, record: the key is still readable.

*Recording*
- [ ] Headphones or AirPods mid-recording: `recorder.routeChanged`, `recorder.engineRestarted`, the
      timer still counting.
- [ ] The Insights button on an entry without insights, then close it: exactly one
      `insights.started`. Skip and scrub a recording near both ends.
- [ ] Every haptic built so far, and the Keep moment on a real recording (B1).

*Fresh install* (see the warning above)
- [ ] First-run model download: recording starts without waiting, `live.assets` shows the download.
- [ ] The recorder prompt appears once.

*Optional, long*
- [ ] A 25-minute recording, on the phone and on OpenAI (chunked uploads, flat memory).
- [ ] Five pages in one entry (memory and stored size at a realistic maximum).

### Then

- [x] Mark PR #6 ready and merge phase-a into `main`. Merged 2026-09-21. The unit suite was green
      (1,355 tests) and the full UI suite was not run: the owner called it on cost, and the three
      Ask UI tests had passed against the new streaming stub earlier the same day.

## 2. Finish Phase B

`tasks/phase-b-ux.md` has each sub-phase in full. The owner accepted all eleven Phase B decisions on
2026-09-19; two of them are conditional and noted where they bite.

| | What | Size | Needs the phone for |
|---|---|---|---|
| [ ] B3 | First run and permissions: three skippable screens, `hasOnboarded` | S | The permission prompts, the ten-second recording |
| [ ] B4 | Recording screen and motion: Carry, waveform ribbon, serif live transcript, read-mode strip | M | Nearly all of it |
| [x] B5 | Insights sheet and entity surfaces restyled as cards | M | Nothing; screenshot-tested. Densest identifiers in the app |
| [x] B6 | App Intents (Shortcuts, Siri, Action button) and the daily reminder | S to M | The Action button, Siri, delivery |
| [ ] B7 | Mind and Ask polish: halos, Bloom, glass, suggested questions, citation cards | S to M | Little |
| [ ] B8 | Recording control, Live Activity, maybe a widget | L, gated | A one-hour signing spike under the Personal Team decides whether it happens at all (decision 10) |
| [ ] B9 | Privacy, review, a device pass over all of it, docs | S | The final pass |

B5 and B6 shipped together on `feature/phase-b5` (PR #23), picked by the owner on 2026-09-21 as
the parts of what was left worth doing, with the one piece of B7 in the same class: Ask's empty
state (five kinds of suggested question instead of one template) and its field. The plan and what
changed while building it are in `tasks/b5-b6-spec.md`. Their device steps are in
`tasks/smoke-test.md` under "B5 and B6". The rest of B7 (Mind's halos, Bloom, glass on the panel),
B3, B4 and B8 are still open, and whether they happen at all is the owner's call.

Two things parked inside work that's already finished:

- [x] ~~**The toolbar mic and the compose menu**~~ (decision 9: remove the mic "once the accessory
  is proven", and B2a deferred collapsing the new-entry buttons into a `Menu` to the same moment).
  Done by PR #65 in a different shape: the tab bar's + fans out Write, Record, and Photograph pages,
  and Journal's toolbar kept only the Settings gear. The UI tests go through
  `MindloreUITests/NewEntryFanHelpers.swift`.
- **The Sounds row in Settings** arrives with B4. The settings sprint left it out on purpose, since a
  switch that controls nothing shouldn't ship. The Reminder row arrived with B6.

## 3. Reflect

The weekly and monthly layer: build plan Phase 3 and §4.3, scoped down to what `tasks/reflect-spec.md`
(revision 1, owner-approved 2026-09-21) actually specced and `feature/reflect` built. The build plan's
compression ladder (a `Summary` model, daily summarising entries, weekly summarising dailies, a
scheduled `BGTaskScheduler` run) did not ship: everything here computes on demand from
`EntryInsights` already on disk, the same way `EntityGraph` and `AskIndex` compute rather than
store, so there is no new persisted model, no background task, and no cost until the user opens
Reflect. That simplification is the answer to two of the four decisions below.

What shipped, phase by phase:

- **R0**: `ReflectAggregator`, the pure aggregation layer (mood distribution, area split, top tags,
  loose-end opens and closes) over a `DateInterval`.
- **R0.5**: `AskRollups` reads the same aggregator for mood/area questions, so Ask and Reflect share
  one source of these counts rather than two.
- **R1**: period navigation (week/month stepper) and the area-balance chart, reached by tapping
  Today's `WeekStrip`, which is now a button. No fifth tab, no `AppRouter` change.
- **R2**: mood over time, a stacked bar chart across the trailing six periods.
- **R3**: the generated narrative, one `TextGenerator` call per period the user actually opens,
  routed through the existing `AskGenerator` setting, built only from the aggregated facts already
  on screen (never raw entry text), never persisted or retried.
- **R4**: privacy test for `reflect.narrated`, and a read-only review of the diff whose seven
  findings were all fixed (a `LooseEnd` soft-delete filter gap, a stale-AI-task race, a loading
  state that read as an empty period, a sixfold loose-end refetch, a spec that described the
  pre-build decision, and the branch's em dashes).

**Reflect merged without its device pass**, the owner's call on 2026-09-21, the same way B5 and B6
did in PR #23. Steps 33-36 in `tasks/smoke-test.md` (a real week, a real month, an empty period,
the generator off) are owed against whatever device session happens next. What that leaves unproven
is only what a simulator can't show: the charts and the narrative against a real journal's shape.

Search, which the build plan lists in the same phase, already shipped as Ask's search panel. The
graph maintenance pass (§4.4, refreshing stale bios) is not part of Reflect and stays open below.

**The four decisions, resolved:**

1. **Observe or suggest.** Observe. The narrative states facts only ("four entries this week,
   mostly reflective, two closed loose ends"), same no-advice rule as Ask and loose ends.
2. **Scheduled or on demand.** On demand: a period's narrative is asked for when opened and
   forgotten when the user leaves. No `BGTaskScheduler`, no nightly cost.
3. **Who writes the summaries.** Neither a fixed provider nor a new setting: whatever `AskGenerator`
   is already set to (off, on-device, or OpenAI).
4. **Where it lives.** Today's `WeekStrip`, tapped open as a sheet. No fifth tab. Superseded on
   2026-09-24: Reflect is now a tab (below).

### Reflect tab and Life (PR #65, 2026-09-24)

`tasks/reflect-tab-and-life.md` has the plan and the owner's decisions. The tab bar is Journal,
Mind, +, Reflect, Chat; the + fans out every way to start an entry; Settings moved behind a gear
on Journal as a sheet. Reflect has three sides, Life, Recaps, and Loose ends, and opens on Life
once there is a reading. Life is the one part of the app allowed to suggest something: bubbles by
area against the author's own baseline, what went quiet and what changed, follow-through, the
values question, area paragraphs and quotes, a monthly portrait, experiments that become loose
ends, and thinking patterns. None of it changed the CloudKit schema: Life's words, feedback, and
experiments are `ReflectSummary` rows under `life.*` kinds.

- [x] Phases 0 to 6 merged in PR #65; phase 7 (review, docs, UI tests, a light and dark look) in
      the follow-up PR.
- [ ] Device steps 37 to 40 in `tasks/smoke-test.md`: the fan's press and slide, the gear, Life on
      your own journal, and an accepted experiment reaching Today.
- [ ] Give Life's rows fields of their own at the next deliberate schema change, and thinking
      patterns a field instead of the reserved `customCardsData` id.

## 4. Later

- **Text import and backfill** (build plan Phase 4). Markdown, plain text, Day One, Apple Journal,
  then entity and insight passes over the imported history. Handwriting import, the other half of
  that phase, already shipped as photo entries.
- **Embeddings for Ask.** Measured rather than assumed: recall@5 on indirect description (a question
  with no word in common with its answer, "Did my rent go up?" against "Ninety more a month") is
  0.00 over seven questions. Lexical retrieval can't close that gap.
- **Typed relationships between entities** ("works with", "sister of").
- **Searching inside past Ask conversations.**

Decided against, so not on this list: user-added life areas (the nine are fixed; rename and hide
only), a multi-provider settings UI (the account plumbing stays a hidden seam), and 3D Mind (the
spike was built and rejected on 2026-09-21; 2D ships), and a web app (2026-09-23; see section 7).

## 5. Blocked

- **A paid tier** (build plan Phase 6: a thin proxy backend, metering, RevenueCat). Not started, and
  a business decision before it's an engineering one.
- **B8** until its signing spike runs.


## 6. iCloud sync, what's left

In `main` since 2026-09-23 (#49, #52): sync on for the journal's own store, its status first in
Settings, the welcome line and the second-device "your journal is here", the export crash fix
(`EntityLink.linkedEntity`), and the safety copy with restore. The owner's phone syncs to CloudKit's
**Development** environment. Nothing below is needed while one phone runs Xcode builds; all of it is
needed before a second device, and phase 7 before moving the phone to TestFlight. Design and
reasoning: `tasks/icloud-sync.md`.

- [x] **Phase 3, AI runs where the entry was made.** A device-local `LocalOrigin` set of entry ids
      this phone created. Transcription, the launch AI pass, titles, and insights skip an entry not
      in it; the manual buttons work anywhere and add it. A synced entry still waiting for text says
      "Waiting for text from your other device" with Transcribe here. Every entry that exists when
      it lands joins the set once. Without it, two phones each run AI on the same entry: two OpenAI
      bills, duplicate loose ends.
- [x] **Phase 4, duplicates two phones make.** Deterministic merges after a remote change and at
      launch, winner by `createdAt` then `id`: `Entity` with the same key and kind (untouched ones
      through `GraphEditor.merge`, the rest to Mind's "same person?"), `EntityLink` with the same
      entity, entry, and source, `ReflectSummary` by period, `EntryInsights` pointing at one entry,
      and `AskMessage` indexes a conversation continued offline on both. `Entry` by id is done
      (`EntryDuplicates`). Also a test that each launch sweep changes nothing on a second run.
      Both landed in PR #68 (2026-09-25), unit-tested only; the two-device steps below are what
      prove them.
- [ ] **Phase 5, settings that follow the journal.** `NSUbiquitousKeyValueStore` mirroring for an
      allow-list: life area names and hidden areas, your name, how you're written about, the
      journal font, insight section toggles, custom prompts, resurfacing. Never the key, provider
      accounts or pickers, Use AI, app lock, the reminder, or the sync switch.
- [ ] **Phase 2b, a sync switch.** Device-local, on by default. Mirroring can't be toggled on a live
      container, so `MindloreApp` has to hold the container as state and rebuild `RootView` under it;
      "takes effect next launch" is the fallback if that fights the coordinators.
- [ ] **Phase 7, before TestFlight on the phone.** Register every record type in Development (a
      DEBUG-only `initializeCloudKitSchema` pass over the SwiftData model; a type with no records yet,
      such as a page, is otherwise missing), then CloudKit Console, Deploy Schema Changes to
      Production. Redo the deploy before any build that adds a model or property. The App Store
      profile already carries iCloud. Then install TestFlight over the dev build: same bundle ID, so
      the journal on the phone stays, and the TestFlight build uploads it to Production. Export a
      backup first.
- [ ] **Smoke on two devices** (the v1 gates, `tasks/icloud-sync.md`): an entry and an edit cross
      both ways; a recording is transcribed only where it was made; a device with no iCloud account
      works fully and says so, then uploads after sign-in; airplane mode, three entries, sign out,
      relaunch, the restore banner brings all three back, and signing back in leaves no duplicates;
      the same new name written on both offline ends as one entity.
- [ ] **Docs.** `CLAUDE.md`'s sync paragraph once the phases land, and the smoke steps in
      `tasks/smoke-test.md`.

Known on the way: `#Predicate` with `relationship == nil` matched every row on the phone
(`EntityLinkRepair` now checks in Swift); a store CloudKit has touched refuses property renames
(add a new property and backfill instead); a synced store opened under a different or no iCloud
account is purged with reason `AccountLogout`, including in the simulator. All three are in
`tasks/lessons.md`. Phone store backups are in `~/Library/Mindlore-backups/`.

## 7. Other devices: watch, Mac, iPad

Decided 2026-09-23, not started, owner's order. Reasoning and scope: `tasks/platforms.md`. No web
app. Every device shares the journal through SwiftData's CloudKit mirroring; the watch goes through
the phone.

- [ ] **Watch sidekick.** Record only: one button, a complication, an Action Button intent, Siri.
      The file goes to the phone with `WCSession.transferFile`, lands in `Recordings/finished/`, and
      `RecordingIngestor` makes the entry, so the watch never opens the store or touches iCloud.
      Doesn't wait on sync. Needs a paired physical watch to test.
- [ ] **Shared package.** Models and the SwiftData-free logic move into a local Swift package every
      target links, so there is one schema. Before the Mac target exists.
- [ ] **Mac.** Native SwiftUI macOS target on the same container. Gated on sync phases 3 to 5
      (section 6). The editor's `UITextView` to `NSTextView` port is the biggest piece; also a Mac
      recording path (no `AVAudioSession`), file and Continuity Camera import instead of VisionKit,
      a sidebar shell, a Mac CI job.
- [ ] **iPad.** The iOS target with iPad added and its own split-view layout reusing the Mac's, not
      the phone stretched. Scribble in the editor, then ink pages: a PencilKit page stored as an
      `EntryPage` plus its `PKDrawing` (a model change: schema flag, cktool check, Console deploy),
      read by the existing page transcription. Keep iPad off until this step.

## TestFlight

`.github/workflows/release.yml` uploads a build after every push to `main` whose CI run passed, on
a `v*` tag, and by hand (`gh workflow run release.yml --ref main`). It stays off until the one-time
setup below, all of it outside the repo:

1. App Store Connect, Apps, +: a new iOS app for bundle ID `com.natefikru.mindlore`.
2. Xcode, Settings, Accounts, Manage Certificates, +, Apple Distribution. Then in Keychain Access,
   export that certificate with its key as a `.p12`, with a password.
3. developer.apple.com, Profiles, +, App Store Connect, `com.natefikru.mindlore`, the distribution
   certificate. Download it.
4. App Store Connect, Users and Access, Integrations, App Store Connect API: a team key with the
   Developer role, which is enough to upload. Download the `.p8` (only offered once) and note the issuer ID.
5. `scripts/release/set-secrets.sh <p12> <profile> <AuthKey_ID.p8> <issuer-id>` loads all of it
   into GitHub and sets `RELEASE_ENABLED`.
6. App Store Connect, the app, TestFlight: an internal group with yourself in it and automatic
   distribution on. Install TestFlight on the phone and turn on automatic updates for Mindlore.

A TestFlight build is Release, so `DiagnosticsLog` is silent and the device smoke loop still uses
`scripts/device/deploy.sh`. Regenerate the profile and rerun step 5 when a capability is added
and before the profile's yearly expiry (2027-09-22). Sync is on in `main`, so every TestFlight
build since #49 syncs to CloudKit's **Production** environment, which has no schema yet: sync in a
TestFlight build shows "Paused" until phase 7 in section 6 deploys it.

**For App Store review:** guideline 5.1.2(i) (November 2025) asks for explicit permission, naming
the third-party AI, before personal data goes to it. `AIConsent` is that ask: the Use AI switch and
saving a key both show it, and only Allow turns AI on. In the review notes, say AI is optional,
uses the user's own OpenAI key, and is asked for by name; give the reviewer a key to try it with.

Not blocked, but done in the GitHub UI rather than the repo: under Branches, protect `main` and
require the `Unit tests` check; the UI shards stay advisory on pull requests (add the `ui` label to
a PR that touches views) and run on every push to `main`.

## Known bugs and debt

Real, deferred on purpose, each with why it can wait.

- [ ] **Device check for the 2026-09-23 journal changes.** Built without a Mac: the caret fix in
      `GrowingTextEditor` (type the first two letters of a new entry, then Edit on a long one and
      type; the letters must land in order), the ready recorder (the empty state's Record opens the recorder
      waiting; its button starts; Siri still starts at once), the kind picker under the title, the
      font setting reaching the editor and read mode, and a photographed page dated at its top
      landing on that day with a generated title after Approve.

- [ ] **`retryAfter` from a 429 is parsed and ignored.** The next attempt waits for a scene change or
      launch instead of the provider's delay.
- [ ] **`JournalSaves.revision` isn't observable.** A screen keyed on it alone misses a background
      save, which is why Settings' About counts can lag while you're looking at them. Today gets away
      with it because the journal list's query redraws it. Making it observable also changes how often
      Today and Ask's index refresh, so it wants measuring, not a quick fix.
- [ ] **`AskConversation.handleMap` grows** as one JSON blob rewritten every turn, roughly 75 KB by
      ten aggregate turns. Not wrong, just larger than it needs to be.
- [ ] **Diff and thumbnail work happens in view bodies** (`CleanupReviewView`, `PageStripView`,
      `PageOrderView`). Fine at today's sizes; cache it if entries or page counts grow.
- [ ] **Test harness fakes hang rather than fail** when a coordinator stops calling them. The unit
      command's per-test time allowance is what stops a full stall.

## Known limits

- Memory and storage above five pages per entry are unverified on a device; the 20-page cap is a
  guard, not a measurement.
- A force-quit inside the document camera loses that scan: VisionKit only hands pages back on Save.
- An upload running when the app is backgrounded may be suspended; it retries later.
- The in-app privacy wording and the `PrivacyInfo.xcprivacy` data collection declarations need their
  own review before any build goes to anyone else.

## What this replaced

The previous version of this file listed the knowledge graph as the next project (it merged as
PR #3) and search under synthesis (it shipped with Ask). Two other plans still describe work as
open that has shipped, and are left as written because they are history:

- `docs/mindlore-build-plan.md` Phase 5 (SpriteKit visualisation) shipped as the Mind tab, on
  `Canvas` rather than SpriteKit. Phase 4's handwriting import shipped as photo entries. "Lock the
  mood vocabulary" in its next steps is done.
- `tasks/ask-conversation.md`'s phase 1 to 3 checkboxes are unticked though all three shipped (#18).
  Only its device step is open, and it's in the session above.
