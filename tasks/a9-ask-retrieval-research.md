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


## What the outside evidence says

Researched 2026-09-18. Sources at the bottom. Three findings changed the plan.

**Query rewriting is the highest-value fix, and it is measured.** Over 60% of follow-up messages in
production conversational systems carry unresolved coreference or implicit context. Rewriting the
follow-up into a standalone query before retrieval gives +15% to +25% retrieval accuracy from turn
three onward. Context summarization does slightly better than plain rewriting, +13.5% R@5. This is
problem 1 above, and it is the single best-evidenced intervention available.

**Embeddings may be premature here.** For a corpus of a few thousand documents the advice is
consistent: build BM25 first, measure, and only add vectors if users say results are okay but not
great. BM25 costs nothing, runs under 10ms, needs no chunking, needs no model, and is debuggable
(you can see exactly why an entry matched). One 2026 benchmark has BM25 beating
`text-embedding-3-large` on every metric except Recall@20. At 300 to 5,000 entries, a good lexical
index plus the entity and date pre-filters Mindlore already has may be the whole answer.

**Agentic retrieval is real but expensive, and it degrades at scale.** Letting the model call a
search tool repeatedly gives 5.2x to 5.9x better recall@1 than single-shot. It also costs 3x to 10x
more, adds 2x to 5x latency, and averages 2.8 retrieval rounds per query. Worse, it scales badly:
going from 100k to 200k documents pushed average tool calls from 38.5 to 86.9, doubled latency and
cost, and **dropped accuracy by 13.6 points**. The 2026 consensus is not "go agentic," it is
adaptive routing: classify the question and send it down the cheapest pipeline that can answer it.

Two more that shaped specifics:

**Apple's on-device model cannot be trusted with a search tool.** A developer wiring Apple's own
`SpotlightSearchTool` into `LanguageModelSession` found the model mostly did not call it and
fabricated plausible answers instead. Twenty consecutive answers looked right and were invented.
Setting `toolCallingMode = .required` forced a tool call on every turn including answer generation
and hung the app in an infinite search loop. What worked was a three-stage split: the model
generates search keywords, deterministic code retrieves real rows, and the model then picks only
from the retrieved list. That pattern is the on-device design, and it happens to be the same call
that does query rewriting.

**Contextual retrieval is cheap here and it applies to BM25, not just vectors.** Prepending 50 to
100 tokens of context to each chunk before indexing cut top-20 retrieval failures by 35% for
embeddings alone and 49% when applied to BM25 as well. Mindlore already has the context to prepend
for free: entry date, title, life area, and the resolved entity names from `EntityLink`. No
generation step needed.

## What to build

Four stages, in this order. Each one ships alone.

### Stage 1: give retrieval the conversation

Nothing else matters until this is fixed. It is problem 1, it is the complaint that started this,
and it has the best evidence behind it.

Before retrieval, turn the follow-up into a standalone retrieval query using the turns already in
`AskService.turns`. Two options:

- **Deterministic**: carry the previous turn's resolved entity IDs and surviving keywords forward,
  merged with the new question's, decayed over three or four turns so a topic fades instead of
  sticking. No model call, no latency, no tokens. Probably most of the benefit.
- **Generated**: one small call that emits search keywords for the current question given the last
  two turns. This is exactly the first stage of the pattern that fixed Apple's tool-calling problem,
  so it is worth building even on the on-device path.

Build the deterministic version first and measure against a fixed set of follow-up questions. Add
the generated version only if the deterministic one misses.

Separately: re-send the blocks for entries cited in the last turn or two, budgeted apart from new
retrieval so they cannot crowd it out. Today the model can see it said something about Maya but
cannot re-read the entry it said it from.

### Stage 2: rollups, and telling the truth about truncation

Cheapest fix for the only failure mode that produces a confident wrong answer (problem 5).

GraphRAG-style global search is the wrong tool: Microsoft's own numbers put 100 global questions at
roughly $650 and 106 million tokens. Their cheaper variant uses root-level summaries for 97% fewer
tokens, which is the same idea as a precomputed rollup and is what fits on a phone.

