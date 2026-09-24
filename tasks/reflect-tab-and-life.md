# Reflect tab, the record button, and Life

Status: approved 2026-09-24 as **one PR in phases** (branch `feature/reflect-life`), built
continuously; the owner is asked only before the merge.

- [x] Phase 0: open loose ends pinned on top, Mind's drawer list room at its end, olive tags
- [x] Phase 1: the shell (tabs, + fan, Settings gear, Reflect as a tab)
- [x] Phase 2: Life from the numbers
- [x] Phase 3: the values question
- [x] Phase 4: words (AI phrasing, quotes, area paragraphs, monthly portrait, feedback)
- [x] Phase 5: experiments that become loose ends
- [x] Phase 6: self-talk patterns
- [ ] Phase 7: review, docs, UI tests, a look in light and dark

## Phase 0 (owner, 2026-09-24)

- Reflect's Loose ends pins every open loose end above the months, due soonest first, then newest
  raised (`ReflectLooseEnds.layout`).
- Mind's drawer list gets `endRoom` below its last row, so the last name rests above the fade
  instead of inside it. Measured on the simulator: the last row ended inside the 32pt fade.
- Tags on Mind are a muted olive instead of grey (`KindTag`).

## What the owner decided (2026-09-24)

- The tab bar becomes **Journal, Mind, +, Reflect, Chat**. Journal stays the home tab.
- **+ holds every way to start an entry.** Touching it fans out three options in a half circle above it (Record,
  Write, Photograph pages); tap one, or tap anywhere else to put them away. Or keep the finger down,
  slide onto an option, and let go to start it; letting go anywhere else cancels. Record starts
  recording at once (the choice was already made). Journal's three creation icons go, leaving its
  toolbar with only the gear. The point is space: nothing new on any screen.
- **Settings leaves the tab bar** for a gear at the top leading edge of Journal, opening the same
  five-row Settings as a sheet. Only Journal has the gear.
- **Reflect is a tab with three sides: Life, Recaps, Loose ends.** Recaps is today's summary
  feed, Loose ends is PR #62's list. It opens on Life once Life has a reading, and on Recaps
  until then.
- Life absorbs the planned Numbers side: every number sits under the observation it supports.
- Life asks one setup question, "which three areas matter most to you right now?"
- An experiment the user accepts becomes a real loose end, and Life reports back on it.
- Life is the one place in the app allowed to suggest something. Ask, loose ends, and Recaps
  keep the no-advice rule.

The design reasoning (what Life is for, the trust rules, the cadence) is in the conversation of
2026-09-24 and summarized under "Life's rules" below.

## Phase 1: the shell (tabs, +, Settings gear, Reflect as a tab)

No model change, no CloudKit deploy.

### Tabs and +

- `AppTab` (`Views/Shell/AppRouter.swift:4`) becomes `journal, mind, record, reflect, ask`.
  `settings` goes.
- `RootView.swift:153-174`: five `Tab`s. `record` is `Tab("New Entry", systemImage: "plus")` with
  an empty body, accessibility id `newEntryTab`.
- The `TabView` binds to `router.selection`, a computed binding over `router.tab` that never
  lets `.record` stick: `AppRouter.select(_:)` toggles `showingNewEntryFan` for `.record` and
  leaves `tab` where it was, otherwise sets `tab` and closes the fan. This is the VoiceOver and
  fallback path, and it makes the rule unit-testable without a view.
- **The fan** (`Views/Shell/NewEntryFan.swift`): a half-circle chooser drawn by `RootView` above
  the `TabView`. The options pop out of the + itself (scaled from zero at the +'s centre, staggered
  springs from `Design/Motion`) and settle on a semicircle above it: Write on the left, Record at
  the top, Photograph pages on the right, each a round glass button with a label under it. With no
  camera (`DocumentCameraView.isSupported || FakePages.isEnabled` false) the two left spread to
  the ends of the arc. The + turns into an x while the fan is open. A dimmed backdrop closes it on
  tap; a light haptic as the finger crosses onto an option; the option under the finger grows.
  Options fold back into the + on close.
- **The press-and-drag** needs a hit area over the + that the system tab bar can't provide (it
  only reports a selection). `NewEntryButtonOverlay` is a transparent view pinned over the tab
  bar's middle slot with one `DragGesture(minimumDistance: 0)`. The fan opens on touch-down (no
  hold threshold) and tracks the finger, highlighting the option under it. On release: over an
  option, start it; still over the + (never left it), keep the fan open for a tap; anywhere else,
  close. A touch-down while the fan is already open closes it. The + never switches the tab or
  opens a screen of its own. The hit area is not derived from slot widths (Liquid Glass doesn't
  promise equal fifths): the + is the middle of five tabs, so it sits on the bar's horizontal
  centre whatever the slot widths are. The overlay is a fixed 64 by 56 pt region centred
  horizontally and pinned to the bottom of the window above the home indicator, never moved by the
  recording accessory (which sits above the bar). No `tabBarMinimizeBehavior` is set, so the bar
  never compacts under it.
