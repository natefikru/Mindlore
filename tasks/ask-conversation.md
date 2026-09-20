# Ask: make it talk like a person, and let it see the year

Branch: `feature/ask-conversation` from `feature/phase-a` at `dc81233`, in a new worktree
`.claude/worktrees/ask-conversation`. The phase-b worktree belongs to the B2 session; nothing here
touches it.

Status: revision 1, awaiting approval. Nothing below is built.

## What's wrong

Three separate faults, all reported from the phone:

1. **The answer talks about its own plumbing.** "These are the 15 entries that best match, out of
   213 that match at all. Do not describe the whole period from this sample; say what you are
   looking at" goes into every cut prompt (`AskPrompt.notes`). The second sentence is an
   instruction to narrate the sample, and the model obeys it. `system()` adds "Answer only from the
   entries provided" and "Cite every entry you use by its handle", which is where "your entry from
   March says" comes from.
2. **There is no voice.** The system prompt is six rules and a date. Nothing asks for warmth,
   nothing asks for plain sentences, so it answers like a search result with grammar.
3. **A year question sees two weeks.** `maxRankedEntriesOpenAI = 15` against a 24,000-character
   budget, both set when Apple's on-device model was the peer. Ask "what happened this year" over
   300 entries and 15 go out, and then the prompt makes the model confess it.

Four owner decisions, 2026-09-19: two-tier retrieval, chips stay but quieter, cost line goes and the
privacy sheet stays, warm persona that may ask one question back and may name a pattern but never
advises.

## Phase 1: the voice

`Mindlore/AI/Ask/AskPrompt.swift` only. No retrieval change, no UI change.

- [ ] Rewrite `system()`. It opens by saying who is speaking (someone who has read all of the
      journal and is easy to talk to), then the data-fence rules unchanged, then the voice: plain
      sentences, specific, warm, no clinical register. `PromptVoice.instruction` still decides
      person, so first/second/name keeps working.
- [ ] Add the silence rule, which is the whole complaint: never mention entries, searching,
      matching, samples, summaries, counts of what was read, or what it was given. Never
      "your entry from March says", never "based on your journal". Say what happened.
      Carry the contrast in the prompt itself, because a rule without an example gets half-obeyed:
      "You were fried the week of the deadline", not "Entry E4 (14 March) indicates fatigue".
- [ ] Permissions, from the owner decision: may name a pattern it actually sees across what it has,
      may ask one short question back. Never advice, diagnosis, a plan, or a verdict on a life.
      The existing "no advice, no diagnosis, no judgement" line stays, joined to that.
- [ ] Coverage without confession: if what it has doesn't answer the question, one plain sentence
      saying so and then what it does know. It may never explain that as a limit of a search.
- [ ] Citations move out of the prose. OpenAI already returns them in a separate `citations` field
      (`AskPrompt.schema`), so the instruction becomes "put the handles in the citations field,
      never write a handle in the answer". The on-device path has no structured output and needs
      `[E3]` markers in text, which `AskAnswerParser.parseMarkers` already strips, so the marker
      instruction is kept but gated on the provider rather than given to both.
- [ ] Rewrite `notes()`. Every note ends up inside the prompt, so each one gets an explicit "this
      is for you, not for the answer" clause:
      - `matchedNothing`: keep the fact, add that it must be said as "I don't have anything on
        that" rather than as a failed lookup.
      - `wasCut`: drop "say what you are looking at". Becomes the honest fact plus "don't mention
        it". After phase 2 this note only fires when digests couldn't cover the matched set either.
      - the range notes keep their current two shapes (named vs inherited), plus the same clause.
- [ ] Update `summaryRule` the same way: it may take counts from the rollup block, and may never
      mention that a block of counts exists.
- [ ] `AskServiceTests:367` asserts the `matchedNothing` sentence; update to the new wording.
      `AskPromptSafetyTests` must stay green untouched, since none of this changes the fences.

## Phase 2: two-tier retrieval

