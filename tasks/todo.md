# Mindlore v1: Capture and Storage

Branch: `feature/v1-capture-storage` from `main`.

The goal of v1 is a journal you would actually use for a week. Write or record an entry, get on-device text from the recording, fix it, save it, and find it later. iCloud sync is designed in from the start but switched on in a separate, final phase. No AI analysis, no entities, no graph.

Revision 3. Revision 2 folded in the plan review (see "Review log"). Revision 3 splits iCloud sync into its own phase because the project signs with a free Personal Team, which cannot use iCloud, CloudKit, key-value storage, or Push Notifications. The owner chose to build local first and decide on the paid Apple Developer Program later.

## Baseline (what exists today)

- `Mindlore/MindloreApp.swift:13-24` builds a `ModelContainer` for the template `Item` with no CloudKit configuration and a `fatalError` on failure.
- `Mindlore/ContentView.swift:1-61` is the stock `NavigationSplitView` list of `Item` timestamps.
- `Mindlore/Item.swift:1-18` is the template model. It gets deleted.
- `MindloreTests/MindloreTests.swift:13-17` is an empty example test.
- `project.pbxproj` uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77), so new files in `Mindlore/` join the target with no pbxproj edits.
- App target: bundle ID `com.natefikru.mindlore`, team `7DZBU56KUA` (Personal Team), `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, Swift 5.0, iOS 26.5. The test target does not default to MainActor, so test suites touching app types need `@MainActor`.
- Background Modes already added: `Mindlore/Info.plist` holds `UIBackgroundModes` = `audio`, `remote-notification`, merged with the generated Info.plist via `INFOPLIST_FILE`. No entitlements file. No CI. Xcode 26.6.
- Stray duplicate `Mindlore/docs/mindlore-build-plan.md` inside the app folder would ship in the bundle. Canonical copy is `docs/mindlore-build-plan.md`.

## Personal Team constraints

- No iCloud, CloudKit, key-value storage, or Push Notifications. Any `CKContainer` call or a `.private(...)` SwiftData configuration without the entitlement fails, so sync code must not run while sync is off.
- Builds installed on a physical iPhone expire after 7 days; reinstall from Xcode.
- No TestFlight or App Store.
- Simulator, recording, background audio, on-device speech, and everything local work normally.

## Key decisions

**The entry is text; audio is one way to produce it.** The core field is `text`. Nothing on `Entry` assumes voice except the optional audio attachment. Typed, voice, and later imported or handwritten entries all end up as text plus metadata about where it came from. `textEditedByUser` records whether generated text was changed, which applies to speech now and handwriting OCR later.

**Sync is one setting.** `Mindlore/AppConfig.swift` holds `static let cloudKitContainerID: String? = nil`. The container factory uses `cloudKitDatabase: .none` while it is `nil` and `.private(id)` once it is `"iCloud.com.natefikru.mindlore"`. Settings mirroring and the sync status monitor read the same value, and nothing touches CloudKit while it is `nil`. Turning sync on is: enroll, add capabilities, set the ID, ship Phase 6.

**CloudKit schema rules apply from day one, even with sync off.** Every stored property has a default or is optional, no `@Attribute(.unique)`, future relationships optional. Enums are stored as raw `String` fields with computed accessors, so `#Predicate` filtering works and an older app version never fails to decode a status added later. Following the rules now is what keeps Phase 6 a configuration change instead of a data migration. A unit test enforces them.

**When sync is on: CloudKit always on, iCloud status only drives UI.** With no iCloud account the store still loads and works locally (confirmed by Apple DTS). Whether records created before sign-in upload afterwards is unverified; Phase 6 smoke step is a gate.

