# Settings sprint

Branch: `feature/settings` from `feature/phase-a` at d9ed765. Worktree `.claude/worktrees/settings`,
simulator `iPhone 17 settings` (`DBF519FD-3CB6-430F-B092-A166BA8C4E5B`). Baseline on that simulator:
1263 unit tests green. The first run failed ten `AskIndexLemmaTests` and one
`AskRetrievalQualityTests` question; that is the cold-simulator lemma asset issue in
`tasks/lessons.md`, and the second run passed with no code change.

Status: built on `feature/settings` (PR #17), approved by the owner on 2026-09-21. The "Done" notes under each phase and the "Built" section at the end record what changed on the way.

## What this is

Settings is 5 view files, 765 lines, plus `Mindlore/Settings/SettingsStore.swift`'s 350 (the 1,115
figure is the six files together). 38 accessibility identifiers, 34 keys. The root is
three unheadered sections. "Edit life areas" is three levels deep under AI, though life areas are a
journal concept that works with AI off. Your own name is set inside AI, under a row called "How AI
writes about you".

The audit's honest finding up front: almost nothing here is a setting that should not exist. The
controls are real and the defaults are sensible. What is wrong is the shape, which is the shape of
the order things were built in. Three things come out, two screens disappear, six controls move
behind an Advanced row, and the root gets organised around parts of the journal instead of
subsystems. The one real bug under the settings, the empty insights schema, turned out to be worse
than the open-defect line says; see below.

## Owner decisions, taken 2026-09-21

1. **Settings becomes a fourth tab**, beside Journal, Mind and Ask.
2. **The root is organised by what a setting touches**: Your journal, Today, AI, About.
3. **Bury, don't delete**, for the power-user controls: model fields, cloud fallback, custom prompts.
4. **Native `Form` on Paper**, not hand-built card rows.

Decision 1 has a consequence worth stating before the audit: the Journal toolbar gear goes. Two
doors to one screen is worse than either door alone, and the gear is the one the tab replaces. Both
UI test helpers reach settings by tapping `app.buttons["Settings"]`, the gear's **label**, not its
identifier. Whether that keeps working once the label sits on a tab instead is an open question
phase 1 answers first, because the answer decides whether those two classes can prove the tab at
all.

## Part one: the audit

Verdicts are **keep**, **cut**, **move**, **rename**. Where a control is cut, the reason names which
of the owner's three kinds it is: *prototype* (built to develop the app), *redundant* (a second way
to do one thing), or *half-finished* (it exists because the feature under it is not done).

### Root, `SettingsView.swift`

| Control | Key | Verdict | Reason |
|---|---|---|---|
| "AI" link | — | **move** | Becomes a headed section at the root, not a door to a subsystem. |
| Keep recordings | `keepAudioAfterTranscription` | **keep**, move | Real, and it is about your journal's storage, not AI. Goes to Your journal. Read by `EditorLifecycle` via `RootView:90`. |
| Names you haven't written about | `resurfacingEnabled` | **keep**, move | Real and the one switch that can spare a painful name. Goes under its own Today heading, since that is the only surface it changes. |

### AI, `AISettingsView.swift`

| Control | Key | Verdict | Reason |
|---|---|---|---|
| Use AI | `aiEnabled` | **keep** | The privacy promise, and the gate on six `AIServices` checks plus `TranscriberRouter`. Rises to the root's AI section. |
| API key field, Save, Replace, Remove, Test connection | Keychain + `providerAccounts` | **keep**, move | Five controls that belong together on their own screen, reached from one "OpenAI key / Saved" row. |
| Speech to text | — | **keep** | Keeps its screen: the engine picker earns explanation. |
| Journal pages | — | **cut** (*prototype*) | The screen holds one control, a model field. It exists because pages needed somewhere to live while pages were being built. The field moves to Advanced and the screen goes. |
| Titles | — | **keep**, flatten | One picker once its duplicate model field goes. Becomes an inline picker with its footer, no screen. |
| Ask | — | **keep**, flatten | Already one picker and a footer. Becomes inline, no screen. |
| Insights | — | **keep** | Keeps its screen: eleven controls. |
| How AI writes about you | `journalVoice`, `userName` | **keep**, **move**, **rename** | Your own name is not an AI setting. Moves to Your journal as **"How you're written about"**. It reaches a provider only under the name voice, which the screen already says. The row is renamed; the type stays `JournalVoiceSettingsView`, since renaming a type buys nothing here. |

