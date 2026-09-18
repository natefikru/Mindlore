# A9: how Ask finds things, and what to replace it with

Research only. No code changed. Branch `feature/a9-ask-retrieval`, based on
`feature/phase-a7-ask` (Ask is not on `feature/phase-a` yet).

## What Ask does today

Every question runs this, start to finish, on the main actor:

`AskService.answer` (`Mindlore/AI/Ask/AskService.swift:201`) calls
`AskSources.journal(in:)`, which fetches **every** `Entry`, **every** `EntityLink`, and **every**
`Entity` (`AskSources.swift:16-46`), resolves merges, builds two dictionaries, and hands the whole
journal to `AskContextBuilder.build`.

The builder (`AskContextBuilder.swift:67-131`) then runs four tiers against that array:

1. **Entities the question names.** Substring match of the question against every entity name and
   alias. For each hit, up to 10 linked entries, reduced to just the sentences naming that entity.
2. **Keyword match.** `keywords(in:)` splits the question on word boundaries, drops words under
   three letters and anything in a hand-written 100-word stop list (`:137-150`), then scores each
   entry by how many distinct keywords appear in `title + text`. Matching is a case-insensitive
   word-boundary regex (`NameMatching.range`).
3. **Date range**, if `AskDates` finds one in the question.
4. **Fallback**: only if tiers 1 to 3 produced nothing, the 5 newest entries.

Blocks are appended until a character budget runs out: 24,000 for OpenAI, 6,000 minus the system
prompt and answer headroom on device (`AskService.swift:294-305`). Each entry is cut to 2,000
characters at a sentence boundary. A block that doesn't fit is skipped whole.

## The six problems

### 1. Retrieval is driven by the current question's literal words, with no conversation state

This is the real version of "the conversation is stuck on the subset."

Retrieval does re-run every turn. That part of the original diagnosis was off. The actual failure is
worse: turn 2 retrieves as if turn 1 never happened.

Ask "What's going on with Maya?" and tier 1 fires, pulling Maya's entries. Then ask the obvious
follow-up: "Why do you think that started?" Run that through `keywords(in:)`. `why`, `do`, `you`,
`think`, `that` are all stop words. `started` is not in the list, so it survives and matches
every entry containing the word "started." No entity is named, so tier 1 is silent. No date, so
tier 3 is silent. The prompt is now a pile of entries about unrelated things that happen to use the
word "started," and Maya is gone.

If the follow-up were "Why?" alone, every word is a stop word, all three tiers produce nothing, and
tier 4 sends the 5 most recent entries. The model is asked to explain something about Maya while
looking at last Tuesday's grocery run.

Compounding it: `history()` (`:308-326`) sends prior questions and answers as message text but
**never re-sends the blocks those answers came from**. The model can see it said something about
Maya. It cannot re-read the entry it said it from. So it either refuses or fills the gap.

Nothing carries the conversation's subject into retrieval. That single missing piece explains most
of what feels broken.

### 2. Full-corpus scan on every question, and on every pause in typing

`AskSources.journal` has no predicate, no limit, and no cache. It is also reached from
`AskService.estimate`, which `AskView` calls on a debounce as the user types
(`AskView.swift:108-122`), to render "Asking sends 12 entries, about 9,000 characters."

So every pause in typing fetches the entire journal, the entire link table, the entire entity
table, rebuilds the merge map, and runs all four retrieval tiers, on the main actor. At the 300
entry demo seed this is invisible. At 5,000 entries with a few thousand links it is a visible stall
on each keystroke pause. At 20,000 it is unusable.

### 3. No relevance ranking worth the name

Tier 2 scores an entry by the count of distinct query keywords present. That is it.

- No IDF. "work" and "ayahuasca" count the same, so a common word drowns a rare one.
- No field weighting. A word in the title counts the same as one buried in paragraph nine.
- No recency weighting except as a tie-break (`:105`, ties go to the newer entry).
- No length normalization, so long entries win by accident.
- No semantic matching at all. "Was I burnt out in the spring?" will not find an entry that says
  "running on empty," "couldn't get out of bed," or "exhausted." The journal's own vocabulary is
  exactly the vocabulary a person does not reuse when asking about it later.

### 4. Tier 2 has no k-cap, so a common word eats the whole prompt

