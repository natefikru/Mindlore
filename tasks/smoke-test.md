# Device smoke test

Run on a physical iPhone. The simulator can't run on-device speech models, so it can't stand in for these steps.

## The loop

1. `scripts/device/deploy.sh` builds a Debug build and installs it. Entries on the phone are kept.
2. `scripts/device/launch.sh <run-id>` launches the app with its console attached and streams `MINDLORE` event lines (Claude runs this under a monitor). The stream ends when the app is killed, which several steps do on purpose.
3. The tester does the physical part of a step and says when it's done.
4. `scripts/device/pull-logs.sh <run-id>` copies `Library/Logs/Mindlore/diagnostics.jsonl` and any Mindlore crash reports into `.smoke/<run-id>/` and prints a timeline. The file survives force-quits, so it's the source of truth; the console is for watching live.
5. Compare the timeline with the expected events below. Fix, redeploy, repeat the failing step.

Events never contain entry text. `id` values are entry UUIDs, so one recording can be followed from `recorder.stopped` through `ingest.completed` to `transcription.completed`.

## Steps

### 1. First voice entry, online

Wi-Fi on. Tap the mic, allow the microphone, speak for about 15 seconds, tap Done. Note whether a Speech Recognition permission prompt appears.

Expect, in order:
- `recorder.started` with a `route` (for example `MicrophoneBuiltIn`)
- `recorder.stopped` with `seconds` near 15 and `bytes` near 720000
- `ingest.completed` with `converted=true`, `seconds` near 15, `audioBytes` far below `sourceBytes`
- `transcription.started` for the same `id`
- `transcription.authorization`: `initial=0 final=3` on the first run (0 is not determined, 3 is authorized); `initial=3` afterwards
- `transcription.module` with `module=SpeechTranscriber` on an iPhone 17 Pro
- `transcription.assets` with `downloading` then `installed` the first time, `alreadyInstalled` later
- `transcription.completed` with `characters` above 0

Failure signs: `transcription.failed` (its `error` names the cause), `module=DictationTranscriber` or `none`, `recorder.permissionDenied`.

### 2. Offline

Airplane mode on. Write an entry. Record a short voice entry.

Expect: `entry.created source=typed`, `save.completed` events while typing, `editor.closed deleted=false`, then the step 1 recording sequence with `transcription.assets status=alreadyInstalled` and `transcription.completed`.

### 3. Kill while typing

Start a written entry, type a sentence, and swipe the app away from the app switcher with the keyboard still up. Relaunch from the home screen.

Expect before the kill: `entry.created`, `save.completed trigger=throttle`, and `app.scenePhase phase=inactive` followed by `save.completed trigger=flush` when the app switcher opened. After relaunch: a new `app.launch` session. In the app, the entry is there, missing at most the last second of typing.

### 4. Lock mid-recording

Record, lock the phone for about 30 seconds, unlock, keep talking, tap Done.

Expect: `recorder.started`, `app.scenePhase phase=background` and later `phase=active`, no `recorder.interrupted`, and `recorder.stopped` whose `seconds` covers the whole recording including the locked time. Playback includes the locked portion.

### 5. Kill mid-recording

Record for about 20 seconds, then swipe the app away. Relaunch.

Expect: the old session ends after `recorder.started` with no `recorder.stopped`. The new session starts with `app.launch`, then `recovery.moved count=1` naming the same file, `ingest.completed` with `seconds` near 20, then transcription events.

### 6. Interruption

Start recording and have someone call or FaceTime-audio you. Decline or end the call, tap the record button to resume, tap Done.

Expect: `recorder.interrupted`, then `recorder.resumed from=interrupted`, then `recorder.stopped`.

### 7. Keep recordings off

Settings, turn off Keep Recordings. Record, wait for text, open and close the entry. Then record another and relaunch the app before opening it.

Expect for the first: `transcription.completed`, then `editor.closed deleted=false audioDiscarded=true`. For the second: its entry still shows a player after relaunch, since it was never closed after text arrived.
