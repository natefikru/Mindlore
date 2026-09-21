# Ask polish, B5, B6

One branch, one PR, three phases. Branch `feature/phase-b5`, worktree
`.claude/worktrees/phase-b5`, already cut from `origin/main` at `c4449a1`.

Status: built, reviewed, and fixed (PR #23). What changed from this plan while building it, and
the code review's findings, are under "As built" at the end. Device steps 28 to 32 in
`tasks/smoke-test.md` are the one thing left.

## Context

`main` is Phase A plus Phase B through B2b. Phase B's own plan draws a cut line after B2b and says
the brief is answered; everything after it is optional, so the three pieces here were picked on
merit rather than by taking B3 to B9 in order. B3 (a three-screen first run for an audience of one),
B7's decoration, and B8 (an L-sized extension gated on a signing spike that will probably fail under
a Personal Team) are deliberately skipped.

What is left is the work you can feel:

- **Ask's composer and empty state** never got the B0 design pass. B0 stopped at the Journal list,
  the editor, the insights sheet's background, and Settings, leaving Ask on the system background
  until B7. The field is a plain `TextField` in a `Color(.secondarySystemBackground)` capsule, and
  the three suggestions are identical grey slabs. The suggestions are also thinner than they look:
  `AskSources.examples` has one template ("What's been going on with X?") applied to the two most
  recently linked entities, plus a fixed "What did I do last week?".
- **B5**: the insights sheet is the screen you land on after every entry and it is a `Form`.
  `InsightCard` is not a card, it is a `Section` with a header and footer (`InsightCards.swift:88`).
  The chips are hand-rolled `.quaternary` capsules that predate `ChipStyle`.
- **B6**: App Intents are a capability, not a skin. Action button to recording, no unlock, no launch,
  is the difference between catching a thought in the car and losing it. Nothing in the repo imports
  `AppIntents` or `UserNotifications` yet, and no entitlements file exists, which is consistent with
  the plan's claim that no extension is needed.

There is no CI in this repo. The check after every push is the local unit run from CLAUDE.md, plus
the UI tests for the phase being built. Every "check CI" step below means that.

## Phase 1: Ask composer and suggestions

Gates the draft PR.

**Suggestions get five sources instead of one template.** Split the way `TodayComposer` /
`TodaySource` is split, which is the house pattern for this exact shape: a pure `nonisolated` decider
fed plain structs, and a main-actor fetcher that touches SwiftData.