**When sync is on: every entry keeps a local safety copy.** Apple's CloudKit mirroring purges local data "by design" when the user signs out, turns off iCloud for the app, or (reported with full iCloud storage) gets a false access-revoked signal. Records not yet uploaded are gone for good. Each local save of an entry with non-empty text also writes a JSON snapshot outside the CloudKit store, and the app offers to restore missing entries after an account change. Audio is not in the safety copy. Chosen by the owner. Built in Phase 6, since there is no purge to protect against while sync is off.

**The filesystem is the recovery journal for in-flight audio.** Recording writes to `Application Support/Recordings/active/<uuid>.caf`. On stop, the file moves to `Recordings/finished/`. A `RecordingIngestor` turns finished files into entries whose `id` is the file's UUID, saves, and only then deletes the file. At launch, before any recording UI can start, leftover `active/` files (from a crash or force-quit) move to `finished/` and go through the same ingest. The UUID-as-id rule makes ingest idempotent.

**Record uncompressed PCM, compress at ingest.** An AAC recording killed mid-write depends on metadata written at close and is likely unplayable. Apple's guidance for crash-surviving capture is to stream PCM to disk. Record 24 kHz mono 16-bit LPCM into CAF (about 170 MB per hour, temporary), convert to AAC `.m4a` data at ingest (about 25 MB per hour, what gets stored). If a force-quit file has an unfinalized CAF header, ingest repairs the data chunk size from the file length. Verified on a real device as the first task of the recording phase.

**Saving is continuous; there is no commit step.** Like Apple Notes or Obsidian, an entry exists and is saved from the moment it has content, and every change after that is saved without the user doing anything. There is no Save button, no draft state, no committed state. The editor's text binds directly to `entry.text`, and an `EntrySaver` writes pending changes to disk at most one second after the last change, at least once per second during continuous typing, and immediately when the app leaves the foreground or the editor closes. The worst case is a hard crash losing under a second of typing; backgrounding, locking the phone, switching apps, and closing the entry lose nothing. Recording audio streams to disk from the first second (see below), so voice entries follow the same guarantee.

**One flag instead of a status.** `awaitingText: Bool` marks a voice entry whose text has not been generated yet. It is set at ingest, cleared when transcription succeeds, and cleared the moment the user types anything. It exists because "audio present, text empty" alone can't distinguish "still transcribing" from "failed" from "the user deleted the text on purpose," and deriving it would re-transcribe entries the user cleared. Generated text is only ever written into an entry whose flag is still set, so transcription never overwrites anything the user typed. Progress ("transcribing now") stays in memory.

**Settings sit behind a key-value protocol.** Phase 2 backs them with `UserDefaults` only. Phase 6 adds `NSUbiquitousKeyValueStore` mirroring. Missing keys are distinguished from `false` so a fresh device never syncs a wrong default back.

**Transcription goes through a protocol.** `Transcriber` has one real implementation (`SpeechAnalyzerTranscriber`) and a fake for tests. `SpeechTranscriber` is unavailable on the simulator and on older devices, so the real implementation falls back to `DictationTranscriber`, then to a clear "not supported on this device" state where the user types instead.

**Concurrency under default MainActor isolation.** System notifications are consumed with `for await` over `NotificationCenter.default.notifications(named:)` inside MainActor tasks. Metering uses a MainActor `Task` sleep loop, not `Timer`. No `AVAudioRecorderDelegate`. Async work holds `PersistentIdentifier`s and re-fetches models after every `await`. PCM-to-AAC conversion runs in a `nonisolated` function that returns plain data; inserts happen on the main actor.

## Data model

```swift
@Model final class Entry {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var sourceRaw: String = EntrySource.typed.rawValue      // voice, typed
    var text: String = ""
    var textWasGenerated: Bool = false
    var textEditedByUser: Bool = false
    var awaitingText: Bool = false
    @Attribute(.externalStorage) var audioData: Data?       // AAC .m4a bytes
    var audioDuration: Double?

    var source: EntrySource { get set }   // computed over sourceRaw, unknown raw -> .typed
}
```

