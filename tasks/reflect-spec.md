# Mindlore Reflect: recaps, area balance, mood over time

Branch: `feature/reflect` from `main` at `c4449a1` ("Phase A is on main").

Status: revision 1, approved by the owner on 2026-09-21. R0 through R4 are built, on `feature/reflect`
(PR #22). The device pass in R4 is still open, run by the owner on a physical iPhone.

## Why

Reflect is the one phase every other plan in this repo has already promised and deliberately
left empty for:

- `tasks/todo.md:53`: "Reflect comes later (weekly recaps, area balance, mood over time) as its
  own phase after A."
- `tasks/todo.md:774`: "Reflect: weekly and monthly recaps, area balance charts, mood over time.
  That's the next phase."
- `tasks/phase-b-ux.md:60-62`: "Reflect stays its own phase (recaps, area balance, mood over
  time, generated narrative). Phase B owns single-item resurfacing and raw counts. One thing is
  pulled forward: the week strip, which is a seven-cell query and later becomes Reflect's way
  in."
- `Mindlore/AI/Ask/AskRollups.swift:11-13`: mood distribution, area split, and top tags are
  named there as Reflect's data and kept out of Ask's rollup blocks on purpose.

So the scope isn't a question: **weekly and monthly recaps, an area-balance view, mood over
time, and one generated narrative paragraph per period.** Two years of entries, nine life areas,
and forty-one moods already sit in `EntryInsights` with nothing that looks back across them. This
phase is that look back.

## What already exists (no new persistence)

- **Mood**: `Mindlore/Models/Mood.swift`. `Mood` (41 cases) rolls up to `MoodCategory` (8 cases,
  `joyful, calm, connected, reflective, anxious, angry, low, drained`) with a `valence` (-1/0/+1)
  and `energy`. `EntryInsights.primaryMood` / `.secondaryMoods` (`EntryInsights.swift:35-41`) are
  the stored values, nil until insights run.
- **Life areas**: `Mindlore/Models/LifeArea.swift`. 9 fixed cases. `EntryInsights.areas`
  (`EntryInsights.swift:49-52`), at most 2 per entry.
- **Tags**: `EntryInsights.tags: [String]` (`EntryInsights.swift:18`), free text the model wrote.
- **Period dates**: `Entry.entryDate` (`Entry.swift:21`) is where an entry belongs in the
  journal, editable, not `createdAt`. Reflect buckets by `entryDate`, the same field
  `JournalGroups` sections the list by.
- **Aggregation, twice already**: `AskRollups` (`Mindlore/AI/Ask/AskRollups.swift`) turns matched
  entries into month/year count lines with no persisted model, a pure function over an in-memory
  index. `EntityGraph.build` (`Mindlore/Graph/EntityGraph.swift`) is `nonisolated`, imports no
  SwiftData, and takes caller-resolved input in, weighted edges out. `ReflectAggregator` (new)
  follows the same shape: a `nonisolated` pure function over fetched `EntryInsights`, never a new
  `@Model`.
- **Cache-invalidation precedent**: `GraphServices.revision` and `AskIndex`'s fingerprint
  (`EntrySaver.revision`, `GraphServices.revision`, `JournalSaves.revision`, all monotonic
  counters) are how this codebase answers "when is a cached computation stale," never a timer.
  Reflect's period data keys off the same three counters.
- **Entry point, half-built**: `Mindlore/Views/Today/WeekStrip.swift` is seven dots today, no tap
  target. `tasks/phase-b-ux.md:62` already names it as Reflect's way in.
- **Shell has no fourth tab**: `AppTab` (`AppRouter.swift:4-5`) is `journal, mind, ask`. Nothing
  in any doc reserves a tab for Reflect.