- **The fan closes on every jump.** Each `AppRouter` jump method (`showEntry`, `showNewEntry`,
  `showNewPages`, `showAsk`, `showInMind`, `showSettings`, `showReflect`) sets
  `showingNewEntryFan = false`, as does the scene leaving `.active`, so a Siri intent or a
  notification landing mid-gesture never leaves a fan over a different tab. The drag's end is
  ignored once the fan is closed.
- Risks to check on the simulator before building the rest: (1) the overlay lines up with the +
  on iPhone 17 and a small phone, with the recording accessory showing and not; (2) a
  `TabView(selection:)` whose setter refuses `.record` shows the old tab with no flash; (3) the
  overlay never swallows a tap meant for the neighbouring tabs. If (1) or (3) can't be made
  reliable, ship tap-to-open only (the `select(.record)` path) and drop the drag.
- Options: Record calls the `IntentHandler` `.record` rules (`IntentRequests.swift:60-104`): a
  ready recorder starts, a running recording expands, idle begins with `startsNow: true`. While a
  recording runs, Record is shown as "Show recording". Write calls `router.showNewEntry()`.
  Photograph pages calls a new `router.showNewPages()` (switch to Journal, one-shot request that
  `EntryListView` consumes by setting `pageOrder = .new`), since the page-order cover lives there.
- `EntryListView.swift:118-131`: the camera, pencil, and mic toolbar buttons go. The empty state's
  big Record and Write buttons stay (the only guidance a new user gets). UI tests that tap
  `newTypedEntryButton`, `newVoiceEntryButton`, or `newPhotoEntryButton` move to the fan
  (`fanRecord`, `fanWrite`, `fanPages`); find every one first.
- The bottom accessory is unchanged: it shows only a real recording.

### Settings behind a gear

- `EntryListView` toolbar gains `ToolbarItem(placement: .topBarLeading)`: a gear, label
  "Settings", accessibility id `settingsButton`. It presents `SettingsView` as a sheet from
  `EntryListView` (`@State showingSettings`). `SettingsView` keeps its own `NavigationStack` and
  gets a Done button.
- As built: `router.showSettings()` is gone. Every caller presents Settings itself, so nothing
  presents over a sheet that is still closing: the welcome screen's Add a key and the two "Open AI
  settings" buttons (the insights sheet, over itself, and Mind's empty state) open
  `AISettingsSheet`, the AI screen on its own, since that is what they are about. From the insights
  sheet, turning AI on and closing Settings lands back on the sheet.

### Reflect as a tab

- `ReflectView` becomes the `reflect` tab's root: its `NavigationStack` stays, the Done button
  goes, and the `Page` picker (`ReflectView.swift:11-22, 52-62`) stays in the principal toolbar
  slot with Recaps and Loose ends. PR 2 adds Life as the first segment.
