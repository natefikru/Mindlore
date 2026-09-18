# A9b build spec: Ask finds things

Branch `feature/a9-ask-retrieval`, off `feature/phase-a`. This spec implements the first three
stages of `tasks/a9-ask-retrieval-research.md`. Read that document's "six problems" first; this one
does not restate them. Revision 2, after a sub-agent review whose findings are listed at the end.

Called A9b (owner, 2026-09-18): `tasks/todo.md` already has A9 for the 3D spike and A10 for privacy
and docs, and neither of those lines moves.

## Scope

The research proposed four stages. This phase builds one, two, and three:

1. Retrieval that knows what the conversation is about.
2. Honest truncation, and enough of a rollup to stop a confident wrong answer.
3. One ranked list, from a lexical index, instead of four tiers.

**Embeddings (stage four) are not in this phase, so no scope change is needed for them.** Phase A's
"Not in scope" line stands: Ask uses names, keywords, and dates, and now it uses them properly. The
research's own conclusion is that embeddings are premature below a few thousand entries and should be
bought with a measurement rather than faith. What ships instead is the measurement: a fixed question
set with expected answers, run as a unit test, that reports the recall the lexical path actually gets.
A weak number gives the owner a reason to spend a week on `NLContextualEmbedding`. A strong one saves
the week.

Also out: agentic tool-calling, adaptive routing, and a generated query-rewrite call. The
deterministic carryforward is the cheap half of stage one, and the quality suite is what says whether
it needs a model call.

## Owner decisions (2026-09-18)

- **Rollups carry counts and coverage only.** "March 2026: 31 entries" and nothing else. Mood
  distribution, area split, and top tags are Reflect's data, and `tasks/todo.md:722` reserves them for
  that phase. The disclosure sentence is the half that kills the confident wrong answer, and it stays.
- **Two PRs, cut after Unit 5.** The retrieval engine lands with its measurement and gets judged on
  recall before the prompt, the UI, and the search panel move.
- **On-device Ask is a fallback.** Its budget lands near 3,300 characters, so it gets About blocks and
  five ranked entries, with rollups and continuity off. Unit tests pin the caps; no phone tuning.
- **A9b, not A9.** The 3D spike keeps A9. This spec appends its own section and log entry to
  `tasks/todo.md` and edits nobody else's lines.

## The shape of the pipeline

Today one function does everything, on the main actor, over every entry, on every pause in typing.
After this phase it is five steps, and only the fourth touches entry text:

1. **`AskIndexStore`** holds an immutable `AskIndex`, built off the main actor. One build per Ask
   appearance, not one per keystroke.
2. **`AskRetrievalQuery`** turns the question plus the turns before it into weighted terms, a date
   rule, and the entries this conversation is already talking about. Pure, and it reads the index
   rather than the store.
3. **`AskRetrieval.plan`** scores the index, takes a top k, and divides the budget into named slices.
   Pure, and it reads no entry text, which is what makes the cost line free.
4. **`AskSources.blocks(for:)`** fetches only the entries the plan chose, re-checks what may leave the
   phone, and hands them over.
5. **`AskContextBuilder`** keeps its current job: handles, sanitizing, fencing, and the authoritative
   budget, now per slice. Its four tiers go.

`AskSources` stays the single gate. Nothing else fetches entry text.

## `AskIndex` (`Mindlore/AI/Ask/AskIndex.swift`, pure, `nonisolated`)

An immutable, `Sendable` snapshot. No SwiftData import. It holds no entry text, which keeps it small
enough to rebuild freely and useless to leak.

