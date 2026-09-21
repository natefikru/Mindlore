# A4 build spec: tabs and the record accessory

Lane 3, branch `feature/phase-a-shell`. Implements the "Shell and tabs" key decisions and the A4
checklist in `tasks/todo.md`, plus review findings 1 and 9.

## Accessory check (done, simulator, 2026-09-17)

A throwaway `TabView` with `tabViewBottomAccessory(isEnabled:)`, three tabs, a pushed detail view,
and launch-argument-driven presentations, screenshotted on the lane simulator:

- **Sheets** (a 220pt detent and a large one) cover the accessory and the tab bar. The accessory
  can't be tapped while a sheet is up, so no sheet can be open when a recording is finished from it.
- **Full-screen covers** hide the tab bar and the accessory completely.
- **A custom bottom panel** in a tab's content lays out above the accessory: the tab's bottom
  safe area already includes the accessory and the tab bar, so Mind's panel needs no manual offset.
- **Pushed views** (the editor) keep the tab bar and the accessory. That is what lets the user switch
  tabs with an entry open, which is why the close rules have to move.
- **`isEnabled: false`** removes the accessory and the tab bar shrinks back.
- At rest the accessory reports the `.expanded` placement. The `.inline` placement only appears if
  the tab bar minimizes, which we don't turn on, but the accessory view still reads the placement
  and draws a compact layout for it.

Still for the phone: the accessory with the keyboard up, and whether the tab bar should minimize on
scroll in the editor. Neither blocks A4.

## New types

### `JournalRoute` and `AppRouter` (`Mindlore/Views/Shell/AppRouter.swift`)

```swift
enum AppTab: Hashable { case journal, mind, ask }

struct JournalRoute: Hashable {
    let entryID: UUID
    var isNew = false        // a new typed entry; the entry is created with this id on first input
    static func new() -> JournalRoute
}

@Observable final class AppRouter {
    var tab: AppTab = .journal
    var journalPath: [JournalRoute] = [] { didSet { diff(oldValue) } }
    // Mind's path arrives with A5; the property exists now so jumps have one shape.
    var mindPath: [EntityRoute] = []
    private(set) var dismissPresentationsToken = 0

    init(opened: @escaping (UUID) -> Void, closed: @escaping (UUID) -> Void)
    func showEntry(_ id: UUID)   // tab = .journal, bump token, journalPath = [JournalRoute(entryID: id)]
}
```

- The path holds ids, not `Entry` objects, the same rule as `EntityRoute`, so a deleted entry never
  leaves a dangling model on the stack.
- `didSet` diffs old and new paths as multisets: each route that left calls `closed(entryID)` once,
  each that arrived calls `opened(entryID)` once. NavigationStack writes the path on push, on back,
  and on a completed back swipe, and not on a cancelled one, so today's "cancelled swipe" special
  case disappears. Changing `tab` touches neither.
- A new typed entry gets its UUID up front (`JournalRoute.new()`), and `EntryEditorView` creates
  the `Entry` with that id on the first keystroke. The close rules then find a new entry by id like
  any other, and find nothing when the user typed nothing.
- `showEntry` replaces the path (closing whatever was open) instead of appending. The token is
  bumped first; the list and the editor close their sheets when it changes. In A4 only the finished
  recording jumps, and the accessory can't be reached under a sheet, so the token matters from A5 on
  (peek card, Ask citations). It's cheap, so it lands now with its test.

### `EditorLifecycle` (`Mindlore/Views/Shell/EditorLifecycle.swift`)

The editor's `onAppear` open and `close()` move here, unchanged in behaviour:

```swift
@Observable final class EditorLifecycle {
    init(context: ModelContext, saver: EntrySaver, presence: EditorPresence, aiPass: AIPassTrigger,
         keepAudio: @escaping () -> Bool, diagnostics: DiagnosticsLog = .shared)
    func opened(_ id: UUID)   // presence.open(id)
    func closed(_ id: UUID)   // presence.close, fetch by id (pending changes included), editorDidClose,
                              // editor.closed event, aiPass.fire(.editorClosed) unless deleted,
                              // saver.flush(), aiPass.onFlagged?()
}
```

