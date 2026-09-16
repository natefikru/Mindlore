# Live on-device transcription (three-tier hierarchy)

Branch: `worktree-transcription-tiers`, off `main`.

## What changes and why

`docs/transcription-hierarchy.md` describes four tiers. Tier 4 (OpenAI Realtime streaming) is cut: it costs tokens continuously, needs a live connection for the whole recording, and buys nothing over the batch cloud call for a journaling app. The spec drops to three tiers.

Tiers 2 and 3 already ship. `SpeechAnalyzerTranscriber` runs `SpeechAnalyzer` against the finished file; `OpenAICompatibleTranscriber` handles the cloud; `TranscriberRouter` picks per entry and the shipped default is OpenAI. Tier 1, live text while the user talks, does not exist.

So: live on-device runs automatically on devices that can run it, and everything else falls through to what already works.

## Decisions

- **All three tiers are user-visible choices.** `SpeechEngine` grows from two cases to three: `onDeviceLive`, `onDevice`, `cloud`. The "Transcribe with" picker shows all three, and the user picks the one they want.
- **`onDeviceLive` is the default.** `speechEngine` becomes a computed default over an availability closure, the same shape `titleGenerator` already uses: a stored choice wins, and with nothing stored the answer is `onDeviceLive` where the device supports it and `cloud` where it doesn't. This flips today's shipped default of `.cloud`.
- **Picking live still falls back to batch on-device.** The live gate is `SpeechTranscriber.isAvailable`, a supported locale, and the model asset already installed. A missing asset never blocks recording: kick off the install in the background and take `onDevice` for this entry. That fallback is automatic and stays inside the Apple path, so it never surprises anyone.
- **Picking `onDevice` never starts a live session**, even on a phone that could run one. It is the choice for someone who wants on-device text without live text on screen.
- **Live text becomes the entry's text** when the session stayed healthy for the whole recording. The entry is saved with `awaitingText: false` and `textGeneratedBy: "apple.live"`, so no second pass runs.
- **Any doubt falls back to batch.** A dropped buffer, an interruption, a converter error, an engine restart, or empty final text all mark the session unhealthy, and the entry is saved `awaitingText: true` exactly as today, picked up by `onDevice`. The audio file is written first and independently, so a live failure can never cost a recording.

## The recorder rewrite is the risky part

`AudioRecorder` uses `AVAudioRecorder`, which hands back no buffers. Live needs `AVAudioEngine` with a tap. One engine, two sinks:

1. Convert each input buffer to the existing 24 kHz mono 16-bit PCM format and write it to `active/<uuid>.caf` via `AVAudioFile`. Same format, same path, same `RecordingIngestor` downstream.
2. Hand the same converted buffer to the live session, if one is running.

The file write happens first in the tap and never depends on sink 2. Metering moves from `averagePower(forChannel:)` to RMS computed off the buffer; `normalizedLevel(decibels:)` and its tests stay.

Gotcha from the spec worth repeating: the input node's format (usually 48 kHz) will not match either the file format or `SpeechAnalyzer.bestAvailableAudioFormat`. A mismatched buffer compiles and transcribes nothing, silently. Convert explicitly and assert the conversion in a test.

## Phases

### 1. Rewrite the spec
- [x] `docs/transcription-hierarchy.md`: three tiers, the user's picker on top of them, Apple as the default where available. Update §3 decision flow (it now starts at the setting, not at capability), §4 (drop `RealtimeProvider`), §7 settings.

### 2. Live session, isolated and testable
- [x] `LiveTranscriptionSession` protocol: start, feed buffer, finish, plus `volatile` and `finalized` as two separate properties (never concatenated blind).
- [x] `SpeechAnalyzerLiveSession`: `SpeechAnalyzer` + `SpeechTranscriber` with volatile results, fed from an `AsyncStream<AnalyzerInput>`.
- [x] `LiveTranscriptionAvailability`: pure function over injected capability flags, so it tests on the simulator.
- [x] `FakeLiveSession` + tests for the healthy/unhealthy outcome rules.

### 3. AudioRecorder on AVAudioEngine
- [x] Replace `AVAudioRecorder` with an engine + tap, dual sink, same output file contract.
- [x] Buffer conversion tested against synthetic `AVAudioPCMBuffer`s (no mic needed).
- [x] Pause, resume, interruption, discard, and stop keep their current behavior and diagnostics.
- [x] File sink tested directly: feed buffers, read the file back, check frame count and format.

### 4. Wire it through
- [x] `RecordingView` shows finalized text with the volatile tail appended in a dimmer style.
- [x] `RecordingIngestor.ingest(_:liveText:)` applies live text at insert time.
- [x] Confirm the automatic AI pass still fires for an entry that skipped the transcription coordinator (`AIPassTrigger`, "a recording's text arriving").

### 5. Settings and copy
- [x] `speechEngine` becomes stored-choice-wins over an `onDeviceSpeechAvailable` closure, mirroring `titleGenerator`. Update `SettingsStoreTests`, which currently asserts the `.cloud` default.
- [x] `AIFeatureSettingsViews`: reorder the picker so `This iPhone` reads first, and say in the footer that a capable iPhone shows text as you talk while OpenAI arrives after the recording.
- [x] `AISettingsView` summary row follows the same value.
- [x] Check `AIConfigurationUITests`, which drives `speechEnginePicker` and assumes the current order and default.

