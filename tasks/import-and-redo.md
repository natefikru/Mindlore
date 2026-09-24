# Redo insights on every entry

Both halves ship in one PR, a commit each (owner, 2026-09-23), on `feature/import-and-redo`, built on #56.

Owner, 2026-09-23: "a button somewhere to run AI insights on every single entry again ... done in
queue." Its own PR, off `main`, independent of import.

## What exists

`InsightsCoordinator.processQueue` already is the queue: it fetches entries with
`insightsPending`, in `entryDate` order, and runs one at a time (`isProcessing` guards
re-entry, `needsAnotherPass` picks up anything flagged meanwhile). `runAI(for:)` is the manual
path for one entry: `automaticAIPassUsed = true`, `AIJobPolicy.manualReset(.insights)` (pending,
attempts 0, failure cleared), save, process. The flag is stored, so a queue cut short by a kill
resumes at the next launch: `canRunAutomatically` is true for a pending entry with attempts under
the cap.

## Change

- `InsightsCoordinator.redoAll(context:)`: every entry `canRunAI` accepts (drafts, entries
  awaiting text, and unapproved pages are left out) gets the same reset `runAI` gives one entry,
  in one save, then `processQueue`. Oldest first, so loose ends settle in the order they were
  written.
- **Progress** is observable on the coordinator: `redoTotal` and `redoDone` for the run, cleared
  when the queue empties. Settings shows "Redoing insights: 42 of 213" with Stop.
- **Stop** clears `insightsPending` on the entries not yet started; the one in flight finishes.
- **Moods the user picked stay.** A rerun writes `setMoods(..., editedByUser: false)` today, which
  overwrites a mood chosen by hand. Rerunning one entry on purpose may mean "try again", but
  redoing 213 must not quietly undo every correction. The bulk path keeps them when
  `moodsEditedByUser`. The other user choices already survive a rerun: `creativeSetByUser`,
  `.user` links, merges, hidden names, loose ends the user touched, a picked day.
- **Offline** pauses the queue as it already does (`pausedForOffline`) and resumes when the
  network returns.
- **Where**: Settings, AI, below What AI does: "Redo insights for every entry", disabled when
  insights are off. A confirmation first, naming who reads them: "Sends 213 entries to OpenAI,
  one at a time" or "Runs on this iPhone, 213 entries, one at a time". No cost in dollars: the
  price per token isn't known to the app.
- Diagnostics: `insights.redoAll` with the count, `insights.redoStopped` with done and total.

## Tests

`InsightsTests` harness with `FakeTextGenerator`: every eligible entry is queued and run in
`entryDate` order, drafts and unapproved pages skipped; progress counts up and clears; Stop
leaves the untouched entries unpending and the finished ones done; a user-picked mood survives
the bulk run; a creative pick survives; a relaunch (new coordinator, same store) finishes the
rest. UI test: the row, the confirmation, progress appears.

## Not in scope

Titles and bios (insights only, as asked). A per-entry cost estimate. Running while the app is in
the background.


# Import a Mindlore export

Owner, 2026-09-23: "I only care about a Mindlore export." No Markdown, Day One, or Apple Journal.
Branch `feature/journal-import` from `main` once #56 is merged (the button lives on its General
screen), worktree `.claude/worktrees/journal-import`.

## The problem with today's export

`journal.json` was written to be read by a person or a script, not to be restored. It keeps each
entry's words, dates, title, formatting, recordings, and page photos, plus flattened mood, areas,
tags, and resolved names. It drops what a restore needs:

- Entry: `isCreative`/`isNote` (kind), `entryDateIsDayOnly`, `textWasGenerated`,
  `textEditedByUser`, `titleWasGenerated`, `originalText`/`originalFormattingRaw`/
  `cleanupAppliedHash` (cleanup revert).