### Speech, pages, titles, ask, `AIFeatureSettingsViews.swift`

| Control | Key | Verdict | Reason |
|---|---|---|---|
| Transcribe with (Live / This iPhone / OpenAI) | `speechEngine` | **keep** | `tasks/lessons.md` argues this one into existence: when a feature needs a choice, give the choice. |
| Speech model | `speechModel` | **move** to Advanced | The only way to use a model Mindlore does not know about. Real, not daily. |
| Use this iPhone when OpenAI fails | `fallBackToOnDevice` | **move** to Advanced | Changes what happens to a failed recording (`TranscriptionCoordinator:113,147`). Worth keeping, not worth meeting on the way to the engine picker. |
| Pages model | `pageModel` | **move** to Advanced | With this gone, `PageSettingsView` is empty and deleted. |
| Write titles with | `titleGenerator` | **keep**, flatten | |
| Model (under Titles) | `textModel` | **cut** (*redundant*) | The same key as Insights' model field. Two places editing one value, and the footer already says "Titles use the same model as insights". One field survives, in Advanced. |
| Answer with (Ask) | `askGenerator` | **keep**, flatten | |

### Insights, `AIFeatureSettingsViews.swift`

| Control | Key | Verdict | Reason |
|---|---|---|---|
| Generate insights (Automatic / When I ask) | `insightsTrigger` | **keep** | |
| Summary, Moods, Life areas, Tags, People and places, Loose ends | six `insight*` keys | **keep**, gated | Real. The all-off defect is fixed below. |
| Edit life areas | `lifeAreaNames`, `hiddenLifeAreas` | **move** to root | The headline IA bug. Life areas are a journal concept: `EntryListView` filter chips, `MindView` regions, `SearchPanel`, `KeepCard`, `InsightCards` all read them with AI off. Goes to Your journal at the top level. |
| Clean up transcriptions | `insightCleanedText` | **keep** | |
| Use the cleaned-up version automatically | `autoApplyCleanedText` | **keep** | Off by default, reversible (`originalText` and `cleanupAppliedHash` survive regeneration), and about your words, so it stays in Insights rather than going to Advanced. |
| Suggest entry dates | `suggestEntryDates` | **keep** | |
| Use the suggested date automatically | `autoApplySuggestedEntryDate` | **keep** | Same argument. Two readers, `RootView:53` and `:82`. |
| Model | `textModel` | **move** to Advanced | The surviving copy. |
| Custom insights | `customInsightPrompts` | **move** to Advanced | A whole CRUD screen for a feature that writes its own prompts. Real, and for one user in fifty. |

### Custom insights, `AIFeatureSettingsViews.swift:296-395`

The screen and its editor hold nine interactive controls the first draft collapsed into the single
row above. All **keep**, all move with the screen, none changes.

| Control | Line | Verdict |
|---|---|---|
| Per-prompt enable toggle | :315 | keep |
| Row tap to edit | :319 | keep |
| Swipe to delete | :322 | keep |
| Drag to reorder | :323 | keep |
| `EditButton` | :340 | keep |
| Add prompt | :329 | keep |
| Name field | :364 | keep |
| Instructions field | :368 | keep |
| Cancel, Save | :382, :385 | keep |

### Life areas, `LifeAreasSettingsView.swift`