- **AI layer conventions a narrative call must follow**: `AIError` carries codes only, never
  provider text; `PromptVoice` is what every prompt (Ask included) renders through; the no-advice
  rule (observes and quotes, never counsels) applies to loose ends and Ask and applies here too;
  diagnostics carry counts/durations/bools only, checked by `DiagnosticsPrivacyTests` running
  real components against a sentinel string. `AIJobPolicy` today governs three *per-entry* jobs
  (text, title, insights) with attempts and failures stored on the `Entry`. A period narrative is
  a new shape: not per-entry, not persisted, not retried, so it does not extend `AIJobPolicy`.
  See "The narrative" below.

## Ground rules

- **No new persisted models.** Mood distribution, area split, tag counts, and the week-over-time
  series are all computed from `EntryInsights` already on disk, the same way `EntityGraph` and
  `AskIndex` compute rather than store.
- **Bucket by `entryDate`**, not `createdAt`, consistent with the journal list.
- **Every new diagnostics event carries counts and durations only**, with a
  `DiagnosticsPrivacyTests` case, same rule as everywhere else in the app.
- **No advice.** The generated narrative states what happened ("Four entries this week, mostly
  reflective, two closed loose ends"), never a suggestion or a judgment. Same rule Ask and loose
  ends already follow.
- **Design system, not a new one.** `Palette`, the life-area hues, `Corner`, and the text-style
  rules from Phase B (`tasks/phase-b-ux.md` "Identity") are reused as-is. Mood stays uncoloured
  good/bad the same way Phase B specified for mood chips.
- **`ReflectAggregator` is the single source of these numbers.** Ask's rollup block reads it too
  (see owner decision 6) rather than growing a second copy of the same counting logic.
- **No change to `EntityGraph`, the coordinators, or the graph simulation.**

## Owner decisions needed

1. **Entry point.** Recommended: make `WeekStrip` tappable, no fourth tab. Built as a sheet over
   Today, its own `NavigationStack`, rather than the push originally recommended here: a push
   would have meant teaching `AppRouter`'s `journalPath` a second route type (`JournalRoute` is
   built specifically around an entry id), where a self-contained sheet needed no `AppRouter`
   change at all. Matches the "way in" language already on file either way.
2. **Periods offered.** Recommended: week and month only, with a simple back/forward stepper
   between periods of the same kind (no custom date range, no year view) in v1. Matches every
   doc quote, none of them say "yearly."
3. **The generated narrative: is it an AI call, and what does it see?** Recommended: yes, one
   `TextGenerator` call per period the user actually opens (not pre-generated, not persisted, no
   background job). The prompt is built only from the aggregated facts already on the chart screen
   (mood distribution, area counts, tag list, loose ends opened/closed that period, entry count),
   never raw entry text. That keeps it cheap, keeps it fast, and means it can't leak anything the
   charts don't already show. On failure it fails silently (no narrative section shown, charts
   still render); there's nothing to retry because reopening the period asks again.
4. **On-device vs cloud for that call.** Recommended: reuse `AskGenerator`
   (`Mindlore/Settings/AISettingTypes.swift:33-37`: `off`, `onDevice`, `openAI`) rather than add a
   second AI setting. Off means no narrative section, same as Ask today.
5. **Empty periods.** Recommended: the same "nothing here" empty state `JournalFilter` already
   renders for zero entries (`JournalFilter.swift:28-31`); no chart, no narrative call, no
   placeholder numbers.
