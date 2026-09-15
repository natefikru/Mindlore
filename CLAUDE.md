# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Mindlore is a voice-first journaling app for iOS, built with SwiftUI and SwiftData. v1 is a local journal: write or record entries, get on-device text from recordings, and never lose anything. The long-term product (AI analysis, an entity knowledge graph, iCloud sync) is described in `docs/mindlore-build-plan.md`. The current implementation plan lives in `tasks/todo.md`. The v1 plan, with the design decisions and review history behind persistence, recording, and transcription, is archived in `tasks/archive/v1-capture-storage.md`; read its "Key decisions" before changing those areas.

Deployment target iOS 26.5, Swift 5.0 language mode. The app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and approachable concurrency, so types are main-actor by default; mark work that must leave the main actor `@concurrent nonisolated`. The test targets do not default to MainActor, so test suites that touch app types are marked `@MainActor`.

The app signs with a free Personal Team. iCloud, CloudKit, key-value storage, and push are unavailable, and any CloudKit call without the entitlement fails at runtime. Sync is gated by `AppConfig.cloudKitContainerID`, which stays `nil` until the project moves to a paid team.

## Commands

Build and run only through Xcode (`Mindlore.xcodeproj`) or `xcodebuild`:

```bash
# Build for the iOS Simulator
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -destination 'platform=iOS Simulator,name=iPhone 17' build

# Unit tests only (the normal iteration loop)
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:MindloreTests -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 60

# Everything, including UI tests (several minutes)
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -destination 'platform=iOS Simulator,name=iPhone 17' test -parallel-testing-enabled NO

# A single Swift Testing test. The trailing () is required; without it xcodebuild runs 0 tests and still reports success.
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -parallel-testing-enabled NO "-only-testing:MindloreTests/EntrySaverTests/flushWithNothingPendingDoesNotSave()"
```

Use a per-test time allowance: an awaited continuation that never resumes hangs the whole run silently. Disable parallel testing so xcodebuild doesn't open a "Clone N of iPhone 17" simulator per worker. The simulator can't run on-device speech models, so transcription can only be verified on a physical iPhone. There is no SwiftPM package, lint config, or CI.

## Device smoke testing

Anything the simulator can't show (recording, locking, force-quits, on-device speech) is verified on a physical iPhone with a feedback loop. The steps and the log events each one must produce are in `tasks/smoke-test.md`.

- `scripts/device/deploy.sh` builds Debug and installs on the first connected iPhone. App data is kept.
- `scripts/device/launch.sh <run-id>` relaunches the app with its console attached and streams `MINDLORE` diagnostics lines (run it under a monitor). Routine throttle saves are filtered out. Arguments for the app go after `--`, or `devicectl` reads them as its own flags.
- `scripts/device/pull-logs.sh <run-id>` copies `Library/Logs/Mindlore/diagnostics.jsonl` and Mindlore crash reports into `.smoke/<run-id>/` (git-ignored) and prints a timeline. Use it after any step that kills the app, since that ends the console stream.

Device builds go to `~/Library/Developer/Xcode/DerivedData/Mindlore-device`. Builds inside `~/Documents` pick up iCloud Drive file attributes and fail code signing.

`DiagnosticsLog` (`Mindlore/Diagnostics/`) writes those events in Debug builds only and is disabled under XCTest. Events carry IDs, counts, sizes, durations, and framework error descriptions, never entry text. Log save errors with `DiagnosticValue.errorCode`, because SwiftData errors can embed model values. `DiagnosticsPrivacyTests` runs real components against a sentinel string to enforce this. When adding behavior that only a device can show, add events for it so the loop can see it.

## Architecture

The project uses file-system synchronized groups, so new files under `Mindlore/`, `MindloreTests/`, or `MindloreUITests/` join their target without editing `project.pbxproj`.

**Models** (`Mindlore/Models/`). `Entry` is the only persisted type. Its core field is `text`; audio is an optional attachment, and naming stays input-neutral (no voice-specific names like `transcript`). There is no status or commit step. `awaitingText` marks a voice entry whose text hasn't been generated, `textWasGenerated` and `textEditedByUser` record where the text came from. Rules that change an entry live in `Entry+Editing.swift` so every caller applies them the same way. Every stored property must be optional or have a default, and nothing may be `@Attribute(.unique)`, so CloudKit sync can be switched on later without a migration; `CloudKitSchemaRulesTests` enforces this. Store enums as raw strings with computed accessors.

**Persistence** (`Mindlore/Persistence/`). `ModelContainerFactory` builds the store: `.default` for the app, `.inMemory` when hosted unit tests run, `.file` named by `UITEST_STORE_NAME` when launched with `-uiTesting`. `EntrySaver` is the only thing that decides when the main context writes to disk. Autosave is off. Call `noteChange()` after edits (saves within one second, even during continuous typing) and `flush()` when leaving a screen or deleting. `RootView` flushes whenever the scene leaves `.active`.

**Audio** (`Mindlore/Audio/`). `AudioRecorder` captures 24 kHz mono 16-bit PCM into `Recordings/active/<uuid>.caf`, because PCM stays readable if the app is killed mid-recording and AAC does not. `stop()` moves the file to `finished/`. `RecordingIngestor` converts finished files to AAC, creates a voice entry whose `id` is the file's UUID, and deletes the file only after the save succeeds. `MindloreApp.init` moves leftover `active/` files to `finished/` before any UI exists, and `RootView` ingests them at launch.

**Transcription** (`Mindlore/Transcription/`). `TranscriptionCoordinator` processes `awaitingText` entries one at a time through a `Transcriber`. `SpeechAnalyzerTranscriber` uses `SpeechTranscriber`, falling back to `DictationTranscriber`. After each await it re-fetches the entry, and `applyGeneratedText` refuses if the user has typed, so generated text never overwrites user text.

**Settings** (`Mindlore/Settings/`). `SettingsStore` reads through a `KeyValueStore` protocol using `object(forKey:)`, so a missing value means "use the default" rather than `false`. `PrivacyInfo.xcprivacy` declares the UserDefaults reason.

**Views** (`Mindlore/Views/`). `RootView` owns the saver, ingestor, and transcription coordinator and passes them through the environment. `EntryListView` lists entries and opens `EntryEditorView` (one editor for every entry, bound directly to `entry.text`) or `RecordingView`.

**Tests.** `MindloreTests/` uses Swift Testing (`import Testing`, `@Test`, `#expect`). For async code, inject dependencies and await the real task (for example `EntrySaver.scheduledSave`) rather than polling with `Task.yield()`, which can starve the main actor. `MindloreUITests/` uses XCTest and relaunches the app against a named file store to prove data survives.
