# Other devices: watch, Mac, iPad

Decided on 2026-09-23, not started. The owner wants three more ways into the same journal, in this
order: a watch sidekick for quick recording, a native Mac app, then a full native iPad app with
Apple Pencil. There is no web app. Every device shares one journal through iCloud, using the
SwiftData CloudKit mirroring `main` already runs. The ordered checklist is section 7 of
`docs/remaining-work.md`. This file holds the reasoning.

## Key decisions

- **Order: watch, Mac, iPad** (owner, 2026-09-23). The watch is small and fits a voice-first
  journal. The Mac comes before the iPad because it forces the big-screen SwiftUI structure
  (`NavigationSplitView`, a multi-column journal, Mind as a full canvas, Ask beside the journal)
  that the iPad then reuses instead of stretching the phone's four tabs.
- **No web app** (owner: too much work). This is also what keeps sync simple. A browser can only
  reach iCloud through CloudKit JS, and SwiftData's mirroring writes records in Core Data's private
  layout (`CD_` fields, its own zone, its own relationship encoding). That layout is undocumented, and
  writing it from JavaScript could corrupt the journal on every Apple device. A real web client would
  have meant replacing the mirroring with `CKSyncEngine` and our own record types, and rebuilding Ask
  retrieval, the graph, and insights in TypeScript. With no web app, none of that is needed.
- **iCloud is native everywhere.** Mac and iPad open the same container
  (`iCloud.com.natefikru.mindlore`) through SwiftData's mirroring. The watch reaches iCloud through
  the phone (below). Audio, page images, and ink all sync, because `Entry.audioData` and
  `EntryPage.imageData` are `@Attribute(.externalStorage)` and mirror as CloudKit assets.
- **Mac and iPad wait on sync phases 3 to 5.** Each is a second device, the case
  `tasks/icloud-sync.md` was written for. Without phase 3, both devices transcribe the same
  recording and run insights on the same entry: two OpenAI bills and duplicate loose ends. Without
  phase 4, both create their own "Maya". Without phase 5, the life-area names, your name, and the
  font differ per device. The watch doesn't wait, because it never opens the store.
- **One model definition for every target.** If the Mac's `Entry` ever differs from the phone's, the
  two schemas fight in one container. The models move into a shared local Swift package before the Mac
  target exists, and `CloudKitSchemaRulesTests` moves with them.
- **The OpenAI key stays per device** unless the owner decides otherwise. Phase 5 never syncs it, so a
  new Mac or iPad asks for it once. Making the Keychain item synchronizable (iCloud Keychain) is the
  alternative, and it's a privacy call, not an engineering one.

## 1. Watch sidekick

A small app whose only job is to record. It needs one big button that starts the moment the app
opens, a complication, an Action Button intent, and Siri ("Record in Mindlore").

- **Relay, never sync.** The watch records to a file and sends it with `WCSession.transferFile`. The
  transfer is queued by the system and delivered once the phone is reachable, even if it wasn't
  during the recording. The phone's session delegate moves the file into `Recordings/finished/`, and
  `RecordingIngestor` makes the entry exactly as it does for a phone recording: the entry's `id` is
  the file's UUID, transcription, the AI pass, and insights follow, and iCloud carries it to every
  other device.
- **Why not SwiftData on the watch.** watchOS can run the mirrored store. But it would put the whole
  model and graph layer on a watch, sync only when watchOS allows it, and upload multi-minute audio
  over the watch's radio. It would also make the watch a device that "made" entries it can't
  transcribe well, which fights phase 3's rule that AI runs where the entry was made. With the relay,
  the phone is where the entry was made.
- **Format.** The same 24 kHz mono PCM `.caf` the phone records, for the same reason: it stays
  readable if the watch app is killed mid-recording. The phone converts it to AAC on ingest as it
  already does.
- **What the watch shows.** Recording, then "Sent to your iPhone" once `WCSessionFileTransfer`
  reports it's queued. A pending count while transfers are still waiting. No journal, no text.
- **Open questions.** Whether a transfer that arrives while the phone app is suspended should be
  ingested in the background (`session(_:didReceive:)` runs, but ingest's save and the AI pass
  expect `RootView`), or held in `finished/` until the next foreground launch picks it up, which
  already works. The simple answer is the second. Also whether a phone-less watch with cellular needs
  anything (probably not: the queue waits).