`updatedAt` moves forward on every save that changed the entry, so it always reflects the last edit.

Settings: `keepAudioAfterTranscription` (Bool, default `true`), `defaultEntryMode` (`voice` | `typed`, default `voice`). With no commit step, audio is removed (when the setting is off) at the first moment the user has seen the generated text: when they close an entry whose text came from transcription. Deleting audio right after an unreviewed transcription would contradict "never lose data" if the transcription was poor.

No `User` model. With sync on, identity is the device's iCloud account, which CloudKit's private database already scopes to.

## Phases

This PR covers Phases 1 to 5 and ships a complete local journal. Phase 6 is a separate PR once the paid program is active.

Each phase is one commit or a small series. Tests pass locally before commit; push before the next phase. Draft PR opens right after Phase 1 is pushed. No CI exists, so "green" means `xcodebuild test` passes locally on the iPhone 17 simulator.

### Phase 1: Data layer

- [x] Bundle ID changed to `com.natefikru.mindlore` (tests `.tests`, `.uitests`).
- [x] Background Modes (audio, remote notifications) added in Xcode.
- [x] Delete `Mindlore/Item.swift` and the duplicate `Mindlore/docs/mindlore-build-plan.md`.
- [x] Add `Mindlore/AppConfig.swift` with `cloudKitContainerID: String? = nil`.
- [x] Add `Mindlore/Models/Entry.swift` and `Mindlore/Models/EntrySource.swift` per the model above.
- [x] Add `Mindlore/Persistence/ModelContainerFactory.swift`: `static func make(_ location: StoreLocation) throws -> ModelContainer` with `.default`, `.inMemory`, and `.file(URL)`. Schema `[Entry.self]`. `cloudKitDatabase` is `.private(id)` only for `.default` with `AppConfig.cloudKitContainerID` set, otherwise `.none`.
- [x] Rewrite `MindloreApp.swift:13-24` to use the factory. In memory when the `XCTestConfigurationFilePath` environment variable is set, so hosted unit tests never open the real store. With `-uiTesting`, use `.file(URL)` named by the `UITEST_STORE_NAME` environment variable inside the app's own Application Support (the test runner and app have separate sandboxes, so a runner path won't work), so UI tests can relaunch the app and prove data survived. Replace `fatalError` with a minimal error view showing the underlying error.
- [x] Replace `ContentView.swift`'s `Item` usage with a bare `@Query(sort: \Entry.createdAt, order: .reverse)` list so the target builds.
- [x] Add `INFOPLIST_KEY_NSMicrophoneUsageDescription` and `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` to both app build configurations.
- [x] Tests, `MindloreTests/EntryTests.swift` (replaces the example test): defaults on a fresh `Entry` (including `awaitingText == false`); `source` raw round-trip; unknown raw value falls back to `.typed`; insert, sorted fetch, delete in an in-memory container.
- [x] Test, `MindloreTests/CloudKitSchemaRulesTests.swift`: inspect `Schema([Entry.self])` and assert no attribute is unique and every relationship is optional. Check against the SDK whether `Schema.Attribute` exposes default values; if it does, also assert every non-optional attribute has one. Runs without any entitlement, so it guards the schema from the first commit.

### Phase 2: Settings and privacy manifest