The loop at `:107-109` appends every matching entry, in score order, until the budget is gone. Ask
anything containing "work" and the 24,000 character budget fills with roughly 12 entries that
mention work, ranked by keyword count rather than by whether they answer the question. There is no
"top k then stop," no diversity, no guarantee the entry that actually answers the question is in
the surviving set rather than one position past the cutoff.

### 5. Aggregate questions get a confidently wrong answer instead of a refusal

This is the most dangerous current behavior.

"How have I been feeling this year?" hits tier 3. The date range matches every entry in the year.
The builder appends them newest first until 24,000 characters run out, which is about 12 entries.
The model then answers the question about the year from the last two weeks, and has no way to know
it is looking at a sample. The answer reads as authoritative. It cites real entries. It is wrong.

Same for "who do I mention most," "what do I keep coming back to," "am I doing better than last
year." None of these are answerable by fetching k documents, and nothing in the current design
notices that.

### 6. Two search implementations that disagree

`JournalSearch` (`Mindlore/Graph/JournalSearch.swift`) powers the search panel: one SwiftData
predicate on `localizedStandardContains`, capped at 30, newest first. `AskContextBuilder` powers
the prompt: four tiers, word-boundary regex, character budget. Same user intent, two different
answers on the same screen. The panel can show an entry the question then fails to send.

## What to build

Four stages. Each one is shippable alone and each one is worth shipping alone.

### Stage 0: give retrieval the conversation (small, fixes the loudest complaint)

Before retrieval, turn the follow-up into a standalone query using the turns already in memory.
"Why do you think that started?" after a Maya turn becomes "Why did Maya's situation start?"

Two ways to do it:

- **Cheap and deterministic**: carry forward the previous turn's resolved entity IDs and keywords,
  and merge them with the new question's. Decay them, so a topic fades over three or four turns
  rather than sticking forever. No extra model call. Probably 80% of the benefit.
- **Better**: one small model call that rewrites the question against the last two turns. Adds
  latency and tokens. On device this is nearly free; against OpenAI it is one extra cheap request.

Also: re-send the blocks for entries cited in recent turns, not just the answer text. Budget for
them separately so they cannot crowd out new retrieval.

Do Stage 0 first regardless of what else happens. It is the difference between a chatbot and a
one-shot question box.

### Stage 1: a real lexical index (medium, fixes scan cost and ranking)

Add a persisted index model alongside `Entry`, maintained incrementally by the same trigger that
already runs `GraphIndexer` after insights are written, with a launch sweep for entries it does not
yet cover. Same shape as `graphIndexedAt`.

Store per-entry term frequencies and a corpus-level document frequency table. Score with BM25
(k1 ≈ 1.2, b ≈ 0.75 are the standard starting points). Add a recency multiplier with a half-life,
reusing the 90-day figure `EntityGraph.build` already uses for edge weight, so Ask and the graph
agree about what "recent" means.

Keep the existing signals as **pre-filters**, not as separate tiers: entity IDs from `EntityLink`,
tags from `EntryInsights`, life areas, and the `AskDates` range all narrow the candidate set before
scoring. That is the right way round, and it is the part of the current design worth keeping.

Then take the top k, where k is a real number, not "whatever fits." Fill the budget from a ranked
list rather than letting the list define itself by the budget.

`JournalSearch` should read the same index, so the panel and the prompt stop disagreeing.

### Stage 2: embeddings, hybrid retrieval (medium, fixes the vocabulary gap)

`NLContextualEmbedding` in the NaturalLanguage framework is the right tool and it is already
available at the deployment target. 512 dimensions, transformer-based, 256 tokens per request,
runs on device, no model download, no network, no cost. Its 256-token window means entries need
chunking anyway, which is fine: journal entries want paragraph-level chunks regardless, because a
long entry covers four unrelated things and embedding it whole averages them into mush.

Chunk at paragraph boundaries into roughly 200-token windows with a sentence or two of overlap.
Short entries stay whole. Prepend the entry's date and title to each chunk before embedding, which
is a cheap version of Anthropic's contextual retrieval trick and costs nothing here.