- New `Mindlore/AI/Ask/AskSuggestions.swift`: `nonisolated`, no SwiftData import, takes plain inputs
  (recent entity names and kinds, one open loose end's text, the heaviest life area, the date) and
  returns three questions. Sources: a recent name, an open loose end ("What happened with the
  landlord?"), the heaviest life area ("How has Work been?"), a time question, and a second name, so
  the three on screen have different shapes.
- Rotation is deterministic by day ordinal and stable within a day, with the date injected so tests
  pin it. Not random: the same open twice must not shuffle.
- Visibility rules carry over from Today (`TodaySource.swift:126-151`). Hidden entities are never
  named, `resurfacingMuted` is respected, and a loose end with any hidden or muted subject is dropped
  whole (privacy over completeness). Only `.open` loose ends, never faded or dismissed.
- **This fixes a live gap.** Today's `examples` filters `isBrowsable` (hidden, merged) but never
  `resurfacingMuted`, so a name you muted on Today can still be suggested in Ask. To be precise
  about which promise is at stake: suggestions never leave the phone, so `AskSources`' network gate
  (`documents`/`blocks`) isn't involved. What's at stake is the UI invariant that a hidden or muted
  name never renders.
- **Computed once, not per render.** `examples` is called inside `AskView.empty`'s body today, so it
  fetches every `Entity` on each render of the empty state. It moves to `@State` filled in the
  existing `.task`, refreshed on the index fingerprint the view already awaits. The heaviest-area
  source is a bounded fetch over the last 30 days of entries, not a scan of the journal.
- `AskSources.examples(in:)` (`AskSources.swift:174`) becomes the fetching half and keeps its name. The
  one call site at `AskView.swift:180` changes from a body call to reading the `@State`.

**The empty state** becomes cards on Paper: a leading Ember glyph per question matching its source (a
person, a thread, an area, a calendar), the question in SF, `.card()` from `CardStyle.swift`, with
`Motion.settle` and a stagger as they arrive. Keeps `askEmptyState` and `askExample`.

**The composer** (`AskView.swift:200-250`): `.glassEffect` on the capsule, which is what the identity
spec reserves glass for, with `.ultraThinMaterial` as the fallback if the 26.5 API doesn't behave
(the Phase B plan already flagged the modifier names as unverified; nothing in the app uses glass
yet). A leading glyph that swaps between magnifying glass and sparkle as the field goes from
searching to asking, an Ember focus ring, `.symbolEffect` on send, `Haptics.selected` on send.

The `TextField` stays one line. The comment at `AskView.swift:221` gives the reason: on a vertical
field the keyboard's Send key inserts a newline instead of sending.

**Untouched**: `AskService`, retrieval, `AskPrompt`, `AskSources.documents`/`blocks` (the privacy
gate), the search panel, the scroll-follow logic, `showsSearchPanel`. Identifiers `askField`,
`askSend`, `askExample`, `askEmptyState`, `askThinking`, `askStop`, `askUnavailable` all stay.

**Tests**: new `MindloreTests/AskSuggestionsTests.swift` (Swift Testing) over the pure decider: each
source's phrasing, hidden and muted entities excluded, a loose end with a hidden subject dropped,
rotation stable within a day and different across days, an empty journal degrading to the fixed
questions. `AskUITests.swift:102` asserts `askEmptyState` exists; that must still pass.
`AskScreenshotTests` gains the restyled empty state and composer, light and dark.

## Phase 2: B5, insights and entity surfaces

**`InsightCard` stops being a `Section`.** It becomes a real card: `.card()`, title, optional caption,
the `copyText` context menu kept as is. `EntryInsightsView`'s `Form` becomes a `ScrollView` +
`LazyVStack` over `paperBackground()`, and the status section becomes the first card.

- `EntityChips`' comment about several chips sharing one `Form` row and needing borderless buttons
  (`InsightCards.swift:251-253`) stops applying, but the borderless style stays; nothing is gained by
  changing it.
- **One UI test breaks for certain and gets updated in the same commit.**
  `InsightsUITests.swift:53-56` scrolls with `app.collectionViews.firstMatch.swipeUp()` to find
  `looseEnd-open`. A `Form` is backed by a `UICollectionView`; a `ScrollView` isn't, so that query
  stops resolving and `testFinishReadInsightsEditRerunAndDelete` fails. It moves to
  `app.scrollViews.firstMatch`. Grepped: no other test scrolls this screen by container type.
  `GraphUITests` and `GraphScreenshotTests` use `collectionViews` heavily, but on `EntityView`,
  which keeps its `Form`, so they're safe.
- Chips move onto `chip(tint:)` from `ChipStyle.swift`: `LifeAreaChips` tinted by `area.color`,
  `WrappingChips` and `EntityChips` neutral. The dashed "guessed" border and the orange "?" badge
  survive unchanged, they carry meaning.
- `MoodCategory.color` moves from `InsightCards.swift:5` to `Design/Palette.swift`, the same move B0
  made for `LifeArea` and `EntityKind`, keeping the property name so call sites don't change. The
  per-category dot stays. The identity spec's "mood is never coloured good or bad" is about not
  grading a mood, and the dot doesn't: its own comment says the word and meaning carry the
  information. Flagging it rather than silently deciding.
- `LooseEndsCard`: rows restyled, strikethrough on resolved kept, the per-row menu kept,
  `Haptics.looseEndClosed` on marking one done.

**`EntityPeekCard`** is already a `VStack`, not a `Form`. It gains glass (it floats over Mind), the
avatar and name in the established card idiom, and recent mentions as dots. `EntityPeekSheet`'s
detents and the merge-redirect environment are untouched.

**`EntityView`** keeps its `Form` container. Content sections (About, Entries, Loose ends, Mentioned
with, Merged into this) get `.listRowInsets(EdgeInsets())` and `.listRowBackground(Color.clear)` with
their content wrapped in `.card()`, so they read as cards on Paper. Editing rows (rename, kind,
aliases, contact, place, merge, hide) stay as ordinary Form rows, because a Form is the right shape
for editing controls. This preserves all ~40 identifiers and the row structure the UI suite asserts
on.

**Untouched**: every model, coordinator and service. `InsightsPresentation`'s state machine,
`EntityPagePresentation`, `EntityPeekPresentation`, the repoint and merge paths, `GraphServices`.
This phase is presentation only.

**Tests**: no new unit tests unless a pure helper appears (`MoodCategory.color`'s move needs none).
The existing UI suites for these screens must pass unchanged, which is the real check: grep the
identifiers first and run `AskUITests`, the insights and entity UI tests, and `GraphScreenshotTests`.
`DesignScreenshotTests`' tour gains the restyled insights sheet and entity page, light and dark, and
the screenshots get looked at.

## Phase 3: B6, App Intents then the reminder

Intents first, in their own commit, so the reminder dragging doesn't hold them up.

**`Mindlore/Intents/`** (file-system synchronized groups, so new files join the target with no
`project.pbxproj` edit): `StartRecordingIntent`, `NewEntryIntent`, `AskJournalIntent`, and an
`AppShortcutsProvider`. In the app target, no extension, no entitlement.

**The bridge is new plumbing, not a reused pattern.** An intent can fire before `RootView.init`
has ever run: `RecordingSession`, `AppRouter` and `AskService` are all built inside it
(`RootView.swift:24-121`), and `MindloreApp.init` holds none of them. `AppRouter.mindFocusRequest`
only looks similar. It solves a request arriving after the router exists but before `MindView` does,
and its caller always already holds the router. So:

- `IntentRequests` is a free-standing `@MainActor @Observable` singleton, independent of `RootView`,
  holding one `pending` action. Borrowed from `mindFocusRequest`: only the take-once shape (nil it
  out on consume).
- `RootView` consumes it on first appearance and on change, so a cold launch and a warm one take the
  same path, exactly once.
- Actions map to what exists: `RecordingSession.begin()` (`RecordingSession.swift:76`) and
  `JournalRoute.new()` through `AppRouter.showEntry`.
- **`showAsk(question:)` needs the router's own shape.** `AppRouter` holds no `AskService`
  (`AppRouter.swift:64-68`), and no existing jump reaches into another `@State` object. So it gets a
  `pendingAskQuestion` that `AskView` consumes, the way `MindView` consumes a focus request, plus a
  `.ask` case in `PendingJump` so it waits behind an open recorder cover like every other jump.
- **Already recording.** `begin()` guards `status == .idle` and silently no-ops otherwise.
  `StartRecordingIntent` checks first: if a recording is running it calls `expand()` to bring the
  recorder back and says "Already recording" to Siri, rather than reporting a success that did
  nothing.

**The reminder**, second commit. `ReminderScheduling` protocol over `UNUserNotificationCenter`,
faked in tests the way `FakeKeyValueStore` and `FakeHTTPClient` are. Settings keys follow
`SettingsStore`'s exact pattern (`Key` enum entry, `didSet { write(...) }`, `bool(key, fallback)` in
init so a missing value means the default). One daily local notification, off by default, neutral
copy, no badge. "Skipped if today already has an entry" can't be decided at fire time, so it is
handled by rescheduling after a save.

**Diagnostics**: `intent.invoked` carrying a fixed-vocabulary kind string and nothing else, never the
question text; `reminder.scheduled` / `reminder.fired` carrying counts and a bool. Each gets a
`DiagnosticsPrivacyTests` case, which is what the privacy rules require of every new event.

**Tests**: unit tests for the intent bridge (each action reaches the right router or session call, a
cold-launch pending action is consumed exactly once, an ask jump waits behind an open cover, record
while recording expands instead of beginning) and for `ReminderScheduler` against the fake
(scheduling, cancelling, rescheduling after a save, the off-by-default path).

Intents themselves are verified on the device. The specific thing to watch there is the cold-launch
race: whether `perform()` can run before `RootView`'s first appearance. The bridge is built to be
correct either way (a request set early waits; a request set late is observed), but only the device
shows which one actually happens.

## Not in scope

- B3 (first run), B4 (recording screen), B7 (Mind halos, Bloom, glass on the panel), B8
  (extension, Live Activity, widget). Phase 1 takes the one B7 item worth having, Ask's empty state.
- Removing the toolbar mic and collapsing the compose buttons into a `Menu`. It is ready to call, but
  it touches 11 UI test files and belongs in its own PR.
- The Sounds settings row (it arrives with B4's sound work).
- Any change to retrieval, prompts, the graph simulation, the coordinators, or any model beyond the
  new settings keys.
- Embeddings, Reflect, iCloud sync.

## Verification

Per phase, in order, before the next phase starts:

```bash
# Unit suite, the iteration loop
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:MindloreTests -parallel-testing-enabled NO \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 60
```

- UI tests: only the phase's own suites, on a simulator dedicated to this worktree, so a parallel
  session's app doesn't get killed mid-run.
- Screenshots: `DesignScreenshotTests` and `AskScreenshotTests` in light and dark
  (`xcrun simctl ui <udid> appearance dark`, since `XCUIDevice.shared.appearance` doesn't reach the
  simulator), attachments exported and looked at by eye before any phase is called done.
- Commit with `gh`, push, re-run the unit suite after each push. There is no CI to check.
- Sub-agent review over the full diff at the end, fixes in separate commits, never amended.
- Device steps (haptics, the Action button, Siri, notification delivery, real transcription timing)
  are listed for you to run; I can't run them.

## Known risks

- **Glass is first contact.** Nothing in the app uses `.glassEffect`, and the 26.5 modifier names are
  unverified. Fallback is `.ultraThinMaterial`, and I'll say so rather than fight the SDK.
- **The insights sheet leaving `Form`** changes row structure. Any UI test asserting on cells rather
  than identifiers will break; grep before, not after.
- **There are three baseline UI failures on Mind/Graph** from a run yesterday (two can't find
  `mindGraphCanvas`, one where `mindSearchField` goes invalid after interruption handling). Confirm
  whether they reproduce on `main` before Phase 2, so a pre-existing failure isn't blamed on the
  restyle.
- **A parallel session is on Reflect** (`.claude/worktrees/reflect`, `feature/reflect`, locked).
  This worktree runs UI tests on its own simulator so neither kills the other's app, and Reflect
  touching `EntryInsights` or Today is worth a look before the PR merges.
- **Session rate limit.** Three research agents died on it earlier; the end-of-PR review agent may
  hit the same wall, in which case the review waits rather than being skipped.

## Plan review (sub-agent, before approval)

Seven findings, all folded in above: the cold-launch bridge needed its own lifecycle rather than
`mindFocusRequest`'s; `showAsk` can't reach `AskService` and needs a pending value plus a
`PendingJump` case; `InsightsUITests.swift:53-56` breaks for certain on the container change;
`examples` runs per render and the heaviest-area source was unbounded; muted names leak into
suggestions today; record-while-recording needed a decided answer; a wrong filename. It also confirmed
the call site, the `TodayComposer`/`TodaySource` split, the untouched list, the 11-file count for the
deferred mic work, and that the phases have no code dependency on each other (their order is a
review choice, not a technical one).

## As built

Where the build left the plan, and why. Each is also in the commit that made it.

**Ask**
- The suggestion fetcher left `AskSources` for its own file (`AskSuggestionSource`) rather than
  keeping the name there. `AskSources`' header promises everything in it is about what may reach a
  provider, and suggestions never leave the phone.
- Glass took on the first try: `.glassEffect(.regular.interactive(), in: Capsule())` compiled
  against 26.5 as written. No fallback to material was needed.
- Added at the owner's request mid-phase: the keyboard can be put away (drag the conversation, tap
  empty space), since it covered the tab bar with no way out but sending.
- Found by looking at screenshots: a fade under the field let a card show through at the capsule's
  edge, and moved onto the field alone it caught the search panel's last row's tap. It lives on the
  whole bottom stack now and takes no touches.
- Found reading Today's code afterwards: the Ask animations skipped `Motion.resolve`, so Reduce
  Motion didn't reach them. Fixed in its own commit.

**B5**
- The entity page keeps its `Form` with Paper behind and `Palette.card` rows, instead of wrapping
  content sections in `.card()` rows. Its sections carry per-row swipe actions (done, let go,
  reopen, undo merge), a disclosure, and links; collapsing a section into one card row would lose
  every swipe, and an inset-grouped section already is a rounded card. The editing rows get the
  same rows, which is what keeps the page one surface.
- The peek card got neither glass nor mention dots. It is a partial-height sheet, which iOS 26
  already draws as glass, so adding glass would be glass on glass. Dots need per-day mention data
  the card doesn't have, which is a data change, not a restyle.
- The plan review said only `InsightsUITests` scrolled the sheet by container. `GraphUITests` and
  `GraphScreenshotTests` did too, on the sheet's chips. The sheet's scroll view is named
  `insightsSheet` and all of them use the name; `scrollViews.firstMatch` could have been the editor
  underneath.
- Tappable chips come out Ember-tinted rather than neutral, because inside a button the chip's fill
  takes the tint. Kept on purpose: a chip that opens something reads as a link.

**B6**
- Start Recording speaks nothing, rather than saying "Already recording" when one runs. A reply on
  the way in would be the first thing the microphone heard, and the recorder coming back is the
  answer.
- `reminder.fired` wasn't built: the app can't see a notification fire without becoming the
  notification delegate. `reminder.permission` and `reminder.scheduled` are the events.
- The reminder schedules a week of single notifications, not one repeating one, because "skip
  today if you've written" can only be decided when scheduling. A journal left alone for a week
  stops getting them.
- Not built: offering the reminder after the third entry (Phase B's plan). It is a switch in
  Settings for now.

## Code review (sub-agent, Sonnet, read-only, over the whole diff)

Five findings, four real, all fixed in their own commits:

1. **Intent jumps didn't wait behind the recorder.** The recorder was never one of the covers the
   router waits for, and the two tests claiming it did registered a cover name production never
   uses. Fixed by putting the recorder away before a new-entry or Ask jump (it keeps recording in
   the accessory), with tests against a real recording session.
2. **A reschedule cut short left no reminders.** It cleared first and added after, on the way to
   the background. It adds first and prunes after now; a test suspends it mid-way.
3. **Permission withdrawn in iOS Settings went unnoticed.** The reminder checks authorization, the
   app reschedules on coming back to the foreground, and a reminder iOS won't show switches off
   with the footer saying why.
4. Not a defect: the entity page's mechanism, which this spec still described the old way. See
   "As built" above.
5. **Suggestions went stale while the empty state stayed up**, so a name hidden in Mind could
   linger. They refresh on the graph and save revisions.

It also noted that no test tapped a citation with the keyboard up, the combination the
tap-to-dismiss gesture could break. `testACitationOpensItsEntryWhileTheKeyboardIsUp` covers it.

## Verification record

- Unit suite: 1,418 pass (1,355 on `main` plus 63 new).
- `GraphUITests`, `GraphScreenshotTests`, `InsightsUITests`: identical before and after B5, ten
  pass. The two failures (`testDemoJournalMind`, `testMindFocusesATappedNodeAndKeepsResponding`,
  both "no `mindGraphCanvas`") fail the same way on `main` and are Mind code this branch doesn't
  touch. The third failure seen on 2026-09-20 (`testMindSearchOpenMergeAndUnmerge`) passed in both
  runs, so it's flaky rather than broken.
- `AskUITests`, `AskScreenshotTests`, `SettingsTabUITests`, `AISettingsUITests`,
  `SettingsScreenshotTests`: pass.
- Screenshots looked at in light and dark: Ask empty, focused, search panel, answer; the insights
  sheet; the entity page; Settings with the Reminder section.
- Every commit builds on its own, app and tests.
- The built app's intent metadata carries all three intents and their phrases.