| Control | Key | Verdict | Reason |
|---|---|---|---|
| Rename, Show (nine each) | `lifeAreaNames`, `hiddenLifeAreas` | **keep** | The screen is right. Only its address is wrong. |
| Debug: distribution + "Regenerate insights for every entry" | — | **cut** from here (*prototype*) | It is a tuning instrument, not a setting. It sat under Life areas because that is what it measures. Moves to a `#if DEBUG` section at the root of Settings, where a developer looks for developer things. It never ships: it is already behind `#if DEBUG`. |

### Journal voice, `JournalVoiceSettingsView.swift`

| Control | Key | Verdict | Reason |
|---|---|---|---|
| Voice (first / second / name) | `journalVoice` | **keep**, move | Reaches prompts through `promptVoice` in Insights, Ask and `GraphServices`. |
| Your name | `userName` | **keep**, move | Also read by `TodaySource` for the greeting, with AI off. Another reason it is not an AI setting. |

### The seven internal keys

These are state, not settings. None gets a control, none is deleted, and the IA must not grow a row
that looks like one.

| Key | Written by | Read by | Note |
|---|---|---|---|
| `aiEnabledAt` | `SettingsStore` when `aiEnabled` goes true | `TranscriberRouter:35` | Recordings made before AI was on never upload. Delete it and old recordings start going to OpenAI. |
| `automationStartedAt` | `MindloreApp:67`, once per install | `AIPassTrigger:59` plus five navigation sites | Entries made before this moment never get an automatic pass. |
| `askGeneratorChosenByUser` | first `askGenerator` write | `refreshAskGeneratorDefault`, `AskView:268` | Ask follows the phone until you choose; after that nothing moves it. |
| `todayDismissed` | `EntryListView:188` | `TodaySource:22` | Day-scoped card dismissals. JSON, so card keys never reach the log. |
| `lifeAreaNames`, `hiddenLifeAreas` | Life areas screen | six and seven feature sites | Backing stores for a control, which is why they look like settings and are not keys to tidy. |
| `providerAccounts` | `ProviderAccountStore:51,64` | `hasUsableKey`, `openAIAccount`, and `SettingsStore:119` | See below. The third reader matters here: the `titleGenerator` getter defaults to `.openAI` when `aiEnabled && !providerAccounts.isEmpty`, so moving the key onto its own screen moves the thing the Titles picker's default depends on. |

### The half-finished feature under the settings

`speechAccountID`, `pageAccountID`, `textAccountID` and `providerAccounts` describe a multi-account,
multi-provider app. There is no UI for any of it: the three account IDs have no app readers outside
`account(for:)` and are written only by `ProviderAccountStore.saveOpenAIKey` (lines 53-55) and
`remove` (66-68), and `openAIAccount` filters on `ProviderPreset.openAI.id`, so the list holds at
most one account. (Tests do read all three: `AccountsTests:59-61,86` and `SettingsStoreTests:218`.)
`CLAUDE.md`'s "Adding a provider" section describes the seam honestly, and the seam is worth
keeping.

Verdict: **keep the keys, add no UI, and do not let the IA imply providers are pluggable.** The AI
section says "OpenAI key", not "Providers". This is the one place the audit found a setting shaped
by an unfinished feature, and the fix is to stop the shape leaking into the screen.

### Score

Counted as audit rows, because counting rendered controls is meaningless here (`LifeAreasSettingsView`
draws 9 name fields and 9 toggles from one `ForEach`, against one row in the table): **29 rows in,
27 out, plus 4 new rows.**

Cut outright, three things: the Journal pages screen (`PageSettingsView`), the duplicate `textModel`
field under Titles, and the Titles screen itself. Moved rather than cut, and therefore still in the
app: the two debug controls, which leave Life areas for a root `#if DEBUG` section.

New rows: OpenAI key, What AI does, Advanced, and About's "Your journal". Two screens disappear
(Journal pages, Titles) and two flatten into inline pickers. Nothing a journaler touches is more
than two levels from the tab.

## The known defect: every insight section off