Storage: a `Data` blob of 512 `Float`s is 2 KB per chunk. At 20,000 entries and three chunks each,
that is 120 MB, which is too much to sync and probably too much to keep resident. Options: store
`Float16` (1 KB per chunk, quality loss is negligible for retrieval), keep the blobs on a model
excluded from CloudKit sync and rebuild them locally, or both. Worth deciding early since the
CloudKit rule (`CloudKitSchemaRulesTests`) applies to any new model.

Search: brute-force cosine with `vDSP` from Accelerate. 60,000 chunks by 512 dimensions is about 30
million multiply-adds, which is a few milliseconds on an A17 and nothing on an A18. No vector
database is needed at this corpus size and probably not before a few hundred thousand chunks. If it
ever is, `sqlite-vec` is the sane choice, not a new dependency stack.

Fuse dense and BM25 with reciprocal rank fusion, `score = Σ 1/(60 + rank)`. RRF needs no score
normalization between the two systems, which is why everyone uses it. Hybrid matters more here than
in most corpora, because a journal is full of proper nouns where lexical wins and full of feelings
where dense wins.

### Stage 3: let the model search (larger, changes the shape)

Instead of stuffing one retrieved set into the prompt, give the model a `search_journal` tool and
let it call it as the conversation goes. This is what actually fixes drift: the model asks for what
it needs, when it needs it, and a follow-up about something new just triggers a new search.

Requirements:

- `TextRequest` and `OpenAICompatibleTextGenerator` need tool calling. Neither has it today.
  `TextRequest` has `schema` for structured output but no tool definitions, and `AskService` does a
  single `generate` call with no loop.
- The agent loop needs a cap on tool calls per turn and a token budget across the loop, or a
  confused model will search twelve times and bill for all of it.
- `FoundationModelsTextGenerator` can do tools today, but the on-device model is about 3B
  parameters and is not reliable about deciding to call one. Expect to keep the stuffed-context
  path for on-device and use tools only on the OpenAI path, at least at first.

Worth noting for later: Apple shipped `SpotlightSearchTool` in the iOS 27 SDK, a first-party
Spotlight-backed search tool that plugs straight into `LanguageModelSession` for local RAG. That is
eventually a replacement for most of stages 1 through 3. It is out of reach at the current 26.5
deployment target, so it is a reason to keep the retrieval layer behind a clean protocol, not a
reason to wait.

### Stage 4: precomputed rollups for aggregate questions (small, kills a wrong-answer class)

Retrieval cannot answer "how have I been feeling this year." Stop trying.

Maintain monthly rollups next to the index: entry counts, mood distribution from `EntryInsights`,
top tags, top entities by link count, life area split. When a question looks aggregate, or when the
matched set is much larger than what fits, inject the rollup as a stats block instead of, or
alongside, a sample of entries.

And tell the truth in the prompt when the set was cut: "showing 12 of 84 matching entries" so the
model hedges instead of generalizing. Same for the line under the field, which today says "Asking
sends 12 entries" and should say "12 of 84."

## Order of work

Stage 0, then 4, then 1, then 2, then 3. Stage 0 fixes the complaint that started this. Stage 4 is
the cheapest fix for the only failure mode that produces a confidently wrong answer. Stage 1 is the
foundation for everything after it. Stage 2 is the quality jump. Stage 3 is the shape change and
should wait until the retrieval underneath it is worth calling.

## Constraints to hold

- New models follow the CloudKit rule: every stored property optional or defaulted, nothing
  `@Attribute(.unique)`. `CloudKitSchemaRulesTests` will catch it.
- Index and embedding work leaves the main actor. Mark it `@concurrent nonisolated` and drive it
  from the existing indexing trigger, not from a view.
- Diagnostics carry ids, counts, durations, and scores. Never a query string, term, chunk, or
  entry text. `DiagnosticsPrivacyTests` runs real components against a sentinel and will catch it.
- `AskSources` stays the single gate on what may leave the phone. Any new retrieval path draws from
  it, so a filtered-out entry cannot reach a provider through the index.

## Open questions for the owner

1. Is on-device Ask a first-class path or a fallback? It changes how much the 6,000 character
   budget matters, and whether Stage 3 is worth building twice.
2. Acceptable index build time on first launch over an existing journal? Embedding 20,000 entries
   with `NLContextualEmbedding` is not instant, and it needs a progress affordance like
   `GraphIndexingOverlay`.
3. Do embedding blobs sync, or rebuild per device? Affects the storage decision in Stage 2.
