# Settings by section, and the reminder that didn't arrive

Branch `feature/settings-sections` from `main` at `be76dc4`, worktree `.claude/worktrees/settings-sections`.

The Settings root is one Form with eight sections (iCloud, Your journal, Privacy and data, an
unlabeled Appearance picker, Today, Reminder, AI, About), and it scrolls past two screens. The owner
asked (2026-09-23) for the sections to be the top level, each opening its own screen, with a General
section holding iCloud and the data tools. Picked: five rows, lock and delete inside General, no
import in this PR.

## Target

```
Settings
  General               On     >   iCloud (status, restore), Lock, Your data (export, delete)
  AI                    On     >   Use AI, OpenAI key, What AI does
  Your journal                 >   life areas, voice, font, appearance, keep recordings, record on open
  Today and reminders   9:00 PM >  resurface quiet names, daily reminder + time
  About          213 entries   >   the journal in numbers, and the app's version
```

Order (owner, 2026-09-23): AI second, right under General.

About gets more (owner, 2026-09-23: "more analytic data if possible"), under the rule
`JournalTotals` already carries from Phase B: counts only, no averages, no streaks, nothing that
reads as a grade or can fall because of something the user didn't do. Whole-journal totals only;
anything over a period is Reflect's (its Numbers view is the planned Mind overhaul follow-up).

- Your journal: entries, days written on (distinct `entryDate` days), writing since (the earliest
  `entryDate`), words.
- How they came in: spoken, typed, photographed (`EntrySource`), and page photos.
- What they are: journal entries, notes, creative (`Entry.kind`), rows with zero left out.
- What it knows: people, places, organizations, projects, events (Mind's rules: not hidden, not
  merged, not tags; zero rows left out), threads closed (`LooseEnd` resolved).
- Chat: conversations.
- Footer: version and build.

`JournalTotals.count` grows to fill these in one pass over non-draft entries (words split on whitespace). Tests in
`JournalTotalsTests`: each new field, drafts excluded throughout, days counted by `entryDate` not
`createdAt`, two entries on one day count one day, words across entries.

Row values: General is `sync.status.summary`; Today and reminders is the reminder time when on, else
"Off"; AI is "On"/"Off"; About is the entry count. Row ids: `generalSettingsLink`,
`journalSettingsLink`, `todaySettingsLink`, `aiSettingsLink`, `aboutSettingsLink`. Every existing
row keeps its accessibility id.

## Phase 1: the reorganization

- `Views/SettingsView.swift`: the root becomes five `NavigationLink`s. Keeps the totals task (the
  About row shows the count) and passes `totals` down. The reminder bindings and the static
  `date(forMinutes:)`/`minutes(of:)` helpers move with the reminder (below); `DailyReminderTests:267`
  is updated to the new owner.
- New `Views/Settings/` folder (file-system synced, no pbxproj edit):
  - `GeneralSettingsView.swift`: `SyncSettingsSection` (moved as is), then the lock and the data
    tools. `PrivacyDataSection` splits in two, and its one joined `footer` becomes two: the lock
    sentence alone, and the export sentence with `exportNote`/`deleteNote`: a Lock section (toggle, its footer) and a Your data
    section (Export journal, Delete all data, the export footer and notes). The fileMover and the
    confirmation dialog stay on the data section.
  - `JournalSettingsView.swift`: the Your journal section plus the Appearance picker.
  - `TodaySettingsView.swift`: the Today and Reminder sections, with `reminderToggle`,
    `reminderTime`, and the two static helpers.
  - `AboutSettingsView.swift`: the sections above.
  - The AI screen is a `Form { AISettingsSection() }` titled "AI", declared beside
    `AISettingsSection` in `AISettingsView.swift`.
  - Move `SyncSettingsSection.swift`, `PrivacyDataSection.swift`, `LifeAreasSettingsView.swift`,
    `JournalVoiceSettingsView.swift`, `JournalFontSettingsView.swift` into `Views/Settings/` too
    (git mv, no code change), so Settings lives in one folder.
- Each screen: `.paperBackground()`, inline title, same as the existing pushed screens.
- UI tests that scroll the root for a row now open the section first:
  - `SettingsTabUITests.testICloudIsTheFirstSection` becomes: General is the first row and reads
    "Off" for a UI-test store; opening it shows `syncStatusRow` and the device-only sentence.
  - `SettingsScreenshotTests.testTour`: root, then each section screen, then the same deeper screens
    as today. The `totalEntries` check moves into About, the root-bottom shot and the
    swipe-hunting in `open()` go (the root is five rows now). Deeper AI screens are one level
    further down; walk every `back()`.
  - `AIConfigurationUITests.openAIFeatures`, `AISettingsUITests.openSettings` (and its post-relaunch
    toggle check at line 56): tap `aiSettingsLink` first. The swipe loops go.
- Unit test: none of this has logic worth a unit test beyond the moved helpers, which keep theirs.
- Run: `scripts/ci/test.sh unit`, then `scripts/ci/test.sh ui SettingsTabUITests AISettingsUITests
  AIConfigurationUITests SettingsScreenshotTests` (phase-scoped UI tests only). Look at the
  screenshot tour's attachments, light and dark.

## Phase 2: the reminder

Owner, 2026-09-23: "the today reminders isn't working ... I didn't see any notifications on my
phone." The phone wasn't connected, so the device log hasn't been read yet. Reading the code, the
likely causes:

1. **Skipped by design and silent about it.** A day with any entry gets no reminder
   (`todayHasEntry`, by `createdAt`). Someone who writes every day never sees one, and nothing says
   so. The most likely explanation.
2. **No foreground presentation.** There is no `UNUserNotificationCenterDelegate`, so a reminder
   that fires while Mindlore is open is dropped. Setting a time two minutes ahead to test it, with
   the app still open, shows nothing.
3. Focus or a scheduled summary holding it. Outside the app; the screen can only point at it.

Fix:
- The Today and reminders screen says what's scheduled: "Next reminder: tomorrow at 9:00 PM" and,
  when today was skipped, "Not today, you've already written." `DailyReminder` keeps the last
  `Outcome` plus the first scheduled date (observable), set by `reschedule`; the footer reads it.
  No pending-request query, since `reschedule` already knows.
- A delegate (`ReminderPresenter`, set in `MindloreApp.init` before launch finishes, as Apple
  requires) returns `[.banner, .sound]` for the reminder's identifiers only. The centre holds its
  delegate weakly, so the presenter is a process-lifetime `static let`, never a local in `init`
  (plan review: a local is freed at once and the fix silently does nothing). It logs
  `reminder.presented` (ids only).
- Tests in `DailyReminderTests`: the outcome records the next date; today skipped reports skipped;
  permission lost clears it. The delegate's filter (reminder ids yes, others no) as a pure function.
- Device check (`tasks/smoke-test.md` new step): Debug build, turn it on, set a time two minutes
  out, stay in the app and see the banner; then background and see it on the lock screen;
  `reminder.scheduled` and a new `reminder.presented` event in the log.

## Not in scope

- Import of any kind (Mindlore round-trip, Markdown, Day One). Next PR; General's Your data section
  is where it will go.
- Any new setting or change to what an existing one does, other than the reminder fixes above.
- Settings search.
- Changing the reminder rule that skips a day with an entry.

## Docs

`docs/privacy-coverage.md` gets a row for `reminder.presented` (no test can drive a delegate
callback from the system; the row says so and names the pure filter test). CLAUDE.md's Settings paragraph (the tab's layout) and the iCloud paragraph's "the iCloud section at
the top of Settings". `docs/remaining-work.md` gets the device step.