- EntryPage: order, `transcribedText`, `writtenDate`, origin, size, thumbnail.
- EntryInsights: `mentionsData`, `sectionsData` (parts), `cleanedText`, custom cards,
  `moodsEditedByUser`, `sourceTextHash`, `generatedAt`, `modelUsed`. `GraphIndexer` builds the map
  from mentions and parts, so without them the map can't be rebuilt at all.
- Entity: merges (`mergedIntoID`, `contributedAliases`), `notSameAs`, `resurfacingMuted`,
  `confirmedByUser`, `kindEditedByUser`, bio provenance, place and contact ids. Merged losers are
  left out entirely.
- EntityLink: not written at all (only the resolved name per entry), so `.user` links from Add a
  name, repoints, and `unsureAmong` are gone.
- LooseEnd: `id`, `userTouched`, `resolvedByEntryID`, `lastMentionedAt`, `statusChangedAt`,
  `promptedAt`.
- AskConversation/AskMessage and ReflectSummary: not written.

## Approach: export writes the records, import puts them back

`journal.json` keeps its current readable fields for people and scripts, and gains a `version: 2`
and a `records` block: every persisted model, stored properties as they are (raw strings, ids,
dates, the JSON `Data` blobs base64), media referenced by the file names export already writes.
Job bookkeeping (attempts, failures, pending flags, chunk plans, `contentRevision`,
`graphIndexedAt`) is not written; import sets it.

Import restores records, not a re-analysis. The links, merges, and parts come back as they were,
so no AI runs and the map is the one that was exported. Then `GraphIndexer.recount` fixes the
denormalized counts.

- **Ids are kept.** An entry, entity, link, loose end, or conversation whose id already exists in
  the journal is skipped, never overwritten: the journal's copy may be newer (it syncs), and an
  import never loses anything. Importing the same folder twice adds nothing.
- **A name the journal already has under another id** (same `EntityNormalizer` key and kind, not
  merged, not hidden): imported links point at the existing entity and the imported one isn't
  created, its aliases and bio added only where the existing one has none. Otherwise a journal
  started fresh on a new phone would get a second Maya beside the one AI already made.
- **No AI on the way in.** Every imported entry gets `automaticAIPassUsed = true`,
  `awaitingText = false`, nothing pending, `pagesConfirmed = true` for photo entries,
  `graphIndexedAt = now`. Drafts stay drafts.
- **No re-indexing either.** `GraphIndexer.staleEntries` treats an entry as stale when
  `graphIndexedAt != insights.generatedAt`, and a stale entry has its `.ai` links deleted and
  resolved again against today's entities. So import sets `graphIndexedAt = insights.generatedAt`
  exactly (nil when there are no insights), not now (plan review).