`docs/remaining-work.md` has it as "Turning every insight section off lets Run AI send a request
with an empty schema, which the provider rejects." It is real, and it is worse than the line
suggests. The first draft of this spec got it wrong in two ways, both caught by the spec review and
then confirmed against the source.

**It is not one-sided.** `AIServices:103` (`automaticInsightsUsable` ends in
`&& !insightSections(settings).isEmpty`) is consulted only by `AIPassTrigger`'s `insightsUsable`
closure at `RootView:38`, and only at the moment an entry is *flagged*. Turn the sections off after
an entry is flagged and the automatic path sends the same empty schema. `AIServices:103` prevents
new flagging; it does not guard a request.

**And `runAI` is the wrong place to guard.** `InsightsCoordinator.runAI` (`:95-109`) never builds a
request: it sets `automaticAIPassUsed`, calls `AIJobPolicy.manualReset`, and hands off to
`processQueue`. The request is built in `generate()`, at the
`InsightsPromptBuilder.plan(...)` call. Three routes reach it without passing through `runAI`:
`regenerateEverything` (`:111-128`) duplicates `runAI`'s body inline; any entry persisted with
`insightsPending == true` is picked up by `processQueue`'s fetch at launch (`RootView:214`),
foreground (`:224`) and network return (`:235`); and page approval plus the launch sweep both arrive
through `AIPassTrigger` the same way.

**The third mistake was the guard's predicate.** `InsightSections.isEmpty` is not the right test in
either direction, because the schema is source-dependent (`InsightsPromptBuilder:243-256`):

- `cleanedText` is emitted only when `source == .voice || source == .photo`, and only when the text
  is within `maxCleanedTextCharacters`.
- `writtenDate` is emitted only when `source == .typed`.

So the configuration the first draft called safe, six toggles off with "Clean up transcriptions"
on, produces a **zero-property schema for a typed entry**. And a schema with only
`suggestEntryDates` on is **valid for a typed entry** while `isEmpty` returns true and would block
it. `MindloreTests/InsightsTests.swift:59,65` already assert this source-dependence.

Fixing it, three parts:

1. **The truth is in `generate()`.** `InsightsRequestPlan` gains `asksForNothing`, computed inside
   `plan(...)` from the built schema's property count, which is the only place that knows. Directly
   after the plan is built, `generate()` returns early when it is true, without recording an attempt
   and without sending. It leaves `insightsPending` set rather than clearing it the way the
   `canRunAI` miss at `:144-149` does, so turning a section back on lets the entry run on the next
   pass instead of silently never running.
2. **A counts-only diagnostics event**, `insights.skipped` with a reason string (`"emptySchema"`)
   and the entry id, so the device loop can see it. It gets a `DiagnosticsPrivacyTests` case like
   every other event.
3. **The UI rule stays, as prevention, and is labelled an approximation.** The last enabled
   section's toggle is disabled using `InsightSections.isEmpty`, with a footer saying insights need
   at least one thing to look for. It stops the common case at the screen. It cannot be exact,
   because exactness needs an entry's source and length, and a settings screen has neither. Part 1
   is what makes that acceptable.
4. **`runAI` keeps a cheap short-circuit** on `sections().isEmpty`, so tapping Run AI with
   everything off does not burn the entry's automatic pass on a request that will not be sent.

## Part two: the information architecture

One `NavigationStack` in a Settings tab. Values on the right of a row so the screen answers
questions without being opened.