`RootView` builds it and hands `opened`/`closed` to the router. `EntryEditorView` loses
`onAppear`'s `presence.open`, the two `presence.open(created.id)` calls, `onDisappear`, `close()`,
and `isPresentingOverEditor` (nothing reads it once `onDisappear` is gone; A6's "add the peek sheet
to `isPresentingOverEditor`" becomes a no-op, noted in the review log).

`EntryEditorView(entry: Entry?, newEntryID: UUID?)`. The list's destination is a small
`JournalEntryDestination(route:)` that fetches the entry by id and shows the editor, or "This entry
was deleted" when an existing route's entry is gone.

### `AudioRecording` protocol (in `Mindlore/Audio/AudioRecorder.swift`)

```swift
protocol AudioRecording: AnyObject, Observable {
    var state: AudioRecorder.State { get }
    var level: Float { get }
    var elapsed: TimeInterval { get }
    var audioGap: String? { get }
    var isResuming: Bool { get }
    var resumeFailed: Bool { get }
    var buffers: AsyncStream<AVAudioPCMBuffer>? { get }
    func start() async throws
    func stopBuffering()
    func pause()
    func resume() async
    func stop() throws -> URL?
    func discard()
}
extension AudioRecorder: AudioRecording {}
```

No other change to `AudioRecorder`.

`UITestingRecorder` (`Mindlore/Audio/UITestingRecorder.swift`, `@Observable`) conforms too: `start`
writes a second of silent PCM to `active/`, `stop` moves it to `finished/`. It's used when the app
launches with `-uiTesting -uiTestingFakeRecorder`, so UI tests never meet the microphone prompt or
depend on the Mac's microphone. Real capture stays a device step.

### `RecordingSession` (`Mindlore/Audio/RecordingSession.swift`)

Owns everything `RecordingView` holds today:

```swift
@Observable final class RecordingSession {
    enum Status { case idle, starting, active, permissionDenied, startFailed }
    private(set) var status: Status
    private(set) var recorder: (any AudioRecording)?
    private(set) var liveSession: (any LiveTranscriptionSession)?
    private(set) var levels: [Float]        // 48 samples, the waveform's history
    private(set) var isFinishing = false
    var isExpanded = false                  // the full recorder is showing

    init(context: ModelContext, ingestor: RecordingIngestor,
         makeRecorder: @escaping () -> any AudioRecording,
         makeLiveSession: @escaping (Locale) -> any LiveTranscriptionSession,
         availability: LiveTranscriptionAvailability = .standard, locale: Locale = .current,
         speechEngine: @escaping () -> SpeechEngine,
         afterIngest: @escaping () async -> Void,      // transcription.processQueue
         onFinished: @escaping (Entry) -> Void,        // router.showEntry
         diagnostics: DiagnosticsLog = .shared)

    func begin()             // no-op unless idle; new recorder, startTask, isExpanded = true
    func minimize()          // isExpanded = false; recording continues
    func expand()
    func togglePause()
    func finish() async      // stop, drain feed, finish live text, ingest, reset, onFinished, afterIngest
    func discard()           // cancel start task, recorder.discard(), cancel feed, reset
    func close()             // ends a session that never started recording (denied / failed)
}
```

- The start task keeps today's `CancellationError` handling, and after `start()` returns it checks
  for cancellation and discards, so a discard during the permission prompt leaves nothing running.
- A monitor task runs while active: every 50 ms it appends `recorder.level` to `levels` and passes a
  new `audioGap` to `liveSession?.markUnhealthy`. Those are today's two `onChange`s. The loop body is
  a method (`sample()`) so tests call it directly instead of sleeping.
- `finish()` runs once: `isFinishing` guards a second tap from the accessory and the full recorder.
  The file is ingested exactly once (the ingestor's in-flight guard stays as a second line).
- Diagnostics: `recording.minimized` and `recording.expanded` (no fields), so the device loop can
  see the new states. Live text is never logged.

`RecordingView` becomes a view of the session: `@Environment(RecordingSession.self)`. Its toolbar
has a Minimize button (chevron down, `minimizeRecordingButton`) while recording, Close when the
session never started, a Discard button (`discardRecordingButton`, confirmation dialog), and Done
(`finishRecordingButton`). `LiveTranscriptText` and `LevelBars` stay as they are.

### `RecordAccessory` (`Mindlore/Views/Shell/RecordAccessory.swift`)

Stateless, reads `RecordingSession` and `tabViewBottomAccessoryPlacement`:

- idle: a Record button, identifier `newVoiceEntryButton`, calling `session.begin()`
- active: a red dot, the elapsed time, a level tick, and a Done button (`accessoryFinishButton`);
  tapping the rest expands the recorder (`recordingAccessory`). A context menu offers Pause/Resume and
  Discard; Discard asks first through a dialog owned by `RootView`.
- `.inline` placement drops the level tick and the button labels.

## Changed files

- **`RootView`**: builds `EditorLifecycle`, `AppRouter`, `RecordingSession` (recorder factory picks
  `UITestingRecorder` under the launch flag). Body becomes
  `TabView(selection: $router.tab) { Tab("Journal", systemImage: "book", value: .journal) { EntryListView() } Tab("Mind", systemImage: "circle.hexagongrid", value: .mind) { MindPlaceholderView() } Tab("Ask", systemImage: "bubble.left.and.text.bubble.right", value: .ask) { AskPlaceholderView() } }`
  with `.tabViewBottomAccessory { RecordAccessory() }`, `.fullScreenCover` bound to
  `session.isExpanded` showing `RecordingView`, the discard dialog, then every existing environment,
  overlay, task, and `onChange` modifier moved over unchanged, plus `.environment(router)` and
  `.environment(session)`.
- **`EntryListView`**: `NavigationStack(path: $router.journalPath)`; rows push
  `JournalRoute(entryID:)`; `newEntryButton` appends `JournalRoute.new()`; `PageOrderView`'s
  callback calls `router.showEntry`. The mic button, the Connections button, `writingNewEntry`,
  `recording`, and the `RecordingView` cover are removed. Sheets close on the router's token.
- **`MindPlaceholderView` / `AskPlaceholderView`** (`Mindlore/Views/Shell/PlaceholderTabs.swift`):
  a `ContentUnavailableView`. Mind's has a "Connections" button that opens today's `ConnectionsView`
  sheet, so the graph stays reachable until A5 replaces it.
- **`EntryEditorView`**: as described above, plus closing its sheets on the router's token.

## Deferred inside A4

- **Area chips on rows and the area filter row** wait for lane 1's `LifeArea`
  (`git grep -q "enum LifeArea" origin/feature/phase-a`).
- **The loose-end prompt line in the recorder** waits for lane 1's `LooseEndPrompter` (A2). Same
  rule: merge it in when it lands and add the line then.

## Tests

Unit (Swift Testing, `@MainActor`):

- `AppRouterTests`
  - pushing a route calls `opened` once; popping calls `closed` once for that id
  - a pop of two routes closes both; the same id pushed twice closes twice
  - switching tabs with a route open calls neither
  - `showEntry` selects Journal, closes every open route, opens the new one, bumps the token
- `EditorLifecycleTests` (real `EditorPresence`, `AIPassTrigger`, `EntrySaver`, in-memory store)
  - closing a new route with nothing typed deletes nothing and doesn't crash
  - closing a blank created entry deletes it and doesn't fire the pass
  - closing a finished entry fires the pass once and closes presence
  - opening, switching tabs (nothing called), then closing leaves presence closed exactly once
  - text-ready deferral: while open, `presence.isOpen` is true
- `RecordingSessionTests` (`FakeRecorder`, `FakeLiveSession`, `IngestHarness`-style temp directory)
  - begin starts the recorder and expands; begin again does nothing
  - minimize keeps recording (no stop, no discard) and logs `recording.minimized`
  - discard while minimized discards the file, resets, creates no entry
  - discard during start (recorder blocked on permission) cancels, discards, never starts live text
  - finish ingests once, calls `onFinished` once with the entry whose id is the file's UUID, runs
    `afterIngest`, resets; a second concurrent `finish()` is a no-op
  - finish passes live text through to the entry
  - permission denied and start failure set the status and `close()` resets
  - `sample()` appends levels in a 48-sample window and marks the live session unhealthy on a gap
- `DiagnosticsPrivacyTests`: a session run with the sentinel as live text never logs it.

UI (XCTest, lane simulator):

- New `RecordingUITests` (`-uiTestingFakeRecorder`):
  - record from the accessory, minimize, switch to Mind, finish from the accessory: Journal is
    selected with the new entry open; back shows one row
  - record, minimize, discard from the accessory menu: no rows
- `GraphUITests`: reach Connections through the Mind tab, return through the Journal tab.
- Phase-scoped run: every class using `newEntryButton`, `newVoiceEntryButton`, or
  `newPhotoEntryButton` (Draft, Title, ContinuousSave, EntryDate, Insights, Graph,
  GraphScreenshot, PageOrder, PageTranscription), plus `RecordingUITests`.

Device (asks first, shared phone): record, switch tabs, lock, come back, finish; a Siri
interruption while minimized; the accessory with the keyboard up.

## Units and commits

1. `EditorLifecycle` + `AppRouter` + editor/list moved onto routes (no tabs yet). Unit tests.
2. `AudioRecording`, `UITestingRecorder`, `RecordingSession`, `RecordingView` rewired (still
   presented from the list). Unit tests, privacy case.
3. `TabView`, accessory, placeholders, Connections moved to Mind, `GraphUITests` updated,
   `RecordingUITests`. Phase-scoped UI run.
4. Review-log entry, tick boxes, land on `feature/phase-a`.
5. Later: area chips and filter, and the prompt line, once lane 1 lands them.

## Not in scope

The Mind graph, search panel, peek card (A5), read mode (A6), Ask (A7), tab bar minimizing, a Live
Activity for recording, CLAUDE.md (A9).

## Review fixes (sub-agent review of this spec, verdict "approve with fixes")

1. **Start races.** `finish()` runs only when `status == .active` and cancels the start task. Closing
   during `.starting` goes through `discard()`. The accessory's Finish is disabled until active.
2. **Stale async work.** Each `begin()` bumps a generation number. The start task captures its own
   recorder and checks the generation after every await; a live session that starts after its
   recording ended is finished and dropped, never stored.
3. **Deleted model during the pop.** The close rules now run when the path changes, while the editor
   is still animating out, so a blank entry can be deleted under a view that is still drawing. The
   editor reads the entry only through `liveEntry` (nil once `isDeleted` or `modelContext == nil`),
   and a UI test types, clears the text, and goes back.
4. **Discard while finishing** does nothing, and both UIs disable it while `isFinishing`.
5. **Cancelled back swipe.** Unverified that NavigationStack leaves the path alone, so a UI test
   drags partway and releases, then checks the entry is still open and its text still saves. The
   1 s delay in `onFlagged` stays.
6. **`JournalRoute` equality and hashing use `entryID` only**, so `showEntry` on an entry that
   started as a new route doesn't close and reopen it.
7. **Both creation paths** (text and title bindings) use `newEntryID`.
8. **Presence double counting** after a full-screen cover (today `onAppear` opens again) is fixed by
   the move; `EditorLifecycleTests` covers open, cover, return, pop, closed once.
9. **`LiveTranscriptText`** takes `any LiveTranscriptionSession`, and that protocol gains
   `Observable`.
10. **`AudioRecording` is `@MainActor`**, like `LiveTranscriptionSession`.
11. **Environment**: `RecordAccessory` and the recorder cover get `session` and `router` injected
    directly.
12. **`GraphUITests`**: every Connections entry and exit goes through `app.tabBars.buttons["Mind"]`
    and `["Journal"]`, including after the relaunch.
13. **The accessory's finish button is labelled "Finish"**, never "Done", so `app.buttons["Done"]`
    stays unambiguous.
14. The empty-list text is reworded ("Tap Record to speak an entry, or the pencil to write one.").
    No existing UI test records, so `RecordingUITests` is the only voice coverage.
16. **`EditorLifecycle` is a plain `final class`**, and the tab-switch case lives in `AppRouterTests`.
17. **The accessory reads `recorder.level`** directly and never `levels`, so it doesn't redraw with
    the waveform history.
