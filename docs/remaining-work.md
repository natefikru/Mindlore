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
5. **Blocked**: iCloud sync and a paid tier, both on the paid Apple Developer Program.

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
- [ ] Today on your own journal, especially "It's been a while" (decision 7 was to try it on real
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

- **The toolbar mic and the compose menu** (decision 9: remove the mic "once the accessory is
  proven", and B2a deferred collapsing the new-entry buttons into a `Menu` to the same moment). The
  accessory shipped in B1, so this is ready whenever you call it. 11 UI test files tap
  `newEntryButton` and need updating with it.
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
4. **Where it lives.** Today's `WeekStrip`, tapped open as a sheet. No fifth tab.

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
spike was built and rejected on 2026-09-21; 2D ships).

## 5. Blocked

- **iCloud sync** needs the paid Apple Developer Program: CloudKit entitlements don't exist on the
  Personal Team. The schema is already CloudKit-safe (`CloudKitSchemaRulesTests`), and
  `AppConfig.cloudKitContainerID` switches it on. The v1 plan (`tasks/archive/v1-capture-storage.md`)
  has the design, including recovery and the cross-device transcription rule.
- **A paid tier** (build plan Phase 6: a thin proxy backend, metering, RevenueCat). Not started, and
  a business decision before it's an engineering one.
- **B8** until its signing spike runs.

## Known bugs and debt

Real, deferred on purpose, each with why it can wait.

- [ ] **Voice chunks aren't saved as they finish.** A failure on chunk 9 of 10 re-uploads all nine,
      up to the 3-attempt cap. Pages already save per page. Costs money only on long recordings
      that fail part-way.
- [ ] **`retryAfter` from a 429 is parsed and ignored.** The next attempt waits for a scene change or
      launch instead of the provider's delay.
- [ ] **A Keychain error reads as "no key".** `ProviderAccountStore` swallows the status, so a locked
      or broken keychain looks like an unconfigured account.
- [ ] **Cancelling "Edit pages" discards pages added during that edit** without asking. Pages already
      on the entry are safe.
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