```
Settings  (tab 4)
|
+- YOUR JOURNAL
|    Life areas                    9 shown        >  LifeAreasSettingsView
|    How you're written about      First person   >  JournalVoiceSettingsView
|    Keep recordings               [on]
|
+- TODAY
|    Names you haven't written about  [on]
|
+- AI                                                (disabled rule below the diagram)
|    Use AI                        [on]
|    OpenAI key                    Saved         >  AIKeyView
|    What AI does                  On           >  AIFeaturesView
|    |
|    +- Speech to text             OpenAI        >  SpeechSettingsView   (engine picker)
|    +- Titles                     [picker inline]
|    +- Ask                        [picker inline]
|    +- Insights                   Automatic     >  InsightsSettingsView
|    +- Advanced                                 >  AdvancedAISettingsView
|         Speech model / Pages model / Text model
|         Use this iPhone when OpenAI fails  [on]
|         Custom insights          None        >  CustomInsightsSettingsView
|
+- ABOUT
|    Your journal                  84 entries    >  (counts only, see below)
|
+- DEBUG  (#if DEBUG only)
     Life area distribution, Regenerate insights for every entry
```

**Which rows go dead when AI is off.** There are two different predicates today and the first draft
of this spec flattened them into one. `AISettingsView:88` disables the "What AI does" section with
`!settings.aiEnabled && settings.titleGenerator != .onDevice`, so on-device titles keep the whole
section live. `SpeechSettingsView`'s cloud block (`AIFeatureSettingsViews:69`) uses a different one,
`!AIServices.pagesUsable(settings:accounts:) && !settings.aiEnabled`. The new "What AI does" row
inherits the first predicate verbatim; the Speech screen keeps the second on its own cloud section.
Neither is changed by this sprint.

What moved and why, in one line each:

- **Life areas** from three levels under AI to the root. It is a journal concept.
- **How you're written about** from inside AI to the root, renamed from "How AI writes about you".
  Your name is set here, and `TodaySource` reads it with AI off.
- **The key** off the AI screen onto its own row, so the AI screen is about what AI does rather than
  half about credentials.
- **Journal pages and Titles** stop being screens.
- **Six controls** behind Advanced.
- **The debug section** out of Life areas.

**"Your journal"** is new, and it is the one thing in this plan that is not audit, cut, move or
restyle. The owner's chosen IA showed it. It is three counts read from the store (entries, names,
hours spoken), no AI call, and it follows phase B's rule that the only numbers on screen are totals
that can only go up: no streak, no average, nothing that can read as a grade. If it is unwanted, say
so and phase 5 drops with nothing else affected.

### What the UI tests do about it

`AISettingsUITests` and `AIConfigurationUITests` each keep a private `openAISettings()`, and both
break on purpose:

- Both tap `app.buttons["Settings"]` (the gear's label). The first draft said both therefore break;
  that is unverified and may well be wrong, because `app.buttons` matches any descendant and a
  `Tab("Settings", …)` item is also a button with that label, so the helpers may keep passing with
  no edit. **Phase 1 verifies this before anything else**, because if they do keep passing, phase 1
  has no test proving the tab and needs one written. The gear's `settingsButton` identifier, which
  nothing uses today, moves onto the tab either way.
- Both then tap `aiSettingsLink`. That link is gone: AI is a root section. They lose the tap.
- `AIConfigurationUITests` reaches `speechSettingsLink` and `insightsSettingsLink`, which now sit
  one level deeper, under "What AI does". One extra tap each.
- Its `back()` taps nav-bar button index 0 and assumes exact stack depths (speech 1 level under AI,
  custom insights 2). Every depth in this plan changes, so `back()` gets called the right number of
  times at each site.
- It asserts link **labels** carry their value: `speechSettingsLink` shows "OpenAI" then
  "This iPhone", `insightsSettingsLink` shows "When I ask", `customInsightsLink` shows the count.
  Every one of those rows keeps showing its value, so those assertions stand.
- `speechModelPicker` / `speechModelField` move to Advanced. This one is not a navigation fix:
  `AIConfigurationUITests:57` asserts one of them exists **on the Speech screen**, so that
  assertion moves to the Advanced screen or goes.

`TodayUITests` never opens settings and is untouched. The 22 identifiers no test uses all survive on
real controls, minus the ones on cut controls (`pageModelField`/`pageModelPicker` move rather than
disappear; the Titles copy of `textModelField` goes with the duplicate).

## Part three: the look

`Form` on Paper, per decision 4. `paperBackground()` already pairs
`scrollContentBackground(.hidden)` with Paper and is already on all five screens, so the surface is
right today. What changes:

- **Serif for your own words only.** The life area name fields, the name field, and the voice
  samples in `JournalVoiceSettingsView` get `.journalText(...)`. Every label, header, footer and value
  stays SF. This is the rule from `Typography.swift`, and settings is chrome, so serif appears in
  exactly three places.
- **Text styles only.** No point sizes anywhere; `.caption`, `.body`, `.callout` as now.
- **Ember** arrives through `.tint`, which the accent already supplies to every system control.
  `JournalVoiceSettingsView`'s checkmark already reads `.tint`.
- **Motion.** Every `if` in these five files appears and disappears with no animation today. There
  are eight, not the four the first draft named: `AISettingsView:30` (the whole key block), `:46`
  (save error), `:49` (Test connection and status); `AIFeatureSettingsViews:61` (the entire cloud
  section on Speech, the largest of them), `:130` (the Titles model section, which this sprint
  deletes), `:171` (the on-device Ask option), `:228` (the life areas link, which moves), `:240` and
  `:257` (the two auto-apply rows). Each surviving one gets
  `Motion.resolve(Motion.settle, reduceMotion:)`, read from `@Environment(\.accessibilityReduceMotion)`.
- **Haptics.** `Haptics.selected` on picking a voice, which is a choice among samples and the one
  place here that feels like a selection. Nothing else. No haptic on a toggle: the system has one.
- **No Liquid Glass.** Every surface here is a list row. Glass is for what floats over content.
- **`LifeAreaRow`** keeps `area.color` from `Palette`, which B0 already moved out of `InsightCards`.

Checked against `TodayCards.swift`, which is the newest screen: it uses `card()`, `chip()`,
`journalText`, `Palette.ink`, `Motion.resolve` with the reduce-motion environment, and `.transition(.bloom)`.
Of those, settings takes `journalText`, `Palette.ink` and `Motion.resolve`. `card()` and `chip()`
stay out, because decision 4 says `Form`, and a `card()` inside a `Form` row is glass on glass's
quieter cousin: two surfaces for one thing.

## Phases

No CI. The gate after every push is the unit command from `CLAUDE.md` against
`id=DBF519FD-3CB6-430F-B092-A166BA8C4E5B`, and UI classes are named individually.

**Phase 1: the tab.** `AppTab.settings`, a fourth `Tab` in `RootView:135`, `EntryListView:88,104`
loses the gear and the sheet, `:13` and `:125` lose the dead `showingSettings` state.
`SettingsView` **keeps its own `NavigationStack`** (`:10`) and loses only the Done button and its
`.toolbar` (`:32-36`): tab content is not inside a stack of its own, `EntryListView:34` owns one the
same way, and without it the root's only link would do nothing. That mistake in the first draft is
what made phase 1 unshippable. No IA changes yet.
First job of the phase: run both UI classes unchanged and find out whether
`app.buttons["Settings"]` now resolves to the tab. Whatever the answer, the phase ends with a test
that fails without the tab. Run: unit, then `AISettingsUITests` and `AIConfigurationUITests`.

**Done.** 1263 unit tests green, and the open question is answered: **both UI classes passed
unchanged.** `app.buttons["Settings"]` matches the tab item exactly as happily as it matched the
toolbar gear, so neither class can tell a gear from a tab and neither would have noticed if the tab
had never been added. `MindloreUITests/SettingsTabUITests.swift` is the test that can: it scopes
every assertion to `app.tabBars`, asserts the gear's `settingsButton` identifier is gone, and opens
Settings from Mind, Ask and Journal in turn. Proven by deleting the `Tab` and watching it fail with
"Settings should be a tab bar item" before restoring it, because a passing test nobody has seen fail
is the same trap in a new place.

**Phase 2: the moves.** The four root sections. Life areas and voice to the top level, the key onto
its own screen, `AIFeaturesView` with Titles and Ask inline, `AdvancedAISettingsView`,
`PageSettingsView` and `TitleSettingsView` deleted (neither is referenced anywhere but
`AISettingsView:65,69`, so both delete cleanly), the duplicate `textModel` field going with
`TitleSettingsView`, the debug section moved. Identifiers travel with their controls. Three things
the first draft missed, all of which break here if they are not done here:

- **`EntryInsightsView:157`** pushes `AISettingsView`, which this phase dissolves. It is the app's
  only recovery path from "AI is off" inside the insights sheet. It gets retargeted at the Settings
  tab, and a tab jump out of a sheet has to dismiss the sheet first.
- **`SettingsView`'s `#Preview` (`:41-46`)** injects only `SettingsStore` and
  `ProviderAccountStore`. The debug section needs `InsightsCoordinator` and `\.modelContext`, so the
  preview gains both or goes.
- **`AIConfigurationUITests:57`**, which asserts the speech model control is on the Speech screen.

Run: unit, both UI classes.

**Phase 3: the defect.** `asksForNothing` on the plan, the `generate()` guard, the
`insights.skipped` event, the `runAI` short-circuit, the last-toggle UI rule. Unit tests: a typed
entry with only cleanup enabled is skipped rather than sent (the case the first draft called safe);
a typed entry with only `suggestEntryDates` is **not** skipped, which `InsightSections.isEmpty`
would have blocked; an entry skipped this way keeps `insightsPending` and runs once a section comes
back on; `regenerateEverything` and the launch sweep are both covered by the same guard. Plus the
`DiagnosticsPrivacyTests` case for `insights.skipped`. Run: unit.

**Phase 4: the look.** Serif in three places, `Motion.resolve` on the four conditional rows,
`Haptics.selected`, a read of every screen in both appearances. New `SettingsScreenshotTests` in
`MindloreUITests/`. `DesignScreenshotTests`'s `attach` helper is `private` (`:22`), so it gets
copied or lifted into a shared extension; copying is the smaller change and matches what the other
three screenshot classes already do. The tour covers root, Life areas,
Voice, Key, What AI does, Speech, Insights, Advanced, Custom insights, and the custom prompt editor.
Dark comes from `xcrun simctl ui <udid> appearance dark` on a **booted** device, per
`tasks/lessons.md`; `XCUIDevice.shared.appearance` does not reach the simulator and produced ten
light screenshots named "dark" last time. Attachments are exported with
`xcrun xcresulttool export attachments` and **opened and looked at**, both appearances, before the
phase is called done. Run: unit, `SettingsScreenshotTests`, both UI classes.

**Phase 5: About, docs, review.** "Your journal" counts. `CLAUDE.md` gains a Settings paragraph,
`docs/remaining-work.md` loses the empty-schema line. `git status` baselined, then a **read-only**
(`Explore`) sub-agent reviews the full diff, per `tasks/lessons.md`: a `general-purpose` reviewer
with write tools spent nine minutes implementing part of the last spec and then reported its own
code as a finding. Run: full unit, all three UI classes.

## Privacy

No new diagnostics events are needed: every control here already writes through
`SettingsStore.write` or `writeJSON`, which record `settings.changed` with the key and, for anything
that could carry the user's words, no value. The four JSON keys (`userName`, `lifeAreaNames`,
`customInsightPrompts`, `providerAccounts`, `todayDismissed`) keep `writeJSON`. If phase 5's counts
turn out to want an event, it carries counts only and gets a `DiagnosticsPrivacyTests` case; the
current plan has it read on appearance and log nothing. Phase 3's `insights.skipped` is the one new
event, carrying an entry id and a fixed reason string, and it gets its case.