- **Testing.** The transfer path doesn't behave the same in the simulator, so a paired physical
  watch is needed, with new `watch.*` diagnostics events for record, queue, and delivery (counts and
  durations only, like every other event).

## 2. Mac

A native SwiftUI macOS target, not Catalyst and not "Designed for iPad". It's a real Mac app on the
same journal.

- **Shared package first.** Move `Models/` and the logic that already avoids SwiftData and UIKit
  (`EntityGraph`, `GraphSimulation`, `AskIndex` and retrieval, `ReflectAggregator`,
  `TodayComposer`, the prompt builders and parsers, `MarkdownCodec`) into a local package all
  targets link. Most of it is `nonisolated` and SwiftData-free by design already. Its tests move too.
- **The editor is the biggest piece.** `GrowingTextEditor` and `FormattingStyle` sit on
  `UITextView` (about 35 references): custom attributes, TextKit 2 `NSTextList` markers, the Return
  and Backspace rules in `ListEditing`, the checkbox gutter tap, and read mode's linked names. On the
  Mac it becomes `NSTextView`. TextKit 2 is shared, so the attribute codec should carry over. The
  view and delegate layers are what get rewritten. `FormatBar` becomes a toolbar and menu commands.
- **Recording.** `AudioRecorder` uses `AVAudioSession`, which doesn't exist on macOS. The Mac needs
  its own capture path to the same `.caf` format, and a microphone permission string.
- **Pages.** No VisionKit document camera on the Mac. Import from Files and Photos, plus Continuity
  Camera from the phone.
- **Shell.** A sidebar (Journal, Mind, Chat, Settings) instead of tabs, a recording control in the
  toolbar instead of `RecordAccessory`, menus and keyboard shortcuts, and multiple windows if they're
  cheap.
- **Smaller ports.** App lock goes from Face ID to Touch ID (same `LocalAuthentication` API).
  `UIFont`, `UIColor`, `UIPasteboard`, and `UIApplication` calls (a few dozen across about ten
  files) get platform branches. The on-device model (Foundation Models) and speech transcription
  (`SpeechAnalyzer`) both exist on macOS.
- **CI.** A Mac build and unit-test job next to the iOS one, and signing for the Mac App Store
  profile with the iCloud entitlement.
- **Testing sync.** Xcode builds talk to CloudKit's Development environment and TestFlight to
  Production, and they never see each other's data. A debug Mac build and a TestFlight phone won't
  sync with each other. Test with both on Xcode builds or both on TestFlight.

## 3. iPad

The same iOS target with iPad added (it is iPhone-only today, `TARGETED_DEVICE_FAMILY = 1`). It
should feel built for the iPad, not like the phone app stretched. Keep iPad off until this step:
turning it on early would put the stretched phone app in front of iPad users.

- **Layout.** Reuse the Mac's split-view structure: sidebar, list and editor side by side, Mind full
  screen with the search panel as a column, Ask beside the journal. It has to hold at every Stage
  Manager window width, down to phone width.
- **Pencil, level one: Scribble.** Handwriting in the editor turns into typed text through the
  system, because the editor is a `UITextView`. That comes free once iPad is a supported device.
  Check that it goes through the coordinator's edit path, so formatting marks and `noteChange()`
  behave the way typing does.
- **Pencil, level two: ink pages.** A PencilKit canvas for writing a page that stays handwriting. A
  pencil page is an `EntryPage` whose image comes from the canvas instead of the camera, so the
  existing pipeline reads it: `PageTranscriptionCoordinator`, approve text, then insights. The
  `PKDrawing` is stored beside the image so the ink stays editable. That's a new optional
  external-storage field, which means the model-change routine: `-initializeCloudKitSchema`,
  cktool check, Deploy Schema Changes. A new `PageOrigin` case marks it.
- **Keyboard and pointer.** A hardware keyboard, shortcuts shared with the Mac, and a pointer on Mind.

## Not doing

- A web app, and with it any `CKSyncEngine` rewrite of sync.
- Mac Catalyst or "Designed for iPad" as the Mac app. Either is a possible stopgap, but neither is
  the plan.
- SwiftData or CloudKit on the watch.
