# Transcription Hierarchy: Feature Spec

How Mindlore captures and transcribes voice entries: one user-facing choice, three tiers behind it.

---

## 1. Goal

Give the user live, on-screen text while they talk, backed by a system that never loses a recording.

The user picks their transcriber once in Settings, from all three tiers by name. Live on-device is the default where the device supports it, because it's free, private, offline, and shows text as you talk. OpenAI is the default everywhere else, and the choice anyone can make if on-device accuracy is poor for their voice or their language isn't supported.

The one automatic move the app makes on its own is dropping from tier 1 to tier 2. Both are Apple on-device, so that fallback never changes where a recording goes, only when its text arrives.

---

## 2. The Three Tiers

### Tier 1: On-device live (SpeechAnalyzer, streaming)

**Settings: "Live on this iPhone." The default where it runs.**

- Apple's `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26+), fed live from `AVAudioEngine`
- Free, private, fast, works fully offline
- Produces two text states as the user speaks:
  - **Volatile**: a realtime guess, rewritten continuously
  - **Finalized**: committed text, never rewritten
- This is what gives the "text appears as you talk" UX

**Available when:** locale is supported, device is iOS 26+, the on-device model asset is already installed. A missing asset never blocks a recording; it downloads in the background for next time while this recording takes tier 2.

### Tier 2: On-device batch (SpeechAnalyzer, file-based)

**Settings: "On this iPhone." Also the automatic catch for tier 1.**

- Same `SpeechAnalyzer`/`SpeechTranscriber` API, run against the finished audio file instead of a live buffer, so no volatile results are needed
- Text arrives a moment after the user hits Done rather than while they talk

**Use when:**
- The user picked it, because they don't want text moving on screen while they're speaking
- The user picked tier 1 but it couldn't run or didn't finish: the model asset wasn't installed yet, the live session dropped mid-recording, a phone call interrupted the app, the engine tap failed. Instead of losing the entry, re-run against the audio file that was already saved to disk.

### Tier 3: Cloud batch (OpenAI transcription API)

**Settings: "OpenAI." The default on devices Apple's stack can't serve.**

- Requires the user's own API key (BYOK) and network connectivity
- Costs the user tokens
- Runs after the recording finishes, so there's no live text on this path