## Not in scope

- Reminders and the Sounds toggle from `tasks/phase-b-ux.md`. Both are settings for features that
  do not exist yet (B6, B4). Adding the rows now means shipping switches that control nothing.
- First run and `hasOnboarded` (B3).
- Any multi-account or "add a provider" UI.
- Any change to `TranscriberRouter`, `AIJobPolicy`, or what a setting does once read. The sprint
  changes where settings live and how they look. The one exception is phase 3, which adds a guard
  and a skip path to `InsightsCoordinator.generate` and a computed property to
  `InsightsRequestPlan`, because that is where the known defect actually lives.
- Migrations. Nothing has shipped; a deleted key is deleted.
- iPad layout, localisation, themes.

## Review log

Revision 2 folds in a read-only (`Explore`) sub-agent review of revision 1, 17 findings, spawned
against a baselined tree (`git status` clean but for this file, 1263 tests green at d9ed765) and
checked clean again afterwards, per `tasks/lessons.md`. Every finding that changed the design was
verified against the source before folding it in.

The three that changed the design, all in the known-defect section: the automatic path is **not**
already guarded (`AIServices:103` guards flagging, not the request); `runAI` is the wrong layer
(`generate()` builds the request, and three routes reach it without `runAI`); and
`InsightSections.isEmpty` is the wrong predicate in both directions, because `cleanedText` needs a
voice or photo entry and `writtenDate` needs a typed one, so the same toggles give a valid schema
for one entry and an empty one for another.

