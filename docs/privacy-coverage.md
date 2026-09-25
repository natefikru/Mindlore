# Diagnostics privacy coverage

Checked on 2026-09-21 against `feature/phase-a` (132 distinct event names in `Mindlore/`), then
extended by `feature/phase-b5` with three more (135): `intent.invoked`, `reminder.permission`, and
`reminder.scheduled`, covered by the last two rows of the table below. On 2026-09-23 four more
(139): `entry.kindSet`, `title.requested`, and `recording.ready` in the table, and
`editor.editFromReadTap` under view events. The formatting editor (`claude/editor-formatting`)
added three more (142) under view events: `editor.formatted`, `editor.checkboxTicked`, and
`editor.nameTyped`. `feature/settings-sections` added `reminder.presented` (143), and `feature/import-and-redo` added
`insights.redoAll`, `insights.redoStopped`, and `journal.imported` (146), all in the table.
Chat's note writing added `ask.noteCreated` (147), in the Ask row.
Reflect's Loose ends tab added `reflect.looseEnd` (148: the action and the status it left, both
literals), driven with the sentinel as the loose end's text and its subject's name, in the table.
Chat's note editing added `ask.noteEdited` (149), in the Ask row.
Reflect's Life side added `life.rendered`, `life.areaOpened`, `life.areaWords`, `life.portrait`,
`life.feedback`, and `life.experiment` (155), driven in the table with the sentinel as entry
text, a tag, an area's own name, the model's answer, and the author's note; and the + fan added
`newEntry.chosen` (156: two literals), under view events.
Those two tests assert that the event was written as well as that the sentinel wasn't, which is
what the instrumented run below establishes for the rest.

**How it was measured.** The event list comes from every `record("…")` call in `Mindlore/`,
including the three ternaries (`insights.completed`/`insights.stale`, `title.completed`/
`title.discarded`, `ask.answered`/`ask.stopped`) and the multi-line `today.shown`. Coverage was measured by instrumenting
`DiagnosticsLog.record` for one run to append each event name to a scratch file, then running
each sentinel test on its own. An event counts as covered only if a test that feeds the sentinel
through the real component actually wrote it. Grepping a test for the event name was not enough.
The instrumentation was reverted and never committed.

To redo it: add a one-line append to `record`, run the tests below one at a time with
`test-without-building`, and diff the union against the event list.

## Covered: 86 events, driven by a sentinel test