`AskRetrieval.swift`, `AskContextBuilder.swift`, `AskSources.swift`, `AskService.swift`.

The top entries still go in whole. Everything else that matched goes in as one line each, which is
what makes a year answerable at a price worth paying.

- [ ] Raise the caps: `maxRankedEntriesOpenAI` 15 -> 20, `openAIBudget` 24,000 -> 64,000. On-device
      numbers do not move; its budget is 6,000 for the whole session and one block can be 2,050.
- [ ] New slice `digests`, absolute like the others: `digestBudgetOpenAI = 24_000`, zero on device.
      Ordered after rollups and before continuity in `slices()`, so an unused digest slice still
      rolls forward into ranked.
- [ ] `Plan.digestEntryIDs: [UUID]`, filled from `matchedEntryIDs` in score order, skipping anything
      already ranked or carried by continuity, capped at `maxDigestEntries = 150` and by the slice.
      `digestCharacters` estimated from a per-line constant the way `AskRollups.estimatedCharacters`
      does, so the plan still reads no entry text.
- [ ] `AskSources.blocks(for:)` fetches digest ids as well and re-checks `isSendable` on each, the
      same gate as a full entry. A digest is entry text leaving the phone; it gets no shortcut.
- [ ] `AskContextBuilder` renders one fenced digest block: a handle, the date, the title, and the
      first ~90 characters of sanitized text, one line per entry, newest first. Handles come from
      the same map, so a digest entry is citable and its chip resolves like any other. The prompt
      says a digest line is a shortened entry, so a quote from one is never presented as the whole.
- [ ] `AskTurn` records how many went in full against how many went in one line (new stored
      property; no migration needed, this is unshipped). `sentEntryIDs` covers both, so the privacy
      sheet already lists them.
- [ ] Tests: `AskRetrievalTests` for the slice order, the cap, the skip of already-ranked ids, and
      the budget squeeze that drops digests entirely; `AskContextBuilderTests` for the rendered
      line shape and its sanitization; an `AskSourcesTests` case proving a non-sendable entry never
      reaches a digest line.
- [ ] Re-run `AskRetrievalQualityTests` and `AskRetrievalParaphraseTests` unchanged. They measure
      ranking, which this doesn't touch; if a number moves, the cause is a bug in the slice maths.

## Phase 3: the chat stops showing its work

`AskView.swift`, `AskTurnView.swift`.

- [ ] Delete the cost line and `AskService.Estimate`'s use in the composer, along with the
      `costDelay` task branch that computes it. The estimate machinery itself stays; only the line
      goes.
- [ ] Demote "What was sent" to a small icon-only button on the answer's footer row, keeping the
      `askWhatWasSent` identifier so the screenshot test still finds it.
- [ ] Chips stay, quieter: smaller type, secondary fill, no handle in the label (it is already only
      an accessibility identifier).
- [ ] The privacy sheet gains one row, "In full" against "In one line", from phase 2's counts.
- [ ] Empty-state copy loses "and say which ones they used", which is a promise about mechanics.
- [ ] `AskUITests:77` asserts the cost line exists; that assertion goes. `AskScreenshotTests` needs
      its shots retaken by whoever owns the phase-b simulator, not from here.

## Phase 4: prove it

- [ ] Unit run per CLAUDE.md, `-only-testing:MindloreTests`, parallel off, on this worktree's own
      simulator.
- [ ] `OpenAILiveTests` with the real key: one broad question ("what happened this year") against
      the demo journal, reading the answer for any surviving mechanics talk.
- [ ] Deploy to the iPhone with the 300-entry demo seed already on it and ask three questions: one
      about a person, one broad, one the journal has nothing on. Ask before deploying.
- [ ] Read-only sub-agent review against the baseline before the commit series lands.

## Not in this plan

Embeddings. `AskRetrievalParaphraseTests` measures indirect description at 0.00 over seven
questions, and digests widen what the model can see without making retrieval smarter. That argument
is still open in `tasks/archive/knowledge-graph.md`'s successor.