6. **Does Ask see Reflect's aggregates?** Owner decided: yes, aggregates only. `AskRollups`
   (`Mindlore/AI/Ask/AskRollups.swift`) reverses its 2026-09-18 exclusion and gains a line per
   month/year block built from `ReflectAggregator` (mood distribution and area split alongside
   the existing entry count and date range), so an aggregate question ("how was my mood in
   September?") is grounded in real numbers instead of Ask's twelve-entry sample. Same
   numbers-only discipline the rollup already has: no entry text, no titles, no names. The
   **generated narrative paragraph stays out of Ask entirely**: it has no entry behind it to
   cite, and Ask's whole answer format depends on every claim tracing to a real entry, so a
   synthesized paragraph never becomes a retrievable or citable document in `AskIndex`.

## Phases

### R0: Data layer (S)
`ReflectAggregator` (new, `Mindlore/Reflect/`, `nonisolated`, no SwiftData import): given a
`DateInterval` and fetched `EntryInsights` + `Entry.entryDate` pairs, returns mood distribution
(count per `MoodCategory`), area counts, top tags, entry count, and loose-end open/closed counts
for that interval. Pure function, unit tested directly (no fixture app needed), same testing shape
as `AskRollupsTests`. No UI in this phase.

### R0.5: Ask's rollup gains the aggregates (S)
`AskRollups.block(for:)` calls `ReflectAggregator` for each month/year line and appends mood
distribution and area split, same numbers-only rule the block already follows. `AskPrompt`'s
existing "these numbers summarize what matched" framing covers the new line without a prompt
rewrite. `AskRollupsTests` and `AskRetrievalQualityTests` gain cases for an aggregate mood/area
question. This is the one phase that touches an existing Ask file, kept separate from R0 so it
can be reviewed and reverted on its own if it turns out to change Ask's answers in an unwanted way.

### R1: Period navigation and area balance (S-M)
`ReflectView` presented as a sheet from Today via the new `WeekStrip` tap target (see owner
decision 1); a period stepper (week/month toggle, back/forward); the area-balance chart (bar or
ring, life-area colours) reading
`ReflectAggregator` output, cached against the three-counter fingerprint the same way `AskIndex`
is. Accessibility identifiers added up front, per the repo's UI-test convention.

### R2: Mood over time (S–M)
The mood chart: `MoodCategory` distribution per period, plotted across a run of periods (a small
number of weeks or months back). Reuses the neutral, uncoloured-by-valence mood treatment Phase B
set for mood chips.

### R3: Generated narrative (S–M)
The `TextGenerator` call described in owner decision 3, its prompt builder, `PromptVoice`
rendering, `AIError` handling, and the `AskGenerator`-driven on/off/on-device/cloud switch. New
diagnostics event (`reflect.narrated`: period kind, entry count, duration, success bool) plus its
`DiagnosticsPrivacyTests` case.

### R4: Review, privacy, device, docs
Privacy test for every new event. Read-only sub-agent review of the whole diff, fixes in separate
commits. Device pass: a real week and a real month on the owner's journal, an empty period, the
narrative on and off. `CLAUDE.md` gains a Reflect paragraph; `docs/remaining-work.md` updated;
`tasks/smoke-test.md` gets the new steps.

Each phase is its own commit (or small commit sequence), tested locally before the next phase
starts. There's no CI in this repo (`tasks/todo.md`: "There's no CI. The check after every push
is the local unit test run"), so "push, check CI" becomes "commit, run the phase's tests, push."

## Not in scope

- iPad layouts, localisation, user-picked accents.
- Embeddings, or any change to Ask's retrieval (`AskIndex`, BM25 scoring) or the coordinators.
- Indexing the generated narrative text as a searchable or citable document in Ask.
- Year-over-year comparison or any period longer than a month.
- Sharing or exporting a recap.
- A fourth tab, or any `AppRouter`/`AppTab` change beyond one new route.
- Changing `EntityGraph`, the graph simulation, or any persisted model.

## Test strategy

- `ReflectAggregatorTests` (new): pure-function tests over constructed `EntryInsights`/date
  fixtures, no app context needed: mood distribution counts, area counts, tag counts, boundary
  entries (entry dated exactly on a period edge), an empty period, a period spanning a DST
  change (calendar-aware bucketing, same caution `AskRollups`'s formatter already documents about
  timezone).
- UI tests for `WeekStrip`'s new tap target and `ReflectView`'s period stepper, following the
  identifier discipline already in `MindloreUITests/`.
- `DiagnosticsPrivacyTests` case for `reflect.narrated` (and any other new event), same sentinel
  pattern as `KeepTests`/`TodayTests`.
- `xcodebuild ... -only-testing:MindloreTests` after each phase; the relevant UI test file only
  once a phase has UI, per the phase-scoped UI test rule already in memory for this repo.