```swift
nonisolated struct AskIndex: Sendable {
    struct DocumentInput: Sendable {
        let id: UUID
        let date: Date                 // entryDate, the journal's own day
        let title: String
        let text: String
        let entityIDs: [UUID]          // resolved through EntityDirectory.root(of:)
        let entityNames: [String]      // names and aliases of those entities
        let tags: [String]
        let areas: [String]            // LifeArea raw values
        let mood: String?              // EntryInsights.primaryMoodRaw
        let isSendable: Bool           // passes InsightsCoordinator.canRunAI
        let blockCharacters: Int       // what rendering this entry would cost
    }

    // Enough to resolve a name in a question without fetching. Bios and loose ends stay out:
    // they are only needed once the plan has chosen, and AskSources.blocks fetches them then.
    struct Entity: Sendable, Equatable {
        let id: UUID
        let name: String
        let aliases: [String]
        let kindRaw: String
        let isBrowsable: Bool
    }

    struct Document: Sendable, Equatable { /* DocumentInput minus text */ }
    struct Scored: Sendable, Equatable {
        let document: Int32
        let score: Double
        let matchedInBody: Bool        // false when only context tokens matched
    }

    static let empty = AskIndex(documents: [], entities: [], /* ... */)

    let documents: [Document]
    let entities: [Entity]

    static func build(from inputs: [DocumentInput], entities: [Entity]) -> AskIndex
    func search(_ query: AskRetrievalQuery) -> [Scored]
    func search(terms: [AskRetrievalQuery.Term], expandingLastTerm: Bool) -> [Scored]
    func tagCounts(matching folded: String) -> [(tag: String, count: Int)]
    func entities(namedIn question: String) -> [Entity]   // NameMatching over name and aliases
}
```

The entity table is what lets steps 2 and 3 run without a fetch. Without it,
`AskRetrievalQuery.build` would need `AskSources.journal`'s three-table scan and the cost line would
still read the whole journal on every pause.

**Terms.** One folded token stream per document, built with `enumerateSubstrings(.byWords)` and
`folding(options: [.caseInsensitive, .diacriticInsensitive])`. One-character tokens are dropped;
two-character tokens are kept, so "AI" and "NY" are findable. The query side drops stop words, and
`AskContextBuilder.stopWords` already covers the two-letter English noise ("me", "my", "in", "on",
"at", "to", "is", "be", "do", "it"), so the three-letter floor that today drops "AI" goes away.

**Body and context are scored separately, not merged.** This is the difference between enrichment
helping and enrichment flattening everything. Each term carries two frequencies per document:

| Stream | Contributes to |
| --- | --- |
| body text (1.0) and title (2.0, `titleWeight`) | the body score |
| entity names and aliases, tags, life areas, mood, the entry's month name and year (1.5) | the context score |

```
score = bm25(bodyFrequency) + contextFactor * bm25(contextFrequency)   // contextFactor = 0.4
```

So an entry that actually writes "Maya" outranks one that is merely linked to her, at equal
frequency, every time. Enrichment still surfaces the entries that never spell the name, which is what
it is for, but it can no longer give forty linked entries one identical score and leave length
normalization to pick the winner.

**BM25.** `k1 = 1.2`, `b = 0.75`, `idf(t) = log(1 + (N - n_t + 0.5) / (n_t + 0.5))`. Each query term's
contribution is multiplied by its own weight from the query, so a carried term counts for less than a
term the person just typed.

**Recency**, reusing the graph's constant so Ask and the graph agree on what recent means:

```
decay = pow(0.5, ageDays / EntityGraph.defaultHalfLife)          // 90 days
final = score * (recencyFloor + (1 - recencyFloor) * decay)      // recencyFloor = 0.5
```

The floor is deliberate. A two-year-old entry that answers the question should not be buried under
last Tuesday; halving it breaks a tie without hiding it.

**Date rules.** A range the current question named is a hard filter, half-open: a question that names
a stretch of time means that stretch. An **inherited** range (Unit 2) is never a filter, only a
multiplier (`inheritedRangeBoost = 2.0`) for in-range documents, and it is dropped entirely when the
current question names an entity. Otherwise "What did I do last week?" followed by "What about Maya?"
would discard every Maya entry older than seven days before scoring, which is worse than today.

**Entities are never a filter either**, only the boost enrichment gives them. Insights miss links, and
an entry about the move can answer a question about Maya without naming her.

**No query terms at all.** "Why?" leaves nothing after stop words. Candidates then rank by recency
alone, and everything that matters comes from the carryforward and the continuity slice.

**Prefix expansion** (`expandingLastTerm`) exists for the search panel, where the last word is
half-typed. A sent question is complete, so Ask never uses it. Each expansion is weighted by its own
IDF and a document takes its **best** expansion, not the sum, so typing "mar" cannot let an entry
containing march, market, and marathon outrank the one entry about Maria. When the prefix path returns
nothing the panel falls back to today's substring predicate, so "iver" still finds "river".

## `AskRetrievalQuery` (`Mindlore/AI/Ask/AskRetrievalQuery.swift`, pure)