- [x] `Mindlore/Settings/KeyValueStore.swift`: protocol with `object(forKey:)` and `set(_:forKey:)`, conformed to by `UserDefaults`. `synchronize()` is added in Phase 6 when `NSUbiquitousKeyValueStore` needs it. `defaultEntryMode` reuses `EntrySource` rather than a second enum with the same cases.
- [x] `Mindlore/Settings/SettingsStore.swift`: `@Observable`, `keepAudioAfterTranscription` and `defaultEntryMode`. Init takes a `KeyValueStore` (UserDefaults in production, a fake in tests). Typed reads treat `nil` from `object(forKey:)` as "use default."
- [x] `Mindlore/Views/SettingsView.swift`: the two settings, plus a storage section: "Your entries are stored on this device only. Mindlore has no servers."
- [x] `Mindlore/PrivacyInfo.xcprivacy`: declare `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`, no tracking, no collected data.
- [x] Tests, `SettingsStoreTests`: defaults when keys are missing, stored `false` stays `false`, writes persist, init writes nothing back, `defaultEntryMode` rejects unknown raw values, wrong value types fall back, round trip through real `UserDefaults`. `PrivacyManifestTests`: the manifest is in the app bundle and declares `CA92.1`.
- [x] Settings button in the list toolbar opens `SettingsView` as a sheet; `SettingsStore` is created in `MindloreApp` and passed through the environment.

### Phase 3: Typed entries, list, editor, continuous save

- [x] `Mindlore/Persistence/EntrySaver.swift`: `@Observable`, owns the save policy for a `ModelContext`. `noteChange()` marks the context dirty and schedules a save one second out; if changes keep arriving, it still saves at least once per second (trailing throttle, not a pure debounce, which would never fire during continuous typing). `flush()` saves immediately if anything is pending. Sets `updatedAt` on changed entries before each save. The interval, clock, and save function are injected; tests use a 10 ms interval and await the scheduled save task, which is deterministic because changes in one synchronous turn can't be interrupted by the save. Save errors are kept and surfaced in the editor ("Couldn't save. Your text is still here; retrying."), and the next change or flush retries.
- [x] Turn off `mainContext.autosaveEnabled` so `EntrySaver` is the only thing deciding when saves happen and tests can reason about it.
- [x] App-level flush: `MindloreApp` calls `saver.flush()` whenever `scenePhase` leaves `.active`, which covers lock, home, app switcher, and incoming calls.
- [x] Replace `ContentView.swift` with `Mindlore/Views/EntryListView.swift` using `NavigationStack`. Rows: date, first line of `text`, a mic icon for voice entries, a "Getting text" badge when `awaitingText`. Swipe to delete. Toolbar: new entry, settings. The voice entry button stays hidden until Phase 4. Empty state says what to do.
- [x] `Mindlore/Views/EntryEditorView.swift`: one view for every entry, new or old. No Save button; back returns to the list. `TextEditor` bound directly to `entry.text`. A new typed entry is inserted on the first non-empty keystroke, so empty entries never exist, then every keystroke calls `noteChange()`. `onDisappear` calls `flush()`. Typing into an entry with `awaitingText` clears the flag. Typing into text that came from transcription sets `textEditedByUser = true`. If the entry's text is empty when the editor closes, the entry is deleted, same as Apple Notes. On close, if `keepAudioAfterTranscription` is off and the text came from transcription, audio is removed.
- [x] `Mindlore/Models/Entry+Editing.swift`: `userDidEditText()` (clears `awaitingText`, sets `textEditedByUser` when `textWasGenerated`), `applyGeneratedText(_:) -> Bool` (writes only if `awaitingText` is still true, sets `textWasGenerated`, clears the flag; returns whether it applied), `isBlank` (no text and no audio, so a voice entry still awaiting text is never discarded), `removeAudio()`, and `static func delete(_:in:)` as the single delete path for swipe and editor, so Phase 6 can add safety-copy removal in one place.
- [x] Tests, `EntrySaverTests`: one change saves once after the interval; ten rapid changes inside the interval produce one save; continuous changes over three seconds produce at least three saves; `flush()` saves immediately and is a no-op with nothing pending; `updatedAt` advances on save; a throwing save keeps the error and the next change retries.
- [x] Tests, `EntryEditingTests`: `applyGeneratedText` writes and clears the flag when set, and refuses when the user already typed; `userDidEditText` rules; `removeAudio` clears both audio fields; delete removes the entry.
- [x] UI test, `MindloreUITests/ContinuousSaveUITests.swift` with `-uiTesting` and a fresh `UITEST_STORE_NAME` per test: create an entry, type a sentence, wait two seconds, `terminate()` the app without navigating back, relaunch, and assert the entry and full text are there. Second test: type, press home (`XCUIDevice.shared.press(.home)`), terminate immediately, relaunch, text is there (proves the scene-phase flush). Third: open a new entry, type nothing, go back, no entry exists. Fourth: swipe delete removes the row and it stays gone after relaunch. Remove template UI test methods that no longer apply.