Mindlore already has the inputs. Maintain monthly rollups next to the entries: counts, mood
distribution from `EntryInsights`, top tags, top entities by `linkCount`, life area split. When a
question is aggregate, or when the matched set is much larger than what fits, inject the rollup
instead of, or alongside, a sample.

And say so in the prompt when the set was cut: "showing 12 of 84 matching entries." The model then
hedges instead of generalizing from the newest two weeks. Same for the line under the field, which
says "Asking sends 12 entries" today and should say "12 of 84."

### Stage 3: a real lexical index

Replace the four tiers with one ranked list.

Add a persisted index model alongside `Entry`, maintained incrementally by the same trigger that
runs `GraphIndexer` after insights are written, with a launch sweep for what it does not cover.
Same shape as `graphIndexedAt`, same `GraphIndexingOverlay` for progress.

Score with BM25, k1 ≈ 1.2 and b ≈ 0.75 as the starting point. Add a recency multiplier reusing the
90-day half-life `EntityGraph.build` already uses, so Ask and the graph agree on what recent means.

Index the contextually enriched text, not the raw text: prepend date, title, life area, and the
resolved entity names for that entry. That is the contextual BM25 half of the 49% figure, and here
it costs nothing because the metadata already exists.

Keep entities, tags, life areas, and the `AskDates` range as **pre-filters** that narrow the
candidate set before scoring, rather than as parallel tiers that each dump entries into the prompt.
That inversion is the actual fix for problems 3 and 4.

Then take a real top-k and fill the budget from a ranked list, instead of letting the budget define
the list. Switch the budget from characters to estimated tokens while you are in there.

`JournalSearch` reads the same index, so the panel and the prompt stop disagreeing (problem 6).

### Stage 4: measure, then decide about embeddings

Do not build this on faith. Build a fixed question set against the 300-entry demo seed, measure
Stage 3, and only continue if lexical retrieval visibly misses.

If it does, the vocabulary gap is the reason: "burnt out" never finds "running on empty." Then:

- **Model**: `NLContextualEmbedding`. 512 dimensions, BERT-class, 256 tokens per request, and the
  weights are an OS-managed shared asset the system downloads on first request rather than
  something shipped in the bundle. That last part matters: the CoreML build of EmbeddingGemma-300M
  is 588 MB at fp16, which is not shippable in a journaling app. If Apple's model turns out too
  weak, `model2vec.swift` (static embeddings, tokenize plus lookup plus pool, no forward pass) is
  the light alternative before anything 300M-parameter.
- **Chunking**: do not chunk short entries. Consensus for journal-length documents is to embed them
  whole. Only split long ones, at paragraph boundaries; paragraph-group chunking measured best at
  about 59% mean nDCG@5. The 256-token window forces splitting on long entries regardless.
- **Storage**: 512 floats is 2 KB per vector, or 1 KB at `Float16` with negligible retrieval loss.
  Decide early whether these sync or rebuild per device, because `CloudKitSchemaRulesTests` applies
  to any new model.
- **Search**: brute force with `vDSP`. sqlite-vec benchmarks 100k vectors at 768 dimensions under
  75ms, and the general guidance is that computing similarity in app code is fine below 100k
  vectors. No vector database. If it is ever needed, sqlite-vec, not a new stack.
- **Fusion**: reciprocal rank fusion, `score = Σ 1/(60 + rank)`. k=60 is the de facto default and
  needs no tuning. Hybrid buys 10% to 25% MRR over dense alone, and it matters more here than most
  places, because a journal is full of proper nouns where lexical wins and full of feelings where
  dense wins.

### Not a stage: adaptive routing

Once Stages 1 through 3 exist, route by question type rather than running one pipeline for
everything. Lookup questions ("what did I do last week") go straight to filters. Aggregate
questions go to rollups. Only open-ended exploration justifies an agent loop, and only on the
OpenAI path, where tool calling actually works. That needs tool definitions added to `TextRequest`
and `OpenAICompatibleTextGenerator`, neither of which has them, plus a hard cap on calls per turn.

Worth knowing before investing there: Apple shipped `SpotlightSearchTool` in the iOS 27 SDK,
first-party Spotlight-backed local RAG that plugs into `LanguageModelSession`. It would replace much
of Stages 3 and 4. It is out of reach at the 26.5 deployment target, and the field report above says
it is rough anyway. Reason enough to keep retrieval behind a clean protocol, not to wait for it.