- **Relationships and ids together.** Entities and entries are inserted before anything that
  points at them, and a link is attached with `attach(to:entity:)`/`point(at:)` so the
  relationship and the id field agree (`EntityLink.swift:57-60`: a link saved against a target the
  store hasn't seen keeps a nil relationship). Pages and insights are attached to their entry the
  same way. A test reads the relationships back, not just the ids.
- **The existing copy wins whole.** When an entry's id is already in the journal, everything
  hanging off it in the import is skipped too: its insights, pages, links, and the loose ends it
  raised. Pieces are never grafted onto an entry the journal already has, or a to-one insights
  would be overwritten and links doubled. Entities, loose ends, conversations, and messages whose
  ids exist are skipped the same way.
- **Entity ids are remapped before anything else goes in.** When an imported name is reused onto
  an existing entity, every field holding an entity id is rewritten: `Entity.mergedIntoID`,
  `Entity.notSameAs`, `EntityLink.entityID`/`originalEntityID`/`unsureAmong`,
  `LooseEnd.entityIDs`. Entry ids are never remapped (entries are matched by id only), so
  `sourceEntryID`, `resolvedByEntryID`, `citedEntryIDs`, `sentEntryIDs`, `handleMapData`, and
  `bioSourceEntries` stay as they are.
- **Saved through `saveStampingEntries` with every imported entry in `except:`**, or stamping
  gives each one `updatedAt = now` and `EntryDuplicates` would later prefer it over a newer synced
  copy. Saved in batches of 100 entries (media is the weight), then one `JournalSaves.revision`
  and one graph revision bump at the end, so `EntryBackups` copies every entry and Ask's index,
  Today, and Reflect refresh once.
- **Media is read per entry at insert time**, never all at once: the JSON is parsed and validated
  whole first, the audio and photos are read from disk as each entry goes in.
- **Things that should happen and look like bugs:** a restored loose end already past its fade
  date fades at the next launch sweep (`LooseEnd.fade`), which is correct. A restored generated
  bio keeps `bioWasGenerated`/`bioDraftedAt`, and the bio drafter must not treat it as due; tested.
- **Version 1 exports** (everything made before this ships) are refused with a sentence saying to
  export again from the phone the journal is on. The app is unshipped and the owner has said no
  backwards compatibility; a v1 import would bring back entries without their map, and look like
  data loss.
- **A partial folder** (media missing, a malformed record) imports what it can and says how many
  were skipped; the JSON is read whole first, so nothing is written from a file that can't be
  parsed.

## Phases

1. **Export v2.** `JournalExport.Records` with one Codable record type per model
   (`Mindlore/Export/JournalRecords.swift`), written into `journal.json`. Tests in the existing
   `JournalExportTests` (`MindloreTests/TrustTests.swift:85`): every field set on a fixture of each
   model appears in the records; media names match; bookkeeping is absent.
2. **Import.** `JournalImport.read(folder:)` (pure, `nonisolated`, parses and validates, off the
   main actor) and `JournalImport.apply(_:into:)` (main actor, inserts, dedupes, one save).
   Tests in `JournalImportTests`: the round trip (build a journal with every kind of record,
   export, import into an empty in-memory store, compare every stored property, including a merge,
   a user link, a repoint, a muted name, a closed loose end, a cleanup with its original, parts,
   a note, a creative piece, a day-only date, a photo entry's page text, an AI-suggested date that
   `EntryDateRepair` must leave alone, relationships as well as ids); nothing is stale to
   `GraphIndexer` or due for a bio draft afterwards; an existing entry skips its children; a
   reused entity's id is rewritten in `notSameAs`, `unsureAmong`, `mergedIntoID`, and loose ends;
   imported entries keep their `updatedAt`; importing twice adds
   nothing; an existing newer entry is kept; a same-key entity is reused; nothing is AI-eligible
   afterwards (`AIPassTrigger.isEligible` false for every imported entry); v1 is refused; a
   missing media file skips that file only. Diagnostics `journal.imported` (counts only) and a
   row in `docs/privacy-coverage.md`.
3. **UI.** General's Your data section gets Import journal: `.fileImporter` for a folder
   (security-scoped), a sheet that says what's in it ("412 entries, 96 names, 3 recordings are
   already here") with Import and Cancel, a progress state, then the result in the section
   footer like Export's. Disabled while recording, like Delete. No UI test: the system folder
   picker can't be driven from XCTest, so the unit tests carry it and the phone step checks the
   picker.
4. **Phone.** Export the real journal, import it into the story journal's store (never the real
   one), look at Mind, Today, Ask, a photo entry, and the log.

## Not in scope

- Any other format. Merging two different journals' edits to the same entry (the journal's copy
  wins). Importing into a journal's settings, key, or life-area renames (Settings are not journal
  data). Undo of an import (a later PR if wanted; export first is the safety net).

## Open questions for the owner

- Should Chat conversations and Reflect summaries come back too? Planned yes: they're small and
  otherwise lost.

## Plan review (2026-09-23)

A Sonnet reviewer read this against the code and found: the `graphIndexedAt` mismatch that would
have re-indexed every imported entry at the next launch; relationships not named; the entity-id
remap unlisted; a skipped entry's children would have been grafted on; stamping would have set
`updatedAt = now`; media loaded all at once; one enormous save. All folded in above.
