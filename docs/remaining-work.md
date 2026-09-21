# Mindlore: what's left

The one ordered list of everything still open, rewritten on 2026-09-21 to replace five partial ones.
It says what to do and in what order. The reasoning behind each piece stays in its own spec, linked
where it matters: `tasks/todo.md` (Phase A), `tasks/phase-b-ux.md` (Phase B),
`docs/mindlore-build-plan.md` (the long-range product), `tasks/smoke-test.md` (device steps and the
events each must produce), and `tasks/archive/` for finished work. When something lands, tick it
here in the same commit.

## Where things stand

`main` is still at PR #3, the knowledge graph. Everything since lives on `feature/phase-a`, which
is 161 commits ahead: all of Phase A, Phase B up to Today (B0 to B2b), the Ask conversation work
(#18), and the settings sprint (#17, #19). Draft PR #6 carries it to `main`. No other branch holds
work phase-a doesn't, except `feature/ask-streaming`, which is in progress in its own worktree
(streaming Ask answers over SSE) and not yet pushed.

The biggest risk on the list is not a feature. It is that phase-a keeps growing while it waits for
one device session, so every sprint added makes the final review bigger and the merge to `main`
harder. Section 1 is first for that reason.

## The order

1. **Get phase-a to `main`.** The no-phone half now, the device session the next time the iPhone is
   at hand, then merge #6.
2. **Finish Phase B**: B3 to B9, with B8 gated on a one-hour signing spike.
3. **Reflect**: weekly and monthly recaps, mood and area over time. Spec first; four decisions below.
4. **Later**: text import, embeddings for Ask, typed relationships.
5. **Blocked**: iCloud sync and a paid tier, both on the paid Apple Developer Program.

Streaming Ask answers runs alongside all of this on `feature/ask-streaming` and lands on phase-a
when it's done.

Reflect after Phase B is the owner's call from 2026-09-19 ("so it's built on the new cards"). It
can be pulled forward; nothing in B3 to B9 is a hard prerequisite for it.

## 1. Get phase-a to main

### Without the phone

- [ ] **Privacy coverage.** About three dozen diagnostics events were added since `main` (`ask.*`, `mind.*`,
      `keep.*`, `today.dismissed`, `insights.skipped`, `looseEnds.*`, the contact and place links,
      and more). Confirm each one runs through `DiagnosticsPrivacyTests` or
      `AIDiagnosticsPrivacyTests` against the sentinel, and add the cases that are missing.
- [ ] **Whole-branch review.** A read-only (`Explore`) sub-agent over `git diff origin/main`, with the
      tree baselined first (`tasks/lessons.md`). Fixes in separate commits.
- [ ] **Docs.** `CLAUDE.md` checked against what shipped (the A10 list asks for the Graph section to
      cover Mind, the search panel, the engine, loose ends, areas and Ask). PR #6's description
      written for the whole branch.

### With the phone: one session

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

- [ ] Mark PR #6 ready and merge phase-a into `main`.

## 2. Finish Phase B

`tasks/phase-b-ux.md` has each sub-phase in full. The owner accepted all eleven Phase B decisions on
2026-09-19; two of them are conditional and noted where they bite.

| | What | Size | Needs the phone for |
|---|---|---|---|
| [ ] B3 | First run and permissions: three skippable screens, `hasOnboarded` | S | The permission prompts, the ten-second recording |
| [ ] B4 | Recording screen and motion: Carry, waveform ribbon, serif live transcript, read-mode strip | M | Nearly all of it |
| [ ] B5 | Insights sheet and entity surfaces restyled as cards | M | Nothing; screenshot-tested. Densest identifiers in the app |
| [ ] B6 | App Intents (Shortcuts, Siri, Action button) and the daily reminder | S to M | The Action button, Siri, delivery |
| [ ] B7 | Mind and Ask polish: halos, Bloom, glass, suggested questions, citation cards | S to M | Little |
| [ ] B8 | Recording control, Live Activity, maybe a widget | L, gated | A one-hour signing spike under the Personal Team decides whether it happens at all (decision 10) |
| [ ] B9 | Privacy, review, a device pass over all of it, docs | S | The final pass |

Two things parked inside work that's already finished:

- **The toolbar mic and the compose menu** (decision 9: remove the mic "once the accessory is
  proven", and B2a deferred collapsing the new-entry buttons into a `Menu` to the same moment). The
  accessory shipped in B1, so this is ready whenever you call it. 11 UI test files tap
  `newEntryButton` and need updating with it.
- **Reminders and Sounds rows in Settings** arrive with B6 and B4. The settings sprint left them out
  on purpose, since a switch that controls nothing shouldn't ship.

## 3. Reflect

The weekly and monthly layer: build plan Phase 3 and §4.3. Nothing is specced yet. What it covers:

- A `Summary` model and the compression ladder: daily summarises entries, weekly summarises dailies,
  monthly summarises weeklies, so cost stays flat as the journal grows to years.
- A scheduled synthesis run (`BGTaskScheduler`).
- Weekly and monthly recap screens: Arc, Recurring, Shifts, Unresolved, per §4.3's prompt, which
  ends "Write plainly. No motivational framing."
- Mood over time and area balance charts (Swift Charts; nothing imports Charts yet).
- The graph maintenance pass (§4.4): refreshing stale bios. It could land here or stay later.

Search, which the build plan lists in the same phase, already shipped as Ask's search panel.

It builds on: `EntryInsights.summary` on every analysed entry (the daily tier's input),
`AskRollups` (counts and coverage for a period, built for Ask), and Today's `WeekStrip`, which was
built as Reflect's way in.

**Four decisions to make before the spec:**

1. **Observe or suggest.** Every rule so far says the app observes and never advises (Phase B's
   thesis; the insights prompt's "do not give advice"). Recaps can stay on that side, with Shifts
   and Unresolved doing the pointing. Suggestions would reverse a principle, not add a feature.
2. **Scheduled or on demand.** A nightly run means token cost you didn't ask for that day, and
   background tasks are untested under the Personal Team. On demand costs nothing until opened.
3. **Who writes the summaries.** OpenAI, or Apple's on-device model for the daily tier with OpenAI
   for weekly and monthly.
4. **Where it lives.** A fifth tab, a screen behind Today's week strip, or part of Mind.

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
