# Mind: Tidy up where it's seen, and a replay of the window you're on

Branch `claude/mind-tidy-replay`, worktree `.claude/worktrees/mind-tidy-replay`, off main at
60270e9 (the #55 merge).

## Decisions (owner, 2026-09-23)

- **Tidy up moves to the map's top bar.** It becomes a round glass button to the right of the time
  control, carrying the number of questions to check. It shows only when there is at least one
  question, so a journal with nothing to tidy has no button. Hidden names stay in the drawer: its
  bottom row becomes "Hidden names · N", shown only when something is hidden, and it opens the
  same sheet.
- **Play replays the window that's selected, in 6 seconds.** Month, 3 months, Year, and All each
  play their own stretch. The map starts empty at the window's start (or at the first mention, if
  that is later), fills in as names are mentioned inside the stretch, and lands on exactly the map
  that was on screen before Play. This replaces the #55 rule that a replay always plays the whole
  journal whatever the window says.

## Design

**Tidy up.**
- `MindView` owns the review count and the session's skips (`skipped` moves up from
  `SearchPanel`, which takes it as a binding so the drawer and the sheet still agree). The count is
  `ReviewQueue.questions(...).count`, the same call `SearchPanel.refresh` makes today, recomputed
  in `MindView.refresh` (per graph revision), never in the view body.
- A `TidyUpButton` in `topBar`'s glass container: `sparkles` with the count, identifier
  `mindTidyUp`, accessibility label "Tidy up, N to check". Tapping it presents `TidyUpView` from
  `MindView`, with the hidden rows read then (`MindDirectory.rows(in:).hidden`). On dismiss it
  refreshes, so the count drops as questions are answered.
- The drawer's bottom row: "Hidden names" with the count, identifier `mindHiddenNames`, shown only
  when `rows.hidden` is non-empty, opening the same `TidyUpView`. `SearchPanel` stops computing
  `questionCount`.

**Replay.**
- `MindReplay.duration` goes from 10 to 6 seconds. That is 60 steps at 100 ms, publishing every
  fifth as before.
- `MindReplay.init(snapshot:window:end:)`: the start is the window's start (`window.interval(
  endingAt: end)?.start`), or the earliest link after it if that is later. For All, the earliest
  link, as today. Nil when nothing in the stretch was mentioned, which also disables Play.
- The frames. `MindMapSnapshot.since(_ start: Date?)` returns the snapshot with links and entry
  dates on or before `start` dropped (start-exclusive, like windows). The player holds that
  trimmed snapshot, and each step renders it with `window: .all` as of the step's date. That
  reuses `MindView.frame`, `MindMap.graph`, and `MindStats` unchanged, instead of threading a fixed
  start through all three. At the last step, all of the window's links are in, as of now, which is
  exactly the window's own map.
- `MindView.startReplay` passes the selected window. During a replay the window control keeps that
  window selected rather than showing none. Tapping a different window still ends the replay.
- The date chip shows the day ("14 Sep") for Month and 3 months, and the month ("Sep 2026") for Year
  and All. The haptic still ticks only when the month changes, so a Month replay doesn't buzz
  thirty times.
- `mind.replayed` gains `window` (its raw value).

## Files

- `Mindlore/Views/Mind/MindView.swift`: count, skips, top-bar button, sheet, replay window, chip.
- `Mindlore/Views/Mind/MindReplay.swift`: duration, windowed start, trimmed snapshot, chip format.
- `Mindlore/Graph/MindMap.swift` (`MindMapSnapshot`): `since(_:)`.
- `Mindlore/Views/Mind/SearchPanel.swift`: skips as a binding, Hidden names row, no count.
- `Mindlore/Graph/GraphServices.swift`: `recordMindReplayed(window:)`.
- `CLAUDE.md`: the Mind paragraph's replay sentence ("first mention to now over 10 seconds") and the
  drawer's Tidy up.

## Tests

Unit (Swift Testing), no new UI tests (owner):
- `MindReplayTests`: the clock runs 6 seconds; each window starts at its own start; a first mention
  later than the window's start starts there; nothing mentioned in the stretch means nothing to
  play; `since(_:)` drops a link on the start instant and keeps one just after; the last step's
  frame equals the window's own frame (`MindView.frame` compared node for node).
- `MindDrawerTests`: the count ignores skipped questions (the existing test moves with the count).
- `AIDiagnosticsPrivacyTests` already drives a replay against a sentinel; it passes a window now.

Existing UI tests that will break: `GraphUITests` lines 328-339 and `GraphScreenshotTests` lines
99-108 scroll the drawer for `mindTidyUp`. They get updated to tap the top-bar button instead and
run once locally (only those two tests). The replay UI test (`GraphUITests` 350+) should still
pass with a shorter run and gets run too.

## Not in scope

- A sliding window through the whole journal.
- Any change to what counts as a review question, or to `TidyUpView` itself.
- Reflect's Numbers button on the top bar's right side, which this now shares room with.

## Review (2026-09-23)

- Fixed: the privacy test now drives a replay trimmed to a window, not only all time.
- Checked and kept: the full drawer covers the top bar, and with it the Tidy up button. Lowering
  the drawer shows it again.
- Not checked: the top bar's width on a 375-point phone (play, four stretches, and the button come
  to about 366 points). The owner dropped the SE check.
- `InsightsUseTheJournalVocabularyTests.withTagsOffNoTagsAreSentEvenWithoutAGraph` crashed the
  test runner once in a full run and passed three runs on its own; unrelated to this branch.
