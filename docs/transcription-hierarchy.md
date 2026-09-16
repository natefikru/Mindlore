# Transcription Hierarchy — Feature Spec

How Mindlore captures and transcribes voice entries, across four tiers of fallback.

---

## 1. Goal

Give the user live, on-screen text while they talk, backed by a system that never loses a recording — while supporting multiple transcription backends without forcing a single point of failure.

This is not "pick one transcription method." It's a fallback ladder: one default path that covers nearly everyone, with automatic and manual escape hatches for the cases it doesn't cover.

---

## 2. The Four Tiers

### Tier 1 — On-device live (SpeechAnalyzer, streaming)

**Default for every recording.**

- Apple's `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26+), fed live from `AVAudioEngine`
- Free, private, fast, works fully offline
- Produces two text states as the user speaks:
  - **Volatile** — realtime guess, rewritten continuously
  - **Finalized** — committed text, never rewritten
- This is what gives the "text appears as you talk" UX

**Use when:** locale is supported, device is iOS 26+, the on-device model asset is installed.

### Tier 2 — On-device batch (SpeechAnalyzer, file-based)

**Automatic fallback within the same framework.**

- Same `SpeechAnalyzer`/`SpeechTranscriber` API, just run against the finished `.m4a` file instead of a live buffer — no `.volatileResults` needed
- Nearly free to add since it's the same transcriber underneath

**Use when:** the live session dropped mid-recording — backgrounding, a phone call interrupted the app, the engine tap failed. Instead of losing the entry, re-run transcription against the audio file that was already saved to disk.

### Tier 3 — Cloud batch (OpenAI Whisper API)

**Fallback for what on-device can't handle.**

- Requires the user's own API key (BYOK) and network connectivity
- Costs the user tokens

**Use when:**
- The spoken locale isn't in SpeechAnalyzer's supported set (its coverage is narrower than Whisper's 100+ languages)
- The on-device model isn't installed and the user is offline (first-run download didn't happen and there's no connectivity to fetch it)
- The user manually opts in because on-device accuracy is poor for their voice/accent

### Tier 4 — Cloud live (OpenAI Realtime API, streaming)

**Opt-in power-user toggle. Not a default for anyone.**

- Streams audio continuously to OpenAI over a live connection
- Costs the user tokens continuously while they talk, requires an active connection throughout
- Only reason to use it: a user specifically prefers cloud transcription quality over on-device, for their voice or language

---

## 3. Decision Flow

```
Start recording
     │
     ▼
Tier 1 available? (iOS 26+, locale supported, model installed)
     │
     ├── YES → Live on-device transcription
     │              │
     │              ├── Completes normally → done
     │              └── Interrupted (background/call/tap failure)
     │                       → fall to Tier 2, re-run against saved audio
     │
     └── NO → Check user's Settings preference
                    │
                    ├── "Prefer cloud" set → Tier 4 (if enabled) or Tier 3
                    └── Not set → Tier 3 (Whisper), one-time per entry
```

**Where user choice enters:** Tiers 3 and 4 are never silently substituted for cost or connectivity reasons alone — a user sets "if on-device isn't working, use my API key" once in Settings, not per-recording. The exception is the automatic Tier 1 → Tier 2 fallback, which is invisible and required (see §5).

---

## 4. Architecture

One protocol, four implementations, selected by a resolver — not four code paths sprinkled through the app.

```swift
protocol TranscriptionProvider {
    var isAvailable: Bool { get async }
    func transcribeLive(from stream: AsyncStream<AVAudioPCMBuffer>) -> AsyncStream<TranscriptionResult>
    func transcribeFile(at url: URL) async throws -> String
}

enum TranscriptionResult {
    case volatile(String)   // rewritten continuously, never persisted
    case finalized(String)  // committed, appended, persisted
}
```

- `OnDeviceLiveProvider` — Tier 1
- `OnDeviceBatchProvider` — Tier 2 (can share most code with Tier 1; same transcriber, different input)
- `WhisperProvider` — Tier 3
- `RealtimeProvider` — Tier 4

A `TranscriptionResolver` picks the provider at record-start based on device capability + user settings, and hands off to Tier 2 automatically on Tier 1 failure.

---

## 5. Interaction With Progressive Save (non-negotiable)

Regardless of which tier is active, the save order is fixed:

1. **Audio saves to disk first**, continuously, as it's captured — independent of transcription succeeding
2. **Transcript saves second**, as finalized segments commit
3. **Analysis runs last**, only once a transcript exists

This means a failure at any tier is always recoverable: the audio file already exists, so falling back to a different tier just means re-running transcription against a file that was never at risk. No tier failure should ever be able to lose a recording — that failure mode is the one thing that kills a journaling app.

---

## 6. Known Gotchas (from research, before implementation)

1. **Silent format mismatch.** `AVAudioEngine`'s input node format (often 48kHz) usually won't match `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)`. Feeding a mismatched buffer compiles cleanly and produces zero transcription — no error thrown. Convert buffers explicitly; this is the most common time-sink reported by other implementers.
2. **First-run model download.** The on-device model asset downloads once via `AssetInventory` on first use. Show progress for this path specifically — don't let it look like a hang.
3. **Live latency is fine once warm.** Early iOS 26 beta reports cited ~14s to first result; on shipping iOS 26.5 it's closer to 0.3–0.5s time-to-first-volatile-result on a warm start. Verify on your own target device rather than trusting either number blindly.
4. **No custom vocabulary support** in SpeechAnalyzer — can't bias toward names/jargon the way some cloud APIs allow.
5. **Volatile vs. finalized must be tracked as two separate properties** — one constantly overwritten, one append-only. Concatenating them naively produces duplicated text.
6. **Info.plist requirements:** both `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` are required, even though you're not using dictation directly.
7. **No watchOS support** for SpeechAnalyzer, if that's ever a target.

---

## 7. Settings Exposed to the User

- **Transcription source:** On-device (default) / Prefer cloud (requires API key)
- **Language,** if not auto-detected from system locale
- A visible note when Tier 3/4 is active that this recording will be sent to their configured provider — consistent with the privacy-first positioning of the rest of the app

---

## 8. Reference

MIT-licensed minimal implementation of Tier 1 (live mic → SpeechAnalyzer, SwiftUI, on-device):
`github.com/simplememofast/ios26-speechanalyzer-live-mic`

Worth reading before writing the resolver — it demonstrates the buffer conversion step that's easy to get silently wrong.