- `AppRouter` gains `showReflect(page:)` (switch tab, token, set a one-shot page request), and a
  `returnTab`: `showNewEntry(startingText:returningTo:)` records the tab to come back to, and
  `journalPath`'s `didSet` switches back once the entry it opened leaves the path, and only
  if the Journal tab is still the one showing. Any tab the user picks by hand (`select(_:)`) or any
  other jump clears `returnTab`, so a deliberate move to Mind is never overridden. This replaces
  `EntryListView`'s `showingReflect` and `returnToReflectAfterEntry` (`EntryListView.swift:21,24,
  58,135-139,155-158,167-171`).
- Today's week strip (`TodayCards.swift:26`) calls `router.showReflect(page: .recaps)`.
- The token no longer needs to close Reflect: it's a tab, not a sheet.

### Tests (phase 1)

- `AppRouterTests`: rewrite the two Settings tests (`AppRouterTests.swift:195-216`) for the
  request contract; add `select(.record)` starts recording and leaves `tab` alone in each of the
  four other tabs; `select(.record)` while recording expands; `showReflect(page:)`; the return tab
  after a Reflect-opened entry closes, and is cleared by any other jump; `showNewPages()` waits
  for covers like the other jumps; opening an entry from Reflect, picking Mind by hand, then
  closing the entry leaves the user on Mind; every jump and `select(_:)` closes the fan.
- `NewEntryFanTests` (pure): the release decision (over an option, over the +, elsewhere), and which
  option a point falls on, including the gaps between options and a point below the arc.
- UI: `AISettingsUITests.openSettings` (`:82-89`) taps `settingsButton`; `ReflectUITests` opens
  Reflect through `app.tabBars.buttons["Reflect"]` and also once through the week strip; one new
  test taps + and then each option, and one press-drags to Write. Every UI test that used the old
  toolbar buttons is updated (grep `newVoiceEntryButton`, `newTypedEntryButton`,
  `newPhotoEntryButton` across `MindloreUITests`); the empty-state `journalEmptyRecord` and
  `journalEmptyWrite` stay as they are. Run only the touched classes locally.
- Docs: CLAUDE.md's Views paragraph (tab list, the mic button, Settings) and the Reflect section
  ("no fourth tab, no AppRouter change").

## Phase 2: Life, from the numbers (no AI)

No model change. Works with AI off and on device, because everything here is math over what
insights already stored.

### Shape

- `Mindlore/Life/LifeSignals.swift`: `nonisolated`, no SwiftData, the `ReflectAggregator` split.
  Input: `[LifeEntryFact]` (id, `entryDate`, areas, primary mood valence or nil, tags, kind; built
  only for entries that have insights, since one without them carries no signal) and
  `[LifeThreadFact]` (status, `sourceEntryDate` as the day it was raised, the same "raisedOn"
  `ReflectLooseEndSource` uses rather than `createdAt`, which is when insights ran;
  `statusChangedAt`, the source entry's areas, due date),
  a window, `now`, a calendar. Output: `LifeReading?`, nil below the threshold.
- `Mindlore/Life/LifeSource.swift`: `@MainActor` fetch half, like `ReflectSource`/`TodaySource`.
  Drafts excluded; only journal-kind entries count toward mood (`EntryKind.keepsMoods`), all
  kinds toward area share; hidden areas (`SettingsStore.hiddenLifeAreas`) dropped; loose ends get
  their areas by joining `sourceEntryID` to the entry's insights (a loose end has no area field);
  people through `EntityDirectory`, walking merges and skipping hidden and muted names.
- `Mindlore/Views/Reflect/Life/`: `LifeView` (the side), `LifeBubbles`, `LifeAreaView` (pushed),
  `LifeCard`. Copy in `LifeCopy`, templated like `TodayCopy`.
- Refresh on `.task(id:)` over the three revision counters (`EntrySaver.revision`,
  `GraphServices.revision`, `JournalSaves.revision`), the window, and the hidden-areas setting.

### What it computes

- **Window**: Month, 3 months (default), Year, the same control Mind uses.
- **Baseline**: mean valence of every journal-kind entry with a mood in the 12 months before
  `now`. `MoodCategory.valence` (-1, 0, +1) already exists and nothing aggregates it yet.
- **Bubbles**: per visible area, share of the window's entries (size) and the area's mean valence
  minus the baseline (height; above the line is lighter than usual). Share is area entries over
  all entries in the window; an entry can carry two areas, so shares may sum past 100% and no copy
  may present them as parts of a whole. An area needs 3 entries to appear, and 3 with a mood before
  it gets a height (otherwise it sits on the line). Colour is the area's own (`Palette`'s `Area*` colours).
- **Headline**: one templated sentence from the biggest area and its height, naming the height
  only when that area has 8 or more entries with a mood and the difference is 0.25 or more ("Mostly Work these
  three months, and heavier than your usual.").
- **What you put off**: per area with 4 or more threads that closed in the window: share resolved,
  faded, dismissed; median days from `createdAt` to `statusChangedAt` for resolved ones. Shown only
  where two areas differ enough to say something (fade share 30 points apart, or median days 2x).
  Links to the Loose ends side filtered to that area.
- **What went quiet**: an area at 10% or more of entries (6 or more entries) in the previous
  window of the same length, at a third of that share or less now.
- **What changed**: the one or two largest moves in share or height between this window and the
  previous one, above fixed floors (share 8 points, height 0.3).
- **Keeps coming up**: tags present in 3 or more distinct months (Year) or 4 or more distinct
  weeks (3 months), most months first, capped at 3, each with a count and the months. Hidden in
  the Month window, which is too short to recur in.
- **Threshold for any reading**: 20 dated entries with insights spanning 21 days. Below it, Life
  says what it needs ("Life reads a few weeks of you. 12 entries so far.") and Reflect opens on
  Recaps.

### The area page

Tapped bubble: the area's name and headline line, mood by month (valence bars against the
baseline), the people in it (top five by links in the window), its recurring tags, its open loose
ends (tap opens the thread), its follow-through line, and its five latest entries (tap opens the
entry). No generated paragraph yet.

### Tests (phase 2)

- `LifeSignalsTests` (the `ReflectAggregatorTests` shape: fixed calendar and `now`, small fact
  factories): threshold both sides, baseline and height sign, an area below 3 entries hidden,
  hidden areas dropped, notes and creative pieces counted for share and not mood, each rule's
  floor on both sides, quiet-area and changed rules against a previous window, recurring tags by
  distinct months, loose-end areas taken from the source entry, a thread with a deleted source
  entry skipped.
- `LifeSourceTests` on an in-memory store: drafts and entries without insights excluded, a loose
  end dated by its source entry, the area page's people ranked by links inside the window with
  merges walked to the winner and hidden and muted names skipped.
- Diagnostics: `life.rendered` with window, entry count, area count, card count, duration. A case
  in `AIDiagnosticsPrivacyTests` with the sentinel as a tag and a name; a row in
  `docs/privacy-coverage.md`.
- UI: one test on the story journal that opens Reflect, sees Life's bubbles, opens an area page.
- A look at it on `-seedStoryJournal` in the simulator, light and dark.

## Phases 3 to 6, as built (2026-09-24)

Owner additions during the build: "loose ends" is never kept as a tag (parsing refuses every
spelling, a launch sweep cleaned existing entries); Mind's Tidy up badge draws over the bar's glass;
tags are dusty mauve after olive was turned down; the gear is at the top right with an inline
title; the tab bar and the + step away while the editor has the keyboard.

- **No CloudKit schema change anywhere.** Life's words, feedback, and experiments are
  `ReflectSummary` rows under `life.*` kinds; thinking patterns ride in `customCardsData` under a
  reserved id. So the merge doesn't wait on a Console deploy. Move them to their own fields at the
  next deliberate schema change.
- **Dropped: AI phrasing of the cards.** The templated sentences already say the numbers in plain
  words; a model rewording them adds a request and risk to the "code finds, model words" rule and
  nothing a reader would notice. The model writes only what code can't: an area's paragraph and
  quotes, and the portrait.
- **Experiments** are chosen by code from lighter against heavier weeks, a tag preferred over an
  area, and word themselves by template. The loose end has no source entry.
- **Thinking patterns** are asked with the moods, cloud only; older entries gain them through Redo
  insights.

The original sketch of these phases follows.

### Sketch

3. **The values question.** `SettingsStore.lifeTopAreas` (a setting with a control, under Your
   journal and asked once on Life). Adds the gap card: a chosen area at under half the share of an
   average area.
4. **Words.** AI phrasing of the cards from their numbers only (the model never decides a pattern
   exists), two quoted lines per area page, an area paragraph built from cached month summaries
   plus that area's digest lines, and the monthly portrait (what lifts you, what weighs on you,
   what you keep coming back to, how you talk about yourself, what you value by attention), each
   line with source chips. "That's right / Not quite" with an optional note that goes into the next
   reading. "Talk about it" opens Chat with the observation; "Write about it" opens a new entry
   with it. New model `LifeReading` (CloudKit schema deploy). Safety: if recent entries touch on
   self-harm, Life stops suggesting and shows resources.
5. **Experiments.** A card offers one small experiment drawn from the user's lighter weeks;
   accepting it makes a loose end with an origin of `life` and a due date (new optional field on
   `LooseEnd`, CloudKit deploy), so Today and the recorder pick it up; the next reading reports on
   the weeks it was done.
6. **Self-talk patterns.** A per-entry insights field for thinking patterns (all-or-nothing,
   catastrophizing), cloud only, surfaced as a card. Needs Redo insights over the journal.

## Life's rules (hold for every later PR)

- Code finds a pattern; a model may only word it.
- Every card shows what it's built from ("Based on 64 entries since July").
- Heights are against the user's own baseline, never absolute: journals over-represent bad days.
- Situations, not traits: "Sunday nights are heavy", never "you're an anxious person".
- Say "what's on your mind", not "your life": writing volume is not time spent.
- A reading changes weekly at most (Sunday); PR 2's math is live, the words from PR 4 on are
  weekly.

## Not in scope

- An always-visible creation strip in the accessory (dropped for +).
- + starting a recording on a plain tap (the owner wants the choice).
- Any change to Mind, Chat, or Today beyond the week strip's target.
- iPad or Mac layouts.
- Big Five or any trait scores.
- Anything from PRs 3 to 6 inside PR 1 or 2.