**Use when:**
- The user picked OpenAI
- The spoken locale isn't in SpeechAnalyzer's supported set (its coverage is narrower than Whisper's 100+ languages)
- On-device accuracy is poor for the user's voice or accent and they said so in Settings

Cloud live streaming (the Realtime API) was considered and cut. It bills continuously while the user talks and needs an open connection for the whole recording, in exchange for text that arrives at roughly the same time as tier 1's. For a journaling app it's cost with no product.

---

## 3. Decision Flow

```
Start recording
     │
     ▼
Settings: which transcriber?
     │
     ├── Live on this iPhone ──▶ Tier 1 available?
     │                           (iOS 26+, locale supported, model installed)
     │                                │
     │                                ├── YES → Live on-device transcription
     │                                │            │
     │                                │            ├── Clean finish → that text is the entry
     │                                │            └── Dropped (background/call/tap failure)
     │                                │                     → Tier 2 against the saved audio
     │                                │
     │                                └── NO → Tier 2, once the recording finishes
     │                                         (and start the model download for next time)
     │
     ├── On this iPhone ───────▶ Tier 2, once the recording finishes
     │
     └── OpenAI ───────────────▶ Tier 3, once the recording finishes
                                      │
                                      └── Request fails → Tier 2, if "use this iPhone
                                          when OpenAI fails" is on
```

**Where user choice enters:** at the top, once, in Settings. Only two moves happen without asking, and both go toward the device rather than away from it: tier 1 dropping to tier 2, and the existing "use this iPhone when OpenAI fails" toggle. A user on OpenAI never silently gets on-device text as their entry, and a user on either iPhone option never has audio leave the phone.

---

## 4. Architecture

Two shapes, not one. Batch transcription is a function from a file to a string; live transcription is a session fed buffers over time. Forcing both into a single protocol makes every implementation carry a method it doesn't mean.

```swift
// Already shipped. Tier 2 and tier 3 both conform.
protocol Transcriber {
    func transcribe(audioFileURL: URL, locale: Locale) async throws -> String
}

// Tier 1.
protocol LiveTranscriptionSession {
    var volatileText: String { get }    // rewritten continuously, never persisted
    var finalizedText: String { get }   // committed, append-only
    var isHealthy: Bool { get }         // false once any audio was dropped

    func start() async throws
    func feed(_ buffer: AVAudioPCMBuffer)
    func finish() async throws -> String?  // nil if the session can't be trusted
}
```

- `SpeechAnalyzerLiveSession`: tier 1
- `SpeechAnalyzerTranscriber`: tier 2 (shipped)
- `OpenAICompatibleTranscriber`: tier 3 (shipped)

`TranscriberRouter` already picks the batch tier per entry from settings. Tier 1 is decided at record-start instead, because it has to be running before there's anything to route.

---

## 5. Interaction With Progressive Save (non-negotiable)

Regardless of which tier is active, the save order is fixed:

1. **Audio saves to disk first**, continuously, as it's captured, whether or not transcription succeeds
2. **Transcript saves second**, as finalized segments commit
3. **Analysis runs last**, only once a transcript exists

The live path makes this concrete: the `AVAudioEngine` tap writes each converted buffer to the recording file *before* handing it to the speech session, and the write never depends on the session existing. This means a failure at any tier is always recoverable, because the audio file already exists and falling back just means re-running transcription against a file that was never at risk. No tier failure should ever be able to lose a recording. That failure mode is the one thing that kills a journaling app.

---

## 6. Known Gotchas (from research, before implementation)

1. **Silent format mismatch.** `AVAudioEngine`'s input node format (often 48kHz) won't match the recording file format or `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`. Feeding a mismatched buffer compiles cleanly and produces zero transcription, with no error thrown. Convert buffers explicitly; this is the most common time-sink reported by other implementers.
2. **First-run model download.** The on-device model asset downloads once via `AssetInventory` on first use. Never make a recording wait on it: take tier 2 for that entry and download in the background.
3. **Live latency is fine once warm.** Early iOS 26 beta reports cited ~14s to first result; on shipping iOS 26.5 it's closer to 0.3–0.5s time-to-first-volatile-result on a warm start. Verify on your own target device rather than trusting either number blindly.
4. **No custom vocabulary support** in SpeechAnalyzer, so it can't bias toward names/jargon the way some cloud APIs allow.
5. **Volatile vs. finalized must be tracked as two separate properties**: one constantly overwritten, one append-only. Concatenating them naively produces duplicated text.
6. **Info.plist requirements:** both `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` are required, even though you're not using dictation directly.
7. **Resamplers hold audio back.** `AVAudioConverter` keeps part of each buffer internally and only releases it when the input is marked as ended. Skip that drain and the last fraction of a second of every recording silently disappears, from the file and from the transcript. Flush the converter when the recording stops.
8. **Replacing `AVAudioRecorder` is the risk.** It writes the file for us today. Moving to an engine tap means we write it, so the file sink needs its own tests: feed synthetic buffers, read the file back, check format and frame count. That path can be tested on the simulator even though tier 1 can't.

---

## 7. Settings Exposed to the User

- **Transcribe with:** Live on this iPhone (default where supported) / On this iPhone / OpenAI (default elsewhere, requires API key). The footer explains what the selected one does: text as you talk, text right after you finish, or text from OpenAI after the recording is uploaded. On a device that can't run tier 1, the live option says so instead of failing quietly when the user records.
- **Use this iPhone when OpenAI fails**: the existing toggle, unchanged.
- **Language,** if not auto-detected from system locale
- A visible note when the OpenAI path is active that this recording will be sent to their configured provider, consistent with the privacy-first positioning of the rest of the app

---

## 8. Reference

MIT-licensed minimal implementation of Tier 1 (live mic → SpeechAnalyzer, SwiftUI, on-device):
`github.com/simplememofast/ios26-speechanalyzer-live-mic`

Worth reading before writing the session type. It demonstrates the buffer conversion step that's easy to get silently wrong.