### Phase 4: Recording, ingest, playback

- [x] **Spike result (2026-09-15, macOS AVFoundation, not yet on device):** a 24 kHz 16-bit PCM CAF copied while still open for writing (what a killed app leaves) has a data chunk size of -1, which CAF allows, and AVAudioFile reads all of its audio back. AAC written the same way reads as 0 seconds in CAF and fails to open in M4A. PCM capture confirmed; header repair is not needed and was dropped. The real force-quit check still runs in device smoke step 3.
- [x] `Mindlore/Audio/RecordingsDirectory.swift`: URLs for `Recordings/active/` and `Recordings/finished/`, created on demand, excluded from device backup (converted audio lives in the store). `recoverInterruptedRecordings()` moves everything in `active/` to `finished/`; called only at launch, before any recording UI exists.
- [x] `Mindlore/Audio/AudioRecorder.swift`: `@Observable`, no delegate. Permission via `AVAudioApplication.requestRecordPermission`. Session `.record`. `AVAudioRecorder` writing 24 kHz mono 16-bit LPCM CAF to `active/<uuid>.caf`, metering on. `start`, `pause`, `resume`, `stop`. Level sampled by a MainActor `Task` loop. `AVAudioSession.interruptionNotification` (phone call) pauses and shows an interrupted state. `stop()` finishes writing, moves the file to `finished/`, deactivates the session, and returns the URL; ingest runs only after it returns.
- [x] `Mindlore/Audio/RecordingIngestor.swift`: `@concurrent nonisolated static func prepare(fileURL:) async -> PreparedRecording?` reads the PCM file off the main actor, converts to AAC `.m4a` (24 kHz mono, 48 kbps, about 21 MB per hour plus a fixed ~33 KB container overhead), and computes duration. The entry's `createdAt` is the file's creation date, so a recording recovered days later keeps the time it was made. An in-flight set stops the launch sweep and a just-stopped recording from ingesting the same file at once. If conversion fails on a non-empty file, keep the raw bytes with `audioDuration = nil` rather than delete. Then on the main actor, per file: if an `Entry` with that UUID exists, delete the file; else insert `Entry(id: uuid, source: .voice, awaitingText: true)`, save immediately (not through the throttle), delete the file. A save failure deletes only that insert (a context rollback would also drop unsaved typing) and leaves the file for next launch. Zero-byte files are deleted.
- [x] Launch sequence: `recoverInterruptedRecordings()` in `MindloreApp.init` (synchronously, before any UI exists), create container, then `RootView` ingests `finished/` in a task; transcription queue follows in Phase 5.
- [x] `Mindlore/Views/RecordingView.swift` (full-screen cover): recording starts as soon as it opens, live level bars, elapsed time, big pause/resume button, Done saves and opens the new entry, Cancel asks before discarding, swipe-to-dismiss is disabled while recording. Denied permission links to system Settings. The list toolbar shows both voice and written buttons, with the `defaultEntryMode` one in the outermost position.
- [x] `Mindlore/Audio/AudioPlayerView.swift`: play/pause over `AVAudioPlayer(data:)`, shown in the editor when `audioData` exists.
- [x] Tests, `RecordingIngestorTests` with temp directories and an in-memory container, generating short real PCM CAF files with `AVAudioFile`: ingest creates an entry with the file's UUID, AAC data, duration, and removes the file; an existing entry with that UUID means no duplicate and the file is removed; zero-byte file deleted with no entry; unconvertible non-empty file becomes an entry with raw bytes and nil duration; injected save failure keeps the file; `recoverInterruptedRecordings` moves `active/` to `finished/`; a CAF copied while still being written is recovered with its full duration; the converted audio plays in `AVAudioPlayer`; a failed save doesn't discard other unsaved edits; the same file ingested twice concurrently makes one entry; directories are excluded from backup. `AudioRecorderLevelTests` covers decibel-to-level mapping.

