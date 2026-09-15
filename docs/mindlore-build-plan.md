# Mindlore — Build Plan

**A voice-first journaling app with a compounding personal knowledge graph.**

Version 0.1 — September 2026

---

## 1. What We're Building

A mindfulness/journaling iOS app where the user speaks (or writes) an entry, gets it transcribed, and receives AI-generated insight — using **their own API key**. The differentiator is not the transcription or the single-entry analysis (both are commodity in 2026). It's the **knowledge graph**: a persistent, evolving map of the people, places, projects and themes in the user's life that gets injected as context into every future analysis, so insight quality *compounds* over time instead of resetting each session.

### The core loop

1. Record (or type, or photograph a paper journal page)
2. Transcribe
3. Extract entities → prompt user for a short bio on anything new
4. Analyze the entry *with the entity graph as context*
5. Periodically re-synthesize across entries into rolling summaries
6. Browse the result as a traversable 2D node graph

### Why this is defensible

The competitive scan (see §9) found a crowded voice-journaling market. Nearly every competitor does **entry → summary, one-shot, no memory**. None of them build a durable entity graph that makes the *next* analysis better. That's the moat, and it's also the hardest part to replicate, because its value accrues to the user over months.

### Business model

- **Free** — user supplies their own API key (BYOK). No inference cost to us.
- **Paid** — we run inference on the user's behalf for those who don't want to manage a key.

This inverts the usual freemium shape: the free tier is fully featured, and the paid tier sells *convenience*, not capability. It also means the knowledge graph can be the most complex and expensive-to-build part of the product without threatening unit economics.

---

## 2. Technology Decisions

Each choice below has a reason and, where relevant, the alternative we rejected.

### Platform & language

| Concern | Choice | Why |
|---|---|---|
| Platform | iOS (iPhone first) | Voice capture is the primary interaction; phone-native is non-negotiable |
| Language | Swift | Only real option for native iOS |
| UI framework | SwiftUI | Declarative, pairs naturally with SwiftData, far less boilerplate than UIKit |
| Minimum target | iOS 26+ | Required for SpeechAnalyzer (see below). Costs us older-device coverage; worth it |
| IDE | Xcode 26+ | Required |
| AI coding assistant | Claude Code | Swift/SwiftUI is not the developer's primary stack; AI-assisted development is assumed throughout |

### Persistence

**Choice: SwiftData.**

The 2026 consensus is that SwiftData is the correct default for new SwiftUI apps targeting iOS 17+, and is considered genuinely production-ready as of iOS 26. It gives us `@Model` macro-based models with no `.xcdatamodeld` file and no `NSManagedObject` subclassing, and it integrates directly with SwiftUI via `@Query`.

**Rejected alternatives:**
- *Core Data* — more mature and still the right call for complex migrations, fine-grained concurrency, or **shared** CloudKit sync. We need none of those. Not worth the boilerplate.
- *GRDB.swift* — faster for genuinely data-heavy workloads (tens of thousands of rows) and better for complex SQL. Our dataset is one user's journal. Premature.

**Caveat to watch:** SwiftData supports lightweight migrations only, and CloudKit sync works for *private* data but not shared data. Both are fine for us — this is a single-user private journal — but it constrains any future "shared journal" feature. Note it and move on.

### Transcription

**Choice: Apple SpeechAnalyzer (on-device) as the default, with OpenAI Whisper API as an optional fallback.**

This is a correction from earlier thinking. An independent benchmark (5,559 LibriSpeech utterances, M2 Pro) found SpeechAnalyzer hit **2.12% WER on clean speech and 4.56% on noisy**, versus Whisper Small at 3.74%/7.95% — roughly a 43% lower error rate — while running about 3x faster. It also reduced word errors ~3.5–4x versus the legacy SFSpeechRecognizer.

Combined with on-device processing (no network, no latency, no cost, no audio leaving the phone), SpeechAnalyzer is the clear default for English.

**Keep Whisper as an option because:**
- Whisper remains more robust on diverse accents and non-native speech patterns
- Whisper supports 100+ languages; Apple's coverage is narrower
- Users on the paid tier may prefer it

**Explicitly rejected:** `SFSpeechRecognizer`. It's the legacy API, it performs worst of the three, and it has undocumented ~1 minute limits on buffer-based requests that make long-form journaling unreliable.

**Also considered:** WhisperKit — on-device Whisper, works back to iOS 16, broadest language support. Worth revisiting only if we decide to lower the minimum iOS target.

### Audio capture

