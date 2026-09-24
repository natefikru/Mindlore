# Chat about this entry

Branch `claude/chat-about-entry`, worktree `.claude/worktrees/chat-about-entry`, off main at 37375c8.

From an open entry (the editor's More menu) or its insights sheet (that sheet's More menu), jump
to the Chat tab with a new conversation about that entry: the entry goes to the model whole on
every turn, the field is focused, and nothing is sent until the author types a question.

## Decisions (owner, 2026-09-23)

- **Context.** The entry goes in first and whole. The rest of the journal is still searched as
  usual, so "has this happened before?" can reach other entries. Insights (summary, mood, names)
  are not added: the entry's own words are the context.
- **History.** The tie lasts only while the conversation stays open. No model change, so no CloudKit
  schema deploy. Reopened from History it goes on like any other conversation, carried by what
  its answers cited (the continuity slice), which is usually the entry.
- **Empty state.** One tappable card ("About this entry", title, date) that opens the entry, the
  field focused, placeholder "Ask about this entry". No suggestions.
- **Insights sheet.** In its More menu, the same as the editor. No new chrome.
- **Drafts** (my call). The item shows only when `InsightsCoordinator.canRunAI(on:)` allows it: a
  draft, an entry awaiting text, or unapproved pages would open a chat with nothing to send. Done
  first, then chat.

## Design

The plan decides and the renderer spends, as the rest of Ask already works.

- `AskIndex.DocumentInput` / `Document` gain `textCharacters` (the entry's full length, uncapped),
  set in `AskSources.documents`. `blockCharacters` stays capped at 2,000 for every other use.
- `AskRetrieval.plan(... focusEntryID:)`. Before anything else, if the focus is in the index and
  `isSendable`, it takes its room: all of its text, capped at `maxFocusCharactersOpenAI` (24,000)
  on OpenAI and at the whole budget on device. That cost comes off the budget before about,
  rollups, digests, continuity, and ranked divide the rest. The focus is in `taken`, so ranked,
  continuity, and digests skip it. `Plan.focusEntryID` / `focusTextLimit`; `entryIDs` puts it
  first, so `AskSources.blocks` fetches it under its own eligibility re-check.
- With a focus, a question that matches nothing ("what do you make of this?") does not fall back
  to the newest five entries and does not get the "nothing here is about this" note. The focus is
  the answer's material.
- `AskContextBuilder.render` adds the focus block first, with `addEntry(limit:)` trimming at
  `focusTextLimit` instead of `maxEntryCharacters`. Same sanitizing, same fence, same handle rules.
- `AskPrompt.focusNote(handle:)`: "The author opened this conversation from one entry, E1, given in
  full. Take each question as being about it unless they say otherwise ... Never mention how the
  conversation started." On device `AskService.budget` holds back `focusNoteHeadroom` for it.
- `AskService.focusEntryID`, set by `newConversation(about:)`, cleared by `newConversation()` and
  `open(_:)`. Passed to the plan on every turn. `ask.retrieved` gains `focused` (a bool).
- `AskFieldRequest.entryID`, `AppRouter.showAsk(question:aboutEntry:)`, `PendingJump.ask(_, _)`, so
  a jump made behind a full-screen cover still carries the entry. `AskView` takes it: an entry
  request always starts a new conversation about it, even over a running answer, since that is
  what the tap asked for.
- The menu items flush the saver, then `router.showAsk(question: nil, aboutEntry:)`. The jump's
  dismiss token already closes the insights sheet (`EntryEditorView` line 278). The editor stays
  on Journal's stack with no close rules run, as with every other cross-tab jump.

## Files

- `Mindlore/AI/Ask/AskIndex.swift`, `AskSources.swift`: `textCharacters`.
- `Mindlore/AI/Ask/AskRetrieval.swift`: focus in `Plan`, `plan(focusEntryID:)`, fallback rule, `wasCut`.
- `Mindlore/AI/Ask/AskContextBuilder.swift`: focus block first, `addEntry(limit:)`.
- `Mindlore/AI/Ask/AskPrompt.swift`: `focusNote`, `focusNoteHeadroom`.
- `Mindlore/AI/Ask/AskService.swift`: `focusEntryID`, `newConversation(about:)`, budget, diagnostics.
- `Mindlore/Views/Shell/AppRouter.swift`: request and jump carry the entry.
- `Mindlore/Views/Ask/AskView.swift`: take the request, focus card, placeholder.
- `Mindlore/Views/EntryEditorView.swift`, `Views/Insights/EntryInsightsView.swift`: menu items.
- `CLAUDE.md`: a short paragraph under Ask.

## Tests

Unit (Swift Testing):
- `AskRetrievalTests`: the focus goes first and whole past 2,000 characters; capped at 24,000 on
  OpenAI; not sendable means no focus; never ranked or digested
  twice; a question matching nothing keeps the focus and skips the recency fallback.
- `AskServiceTests`: the first request carries the whole entry and the focus note, and a follow-up
  with no matching words still does; `newConversation()` and `open(_:)` clear the focus; a draft
  focus sends nothing of the draft.
- `AskContextBuilderTests`: the focus block renders first, trimmed at its own limit, sanitized.
- `IntentTests` (router): `showAsk(aboutEntry:)` carries the entry, including behind a cover.
- `DiagnosticsPrivacyTests` already runs Ask against a sentinel; add a focused conversation to it.

No UI test (owner, 2026-09-23): unit tests only.

## Not in scope

- Persisting the tie on `AskConversation` (a model change).
- Sending insights, names, or loose ends with the entry.
- Starter questions, a visible button on the insights sheet, or a Chat item in list swipe actions.
- Any change to the Ask prompt for ordinary conversations.

## Plan review (2026-09-23)

- **Fixed: an abandoned answer blocked the new conversation's send.** `isRunning` was one flag on
  the service, cleared only when the old `answer()` returned. Opening a chat about an entry over a
  running answer starts a new conversation, and on device there is no stream to cancel, so the old
  generate call held the send button for seconds. `isRunning` is now `runningIn == conversationID`:
  running belongs to the conversation that asked, and the old answer still finishes into nothing
  through `stillOpen`. The streaming reader's `defer` clears only its own task for the same reason.
  This also covers opening a conversation from History mid-answer, which had the same flaw.
- **Fixed: `ask.retrieved`'s `focused`** now reports whether the entry actually went out, not
  whether it was planned (it can have become a draft since the index was built).
- **Kept: on device the focus can take the whole budget.** The owner doesn't expect this to be used
  with the on-device model, so there is no on-device test and no further work there. That budget
  is about 3,300 characters,
    where one other entry's block is up to 2,050. On OpenAI the focus is capped at 24,000 of 64,000,
  so the journal is still searched.
- **Checked, no change:** the overhead arithmetic against `blockCharacterEstimate`, the privacy gate
  (the focus passes the index's `isSendable` and `AskSources.blocks`' re-check), and the jump
  behind a full-screen cover.
- Added to tests: `AskServiceTests`, a send in a new conversation goes through while the abandoned
  answer is still being generated.