### Phase 5: Transcription

- [ ] `Mindlore/Transcription/Transcriber.swift`: `protocol Transcriber { func transcribe(audioFileURL: URL, locale: Locale) async throws -> String }`, plus `enum TranscriberAvailability { case available, unsupportedDevice, unsupportedLocale }`.
- [ ] `Mindlore/Transcription/SpeechAnalyzerTranscriber.swift`: request speech recognition authorization before the first transcription. Pick `SpeechTranscriber` if `isAvailable`, else `DictationTranscriber`, else report `unsupportedDevice`. Resolve the locale with `supportedLocale(equivalentTo:)`. Call `AssetInventory.assetInstallationRequest(supporting:)`; `nil` means assets are installed, otherwise `downloadAndInstall()`. Start a task reading `results` before `analyzer.start(inputAudioFile:finishAfterFile: true)`, then await it and join finalized results. Distinct errors for denied authorization, unsupported locale, asset download failure, analysis failure.
- [ ] `Mindlore/Transcription/TranscriptionCoordinator.swift`: `@Observable`, tracks in-progress `PersistentIdentifier`s and per-entry errors. `processQueue(context:)` fetches entries with `awaitingText == true`, one at a time: write audio to a temp file, transcribe, re-fetch by identifier after the `await`. If the entry is gone, discard the result. Otherwise call `applyGeneratedText(_:)` (which refuses if the user typed in the meantime) and save immediately. On failure the flag stays set and the error is stored in memory; the entry is retried next launch unless the device is unsupported. Called at launch after ingest and after each new ingest.
- [ ] Editor states for voice entries with `awaitingText`: in progress (progress, and the text field stays editable; typing clears the flag and the pending result is dropped); failed (reason, "Retry"); unsupported device (explanation). The "Type instead" button goes away because typing is always available.
- [ ] Remove `INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` only if device testing proves authorization is never requested.
- [ ] Tests, `TranscriptionCoordinatorTests` with `FakeTranscriber`: success sets `text` and clears the flag; failure keeps the flag and records the error; user types during transcription, their text is kept and the result dropped; entry deleted during transcription does not crash; entries without the flag are never touched; two queued entries both process in order.

### Wrap-up for this PR

- [ ] Sub-agent code review over the full PR diff; fixes in separate commits.
- [ ] Device smoke test, local steps 1 to 5 (below), on a physical iPhone signed with the Personal Team.
- [ ] Update `CLAUDE.md` Architecture for the new folders, `AppConfig`, and the CloudKit schema rules.
- [ ] `gh pr ready`.

### Phase 6: iCloud sync (separate PR, blocked on Apple Developer Program enrollment)

Owner, in Xcode, Signing & Capabilities on the Mindlore target, after the paid team appears:
- [ ] Switch **Team** to the paid team.
- [ ] Add **iCloud**, check **CloudKit** and **Key-value storage**, create container `iCloud.com.natefikru.mindlore`. The container is permanent.
- [ ] Add **Push Notifications** (`aps-environment`).
- [ ] Confirm `Mindlore/Mindlore.entitlements` has the container ID, `com.apple.developer.ubiquity-kvstore-identifier`, and `aps-environment`.

