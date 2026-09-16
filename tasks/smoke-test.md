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

## AI steps (added for the AI providers PR)

These need AI on with an OpenAI key saved on the phone, except step 8, which runs before anything else.

### 8. Upgrade over real entries

Deploy over the previous build without deleting the app. Open the list.

Expect:
- Every entry that was there before is still there, in the same order, with its own date.
- `store.entryDatesRepaired` with a `count` matching the number of entries, once, on the first launch of this build. Later launches don't log it.
- No `store.openFailed`.

### 9. Key setup

Settings, AI, turn AI on, paste the key, Test connection.

Expect: `ai.keySaved`, then `ai.connectionTested` with `ok=true` and a `models` count. The key itself never appears in the log.

### 10. Voice entry through OpenAI

Record about 15 seconds and stop.

Expect: `transcription.started` with `engine=openai:gpt-transcribe`, `ai.request` with `capability=speech` and a duration, `transcription.completed` with the same engine. The entry's text appears, and its title follows if titles are on. Insights run once the entry closes or Done is tapped.

### 11. Airplane mode falls back to this iPhone

Turn on airplane mode, record 10 seconds, stop.

Expect: `ai.error` or `transcription.fallback` with an offline reason, then `transcription.completed` with `engine=apple`. The editor shows "Transcribed on this iPhone". `textAttempts` is not spent: the entry's next cloud attempt still works once the network is back.

### 12. Bad key

Settings, AI, replace the key with `sk-not-a-real-key`. Record 10 seconds.

Expect: `ai.error` with `error=ai.invalidKey`, `transcription.fallback`, text from Apple. Force-quit and relaunch: no new `ai.request` for that entry, because a permanent failure isn't retried. Put the good key back afterwards.

### 13. Long recording

Record 25 minutes (or set a shorter chunk target and record 5) and stop.

Expect: `transcription.chunks` with `count` above 1 and per-chunk seconds, one `ai.request` per chunk, one `transcription.completed`. The text reads continuously across the joins.

### 14. Journal pages, real handwriting

Photograph five pages of a real journal, reorder one, confirm, wait.

Expect: `pages.added` with the byte size per page, `pages.confirmed` with `transcribe=true`, `pages.transcription.pageCompleted` per page with upload bytes and tokens, `pages.transcription.completed`. Compare the text against the pages: note anything wrong, especially names and dates. If a page has a date, check the entry offers it.

Also note: stored bytes per page, and whether the app stays responsive with five pages.

### 15. Pages offline

Airplane mode on, photograph two pages, confirm.

Expect: `ai.offline` once, no repeated requests. Turn airplane mode off with the app still open: transcription finishes on its own without touching the app.

### 16. Pages: edit, restart, and typing over

Open a transcribed photo entry. Edit pages, cancel: the text is unchanged. Edit pages, remove a page, confirm the warning.

Expect: `pages.restarted`, then a fresh transcription of the remaining pages, and review again. Then type into an entry while its pages are still transcribing: your text stays, and "Replace with page transcription" brings the page text back.

### 17. Titles offline

Airplane mode on, with titles set to This iPhone. Write an entry and tap Done.

Expect: `title.started` with `model=apple:foundation` and `title.completed`. With Apple Intelligence unavailable, expect `title.unavailable` with the reason instead.

### 18. Insights once, and Run AI

Write an entry, tap Done, open Insights.

Expect: `ai.pass` with `moment=finished`, `insights.started`, `insights.completed` with token counts. Edit the entry and close it: no second `insights.started`. The sheet says the insights are out of date; Update insights runs once more. Run AI on an entry from before AI was on: it runs.

### 19. Cleanup, applied and reverted

With a voice entry, Review the cleaned-up text, Replace my text, then View original text.

Expect: `cleanup.applied`, then `cleanup.reverted`. The original comes back exactly. Regenerate insights and check "View original text" is still there.

### 20. Force-quit during insights

Tap Done and force-quit while insights are running. Relaunch.

Expect: the run completes after launch, `insightsAttempts` reaches 1, and there is exactly one `insights.completed` for that entry.

### 21. Key survives relaunch and lock

Lock the phone, wait a minute, unlock, record an entry.

Expect: cloud transcription still works, so the key was readable after first unlock.