### 6. Diagnostics and smoke steps
- [x] `live.availability`, `live.started`, `live.dropped` (reason), `live.finished` (character count, seconds), `live.usedAsEntryText`. Counts and codes only, no text.
- [ ] `DiagnosticsPrivacyTests` doesn't exist on main (it arrives with the knowledge graph branch). The live events carry locales, counts, and reason codes only, so there is nothing to redact; add the sentinel pass when the branches meet.
- [x] Add the live steps to `tasks/smoke-test.md`: text appears while talking, a phone call mid-recording falls back to batch, airplane mode with no key still produces text.

### 7. Verify
- [x] Full unit suite, parallel testing off: 332 passed.
- [x] UI tests for the screens that changed: `AIConfigurationUITests` (now also checks the picker offers three options), `AISettingsUITests`, and `EntryDateUITests` as a control. All pass on a dedicated simulator. No UI test drives the recording screen, before or after this branch.
- [x] Device smoke, session 1 (2026-09-16, iPhone 17 Pro). See the review below. First-run download and headphones are still unrun (`docs/remaining-work.md`).

## Review

### Three bugs found before any device run

**The buffer stream leaked on every non-live recording.** `AudioRecorder` yields each written buffer
into an unbounded `AsyncStream` for a transcriber to read. On a recording where live never starts
(OpenAI picked, unsupported locale, asset still downloading) nobody reads it, so every buffer queues
for the length of the recording: roughly 6 MB a minute, 150 MB on a 25-minute entry. Fixed with
`stopBuffering()`, called the moment the app knows live isn't running, which finishes the stream
while the file keeps being written. Covered by `droppingTheTranscriberKeepsWritingTheFile`.

**The last seconds of speech could vanish.** `finish()` stopped the recorder and then immediately
finished the live session, while the task draining the buffer stream was still feeding it. The
session would close its input early and silently return a truncated transcript, which then became
the entry's text. Fixed by holding the feed task and awaiting it before finishing the session.

**Every recording lost its last moment.** `AVAudioConverter` keeps back part of each buffer it
resamples and only releases it when told the input has ended. Nothing told it, so up to about 85 ms
at the end of every recording never reached the file, or the live transcriber: often the last word.
Measured directly: six 100 ms buffers produced 13,664 frames instead of 14,400. `BufferConverter.flush()`
now drains it, and `RecordingWriter.finish()` and the live session's `finish()` both call it. Six
buffers now produce 14,416, the extra 16 being the filter's tail.

### How that third bug nearly shipped

Three writer tests failed on first run by a few hundred frames. I explained the gap as resampler
startup latency "emitted on the first call", which had the sign wrong (the files were short, not
long), loosened the tolerances to 500 frames, and moved on. The real cause only surfaced when a new
test failed by a different amount and a probe printed the actual lengths. The tolerances are back to
32 frames and every stream test now checks that the transcriber received exactly the frames the
file holds.

### A false alarm worth remembering

`EntryDateUITests`, which this branch never touches, failed with "unexpected termination" and no
crash report, and passed on `main`. It looked like this branch broke app launch. It didn't: another
worktree was running its own UI tests on the same `iPhone 17` simulator, and both runs install and
terminate the same bundle ID. On a simulator of its own the test passes.

### On the device

Runs `live-01` to `live-04` on an iPhone 17 Pro.

| Check | Result |
|---|---|
| Picker offers three options, choice persists | pass |
| Text while talking | pass: live started 90 ms after recording, 48 kHz mic converted to 16 kHz |
| Last word after an immediate Done | pass in text and audio; the drain recovered 50 ms on one recording |
| Siri interruption | live text discarded, file transcribed on-device in 0.3 s |
| Resume after Siri | **failed on first tap**, fixed, passes with one tap |
| This iPhone, OpenAI | never started a live session; OpenAI returned text in 2.2 s |
| Lock mid-recording | whole recording kept; live text kept running while locked |
| Force-quit mid-recording | recovered on relaunch with 22.4 s of audio, transcribed |

**Resume after an interruption needed two taps.** iOS posts the interruption's end several seconds
before it lets the app reactivate its audio session. `setActive(true)` threw `!pla` 1.5 s after
Siri's end notice and succeeded 5.2 s after it, on two separate runs. The old code swallowed that
error with `try?`, so the engine then failed with a generic `'what'` and the tap looked dead. Resume
now retries for up to 8 seconds, showing "Resuming…", logs one `recorder.resumeFailed` with the
stage if it gives up, and rebuilds the tap for the input's current format, since Siri and calls can
change it. Measured on the device: one tap, 14 attempts, resumed.

**Route changes would have stopped recording silently.** `AVAudioRecorder` carried on through
headphones connecting; `AVAudioEngine` stops itself and posts `AVAudioEngineConfigurationChange`.
Nothing listened for it, so the timer would freeze with the screen still saying Recording. Found by
reading the code after the resume bug, not on the device; the handler restarts the engine and marks
the gap, and it has not yet been seen running on a phone.

**`recorder.stopped` reported the length before the drain,** so it disagreed with `ingest.completed`
by up to 50 ms. It now reads the length after the file is closed.

Two follow-ups came out of the session and are tracked in `docs/remaining-work.md`: the Insights
button should generate, and the player needs 10-second skips and a scrubber.

### Not done

Tier 1 has never run. Nothing here proves live transcription works, only that everything around it
behaves: the availability rules, the conversion, the file sink, the settings default, and the entry
that comes out the other end. The device steps in `tasks/smoke-test.md` (22 through 27) are the
whole verification, and step 27 re-runs the existing lock, force-quit, and long-recording steps
because `AVAudioEngine` now writes the file that `AVAudioRecorder` used to.