Code:
- [ ] Set `AppConfig.cloudKitContainerID = "iCloud.com.natefikru.mindlore"`.
- [ ] Test, `CloudKitSchemaTests`: load a `.private(...)` configuration at a temp URL, insert nothing, assert it loads. Enabled only when the entitlement is present.
- [ ] Conform `NSUbiquitousKeyValueStore` to `KeyValueStore`. `SettingsStore` takes local and remote stores: writes go to both, a MainActor task consumes `didChangeExternallyNotification` and pulls remote values into local, reads come from local. Tests with two fakes.
- [ ] `Mindlore/Sync/SyncStatusMonitor.swift`: `@Observable`, `syncing | deviceOnly | checking`, refreshed at init and on `.CKAccountChanged`, account lookup injected. Computes a local account fingerprint (hash of status plus opaque user record name, never name or email) stored in `UserDefaults`, and sets `pendingRecoveryCheck` when it changes from a previously available account. Settings storage text switches to "stored on this device and in your private iCloud" when syncing.
- [ ] Safety copy: `EntryBackupStore` (atomic JSON snapshots in `Application Support/EntryBackups/`, stays in device backup), writes hooked to `ModelContext.didSave` on the main context (verify notification and key names against the SDK), removal added to `Entry.delete`.
- [ ] `EntryRecovery` (`missingEntries(backups:storeIDs:)`, restore keeping original `id`), run at launch and on remote store changes while `pendingRecoveryCheck` is set. `RecoveryBanner` with Restore all, Review, Not now.
- [ ] `EntryDeduplicator`: keep newest `updatedAt` per `id`, run at launch and on remote store changes.
- [ ] Cross-device transcription: keep a device-local `locallyIngestedEntryIDs` list; the coordinator only auto-transcribes entries this device ingested. Entries from another device show "Waiting for text from your other device" with "Transcribe here"; typing still works and clears the flag.
- [ ] Tests for all of the above: settings mirroring, status mapping and fingerprint changes, backup store, didSave hook, missing-entry detection, restore, dedupe with two and three copies, coordinator skipping non-local entries and `transcribeHere`.
- [ ] Before any TestFlight build: deploy the CloudKit schema to Production in CloudKit Console.
- [ ] Device smoke steps 6 to 10 (below).

## Test commands