The one that changed the plan's shape: phase 1 as written dropped the `NavigationStack` that its own
only link needs, so it shipped a dead row and was not independently testable. Phase 2 was missing
three things that break in it (`EntryInsightsView:157`, the `#Preview`'s environment, and
`AIConfigurationUITests:57`).

The rest were counting and citation corrections, folded in where they sit: line counts, nine
unlisted custom-insight controls, the score restated as audit rows, two reader counts, the two
different disabled predicates, eight conditional rows rather than four, `attach` being private, and
`VoiceSettingsView` not being a type that exists. The reviewer confirmed the tab mechanics are safe
(`AppTab` is never persisted, `tabViewBottomAccessory` is unaffected, every environment the tab
needs is already attached at or above the `TabView`) and that no other UI test counts tabs or
toolbar buttons.

## Open question for the owner

One, and it is small: **"Your journal" in About.** It is new behaviour rather than audit or
restyle, it was in the IA you picked, and it is phase 5, so it can be dropped without touching
anything else. Say the word either way when you approve the rest.

## Built

Five commits on `feature/settings`, PR #17. 1271 unit tests (1263 at the start), plus
`AISettingsUITests`, `AIConfigurationUITests`, `TodayUITests`, and two new classes:
`SettingsTabUITests` and `SettingsScreenshotTests`.

What changed on the way, against the plan above:

- **Phase 1's open question was answered the uncomfortable way.** Both AI settings classes passed
  unchanged, because `app.buttons["Settings"]` matched the tab item as readily as the gear.
  `SettingsTabUITests` scopes to `tabBars` and was proven to fail with the `Tab` deleted.
- **Phase 3's guard failed the way the review predicted.** With the guard removed, the new test's
  failure printed the request going out with `schema: object([])`.
- **The screenshots caught four things the suite did not**: life area names in placeholder grey,
  the voice options in Ember, a bare "I" as the root row's value, and an Edit button on an empty
  list. All fixed, then re-shot and looked at again. Twenty screenshots, ten screens in each
  appearance, plus the bottom of the root in both.
- **About lost "hours spoken".** `Entry.removeAudio()` clears `audioDuration` when Keep recordings
  is off, so that total would shrink behind the user's back, which breaks phase B's rule for numbers
  on screen. Entries and names stay. Keeping the duration after the audio goes is a model change,
  left for whoever wants the number.
- **Advanced's model rows** show two free-text fields and one picker under the UI test stub, because
  `ModelField` falls back to a field when the provider's list has one match or fewer. With a real
  key all three are pickers. Left as it is.
