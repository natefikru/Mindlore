# Ask: answers that arrive as they are written

Branch: `feature/ask-streaming` from `feature/phase-a` at `d3430c7` (PR #18 merged), in
`.claude/worktrees/ask-streaming`. Simulator: the `iPhone 17 ask-conv` one, now free.

Status: revision 2, approved. Phases are ticked as they land.

## Why

Measured on the phone against the 300-entry demo journal, 2026-09-21: 4.0s, 5.0s, 6.3s, 7.4s, 8.4s.
Every one of those is a spinner on a blank screen, and the first sentence of the answer was ready
inside a second. Nothing in the design prevents streaming; it was never built.

Owner decisions, 2026-09-21: Ask over OpenAI only (titles and insights are background jobs nobody
watches, and Apple's on-device model keeps its current path); a stream that dies halfway discards
what arrived and shows the ordinary failure with Retry.

## The one piece of real design

Ask uses structured output: `{"answer": "...", "citations": ["E3"]}` against a strict schema, and
the citations are what the chips are built from. Streaming that means the answer arrives as partial
JSON, so showing text live needs to read a half-finished string out of a half-finished object, and
the chips can only land when the object closes.

`StreamingJSONString` does that **statelessly**: it re-scans the accumulated buffer after each
chunk, finds `"answer":"`, and decodes forward until an unescaped closing quote or the end of what
has arrived. Stateless on purpose, because the alternative keeps escape-decoder state across chunk
boundaries and `é` split across two frames is exactly the case that would break in the field
and not in a test. Re-scanning a few kilobytes per frame is free.

## Phase 1: the transport

- [x] `HTTPClient` gains `stream(_ request: URLRequest, body: Data?) async throws ->
      AsyncThrowingStream<Data, any Error>`. Three conformers to update: `URLSessionHTTPClient`,
      `FakeHTTPClient`, `UITestingHTTPClient`.
- [x] `URLSessionHTTPClient.stream` uses `session.bytes(for:delegate:)` with the same `TaskTracker`,
      so `AIError.from(error, bytesSent:)` still tells offline from died-mid-request. That is the
      machinery PR #15 fixed and it has to come along.
- [x] A non-2xx status is not a stream. The status is read from the response before any byte is
      yielded, the body is collected, and it goes through `OpenAIErrorMapper.map` exactly as the
      single-shot path does, so a bad key or a rate limit reads the same either way.
- [x] An idle watchdog: no frame for `streamIdleTimeout` (30s) fails the stream. A server that
      accepts the request and then stalls would otherwise hang until the 300s request timeout with a
      half-written answer on screen.
- [x] `SSEParser`: fed `Data`, emits payloads. Handles a frame split across chunks, CRLF, multiple
      `data:` lines in one frame, comment/keep-alive lines, and `[DONE]`. Pure and `nonisolated`,
      tested on its own.

## Phase 2: the generator

- [x] `StreamingTextGenerator`: `func stream(_ request: TextRequest) -> AsyncThrowingStream<Event,
      any Error>`, where an event is `.delta(String)` or `.finished(TextResult)`.
      `OpenAICompatibleTextGenerator` conforms; nothing else does, and `AskService` checks
      conformance rather than the provider kind, so a future provider opts in by conforming.
- [x] The body gains `"stream": true` and `"stream_options": ["include_usage": true]`, so the final
      chunk still carries token counts and `TextResult` keeps meaning what it means.
- [x] A server that rejects either flag falls back to the single-shot path for the rest of the
      session, remembered the way `JSONModeMemory` already remembers a rejected strict schema. Same
      shape, same reasoning: an OpenAI-compatible server is not necessarily OpenAI.
- [x] `StreamingJSONString` above, with its own tests: escapes (`\n`, `\"`, `\\`), a `\uXXXX` split
      across a boundary, a lone trailing backslash, and text containing `","citations":` which must
      not be read as the end of the field.

## Phase 3: the service

- [ ] `AskService.answer` appends the assistant turn empty with `isStreaming = true`, then updates
      its text per delta. `stillOpen(askedIn:)` is re-checked on every delta, because a conversation
      can be deleted or replaced while the answer is arriving.
- [ ] Citations, diagnostics and persistence all happen once, at the end, from the complete JSON
      through the existing `AskAnswerParser.parseJSON`. Nothing partial is ever written to the store.
- [ ] A mid-stream failure removes the streaming turn and appends the ordinary failure turn, so it
      behaves exactly like a dropped request does today, Retry included (owner, 2026-09-21).
- [ ] `ask.answered` gains `firstChunkMilliseconds` and `streamed`. Counts and durations only, as
      ever. Nothing about a delta's text is ever logged.
- [ ] Stop. The button only exists while a stream is running, and **keeps** what arrived, marked as
      stopped, with no chips: the user chose to stop, so it is not a failure and there is nothing to
      retry. Ruled on by the owner, 2026-09-21: keep the partial text.

## Phase 4: the screen

- [ ] `AskTurnView` renders the growing text; still `Text(verbatim:)`, so nothing an entry contains
      becomes markdown while it streams. A caret or a quiet pulse while it is running.
- [ ] `askThinking` shrinks to what it should always have been: the wait before the first delta.
- [ ] The scroll follows the growing answer, coalesced rather than per delta, or a long answer
      fights the user's thumb the whole way down.
- [ ] `UITestingHTTPClient` gains a streaming stub, or the Ask UI tests stop covering the real path.

## Phase 5: prove it

- [ ] Unit run per CLAUDE.md on this worktree's simulator.
- [ ] `OpenAILiveTests` gains one streaming case that prints time to first delta and total.
- [ ] Device: the same three questions against the 300-entry demo journal, reading
      `firstChunkMilliseconds` against today's 4.0s to 8.4s totals. That number is the whole point of
      the phase, and it can only be measured there.
- [ ] Read-only sub-agent review before the PR, with the baseline taken first.

## Risks worth naming

- **Every delta touches main-actor state.** Deltas arrive tens of times a second and each one
  mutates an `@Observable` turn. If SwiftUI struggles, coalesce on a short timer rather than
  per delta; measure before optimising.
- **Cancellation is now two things.** A cancelled `Task` (screen left, conversation switched) and an
  explicit Stop, which are different outcomes from the same interruption. Both have to leave
  `isRunning` false and the store consistent.
- **Not a cost change.** Streaming does not alter tokens sent or billed. It changes when text
  appears, nothing else.