```bash
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

## Device smoke test

Local (this PR):
1. Airplane mode on: type an entry, record an entry, get text. Everything works without network.
1a. Type a paragraph, then immediately force-quit from the app switcher while the keyboard is still up. Relaunch: everything except at most the last second of typing is there. Repeat by locking the phone mid-sentence and force-quitting after unlock: nothing is lost.
2. Record 30 seconds, lock the phone 30 seconds, unlock, stop. Audio contains the full minute.
3. Record, then force-quit from the app switcher. Relaunch. A voice entry exists with audio up to the kill, and it gets text.
4. Phone call mid-recording: recording pauses and resumes cleanly.
5. Turn off `keepAudioAfterTranscription`, record, let text generate, open and close the entry: audio is gone. Close the app before opening it instead: audio is still there. On a device or simulator where `SpeechTranscriber` is unavailable, the voice entry shows the unsupported state and typing works.

Sync (Phase 6):
6. Two devices on one iCloud account: an entry saved on one appears on the other; an edit syncs back; the second device shows "Waiting for text from your other device" and does not transcribe on its own.
7. `keepAudioAfterTranscription` off on one device: audio removal syncs to the other.
8. **Gate:** device with no iCloud account works fully and Settings says device only. Sign in. Entries created while signed out upload and appear on a second device. If not, stop and re-plan sync.
9. **Gate:** airplane mode on, create three entries, sign out of iCloud. After relaunch the recovery banner appears; restore brings back all three with correct text; sign back in and confirm no duplicates after sync.
10. Settings change on one device appears on the other.

## Risks and open questions

- **The recording screen has only been exercised through unit tests of what sits behind it.** Microphone capture, locking, and interruptions are verified in device smoke steps 1 to 4.
- **Sync may need rework if smoke gate 8 fails.** Following CloudKit schema rules now keeps that risk in the sync layer, not the data model.
- **Personal Team builds expire after 7 days on a physical device.** Reinstall from Xcode; data in the app sandbox survives a reinstall over the same bundle ID.
- **Audio from unsynced voice entries is not in the safety copy** (Phase 6). Accepted.
- **Backups of entries deleted on another device linger** until discarded (Phase 6). Accepted.
- **Concurrent edits on two devices** resolve last-writer-wins per record. Accepted.
- **Long recordings.** Temporary PCM is about 170 MB per hour; stored AAC about 25 MB per hour. Fine for v1.
- **No CI.** Verification is local. A GitHub Actions macOS workflow is a reasonable follow-up.

## Not in scope

- AI analysis, BYOK API keys, Keychain, provider abstraction
- Entities, relationships, summaries, embeddings, graph visualization
- Onboarding beyond the empty state and Settings storage explanation
- Search, filtering, tags, mood
- Import (text or handwriting), export
- Whisper or any non-Apple transcription
- Replacing SwiftData sync with `CKSyncEngine`
- Safety copies of audio
- Sync progress and CloudKit mirroring error UI beyond account status
- Audio route-change handling, playback scrubbing
- iPad-specific layout, widgets, Siri, Apple Watch
- CI setup

## Review log

Revision 5 (during Phase 3): added `Entry.textWasGenerated`, since without it the app can't tell generated text from typed text, and both `textEditedByUser` and the keep-recordings rule depend on that. UI tests name their store instead of passing a path. The UI test helper waits for the editor to be hittable before tapping, and forces portrait because the launch screenshot tests leave the simulator in landscape.

Revision 4: continuous saving, no commit step (owner direction). Removed `EntryStatus`, `statusRaw`, `draft`, `committed`, the Save button, and "Type instead." Added the `awaitingText` flag, `EntrySaver` with a one-second trailing throttle plus scene-phase and close flushes, file-backed UI tests that terminate and relaunch the app to prove text survives, and a force-quit-while-typing smoke step. `keepAudioAfterTranscription` now applies when the user closes an entry with generated text.

Revision 3: iCloud work moved to Phase 6 behind `AppConfig.cloudKitContainerID` (Personal Team cannot use iCloud capabilities). The schema check became an introspection test that needs no entitlement; the `.private` load test moved to Phase 6. Settings start `UserDefaults`-only. Cross-device transcription rule moved to Phase 6.

Revision 2 changes from the plan review:
1. Sign-out purge deletes unsynced entries for good: added local safety copy, recovery, dedupe, and a smoke gate (owner decision).
2. AAC-in-CAF crash resilience was unproven: PCM capture with AAC conversion at ingest, header repair, device spike first.
3. SpeechTranscriber unavailable on simulator and older devices: DictationTranscriber fallback, unsupported state, optional asset request, `supportedLocale(equivalentTo:)`, read-results-before-start ordering.
4. Hosted unit tests would open the real store: in-memory store under XCTest.
5. Ingest duplicates and races: UUID-as-id, `active/` and `finished/`, never delete non-empty unconvertible files, ingest after `stop()` returns.
6. Draft text loss and empty rows: save on scene phase and disappear, create entry on first keystroke.
7. Coordinator crash on deleted models and cross-device overwrite: `PersistentIdentifier` plus re-fetch, local-only auto-transcription.
8. `bool(forKey:)` can't tell missing from false: `object(forKey:)`.
9. Notification threading and Timer isolation: async notification sequences, Task-based metering, no delegate, off-main conversion.
10. Missing `aps-environment` check and `PrivacyInfo.xcprivacy`.
11. Setup and data layer must land together; voice button hidden until recording exists.
12. Pre-sign-in upload unverified: smoke gate.

Cut per review: audio route-change handling, playback scrubber, five-state account status. Kept pause/resume because the build plan lists it.