- `AVAudioRecorder` for simple file-based recording (sufficient for v1)
- `AVAudioEngine` if we later want live waveform visualization or real-time streaming transcription
- Store as `.m4a` in the app sandbox

### Entity extraction

**Two-stage, cheap-then-smart:**

1. **`NLTagger`** (Apple's Natural Language framework) — on-device named entity recognition. Free, instant, no API call. Catches obvious person/place/organization names.
2. **LLM pass** — catches what NLTagger misses: projects, recurring concepts, relationships, nicknames, and anything requiring semantic judgment. Runs as part of the analysis call we're already making, so no extra round-trip.

Stage 1 alone is not sufficient — it won't recognize "the Tuesday thing" as a recurring entity. Stage 2 alone is wasteful. Together they're both cheap and thorough.

### AI / LLM integration

- **BYOK architecture** — user's key stored in **Keychain**, never plaintext, never on our servers
- Client calls the provider API directly from the device; **no backend required for the free tier**
- Provider-agnostic abstraction layer from day one (OpenAI, Anthropic, others) — do not hardcode one provider
- Paid tier later adds a thin proxy backend (see §8)

### Handwriting import (paper journal photos)

**Choice: multimodal LLM vision, not on-device OCR.**

Apple's Vision framework (`VNRecognizeTextRequest`) is excellent for printed text — 95–99% on clean documents, matching cloud OCR — but degrades sharply on handwriting. One test of 100 handwritten receipts put Vision at **72% versus Google Cloud Vision at 91%**.

More importantly, research on LLM-based OCR shows that multimodal LLMs perform **error correction based on knowledge of sentence structure and topic** for coherent text — which is exactly what journal entries are. Dedicated OCR wins on random/incoherent strings; LLMs win on prose.

**Therefore:**
- Use `VNRecognizeTextRequest` **only** for page detection, cropping, and deskewing (fast, free, on-device)
- Send the cleaned image to a multimodal LLM for the actual handwriting transcription
- This is a hybrid: on-device capture and clean-up, cloud for the heavy lift

### Graph visualization

**Choice: SpriteKit, 2D.**

- Physics engine built in (`SKPhysicsBody`) gives force-directed layout close to free
- `SKCameraNode` handles pan/zoom/traverse as a solved problem
- Far better performance-to-effort ratio than SwiftUI `Canvas` once node count grows

**Rejected:** SwiftUI `Canvas` (fine for dozens of nodes, struggles with live physics at scale); Metal (overkill below thousands of nodes); 3D (complicates mobile UI for no real gain — this was the user's own call and it's the right one).

### Sync

- **CloudKit** private database, via SwiftData's built-in integration
- Private-only is a known SwiftData constraint and is exactly what we want here

---

## 3. Data Model

```swift
@Model class Entry {
    var id: UUID
    var createdAt: Date
    var source: EntrySource        // .voice, .typed, .imported, .handwritten
    var audioFileURL: URL?
    var transcript: String
    var userEdited: Bool           // did they correct the transcript?
    var analysis: EntryAnalysis?
    var mentions: [Entity]         // resolved entity links
}

@Model class EntryAnalysis {
    var summary: String
    var mood: String               // stored as tag-friendly token
    var themes: [String]
    var openThreads: [String]      // feeds the rollup synthesis
    var generatedAt: Date
    var modelUsed: String          // for reproducibility when models change
}

@Model class Entity {
    var id: UUID
    var name: String
    var aliases: [String]          // "Sarah", "Sar", "my sister"
    var type: EntityType           // .person, .place, .project, .topic, .goal
    var userBio: String?           // what THEY wrote — the ground truth
    var aiSummary: String?         // evolves as mentions accumulate
    var firstMentioned: Date
    var lastMentioned: Date
    var mentionCount: Int
    var relationships: [Relationship]
}

@Model class Relationship {
    var source: Entity
    var target: Entity
    var type: String               // "works with", "conflict", "part of"
    var confidence: Double         // AI-inferred vs user-confirmed
    var userConfirmed: Bool
}

@Model class Summary {
    var tier: SummaryTier          // .daily, .weekly, .monthly
    var periodStart: Date
    var periodEnd: Date
    var content: String
    var sourceEntryIDs: [UUID]
}
```

### Two critical design notes

**Separate `userBio` from `aiSummary`.** The user's own words about a person are ground truth and must never be silently overwritten by an AI-generated summary. Keep them as distinct fields; show both.

**The summary tiers are a compression ladder.** Daily compresses entries, weekly compresses daily, monthly compresses weekly. This is what keeps token costs sane and bounded as the journal grows to years. Never feed raw transcripts into a long-range synthesis — feed the appropriate summary tier.

---

## 4. AI Integration Points & Prompts

There are four distinct AI calls. Keep them separate; don't merge them into one mega-prompt.

### 4.1 Single-entry analysis

Runs on every new entry. Context injected: the transcript + bios of any entities mentioned + the current weekly summary.

```
You are analyzing a personal journal entry. Be direct and concise.
Do not restate the entry back to the user.

KNOWN CONTEXT:
{entity bios for anyone mentioned}
{current weekly summary, if any}

ENTRY:
{transcript}

Respond in exactly this structure:

## Summary
1-2 sentences. What this entry was actually about.

## Mood
Single token from: [anxious, content, frustrated, energized, reflective,
low, angry, hopeful, numb, overwhelmed]. Then one line of evidence.

## Themes
2-4 bullets, one theme per line.

## Entities
- Name — type — how they came up
- Mark NEW if not in KNOWN CONTEXT above.

## Open Threads
Anything unresolved or worth revisiting. Blank if none.

Do not offer advice, therapy-style reflection, or diagnostic language.
Observe and organize only.
```

**Why the constrained mood vocabulary:** free-text mood is unqueryable. A closed set makes "show me every anxious entry in March" trivial and makes trend charts possible. Decide the vocabulary now — retrofitting old entries is painful.

**Why "do not offer advice":** unconstrained, every model defaults to gentle-therapist voice with unsolicited suggestions. It clutters the note and it isn't what the product is for. This app observes; it does not intervene.

### 4.2 Entity bio generation (assisted, not automatic)

When a NEW entity is flagged, prompt the user in-app. Offer a draft based on context, but the user's version wins:

```
Based only on how {name} was described in this entry, draft a
one-sentence neutral description. Do not speculate beyond what was said.
If there is not enough information, say so.
```

### 4.3 Rolling synthesis

Runs nightly or on-demand. Context: today's entries + the tier below + relevant entity bios.

```
Synthesize these journal entries into a {daily|weekly|monthly} summary.

ENTRIES / LOWER-TIER SUMMARIES:
{content}

ENTITY CONTEXT:
{bios of entities appearing more than once in this period}

Produce:
## Arc — what actually happened across this period, 3-4 sentences
## Recurring — what came up more than once
## Shifts — anything that changed from the previous period
## Unresolved — open threads still open

Write plainly. No motivational framing.
```

### 4.4 Graph maintenance

Runs weekly. This is the piece that prevents the graph from going stale.

```
Here is a stored description of {entity} and their recent mentions.

STORED: {aiSummary}
RECENT MENTIONS: {excerpts}

1. Does the stored description still match? If not, propose a revision.
2. Any new relationships to other known entities implied? List with
   confidence (high/medium/low).

Flag rather than assert. The user confirms all changes.
```

Someone filed as "new coworker" eight months ago needs to stop being described that way. Without this pass, the graph silently rots.

---

## 5. The RAG / Context Problem

The hardest engineering question in this app is: **what goes in the context window?**

Sending the whole graph doesn't scale past a few months. Sending too little defeats the entire premise.

### Retrieval strategy, in priority order

1. **Direct mentions** — entity bios for anyone named in the current entry. Always included. Cheap and highest-signal.
2. **Recency-weighted neighbors** — entities linked to those entities that have been mentioned in the last ~30 days.
3. **Semantic similarity** — embed each entry on creation; retrieve the *k* most similar past entries.
4. **Current summary tier** — always include the active weekly summary.

### Embeddings

- Generate on-device where possible (`NLEmbedding`, or a small Core ML sentence-transformer) to keep the free tier genuinely free
- Store vectors in SwiftData; brute-force cosine similarity is completely fine at personal-journal scale (thousands of entries, not millions). **Do not reach for a vector DB.** It's unnecessary complexity here.

### Budget

Set a hard token ceiling per call and fill it by priority order above, truncating from the bottom. Make the ceiling user-visible in settings — BYOK users are paying per token and will care.

---

## 6. Build Phases

Ordered by dependency and by what de-risks the most uncertainty earliest.

### Phase 0 — Spike (before committing)

**Goal:** prove the riskiest assumptions before building the real thing.

1. Bare SwiftUI app: record → SpeechAnalyzer → display transcript
2. One hardcoded API call producing a structured analysis
3. Verify SpeechAnalyzer quality **on your own voice, in your real environments** — subway, walking, in bed

Benchmarks on LibriSpeech do not predict quality on your microphone, your rooms, your accent. Verify before building on top of it.

**Tooling:** Xcode, SwiftUI, Speech framework, `AVAudioRecorder`, Claude Code.

**Exit criteria:** transcription is good enough that you'd actually use it, and the analysis output is worth reading.

---

### Phase 1 — Core capture & storage (MVP)

**This is the phase that has to feel good.** Everything else is worthless if recording is annoying.

1. SwiftData models: `Entry`, `EntryAnalysis`
2. Recording UI — large obvious mic button, waveform feedback, pause/resume
3. SpeechAnalyzer transcription with progress state
4. **Progressive save** — audio persists first, then transcript, then analysis, as independent steps
5. Typed entry mode (equal citizen, not an afterthought)
6. Transcript review/edit screen before commit
7. Keychain API key storage + provider abstraction
8. Single-entry analysis call (§4.1)
9. Entry list view

**Tooling:** SwiftUI, SwiftData, Speech, AVFoundation, Security (Keychain), Claude Code.

**Non-negotiable:** a dropped connection or a phone lock must never lose a recording. This is the one failure mode that kills a journaling app. Design for it now, not later.

---

### Phase 2 — The knowledge graph (the actual product)

1. `Entity`, `Relationship` models
2. `NLTagger` extraction pass
3. LLM entity extraction integrated into the analysis call
4. **Entity resolution** — matching "Sarah" / "Sar" / "my sister" to one record. Harder than it looks; see §7.
5. New-entity prompt flow — non-blocking, skippable, batched
6. Entity detail view: bio, mention history, linked entries
7. Context injection into analysis prompts
8. Embeddings + similarity retrieval

**Tooling:** NaturalLanguage framework, SwiftData relationships, Core ML (embeddings), Claude Code.

**This is where the product becomes itself.** Phase 1 is a commodity voice journal. Phase 2 is the reason to use it.

---

### Phase 3 — Synthesis & longitudinal view

1. `Summary` model and the tiered compression ladder
2. Nightly background synthesis (`BGTaskScheduler`)
3. Weekly/monthly rollup views
4. Mood trend charts (**Swift Charts**)
5. Graph maintenance pass (§4.4)
6. Search across entries and entities

**Tooling:** BackgroundTasks, Swift Charts, SwiftData.

---

### Phase 4 — Import paths

1. Text import (Markdown, plain text, Day One export, Apple Journal)
2. **Handwriting import:** camera → `VNRecognizeTextRequest` for detection/crop/deskew → multimodal LLM for transcription → user reviews and corrects before commit
3. Backfill: run entity extraction and analysis across imported history

**Tooling:** Vision framework, VisionKit (`VNDocumentCameraViewController` for the scanning UI), multimodal LLM API.

**Always show the user the extracted text for correction before saving.** Handwriting OCR will be wrong sometimes, and silently storing a wrong transcript poisons the graph downstream.

---

### Phase 5 — Visualization

1. SpriteKit scene embedded in SwiftUI via `SpriteView`
2. Force-directed layout for entity clusters
3. **Chronological spine constraint** — entries anchored along a time axis, entities blooming off it. Pure force-directed graphs become unreadable past ~100 nodes; the spine keeps it legible.
4. Node styling: entries small, entities larger and colored by type, size scaled by recency-weighted mention count
5. Edge styling: solid = mention, dotted = daily chronological connector, dashed = inferred entity relationship, opacity fading with staleness
6. Tap-to-focus: camera centers, neighbors highlight, everything else dims
7. Pinch/pan via `SKCameraNode`
8. Level-of-detail: cluster into blobs when zoomed out
9. **Precompute layout nightly**, run live physics only on the focused neighborhood

**Tooling:** SpriteKit, `SpriteView`.

Explicitly last. It's the most visible feature and the least essential — a beautiful graph over a thin, contextless dataset is worthless.

---

### Phase 6 — Paid tier

1. Thin proxy backend — Go (plays to existing strengths) or a managed platform
2. Key management, per-user rate limiting, usage metering
3. **RevenueCat** for subscription handling (do not hand-roll StoreKit)
4. Same client code path; the provider abstraction from Phase 1 makes this a config change, not a rewrite

**Tooling:** Go backend, RevenueCat, StoreKit 2.

---

## 7. Known Hard Problems

Flagging these now so they don't surprise us.

**Entity resolution.** "Sarah," "Sar," "my sister," and "S" may all be one person. Get this wrong and the graph fragments into near-duplicates, which is worse than no graph. Plan: alias list on each entity, fuzzy match on write, and *always* let the user merge two entities manually. Never auto-merge silently.

**Prompt fatigue.** Asking "who is this?" after every entry will make people quit. Batch the prompts, make them skippable, and only ask about entities mentioned more than once or clearly significant. An entity can live in the graph with no bio.

**Model drift.** Analyses generated by different models aren't directly comparable. Store `modelUsed` on every analysis so trends can be interpreted honestly later.

**Privacy expectations.** This is among the most sensitive data a person can produce. Commit to: audio and text never leave the device except to the user's chosen provider; no analytics on content; local-first storage; clear disclosure of exactly what gets sent where and when. Say it plainly in-app, not buried in a policy.

**The blank-graph problem.** On day one the graph is empty and the app looks pointless. Onboarding needs to either seed entities via a few setup questions, or set the expectation explicitly that this gets better over weeks.

**iOS 26 minimum.** Locks out older devices. Accepted deliberately for SpeechAnalyzer. Revisit with WhisperKit if adoption data argues otherwise.

---

## 8. Naming

**Working name: Mindlore.**

Checked against the App Store and general web: no App Store app found under this name. Off-store collisions are a small tech blog and an unrelated book shop. "Lore" describes precisely what the entity graph *is* — the accumulated knowledge of who's who and what happened. It's a coined compound, so it's ownable and trademarkable in a way a dictionary word is not.

**Still to do before committing:** live USPTO TESS search, and domain availability for `mindlore.app` / `mindlore.com`.

**Rejected after checking:** Synapse, Tapestry, Mindline, Skein, Contexture, Clew, Weft, Dendrite, Constellate, Throughline, Ariadne, Tessera, Whorl, Cognate, Rhizome — all taken, most with concept-adjacent apps. Backups: Mindweb, Threadline.

---

## 9. Competitive Landscape

Surfaced during name research. All are live voice-journaling apps:

- **Audio Diary** (Soliloquy Apps) — 315 ratings, 4.9★, the most established. Voice journal with optional AI reflection, follow-up questions, monthly summaries.
- **Solilo** — voice-first AI journaling, spoken thoughts into reflections
- **Unspool** — voice journal with AI transcription, mood tracking, weekly insights
- **Murmur, Jots, Glimpse, Lid, ALog, Autobiographer** — all in the same space
- **Constella** — "your digital brain," connected notes with AI memory. Closest to our graph concept, but note-taking rather than journaling.

**What none of them appear to do:** build a persistent entity graph with user-authored bios that gets injected as context into future analyses. Mood tracking and monthly summaries are table stakes now. The graph is the wedge.

**Honest read:** this is a crowded market with established incumbents. The graph is a real differentiator, but it's a *slow-burn* one — its value isn't visible in a 30-second App Store demo. Positioning and onboarding will matter as much as the engineering.

---

## 10. Immediate Next Steps

1. Run Phase 0 spike — 1-2 evenings. Test SpeechAnalyzer on your own voice in real conditions.
2. Lock the mood vocabulary (§4.1). Changing it later means re-analyzing every historical entry.
3. USPTO + domain check on Mindlore.
4. Decide: is this a personal tool or a product? It changes how much polish Phase 1 needs, and whether Phase 6 exists at all.

---

## Appendix — Tooling Summary

| Layer | Tool | Phase |
|---|---|---|
| UI | SwiftUI | 1 |
| Persistence | SwiftData | 1 |
| Sync | CloudKit (private DB) | 1 |
| Audio capture | AVAudioRecorder / AVAudioEngine | 1 |
| Transcription | Speech / SpeechAnalyzer (on-device) | 1 |
| Transcription (fallback) | OpenAI Whisper API | 1 |
| Secrets | Keychain (Security framework) | 1 |
| NER | NaturalLanguage / NLTagger | 2 |
| Embeddings | NLEmbedding or Core ML | 2 |
| Background jobs | BackgroundTasks / BGTaskScheduler | 3 |
| Charts | Swift Charts | 3 |
| Document scan UI | VisionKit | 4 |
| OCR (detect/crop) | Vision / VNRecognizeTextRequest | 4 |
| Handwriting transcription | Multimodal LLM | 4 |
| Graph rendering | SpriteKit + SpriteView | 5 |
| Subscriptions | RevenueCat + StoreKit 2 | 6 |
| Backend (paid tier) | Go | 6 |
| Development | Xcode 26+, Claude Code | All |