This is problem 1, and it is the point of the phase.

```swift
nonisolated struct AskRetrievalQuery: Sendable, Equatable {
    struct Term: Sendable, Equatable { let text: String; let weight: Double }

    let terms: [Term]
    let namedRange: DateInterval?      // this question's own, a hard filter
    let inheritedRange: DateInterval?  // an earlier question's, a boost
    let namedEntityIDs: [UUID]         // named in this question
    let carriedEntityIDs: [UUID]       // named in the last two, still the subject
    let continuityEntryIDs: [UUID]     // cited by the last two answers
    let aggregateHint: Bool            // a marker in the wording; the plan decides

    static func build(
        question: String,
        previousQuestions: [String],   // newest first, capped at carryDepth
        citedEntryIDs: [[UUID]],       // newest answer first, capped at 2
        index: AskIndex,
        now: Date,
        calendar: Calendar
    ) -> AskRetrievalQuery
}
```

**Decay.** The current question's terms weigh 1.0. The question before it, 0.5. The one before that,
0.25 (`carryDecay = 0.5`, `carryDepth = 3`). A term in more than one turn takes the highest weight,
never the sum. So "What's going on with Maya?" then "Why do you think that started?" retrieves Maya's
entries at half weight and entries about starting things at full weight: still about Maya, now about
how it began. Today the second question loses her entirely, because every word of it is either a stop
word or "started".

Entities named in earlier questions carry the same way, by contributing their name and alias tokens as
carried terms. There is no separate entity carryforward mechanism.

**Dates.** `AskDates` is unchanged and still parses the current question into `namedRange`. When the
current question names no range, the most recent previous question's range becomes
`inheritedRange`, one turn only, and only when the current question names no entity. The index treats
the two differently, as above, and the prompt says which days the entries came from whenever either
applied, so an inheritance the user did not intend is legible instead of silent.

**Continuity.** The entry ids cited by the last two answers. The model can see it said something about
Maya; today it cannot re-read the entry it said it from, so it hedges or invents. Unit 3 gives these
their own slice so new retrieval cannot crowd them out, or vice versa.

**Aggregate.** `aggregateHint` is set by a fixed English marker list ("how often", "how many", "how
much", "most", "usually", "always", "never", "every time", "pattern", "patterns", "trend", "trends",
"in general", "generally", "typically", "on average", "average", "keep coming back", "come back to",
"compare", "better than", "worse than"). It is a hint, not the answer: `AskRetrieval.Plan.isAggregate`
is the single source of truth, computed as `hint || matchedCount > aggregateSizeFactor * k`, and only
the plan reaches the prompt.

**Nothing about carryforward is stored.** A reopened conversation recomputes all of it from
`AskMessage.text` and `AskMessage.citedEntryIDs`, which are already saved.

## `AskRetrieval.plan` (`Mindlore/AI/Ask/AskRetrieval.swift`, pure)

```swift
nonisolated enum AskRetrieval {
    struct Slices: Sendable, Equatable {   // absolute characters, not percentages
        var about = 0
        var rollups = 0
        var continuity = 0
        var ranked = 0
    }

    struct Plan: Sendable, Equatable {
        var aboutEntityIDs: [UUID] = []
        var rollupMonths: [DateInterval] = []
        var continuityEntryIDs: [UUID] = []
        var rankedEntryIDs: [UUID] = []       // best first
        var excerptOnlyEntryIDs: Set<UUID> = []  // matched on context only: render as excerpts
        var matchedCount = 0
        var estimatedCharacters = 0
        var appliedRange: DateInterval?
        var rangeWasInherited = false
        var isAggregate = false
        var slices = Slices()
    }

    static func plan(query: AskRetrievalQuery, index: AskIndex, budget: Int,
                     provider: AskProviderKind) -> Plan
}
```

**Top k.** `maxRankedEntries` is 15 for OpenAI and 5 on device. The budget was the only cap before,
which is how "work" came to fill 24,000 characters with whatever mentioned work. A ranked list with a
k and a budget is two brakes, and the list decides the order rather than the order deciding the list.

**Slices are absolute characters per provider, not percentages.** Percentages do not survive the
on-device path: its budget is `max(0, 6000 - fixed)` (`AskService.swift:294-305`), which lands near
3,300 characters, and 20% of that is 660 while a single entry block can be 2,050. So:

| Slice | OpenAI | On device |
| --- | --- | --- |
| About blocks | 3,600 | 800 |
| Rollups | 6,000 | 0 |
| Continuity | 4,800 | 0 |
| Ranked | the rest, never below 9,600 | everything left |

On device, rollups and continuity are off until the owner says on-device Ask is first-class (open
question 3). A slice that goes unused rolls into ranked, which is last for that reason.

**`AskContextBuilder` is told all four numbers and enforces each at append time.** The plan adds up
`blockCharacters` from the index, which is what rendering cost at build time; the renderer holds the
real limits. A rollup block that renders larger than planned can then only eat the rollup slice, never
the ranked floor. And `rankedEntryIDs` is capped to what the advisory arithmetic says fits, so the
cost line does not over-report what left the phone.

**`matchedCount`** counts documents scoring at or above `matchRelevanceFloor` (0.25) of the top score,
inside the date filter. Counting every non-zero score would make the number meaningless: with
enrichment, a journal where 60% of entries carry the `work` area matches 60% of itself on "how was
work", and "12 of 3,000" teaches both the user and the model to ignore the line. A quarter of the top
score means 84 comparable entries, which is what the sentence claims.

**Excerpt rendering.** A document whose match was context-only (`matchedInBody == false`) is rendered
as the sentences naming the entity (`BioExcerpts.sentences`), the way today's tier 1 does, not as a
2,000-character block. Ten excerpts fit where three blocks do. Dropping this was the review's sharpest
finding: without it, "What's going on with Maya?" sends less about Maya than it does today.

## `AskIndexStore` (`Mindlore/AI/Ask/AskIndexStore.swift`)

```swift
nonisolated protocol AskIndexBuilding: Sendable {
    @concurrent func build(_ inputs: [AskIndex.DocumentInput],
                           entities: [AskIndex.Entity]) async -> AskIndex
}

nonisolated struct AskIndexBuilder: AskIndexBuilding {
    @concurrent func build(...) async -> AskIndex
}

@Observable @MainActor final class AskIndexStore {
    private(set) var index = AskIndex.empty
    func refreshIfNeeded(revisions: Revisions, in context: ModelContext) async
}
```

`@concurrent` on the requirement, not just `nonisolated`. A8's review caught exactly this:
`SWIFT_APPROACHABLE_CONCURRENCY` turns on `NonisolatedNonsendingByDefault`, so a `nonisolated async`
function runs on the caller's actor and `nonisolated` alone would leave tokenizing on the main thread.
`Mindlore/Contacts/ContactDirectory.swift` is the pattern. An in-flight guard holds the running
`Task`, so appear-then-send does not build twice.

**When it rebuilds.** A fingerprint of ordinals only. No dates:

```swift
struct Revisions: Equatable { let saver: Int; let graph: Int }
struct Fingerprint: Equatable {
    let entries: Int        // context.fetchCount(FetchDescriptor<Entry>())
    let links: Int
    let entities: Int
    let revisions: Revisions
}
```

**`graph` is the primary signal, not a footnote about renames.** Writing insights deliberately does
not stamp the entry: `ModelContext.saveStampingEntries(except:)` exists for that, and both
`InsightsCoordinator.swift:41` and `GraphIndexer.swift:223` use it. So an entry's tags, mood, and life
areas can all land without `Entry.updatedAt` moving, and `GraphServices.revision` is the only thing
that sees it. Miss that and every freshly analysed entry is unfindable by its tag or its person, in
both Ask and the panel, until relaunch.

**No max-of-dates.** An earlier draft fingerprinted `max(Entry.updatedAt)`. `Entry.graphIndexedAt` is
an exact-equality stamp precisely because a clock that steps back must not hide regenerated insights,
and a max comparison loses that: a restored entry with an older `updatedAt` changes no count and no
maximum, so the user's text stays invisible with no way to force a refresh. `EntrySaver` gains a
monotonic `private(set) var revision`, bumped on each successful save, and Ask reads it. Monotonic
counters cannot be walked backwards by a clock.

**Who calls it.** `AskView.task` on appear, and `AskService.send` before it plans. Not on a keystroke.
`estimate` reads whatever snapshot is there and never fetches, which is the whole of problem 2.
`AskService` and `AskView` both take `revisions: @escaping () -> AskIndexStore.Revisions`, wired in
`RootView` from `EntrySaver` and `GraphServices`.