## What the current design already gets right

Worth keeping through any rewrite:

- `AskSources` as the single gate on what may leave the phone. Any new retrieval path draws from it.
- Citations constrained to an enum of handles actually sent (`AskPrompt.schema`, `handlesSent`).
  This is the same defense the tool-calling field report arrived at the hard way: the model cannot
  name an entry it never received. Keep it.
- Delimiter fencing and `sanitized()` against prompt injection from photographed pages.
- Character budgets computed per provider rather than one global number.

## Order of work

1. Conversation-aware retrieval. Fixes the complaint, best evidence, smallest change.
2. Rollups and honest truncation. Kills the confident-wrong-answer class.
3. BM25 index with contextual enrichment and pre-filters. Fixes ranking and the scan cost.
4. Measure. Embeddings and RRF only if the measurement says so.

## Constraints to hold

- New models follow the CloudKit rule: every stored property optional or defaulted, nothing
  `@Attribute(.unique)`. `CloudKitSchemaRulesTests` will catch it.
- Index and embedding work leaves the main actor. Mark it `@concurrent nonisolated` and drive it
  from the existing indexing trigger, not from a view. Today `AskSources.journal` runs a full
  three-table scan on the main actor on every pause in typing.
- Diagnostics carry ids, counts, durations, and scores. Never a query string, term, chunk, or entry
  text. `DiagnosticsPrivacyTests` runs real components against a sentinel and will catch it.

## Open questions for the owner

1. Is on-device Ask first-class or a fallback? It decides whether the keyword-generation call in
   Stage 1 has to work on a 3B model, and whether adaptive routing is built twice.
2. Acceptable first-launch index build time over an existing journal, and does it need a progress
   affordance like `GraphIndexingOverlay`?
3. If Stage 4 happens: do embedding blobs sync, or rebuild per device?

## Sources

- [Query rewriting before retrieval in multi-turn RAG](https://alhena.ai/blog/query-rewriting-before-retrieval-multi-turn-rag/)
- [Query rewriting for RAG, Meilisearch](https://www.meilisearch.com/blog/query-rewrite-rag)
- [Quantifying accuracy and cost in budget-constrained agentic LLM search](https://arxiv.org/pdf/2603.08877)
- [Agentic RAG vs traditional RAG, a cost-honest comparison](https://www.sphereinc.com/blogs/agentic-rag-vs-traditional-rag-vs-chatgpt)
- [RAG architectures and how to avoid over-engineering](https://www.lighthousenewsletter.com/p/rag-is-simpler-than-you-think)
- [BM25 vs embeddings, why hybrid retrieval wins](https://sesen.ai/blog/bm25-vs-embeddings-hybrid-retrieval)
- [Contextual Retrieval, Anthropic](https://www.anthropic.com/engineering/contextual-retrieval)
- [I gave an on-device LLM a search tool and it ignored it](https://hackernoon.com/i-gave-an-on-device-llm-a-search-tool-it-ignored-it-and-made-up-data-instead)
- [What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)
- [LLM search using Core Spotlight, WWDC26](https://developer.apple.com/videos/play/wwdc2026/246/)
- [Apple embeddings, NLContextualEmbedding details](https://www.callstack.com/blog/on-device-ai-introducing-apple-embeddings-in-react-native)
- [EmbeddingGemma-300M CoreML build](https://huggingface.co/mlboydaisuke/embeddinggemma-300m-coreml/blob/main/README.md)
- [model2vec.swift, static sentence embeddings on device](https://github.com/shubham0204/model2vec.swift)
- [sqlite-vec v0.1.0 release notes and benchmarks](https://alexgarcia.xyz/blog/2024/sqlite-vec-stable-release/index.html)
- [From Local to Global: a GraphRAG approach](https://arxiv.org/pdf/2404.16130)
- [LazyGraphRAG, quality and cost](https://www.microsoft.com/en-us/research/blog/lazygraphrag-setting-a-new-standard-for-quality-and-cost/)
- [A systematic investigation of document chunking strategies](https://arxiv.org/html/2603.06976)
