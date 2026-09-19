# Mindlore Phase B: Feel

Branch: `feature/phase-b` from `feature/phase-a` (rebased onto `main` once PR #6 merges).

Status: revision 2, approved by the owner on 2026-09-19 (every recommendation under "Owner
decisions" accepted). Revision 2 folds in the sub-agent review of revision 1 (12 findings; see
"Review log"). Nothing below is built. The design direction
came from a design pass on 2026-09-19 against a full inventory of today's UI; the claims it
flagged were then checked against the code (see "Checked").

## Why

Phase A made the app work. It still looks like a Settings screen. There is no colour of its own
(`AccentColor` is unset, so everything is system blue), no app icon images, no type choices, no
shared styles, one haptic in the whole app, and no Liquid Glass on an iOS 26 target. There is no
first run. Finishing a recording, the most important moment in the product, has no payoff: the
recorder closes and you land in an editor. Mood and summary never appear outside a `Form` sheet.
Nothing gives you a reason to open the app tomorrow: no resurfacing, no reminder, no Action
button, no widget.

Phase B gives the app an identity, a reward for every entry, and a reason to come back.

## The thesis

A quiet, warm room that was paying attention. You talk for ninety seconds and put the phone
down. A few seconds later it shows you, without comment, what it heard: who, where, how it felt,
and which open thread you just closed.

Three mechanics from the best apps carry over to a private journal:

- **The zero-decision first action** (Uber's "Where to?", ChatGPT's composer). The app opens
  onto one primed input, not a library. Here that is the record accessory, plus a home surface
  that answers "what would I say?" before you ask.
- **Variable reward made of your own content** (Instagram's feed, Photos Memories). The pull to
  reopen is not knowing what you'll see. The honest version in a journal is resurfacing: one day
  an entry from a year ago, another day a thread that closed, another a person gone quiet.
- **Investment you can see compound** (Hinge's profile, Claude's projects). Every entry makes
  the graph denser and Ask smarter, and today that growth is invisible. Show the delta.

What does not carry over: infinite scroll, social proof, streaks that punish, red badges,
re-engagement notifications with fake urgency, and any copy that grades the user. The test for
every number on screen: can it ever make the user feel they failed? If yes, it does not ship.
The app observes. It never judges and never advises.

## Ground rules

- **Identifiers survive.** About 124 accessibility identifiers hold the UI suite up. Grep
  `MindloreUITests/` before moving any control.
- **No new AI calls.** Every "the app noticed" surface is a query over data Phase A already
  stores (`LooseEnd.resolvedByEntryID`, `statusChangedAt`, `dueDate`, `Entity.lastLinkedAt`,
  `linkCount`).
- **Privacy and no-advice rules stand.** New diagnostics events carry counts only and get a
  `DiagnosticsPrivacyTests` case. Resurfacing copy states facts ("Maya last appeared 12
  August"), never suggestions.
- **Colours live in the asset catalog** with light and dark variants. No hex in code.
- **Text styles only, never point sizes.** Dynamic Type keeps working. Reduce Motion collapses
  every motion to a 0.2 s crossfade through one helper.
- **Screenshot before done**, per `tasks/lessons.md`. Each sub-phase adds its states to a
  screenshot test and the screenshots get looked at.
- **Reflect stays its own phase** (recaps, area balance, mood over time, generated narrative).
  Phase B owns single-item resurfacing and raw counts. One thing is pulled forward: the week
  strip, which is a seven-cell query and later becomes Reflect's way in.

## Identity

**Colour.** Accent "Ember", a warm amber-coral: light `#E8703A`, dark `#FF8A55`, set as
`AccentColor` so every system control inherits it. It replaces the record button's alarm red;
red stays for destructive actions and the live recording dot. Surfaces are warm: Paper
`#FAF7F2` / `#141210`, Card `#FFFFFF` / `#1E1B18`, ink `#1C1A17` / `#F2EEE8`.

Life areas, one hue each at matched lightness, dark variants lifted about 12 percent: Work
`#4C7DD9`, Money `#3E9C6E`, Health `#E0524D`, Mind `#8A63D2`, Family `#E39A2D`, Love `#E0569B`,
Friends `#2FA7B8`, Play `#F0C02E`, Home `#9A7B5C`.

Entity kinds, a cooler and less saturated family so a kind is never mistaken for an area on the
graph: Person `#6C8CFF`, Place `#35B58A`, Organization `#7A8CA5`, Project `#B57BFF`, Event
`#FF9F5A`, Tag `#A8A294`, Other `#8A8A8E`. `EntityKind` has seven cases, and
`entityKindColorsAreDistinct` compares all seven, so every one needs its own colour set.

Mood is never coloured good or bad. Mood chips are neutral ink on Card.

**Type.** One rule the user can feel without being told: serif is you, sans is the app. System
serif (New York, `.fontDesign(.serif)`) for the user's own words: entry body, titles, quoted
snippets in citations and resurfacing cards. SF Pro for chrome and everything the AI wrote. SF
Rounded for the timer and totals. No bundled fonts.

`.fontDesign(.serif)` stops at SwiftUI. `GrowingTextEditor` is a `UITextView` that sets
`.preferredFont(forTextStyle: .body)` itself (line 20), so the editor gets its serif from a
`UIFont` built on the body descriptor `withDesign(.serif)` and scaled through `UIFontMetrics`,
or Dynamic Type stops following. That one font line is the only thing B0 changes in the editor;
its growth and caret logic stay as they are. Read mode's attributed text takes the same font.

**Shape and material.** Continuous corners: 24 for cards, 16 for inner tiles, capsules for
chips. Content cards are opaque with a hairline stroke. Liquid Glass only on what floats over
content: the record accessory, the Mind panel, the peek card, graph controls, the Ask composer.
Never glass on glass, never on list rows.

**Motion** (`Motion.swift`), four named motions:
- **Settle**, `spring(duration: 0.45, bounce: 0.18)`: anything arriving.
- **Bloom**, `spring(duration: 0.6, bounce: 0.3)`, scale 0.6 to 1 with opacity, staggered 60 ms:
  insights landing, graph nodes appearing.
- **Carry**, matched geometry or the zoom transition, `spring(duration: 0.5, bounce: 0.12)`: one
  object moving between places (accessory to recorder, row to entry, peek card to page).
- **Breathe**, 2.4 s ease in and out at low amplitude: waiting on AI, the idle mic.

**Haptics** (`Haptics.swift`, `.sensoryFeedback` only): record start medium impact, record stop
heavy impact, entry kept success, insights landing on screen soft impact, loose end closed
success, name or node tapped selection, panel detent light impact, replay tick soft impact at
0.4, error warning. Nothing on scroll.

**Sound.** Two soft ticks, record start and stop, off by default, for eyes-free use from the
Action button.

**Icon.** An ember disc on dark Paper: five to seven small nodes joined by fine lines that read
as a lowercase "m" and as a waveform. Built layered in Icon Composer for the glass, tinted, and
dark variants.

## The loop

**Trigger.** "Something happened", or "I want to see what it noticed". Outside the app: one
optional daily reminder, the Action button, a lock screen control.

**Action.** Talk. One tap from anywhere, none from the Action button.

**Reward: the Keep moment.** On stop, the recorder collapses (Carry) into a card titled "Kept"
with duration and word count, and a success haptic fires. The live transcript already exists,
so the first line of your words is there at once, in serif. As the pipeline lands, things Bloom
into the card: title, mood chips, area dots, then "Noticed" rows of people and places with new
ones marked. Then the best line in the app: "Closed: call the landlord (open since 3 Sept)".
With AI off or offline the card still shows Kept, the words, and "Insights will arrive when
you're online". One tap dismisses it. It never blocks, and swiping it away at any moment is
safe, because the save already happened.

The card is for voice entries. A photo entry has no exit to intercept: confirming pages happens
before any text exists, and approving text is a button inside an editor that's already open. So
photo and typed entries get the same payoff in place, through the read-mode strip (B4).

**What the card does to the automatic AI pass.** Today the editor opens after Finish and marks
`EditorPresence`, and `transcription.onTextReady` (`RootView.swift:71`) fires `.textReady` only
when the entry is not open. So for a recording the user is looking at, the pass waits for
`.editorClosed`. The Keep card does not register with `EditorPresence`, on purpose: text
arriving while the card is up fires `.textReady` at once, which is what lets insights Bloom
into the card. That makes `.textReady` the normal path for voice. If the user taps through to
the editor mid-run and types, the coordinators' `contentRevision` check already drops the stale
result. `AIPassTrigger`'s code doesn't change; which moment wins does, and B1 tests it.
(`Moment.finished` still means Done tapped in the editor, never a recording finishing.)

**Investment.** The card ends with the delta: "Your mind map: 84 people and places, 3 new
connections". Tapping it opens Mind focused on this entry's nodes.

**Tomorrow: Today.** A header above the Journal list, not a fourth tab. A serif greeting, a
seven-dot week strip (a dot per day, filled if there's an entry, tinted by that day's areas),
and at most three cards picked by a pure, deterministic `TodayComposer` in this order:

1. a loose end due today, or one your last entry closed
2. on this day: prior years, then a month ago, then six months ago
3. still open: the oldest open loose end, in your own quoted words
4. it's been a while: a well-linked entity whose `lastLinkedAt` is over 30 days old, stated as
   fact
5. the latest entry's summary

Cards are dismissible and don't return the same day. "It's been a while" skips hidden entities,
has a per-person "don't show", and has a Settings switch, because a lapsed person may be a
painful one.

`TodayComposer` follows `EntityGraph`'s shape: no SwiftData import, `nonisolated`, fed plain
structs. A main-actor `TodaySource` does the fetching: one `Entity` fetch into the usual
`[UUID: Entity]` map, the `mergedIntoID` walk with the cycle guard, hidden filtering, open loose
ends, candidate entries by date. This is the first place loose-end `entityIDs` get resolved and
hidden-filtered together (the insights sheet shows them raw), so a loose end about a hidden
person never becomes a card.

Dismissals live in two places. "Not today" is one `SettingsStore` key holding a small JSON value
(the day plus the dismissed card keys), thrown away when the day changes. "Don't show this
person" is `Entity.resurfacingMuted: Bool = false`, because it should follow a merge to the
winner and sync one day; `CloudKitSchemaRulesTests` covers it.

**No streaks.** The week strip shows presence, not obligation: no counter, no "don't break it".
The only running numbers are totals that can only go up (entries, people, places, hours spoken).

**Reminder.** One local notification a day at a chosen time, off by default, offered once after
the third entry. Neutral copy ("A moment for today?") because lock screens are public; loose-end
text on the lock screen is opt-in. Skipped if today already has an entry. No second nudge, no
icon badge.

## Screen by screen

- **First run** (missing today). Three skippable screens: the promise and the privacy stance
  ("Your words stay on this phone unless you turn on AI"), a mic and speech permission primer
  that asks in context, then "say anything for ten seconds" on the real recorder, so the Keep
  moment is the tutorial. Skipped automatically under `-uiTesting`.
- **Journal** (top priority). Keep `List` (swipe actions, `entryRow`, test behaviour) with clear
  row backgrounds, hidden separators, `.scrollContentBackground(.hidden)` over a Paper
  background (without that pair the system list background wins and Paper never shows; the
  same goes for every `Form`), and card rows: serif title, two-line preview, a footer of
  date, mood words, and area dots, a small source glyph. The sparkles icon goes. Mood and
  summary finally show outside the sheet. Toolbar drops to a gear and one compose menu; the
  three `new*EntryButton` identifiers stay on real controls. Filter chips become capsules in
  area colours.
- **Voice capture.** Carry from the accessory, the live transcript in large serif with older
  lines fading, one Ember waveform ribbon (Canvas) in place of the level bars, a quiet rounded
  timer, an Ember stop button with a small red live dot.
- **Photo capture.** A Breathe shimmer per page while it transcribes, text Blooming in per page.
  After approval the read-mode strip Blooms in with the insights. No Keep card (see the loop).
- **Editor and read mode** (mostly right). Serif body, a line measure near 66 characters, names
  underlined in Ember, a metadata strip under the title (date, mood, areas) that opens insights
  and Blooms in when insights land. `GrowingTextEditor` internals are not touched.
- **Insights sheet** (a `Form` today). A card stack built from the Keep card's pieces: summary,
  mood chips, area tiles, people and places, loose ends with a struck-through "closed here", the
  cleanup offer. It stays a sheet.
- **Mind** (strongest screen, polish only). New kind palette, glass on the panel and controls, a
  Breathe halo on nodes touched in the last seven days, new nodes Bloom, replay ticks, a
  designed empty state. The simulation is not touched.
- **Peek card and entity page.** Glass card with avatar, one-line bio, "last appeared", a count,
  and recent mentions as dots; Carry into the full page. Entries restyled as Journal rows.
- **Ask** (close). Citations as small serif quote cards, a Breathe indicator while waiting,
  three suggested questions in the empty state filled locally from the user's top entities and
  areas (templates, no AI call), a quieter cost line.
- **Settings.** Fine as Forms. Add Reminders, a Sounds toggle, and a "Your journal" totals row.

## Phases

Ordered by what the user feels per unit of work. Tokens go first but thin: every later
sub-phase consumes them, and accent plus serif plus icon change the whole app in one small PR.
B0 must not turn into a refactor of every view.

### B0: Foundation and skin (S to M)
- [ ] `Mindlore/Design/`: `Palette.swift` (names only, values in `Assets.xcassets`),
      `Typography.swift`, `Motion.swift`, `Haptics.swift`, `CardStyle.swift`, `ChipStyle.swift`.
- [ ] `AccentColor`, Paper, Card, ink, nine area colours, six kind colours, light and dark.
- [ ] `LifeArea.color` and `EntityKind.color` are inline system-colour switches in a view file
      today (`InsightCards.swift:19-33,94-104`). They move to `Design/Palette.swift` and read the
      asset catalog. The property name stays `color`, so the nine call sites don't change.
- [ ] `GraphCanvasView` reads `kind.color` inside the per-frame draw closure (line 232). Resolve
      the palette once per appearance or colour-scheme change into the existing draw cache, not
      by name per node per frame.
- [ ] Look at every place that composites over a colour (`EntityAvatar.swift:26`'s 0.15 fill,
      `GraphCanvasView.swift:311`'s bucket opacity, `MindLens`, `SearchPanel`,
      `LifeAreasSettingsView`, `MoodPickerView`), in light and dark.
- [ ] Serif on entry text and titles, including the one `UIFont` line in `GrowingTextEditor`.
      The two fixed font sizes go.
- [ ] Paper behind `List` and `Form` screens.
- [ ] App icon (needs the owner's eye; a generated first pass, then Icon Composer).
- [ ] A `DesignScreenshotTests` class covering Journal, editor, Mind with the search panel up, a
      peek card, Ask, the insights sheet, and Life areas settings, in light and dark.
- Leaves alone: every layout.

### B1: The Keep moment (M)
- [ ] `Views/Capture/KeepCard.swift`, `KeepModel.swift` (observes the entry by id, re-fetches
      after each await, tolerates the entry being deleted underneath it).
- [ ] Shared insight card pieces pulled out of `InsightCards.swift`.
- [ ] `RecordAccessory`, `RecordingView`, and the `onFinished` route in `RootView` (line 113
      today), which shows the card instead of calling `appRouter.showEntry`. Voice only.
- [ ] `keep.shown` and `keep.dismissed` events, counts only, with privacy test cases.
- [ ] Unit tests for `KeepModel`'s progression on the existing fakes, including AI off, offline,
      and text arriving late from the cloud path. Tests for the pass: text arriving under the
      card fires `.textReady` once, tapping through to the editor and closing it doesn't fire a
      second pass, and typing in the editor mid-run drops the stale insights.
- [ ] "Closed" and "N new connections" come from stored data: `LooseEnd.resolvedByEntryID ==
      entry.id`, and the entry's `EntityLink`s whose entity has `linkCount == 1` or
      `firstLinkedAt` from this entry. Fetched by id after `graph.revision` moves. `RecordingUITests` expects the editor after
      Finish: keep a tap-through and update it.
- Leaves alone: coordinators, `AIPassTrigger`, `EntrySaver`.
- Device: haptics, real transcription timing.

### B2a: Journal rows (S to M)
- [ ] `EntryListView` rows, toolbar, filter chips. Row counting in UI tests already counts
      `entryRow`, not cells (A8), so restyled rows are safe; check it still holds.
- Leaves alone: `JournalGroups`, `JournalFilter` logic.

### B2b: Today (L)
- [ ] `Views/Today/TodayComposer.swift` (pure, `nonisolated`, injected date and plain inputs),
      `TodaySource.swift` (main actor, does the fetching and resolution), `TodayCards.swift`,
      `WeekStrip.swift`. Today is a header section of the `List`, above `JournalGroups`'
      sections, carrying no `entryRow`.
- [ ] `Entity.resurfacingMuted`, the day-scoped dismissal key in `SettingsStore`.
- [ ] Unit tests: card priority, on-this-day date maths across leap years and day-only entries
      (`entryDateIsDayOnly` is noon), hidden and merged entities on both entity and loose-end
      cards, faded loose ends never shown, both kinds of dismissal, a clock stepping back.

**Cut line.** After B0, B1, B2a, and B2b the app has an identity, a payoff for every entry, and a reason to
open it tomorrow. If the phase stopped here, the brief would be answered.

### B3: First run and permissions (S)
- [ ] `Views/Onboarding/`, `hasOnboarded` in `SettingsStore`, skipped under `-uiTesting`.
- Device: the permission prompts and the ten-second recording.

### B4: Recording screen and motion pass (M)
- [ ] Carry transition, waveform ribbon, serif live transcript, symbol effects on the accessory,
      the read-mode metadata strip.
- Device: nearly all of it.

### B5: Insights sheet and entity surfaces (M)
- [ ] `EntryInsightsView`, `LooseEndsCard`, `EntityPeekCard`, `EntityView`. The insights sheet
      has the densest identifiers in the app.

### B6: App Intents and the reminder (S to M)
- [ ] `Mindlore/Intents/` (`StartRecordingIntent`, `NewEntryIntent`, `AskJournalIntent`), in the
      app target, no extension, no entitlement: Shortcuts, Spotlight, Siri, the Action button.
- [ ] `Reminders/ReminderScheduler.swift` behind a protocol, tested with a fake centre.
- Device: Action button, Siri, delivery.

### B7: Mind and Ask polish (S to M)
- [ ] Halos, Bloom, glass, empty state, suggested questions, citation cards.

### B8: Extension: recording control, Live Activity, maybe a widget (L, gated)
- [ ] Starts with a one-hour signing spike: add an empty widget extension and install it on the
      phone under the Personal Team. If signing fails, B8 is dropped without loss.

### B9: Review, device, docs
- [ ] Privacy test for every new event. Read-only sub-agent review of the whole diff.
- [ ] Device pass: every haptic, the Keep moment on a real recording, first run on a fresh
      install, the reminder, the Action button.
- [ ] `CLAUDE.md` gains a Design section; `docs/remaining-work.md`; `tasks/smoke-test.md`.

## Checked

- `AudioRecorder` has `pause()` and `resume()` (`AudioRecorder.swift:149,156`), so the recorder
  redesign keeps pause.
- The screenshot tests attach screenshots and compare nothing, so a reskin can't turn them red.
- `newVoiceEntryButton` is used by one UI test file (`RecordingUITests`, twice).
- `LooseEnd` and `Entity` hold every field Today and the Keep card read.

Still to verify at build time: the exact Liquid Glass modifier names in the 26.5 SDK, whether
the zoom transition accepts an overlay as its source (else `matchedGeometryEffect` inside one
hierarchy), and Personal Team support for extensions, App Groups, and Live Activities (B8's
spike answers all three).

## Not in scope

- Reflect: recaps, charts, mood over time, generated narrative about a period.
- Embeddings for Ask (the measured indirect-description gap from A9c).
- Any change to the simulation, the coordinators, retrieval, or the models beyond small settings.
- iPad layouts, localisation, themes or user-picked accents.
- Social or sharing features.

## Owner decisions needed

1. **Name of the home surface.** Recommended: "Today".
2. **Streaks.** Recommended: none, ever. Week strip and up-only totals are the ceiling.
3. **Serif for your words.** Recommended: yes, system New York.
4. **Accent.** Recommended: Ember, accepting that the record button stops being red.
5. **Sound.** Recommended: exists, off by default.
6. **Keep card for typed entries too?** Approved as voice and photo; revision 2 narrows it to
   voice only, because the review found a photo entry has no exit to hang a card on. Photo and
   typed entries get the read-mode strip. Flagged to the owner.
7. **"It's been a while" cards.** Recommended: on, with a switch and per-person "don't show".
   Try it on your own journal before deciding; it's the one feature that can hurt.
8. **Loose-end text on the lock screen.** Recommended: opt-in only.
9. **Toolbar mic.** Recommended: remove once the accessory is proven; one test file to update.
10. **B8 at all.** Recommended: decide after the signing spike. App Intents carry most of the
    habit value without an extension.
11. **Order against A10 and Reflect.** Recommended: B0 to B2 can start now off `feature/phase-a`
    while A10 waits for the phone, and Reflect follows Phase B so it's built on the new cards.

## Review log

Revision 1 (read-only sub-agent review, 2026-09-19; 12 findings, every factual one checked
against the code before folding in):

1. `EntityKind` has seven cases and the palette had six: added Other, moved Organization off
   the grey it would have shared.
2. The colours weren't an indirection to repoint but inline switches in `InsightCards.swift`:
   B0 now moves them.
3. Serif can't reach `GrowingTextEditor` through SwiftUI, and the plan both promised it and
   promised not to touch the editor: the one font line is now named, with `UIFontMetrics`.
4. A Keep card that skips `EditorPresence` changes which moment fires the automatic pass:
   accepted on purpose, written down, and tested in B1.
5. "The photo approval exit" was two different moments, neither usable: the card is voice only.
6. Dismissals had no home in `SettingsStore`'s scalar keys: one JSON key for the day,
   `Entity.resurfacingMuted` for a person.
7. `List` never shows Paper without `.scrollContentBackground(.hidden)`: added, Forms too.
8. A pure `TodayComposer` can't walk `mergedIntoID`: `TodaySource` pre-resolves, `EntityGraph`
   style.
9. Nine `.color` call sites composite with opacity: B0 looks at each, and the screenshot class
   covers more screens.
10. Today is the first place loose-end entities get resolved and hidden-filtered: B2 split into
    B2a (rows) and B2b (Today, sized L).
11. Asset colours resolved by name inside the per-frame draw closure: cached once per appearance.
12. `Moment.finished` means Done in the editor, not a recording finishing: noted beside the
    pass rules.