**The honest cost.** `AskSources.documents(in:)` fetches every `Entry`, `EntityLink`, and `Entity`, and
reads `entry.insights?.tags`, `.areasRaw`, and `.primaryMoodRaw` per entry, which faults the to-one
relationship once each. That is strictly more main-actor work than today's `journal(in:)`, now paid as
a hitch when the Ask tab appears rather than on every pause in typing. Reading a to-one in memory over
one fetch is the pattern `JournalSearch` already uses and the one `tasks/lessons.md` permits; what it
forbids is a predicate reaching through a relationship, which this does not. A background `ModelActor`
would remove the hitch and is deliberately not in this phase. The number gets measured and written
into the review log rather than assumed.

**One index, two rules.** `documents(in:)` includes every non-draft, non-deleted entry with
`isSendable` set from `InsightsCoordinator.canRunAI`. Ask only ever plans over `isSendable` documents;
the panel uses all of them. Entities in the table carry `isBrowsable`, and only browsable ones are
offered to a prompt, so a hidden entity stays hidden (`AskEligibilityTests.aHiddenEntityIsNeverDescribed`).

## Rollups (`Mindlore/AI/Ask/AskRollups.swift`, pure)

Counts and coverage only (owner, 2026-09-18):

```
March 2026: 31 entries, 2 to 30 March
2026 so far: 214 entries across 9 months
```

That plus the disclosure sentence is what stops "how have I been feeling this year" being answered from
the last two weeks, and it takes no data Reflect is meant to own. Mood distribution, area split, and
top tags are out.

- Computed from **`isSendable` documents only**. An earlier draft computed over every document in the
  index, which would have let an entry awaiting text reach a provider through a summary, and the count
  the model reasons about has to match the corpus it was given. Cases go in `AskEligibilityTests`.
- A rollup block carries only numbers, a month name, and two dates: no title, no tag, no name, no
  sentence of entry text. It still sits inside the same fence as an entry, since a block the model
  reads is a block the rules have to cover.
- Months capped at 24 for OpenAI; past that they roll up by year. Oldest drop first when the slice
  binds. None on device.
- Rollup characters count toward the cost line, and "What was sent" gains a row, so widening what
  leaves the phone stays visible.

## Prompt changes (`Mindlore/AI/Ask/AskPrompt.swift`)

**Voice.** `AskPrompt.system(today:voice:)` takes a `PromptVoice`, resolved from
`settings.promptVoice` and threaded into `AskService` as `@escaping () -> PromptVoice`, the shape
`InsightsCoordinator` and `GraphServices` already use. Today Ask's prompt says "one person's private
journal" and "the journal is theirs"; those become "the author" plus `voice.instruction`, so an answer
reads "You were tired that week", "I was tired that week", or "Nate was tired that week" to match
every other piece of generated text in the app. The name reaches a provider only under the name voice,
which `PromptVoice.init` enforces by construction.

**Two new lines in the user message**, above the blocks:

- When `matchedCount` exceeds what went in: "These are the 12 entries that best match, out of 84 that
  match at all. Do not describe the whole period from this sample; say what you are looking at."
- When a range applied: "These entries are from 1 March 2026 to 31 March 2026." Added for a named or
  an inherited range, which is what makes an inheritance self-correcting.

**One new system rule**, only when a rollup is present: counts come from the summary blocks, quotes
and specifics from the entries, and never count the entries shown as if they were all of them.

`AskPrompt.folded` is unchanged. The on-device budget subtracts these lines with the rest of the fixed
prompt, as it already does.

## UI changes

- **Cost line** (`AskView.swift:224`). "Asking sends about 12 of 84 entries, about 18,000 characters"
  when the set was cut, today's wording when it was not. The plan's numbers are advisory, so the line
  says "about" for the count as well; "What was sent" keeps the true figure from the request.
- **"What was sent"** (`AskTurnView.swift:174`). A "Matching entries" row when `matchedCount` exceeds
  the count sent, and a "Monthly summaries" row when rollups went out. Both have to survive a reopen,
  and a past turn cannot recompute them from an index that no longer exists, so `AskMessage` gains
  `matchedCount: Int = 0` and `rollupMonthCount: Int = 0`, `AskTurn` carries them, and
  `CloudKitSchemaRulesTests` gets the two cases. (Defaulted, nothing unique: the rules hold.)