| Test | Events it drives |
|---|---|
| `DiagnosticsPrivacyTests/entryTextNeverReachesTheLog` | `save.completed`, `ingest.completed`, `transcription.started`, `transcription.completed`, `transcription.failed` |
| `AIDiagnosticsPrivacyTests/aiPathsNeverLogTextKeysOrProviderBodies` | `ai.keySaved`, `ai.connectionTested`, `settings.changed`, `pages.transcription.started`, `pages.transcription.pageCompleted`, `pages.transcription.completed`, `insights.requested`, `insights.started`, `insights.completed`, `insights.failed`, `insights.skipped`, `looseEnds.written`, `looseEnds.faded`, `title.started`, `title.failed`, `graph.indexed`, `graph.entityEdited`, `graph.renameRewrote`, `graph.hidden`, `graph.resurfacingMuted`, `graph.suggestionDismissed`, `graph.merged`, `graph.unmerged`, `graph.repointed`, `graph.nameAdded`, `graph.nameRemoved`, `graph.contactLinked`, `graph.contactUnlinked`, `graph.contactAccess`, `graph.placeLinked`, `graph.placeUnlinked`, `graph.rendered`, `mind.reviewAnswered`, `mind.focused`, `mind.windowChanged`, `mind.changeTapped`, `mind.replayed` |
| `AIEdgePathDiagnosticsPrivacyTests/unhappyAIPathsNeverLogTextOrKeys` (new) | `ai.pass`, `ai.offline`, `ai.keyRemoved`, `insights.unavailable`, `insights.stale`, `insights.discarded`, `title.unavailable`, `title.held`, `cleanup.held`, `cleanup.applied` (held, applied on close), `title.discarded`, `title.completed`, `pages.transcription.unavailable`, `pages.transcription.failed` |
| `AskDiagnosticsPrivacyTests/askNeverLogsTheQuestionTheEntriesOrTheAnswer` | `ask.indexed`, `ask.retrieved`, `ask.answered`, `ask.stopped`, `ask.failed`, `ask.conversationDeleted`, `ask.noteCreated`, `ask.noteEdited` |
| `CloudTranscriptionIntegrationTests/keyAndProviderErrorBodiesNeverReachTheLog` | `ai.error`, `transcription.fallback` (plus `ai.keySaved`, `ai.connectionTested`, `transcription.*` above) |
| `BioDiagnosticsPrivacyTests/draftingNeverLogsNamesExcerptsOrBios` | `graph.bioDrafted`, `graph.bioFailed` |
| `KeepTests/nothingTheCardLogsCarriesAWordTheUserSaid` | `keep.shown`, `keep.dismissed` |
| `TrustDiagnosticsPrivacyTests/exportWipeAndLockNeverLogJournalText` | `journal.exported`, `journal.wiped`, `lock.locked`, `lock.unlock` |
| `TodayTests/nothingTodayLogsCarriesAWordTheUserWrote` | `today.shown`, `today.dismissed` |
| `ReflectLooseEndSourceTests/theLogSaysWhatWasDoneAndNeverWhatItWasAbout` | `reflect.looseEnd` |
| `RecordingSessionTests/liveTextNeverReachesTheLog` | `live.availability`, `recording.expanded`, `recording.minimized` |
| `RecordingSessionTests/takingAPromptMarksItAndLeavesItAloneForAFewDays` | `looseEnds.prompted` |
| `IntentTests/theLogSaysWhichIntentAndNeverWhatWasAsked` | `intent.invoked` (the question is the sentinel) |
| `EntryKindDiagnosticsPrivacyTests/kindTitleAndReadyRecorderNeverLogTheUsersWords` | `entry.kindSet`, `title.requested`, `recording.ready` (added 2026-09-23 with entry kinds and the waiting recorder) |
| `DailyReminderTests/theLogCarriesCountsOnly` | `reminder.permission`, `reminder.scheduled` (no user text ever reaches the reminder, so there is no sentinel to feed; the test checks both are written and that not even the fixed notification line is) |
| `JournalImportTests/theLogCarriesCountsOnly` | `journal.imported` (names, a loose end, and entry text from a real import are the sentinels) |
| `RedoInsightsTests/theLogCarriesCountsOnly` | `insights.redoAll`, `insights.redoStopped` (entry text is the sentinel) |
| `LifeDiagnosticsPrivacyTests/lifeNeverLogsEntryTextTagsNamesAnswersOrNotes` | `life.rendered`, `life.areaOpened`, `life.areaWords`, `life.portrait`, `life.feedback`, `life.experiment` |
| `DailyReminderTests/thePresenterShowsOnlyTheReminder` | `reminder.presented` (fired from the system's delegate callback, which no test can drive; the event carries one fixed bool, and the test covers the filter that decides it) |

Of the 32 events added since `main`, 30 are in this table. The other two are `demo.seeded` and
`demo.seedFailed`, covered below.

## Not driven: 76 events, each with a reason

For each of these, every field at every call site was read. A field is either a typed number or
bool, an `.id(UUID)`, `.errorCode` (domain and code), a string literal, an enum's `rawValue` or
`String(describing:)` of an enum, a file name that is a UUID, or a locale identifier. None of
them can hold text the user wrote or said, whichever path reaches it. The sentinel tests exist
for fields derived from user data at runtime. These events have none.

**Needs the microphone or on-device speech** (the simulator has neither, see `CLAUDE.md`):
`recorder.started`, `recorder.stopped`, `recorder.discarded` (file name is the UUID),
`recorder.paused`, `recorder.resumed`, `recorder.resumeFailed`, `recorder.interrupted`,
`recorder.interruptionEnded`, `recorder.routeChanged` (audio port type), `recorder.routeRestartFailed`,
`recorder.engineRestarted`, `recorder.audioGap` (reason is a literal), `recorder.permissionDenied`,
`recorder.startFailed`, `live.started` and `transcription.module` (locale identifier),
`live.dropped` (a literal, or the Swift type name of the framework error), `live.finished`,
`live.assets`, `transcription.assets`, `transcription.authorization`.

**Runs in a SwiftUI view or at app launch**, with no unit-test seam: `ai.consent` (a bool), `backup.writeFailed`, `backup.filledIn`, `backup.fillInFailed`, `recovery.pending` (a literal reason), `recovery.pruned`, `recovery.restored`, `recovery.failed`, and `recovery.duplicatesMerged` (counts and error codes; `SafetyCopyTests` drives most of them), `sync.storeFailed` (an error code), `sync.originSeeded` and `sync.originSeedFailed` (a count or an error code; `LocalOriginTests` drives the first), `sync.duplicatesMerged` and `sync.duplicatesFailed` (four counts or an error code; `SyncDuplicatesTests` drives the first, and `graph.merged` gains a `byUser` bool there), `sync.schemaInitialized` (Debug only, behind a launch flag: a bool, a duration, a literal reason, or an error code), `sync.status` and `sync.event` (a status name, an event kind, a bool, a duration, and a CloudKit error code; `SyncStatusMonitorTests` drives them, but they carry nothing a sentinel could reach), `app.launch` (`run` is the
developer's `-diagnosticsRun` argument), `app.scenePhase`, `recovery.moved` (UUID file names),
`store.openFailed`, `store.entryDatesRepaired`, `store.entryDateRepairFailed`, `store.linksRepaired`, `store.linkRepairFailed`, `editor.closed`,
`entry.created`, `entry.finished`, `entry.deleted` (source is an enum),
`newEntry.chosen` (the option and whether it was a tap or a slide, both literals), `editor.editFromReadTap` (an id), `editor.focusRestored` (no fields), `editor.formatted` (an id), `editor.checkboxTicked` (two
bools), `editor.nameTyped` (an id, a literal for the kind of link, a bool; never the name or the
tag), `entryDate.changed`,
`entryDate.dismissed`, `cleanup.applied`, `cleanup.dismissed`, `cleanup.reverted`,
`text.approved`, `insights.deleted`, `insights.moodsEdited`, `pages.added`, `pages.confirmed`,
`pages.reordered`, `pages.removed`, `pages.restarted`, `pages.editCancelled`,
`pages.textReplaced`. Where one of these also fires from a coordinator (`entryDate.changed`,
`entryDate.suggested`, `cleanup.applied` in `InsightsCoordinator` and
`PageTranscriptionCoordinator`), that call site logs an id and literals only.

**Debug seeder:** `demo.seeded` and `demo.seedFailed` log counts, a duration and an error code
through `DiagnosticsLog.shared`, which is disabled under XCTest. They also run over generated
demo text, never the user's own.

**Coordinator failure and race paths** that need a failing store, a split recording, or a
provider route the test harness doesn't build: `ai.request` (the provider label, `preset:model`,
which is configuration, not journal content), `transcription.chunks` (count and chunk
durations), `transcription.discarded`, `transcription.saveFailed`, `ingest.skipped` and
`ingest.saveFailed` (UUID file name), `save.failed` (`.errorCode`, which exists for exactly this
reason), `graph.saveFailed`, `graph.sweep` (counts), `graph.ambiguous` (the kind's raw value),
`graph.collisionForced`, `pages.transcription.dropped` (a literal reason).

A new event whose fields come from anything the user typed, said, photographed, or named must
go in a sentinel test, not in this list.