- **Search panel.** `JournalSearch.results` ranks through `AskIndex.search(terms:expandingLastTerm:)`,
  then fetches those ids for titles and snippets. Tag rows come from `AskIndex.tagCounts`. The panel
  and the prompt stop being two search engines that disagree (problem 6), and two full-journal scans
  per query become none.
  - **Ranked replaces newest-first**, so `JournalSearchTests.newestFirstAndCappedAtThirty` becomes a
    ranking test with the cap kept.
  - **A row can now match on something invisible.** With enrichment an entry can rank on a tag, a
    mood, a life area, or an entity name that appears nowhere in its text, and
    `JournalSearch.snippet(around:)` then falls back to the opening of the entry: a row with no visible
    reason for being there. Such a row shows why instead, as a caption ("tag: deadline", "mentions
    Maya"), and gets its own test.
  - Substring matching survives as the fallback when the prefix path finds nothing, so nothing a user
    could do today stops working.

`AskService` gains the index store, the voice, and the revisions closure. `RootView` builds the store
beside `GraphServices`.

## Diagnostics and privacy

- **`ask.indexed`**: `documents`, `sendable`, `entities`, `terms`, `postings`,
  `durationMilliseconds`, and `fetchMilliseconds` separately, since that is the number that decides
  whether a `ModelActor` is needed later.
- **`ask.retrieved`**: `matched`, `ranked`, `excerpts`, `continuity`, `rollupMonths`, `carriedTerms`,
  `carriedEntities`, `aggregate`, `rangeInherited`, `durationMilliseconds`, and `topScore` rounded to
  two decimals. A score is a number derived from text and cannot carry text.
- **`ask.answered`** keeps its fields and gains `matched`.
- Never a term, a query, a tag, a name, a month's contents, or a handle map.
- `AskDiagnosticsPrivacyTests` grows to run the real index build, the real planner, the rollups, and
  the search panel, with the sentinel used as entry text, title, tag, life area, entity name, alias,
  loose-end text, the question, the answer, and the owner's name under `.name` voice. The name case
  follows the precedent at `DiagnosticsLogTests.swift:229`.

## Tests

**Existing tests that change, all of them named:**

- `AskContextBuilderTests` (12): the tier-order and tier-dedupe cases go; budget skipping, sentence
  truncation, handle stability, stored-map reuse, and alias lookup move onto the plan.
- `AskServiceTests`: `anEmptyJournalSendsNoRequest` and `aQuestionThatLeavesNoRoomForABlockSendsNoRequest`
  both read `journal.entries` and the single budget, and move to the index and the slices.
- `AskEligibilityTests`: `anEntityWhoseOnlyEntryIsADraftContributesNoExcerpt` and
  `aHiddenEntityIsNeverDescribed` move to the `documents`, entity-table, and rollup paths.
- `JournalSearchTests`: `newestFirstAndCappedAtThirty` becomes a ranking test;
  `theSnippetIsAWindowAroundTheFirstMatch` gains the context-only sibling above;
  `thePredicateMatchesCaseAndDiacriticsLikeTheInMemoryRule` now pins the folding rule.
- `AskPromptSafetyTests`, `AskAnswerParserTests`, `AskDatesTests`, `AskProviderTests`: unchanged.

**New unit suites:**

- **`AskIndexTests`**: folding and case, two-character terms kept, title weighting, a body hit
  outranking a context-only hit at equal frequency, IDF putting a rare word above a common one,
  length normalization, the recency multiplier and its floor, a named range filtering half-open, an
  inherited range boosting but never filtering, an inherited range dropped when an entity is named, an
  alias finding a renamed entity, prefix expansion taking the best not the sum, the substring
  fallback, and an empty query ranking by recency.
- **`AskRetrievalQueryTests`**: the decay ladder, highest-weight-not-sum, `carryDepth` cutting at
  three, a range carrying exactly one turn, the current question's range winning, continuity ids from
  the last two answers, the aggregate markers, and a rebuild from stored message text matching a live
  conversation's query.
- **`AskRetrievalTests`**: the four slices as absolute numbers for both providers, an unused slice
  falling through to ranked, the k caps, `matchedCount` against the relevance floor (and that a
  journal where most entries share a life area does not report the whole journal as matching),
  aggregate by marker and by size, and `excerptOnlyEntryIDs` picking up the context-only matches.
- **`AskIndexStoreTests`**: the fingerprint skips a rebuild when nothing changed; each of the five
  fields forces one; **insights written through the exempting save still force one** (the
  `graph.revision` case, which is the one that would silently break search); the in-flight guard
  collapses appear-then-send into one build; and `estimate` performs no fetch, proven by deleting
  every entry from the context and still getting the last snapshot's numbers.
- **`AskRollupsTests`**: month bucketing, the caps and the roll-up-by-year path, oldest-first
  dropping, that a block carries nothing but numbers and dates, and that a non-sendable entry is not
  counted.
- **`AskRetrievalQualityTests`**, the measurement the phase exists to leave behind. About 25
  hand-written entries with known content and about 15 questions with the entry ids that answer them,
  asserting recall@5 and printing the actual number per question so a regression names the question it
  broke. Two rules keep it from marking its own homework:
  - Expected sets are written from the entry text before retrieval is run once, not read off what
    retrieval returned.
  - Follow-up scenarios are scored **with the continuity slice disabled**, so the number measures
    whether the carryforward found the entries rather than whether the last turn already had them.
  - The flagship case: "What's going on with Maya?" then "Why do you think that started?" must still
    retrieve Maya's entries.
  - The vocabulary gap is recorded as a **known miss**: "Was I burnt out in the spring?" against an
    entry that says "running on empty". Lexical retrieval cannot do this, and the suite asserts the
    miss rather than pretending, so the number in front of the owner for stage four is measured, not
    argued.
- **Timing**, reported in two halves because they have different fixes: tokenizing 2,000 synthetic
  documents under 500 ms (asserted, generous, with the actual printed), and the fetch over an
  in-memory store of 2,000 entries with insights (measured and printed, not asserted, since it is the
  half a `ModelActor` would fix). `tasks/lessons.md` on measured tolerances applies to both.

`OpenAILiveTests`, with the owner's key: a seeded fact plus a follow-up that names nobody ("and when
did that start?") still cites the right entry, and an aggregate question over a seeded year answers
with the rollup's count rather than the sample's.

UI, on `iPhone 17 a9-retrieval` with the stub: `AskUITests` and `AskScreenshotTests` only. The cost
line's "12 of 84" and the panel's ranked order with its new caption are screenshot material, and
`tasks/lessons.md` is blunt about what tests miss that a screenshot catches.

Device (ask before deploying): the demo seed at 300, a three-turn conversation where turns two and
three name nobody, and one aggregate question about the year.

## Units and commits

**PR 1, the retrieval engine:**

1. `AskIndex`: enrichment, the body/context split, BM25, the date rules, prefix expansion. `AskIndexTests`.
2. `AskRetrievalQuery`. `AskRetrievalQueryTests`.
3. `AskRetrieval.plan`, the slices, `matchedCount`. `AskRetrievalTests`.
4. `AskIndexStore`, the `@concurrent` builder, `EntrySaver.revision`, `AskSources.documents`, and
   `AskSources.blocks`. `AskIndexStoreTests`.
5. `AskContextBuilder` rewritten onto the plan with per-slice budgets and excerpt rendering,
   `AskService` wired to the store, the four tiers deleted, the affected suites rewritten, and
   `AskRetrievalQualityTests`.

**PR 2, the surface:**

6. `AskRollups` and the aggregate path, the prompt's two lines and its rollup rule, `PromptVoice` in
   Ask's prompts, `AskMessage`'s two properties, and the UI's counts.
7. `JournalSearch` onto the index, with the caption and the substring fallback. The privacy test, the
   live tests, and the UI run.
8. Sub-agent review of the diff, fixes in separate commits, the CLAUDE.md Ask section, and the review
   log.

## Not in scope

- **Embeddings and semantic search** (research stage 4). The measurement ships; the decision waits.
- **A generated query rewrite** on either provider.
- **Agentic tool-calling and adaptive routing.** `TextRequest` has no tool definitions, and the
  research's own numbers say accuracy drops 13.6 points as the corpus grows.
- **A persisted index.** In-memory, rebuilt on a fingerprint change. No new `@Model` for the index, so
  no CloudKit surface, no launch sweep, no progress overlay, and nothing for `EntityProseRewriter` to
  invalidate on a rename.
- **A background `ModelActor`** for the document fetch. Measured, reported, and left for later.
- **Reflect's recaps**: mood over time, area balance charts, weekly and monthly summaries as a
  feature. Rollups here are counts in a prompt, not a screen.
- **Searching inside past conversations**, streaming, and the rest of A7's "Not in scope".
- **Non-English stop words, aggregate markers, and date phrases.**
- **Retrieval over `EntityLink.surface`, contact identifiers, or place coordinates.** A8 added them; a
  name already retrieves through enrichment, and a coordinate is not something a question asks in.

## Review fixes (sub-agent review of revision 1, verdict "rework", 20 findings)

One finding was discarded: the reviewer wrote `AskFocus.swift` and two test files into the worktree
during its run, then reported them as pre-existing work this spec had failed to account for. The
working tree was clean at 1024 tests before it started and is clean again; the files are kept outside
the repo in case anything in them is worth reading later. Everything below is a real finding, and the
two that changed the design most were checked against the code before being folded in.

Folded in above:

1. **Rollups walked around the gate.** They now count `isSendable` documents only, with cases in
   `AskEligibilityTests`. The hidden-entity half of the finding is moot under the owner's
   counts-only cut, since a rollup names nobody.
2. **The query needed an entity table the snapshot did not have**, which would have put a three-table
   fetch back on the cost line. `AskIndex` carries one; bios and loose ends stay out until send time.
3. **An inherited range as a hard filter regressed a real question.** "What did I do last week?" then
   "What about Maya?" discarded every older Maya entry. Inherited ranges are a boost, never a filter,
   and are dropped when the current question names an entity.
4. **Deleting `BioExcerpts` made entity questions worse.** Enrichment gave forty linked entries one
   identical score. Body and context are now scored separately, and a context-only match renders as
   excerpts.
5. **The slice caps had no enforcement.** Four absolute budgets go to the renderer, which holds each
   one.
6. **Percentages were unusable on device** against a 3,300-character budget. Absolute numbers per
   provider, with rollups and continuity off there.
7. **`matchedCount` would have fired on almost every question.** It now counts against a relevance
   floor, so "12 of 84" means 84 comparable entries.
8. **`graphRevision` was treated as a rename footnote.** Insights save through the exempting path
   (`InsightsCoordinator.swift:41`, `GraphIndexer.swift:223`), so it is the primary signal; without it
   a freshly analysed entry is unfindable by its tag until relaunch.
9. **`max(Entry.updatedAt)` reintroduced a clock-step-back hole** the project already refused for
   `graphIndexedAt`. `EntrySaver` gains a monotonic revision instead.
10. **Two sources of truth for "aggregate".** The query hints, the plan decides.
11. **"What was sent" needed persistence.** `AskMessage` gains two defaulted properties, with
    `CloudKitSchemaRulesTests` cases.
12. **The cost line stopped being exact** while "What was sent" stayed true. The plan is capped to
    what fits and the line reads as an estimate.
13. **The build moved the main-actor cost rather than removing it**, and the ceiling test would have
    measured only the half that was already fast. Timing is reported in two halves, and the fetch cost
    is stated instead of hidden.
14. **The quality harness marked its own homework.** Expected sets are written before the first run,
    and follow-ups are scored with continuity disabled.
15. **Prefix dilution at `1 / count` defeated the panel's main case** ("mar"). IDF-weighted, best
    expansion per document, with a substring fallback that also retires revision 1's open question
    about losing "iver".
16. **Unnamed breaking tests.** All of them are listed, including the context-only snippet row that
    would have shown a result with no visible reason for being there.
17. **Scope.** Rollups overlapped Reflect and the phase was too big for one PR. Both went to the owner
    and are settled under "Owner decisions" above.
18. **API gaps:** `AskIndex.empty` declared, `tagCounts` takes a folded string, `JournalSearch` gets
    its own `search(terms:expandingLastTerm:)` entry point, `EntityDirectory.root(of:)` returns a
    `UUID` so names are a second lookup, `refreshIfNeeded` has an in-flight guard, and the claim that a
    fake builder proves off-actor execution is dropped, since a fake without `@concurrent` runs on the
    caller.
