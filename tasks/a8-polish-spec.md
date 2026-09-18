# A8 build spec: the phone's own world, and the journal's manners

Branch `feature/phase-a8-polish`, off `feature/phase-a` at `c154ee8`, PR against `feature/phase-a`.
Implements the nine A8 items in `tasks/todo.md:657-695`. Runs in a worktree beside A7 (Ask), which
owns `Mindlore/AI/Ask/` and the Ask views.

Both lanes append to `SettingsStore`'s `Key` enum (`SettingsStore.swift:6-34`). Different keys still
conflict textually in one block, so **A8 rebases onto `feature/phase-a` before opening its PR and
takes the conflict** if A7 landed first.

Nine items, four groups. Contacts, places, and the rename rewrite carry the design weight. The
journal-list items are small but touch views every UI test walks through.

## What exists today

- **`Entity`** (`Mindlore/Models/Entity.swift:22-63`) has 23 stored value properties plus the `links`
  relationship, every one optional or defaulted, nothing unique. `CloudKitSchemaRulesTests` fails the
  build otherwise. No field points at anything outside the app.
- **`GraphEditor.rename`** (`GraphEditor.swift:32-50`) renames, re-keys, optionally appends the old
  name to `aliases` when `keepingOldNameAsAlias` is true and the old name's key actually differs,
  claims the entity, and logs `graph.entityEdited`. It never saves. `GraphServices.rename`
  (`GraphServices.swift:55`) wraps it in `edit`, which calls `save` and bumps `revision`
  (`GraphServices.swift:210-224`).
- **Two saves, not one.** `GraphServices.save` calls `saveStampingEntries()` with no exemptions.
  `GraphEditor.save(_:touchedBy:)` (`GraphEditor.swift:312-320`) is the one that exempts entries whose
  links moved, because "moving a link is not an edit to the entry". Anything that writes through
  `EntryInsights` puts the owning `Entry` into `changedModelsArray` and moves its `updatedAt`
  (`ModelContext+Stamping.swift:6-13`).
- **`NameMatching.ranges`** (`NameMatching.swift:11-17`) is a whole-*word* matcher, case-insensitive:

  ```swift
  let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}])"
  ```

  A space is not `\p{L}`, so "Sarah" matches inside "Sarah Jane", and "Mark" matches the verb in
  "make your mark". It finds a name in an entry so a chip can point at it. It is not safe to hand
  straight to a replacement.
- **App-generated prose** lives in three places that can name an entity: `Entity.bio`
  (`EntityBioDrafter.swift:100-106`), `EntryInsights.summary` (`InsightsCoordinator.swift:224`), and
  `LooseEnd.text` (`LooseEndWriter.swift:63-71`). The user's own words live in `Entry.text`,
  `Entry.originalText`, `EntryInsights.cleanedText` (a cleaned copy of the user's words), and
  `EntityLink.surface` / `writtenSurface` (the entry's own wording, which read-mode highlighting
  measures against the entry). `EntryInsights` has **no `entryID`**: it reaches its entry through
  `var entry: Entry?` (`EntryInsights.swift:8`).
- **"the writer"** appears in twelve prompt strings (`InsightsPromptBuilder.swift:142, 155, 204, 216,
  243, 263`, `LifeArea.swift:18, 23`, `EntityBioDrafter.swift:68, 69`, `TitleCoordinator.swift:18`,
  `PageTranscriber.swift:36`) and in two strings the user actually sees: the custom-prompt placeholder
  (`AIFeatureSettingsViews.swift:319`) and the UI-test stub bio (`UITestingHTTPClient.swift:34`).
- **The loose-end bar** is one abstract paragraph with no examples. `InsightsPromptBuilder.swift:214-220`
  is the bar itself; `221-223` appends the entry date and `224-230` the known-handle block.
- **`SettingsStore`** has 28 keys read in `init` through helpers that all go via `object(forKey:)`.
  User-typed words go through `writeJSON` and are never logged verbatim (`SettingsStore.swift:144-146`).
- **The journal list** (`EntryListView.swift`) is one flat `List` with the area filter as row 0, one
  `ForEach(shownEntries)`, and `.onDelete` indexing straight into `shownEntries` (`:186-197`).
  `EntryRow` (`:217-296`) stacks up to five elements and is tall.
- **The area filter** is single-select (`EntryListView.swift:16`) through the pure `JournalFilter`
  (`Views/Shell/JournalFilter.swift`, 22 lines, 4 tests), which takes `[[String]]` rather than
  entries, so it stays `nonisolated`. No test touches `areaFilter-<raw>`.
- **The peek card** detent is `PresentationDetent.height(220)` (`EntityPeekCard.swift:11`) and its head
  is an `HStack(alignment: .firstTextBaseline)` of a `Label` (name plus kind symbol) and an "Open"
  button.
- **The cleanup card's "Not now"** is `EntryEditorView.swift:391`, with no identifier and no test.
  `RepointView.swift:112` has its own "Not now" on a different screen.
- **Both privacy suites** live in `MindloreTests/DiagnosticsLogTests.swift` (`DiagnosticsPrivacyTests`
  at :117, `AIDiagnosticsPrivacyTests` at :169). There is no separate file. The required-event loop at
  `:325-330` fails the moment an event name is added without a call that exercises it.
- **Nothing imports Contacts, MapKit, or CoreLocation.** Usage descriptions are build settings
  (`project.pbxproj:417-419` Debug, `453-455` Release). `PrivacyInfo.xcprivacy` declares UserDefaults
  only, and `PrivacyManifestTests` already asserts no collected data types.

## The model's manners

### First person

A setting picks the voice the app writes in, and Settings learns the user's name.

```swift
nonisolated enum JournalVoice: String, CaseIterable, Codable, Sendable { case first, second, name }
```

The prompt needs two things separated, or the instruction contradicts itself: who the instruction is
*about*, and what person the output is *written in*. Telling a model "the strongest mood I express"
makes the model the speaker. So every prompt refers to the author as **"the author"**, and one line
tells the model what voice to write in:

| Setting | Instruction added to the system prompt |
|---|---|
| `first` (default) | "Write about the author in the first person, as I and my." |
| `second` | "Write about the author in the second person, as you and your." |
| `name` | "Write about the author by name, as Nate." |

`Mindlore/AI/PromptVoice.swift` is a pure `nonisolated struct` with `subject`, `possessive`, and
`instruction`, built from the setting and the name. `.name` with an empty or whitespace name falls
back to `.first`, so the model is never told to write "as ." It lives in its own file, not in
`AIServices`, so A7 can adopt it after the merge without a conflict.

**The name is only put in the prompt under `.name`.** Under first and second person the model has no
use for it, and sending it is disclosure for nothing.

All fourteen "the writer" strings change. The twelve prompt sites become "the author"; the
custom-prompt placeholder becomes "What am I grateful for?"; the stub bio in `UITestingHTTPClient`
loses the phrase, since it is what every stubbed UI run renders on screen. The voice instruction is
appended in `InsightsPromptBuilder.plan` and `EntityBioDrafter.request`, which covers summaries, bios,
and loose ends, which is what the plan asks for. `LifeArea.meaning`'s two strings stay static and
reworded, since the voice instruction governs the output. `LifeAreaTests.swift:19-20`,
`EntityBioTests.swift:138, 143, 425, 427`, and `OpenAILiveTests.swift:68` are updated.

The page transcriber is copying handwriting and has no voice, so it only loses the phrase. Titles are
in Open questions.

**Settings.** Two keys: `journalVoice` (raw string, default `first`) and `userName` (the user's own
words, so it follows the `lifeAreaNames` pattern: trimmed, capped at 40 characters, never logged
verbatim). `AISettingsView` gains a row under "What AI does", "How AI writes about you", opening
`JournalVoiceSettingsView`: a picker with the three options, each showing a sample sentence, and a
name field. The footer says the name goes to your AI provider in prompts when you pick the name
option.

`AIDiagnosticsPrivacyTests` sets the name to the sentinel and runs a real insights pass and a real bio
draft to prove it never reaches the log.

### Loose ends are commitments

The bar today is abstract with no examples, and the model reads "waiting to hear from someone"
generously. Tighten it to a commitment worth keeping for days or weeks, and show both sides.
**Only `InsightsPromptBuilder.swift:214-220` is replaced.** The entry-date sentence (221-223) and the
known-handle block (224-230) are untouched, as are the schema, the caps, and the parser, so
`LooseEndTests` keeps passing and the change is checked against the real model.

```
A loose end is a commitment: a plan to make, a task to do, a decision not yet made, or something
being waited on. It has to still be open when the entry ends, be worth keeping for days or weeks,
and be something a later entry could settle.

Yes: call the landlord about the lease. Decide whether to take the Denver job. Waiting to hear
back from the clinic. Book flights before the wedding.

No: a feeling or a mood. An intention to think about something more. Anything already done by the
end of the entry, such as grabbing coffee after this or finishing a page. Anything that settles
itself within the day.

Most entries have none, and an empty list is the normal answer. Write at most \(maxNewLooseEnds)
new ones.
```

The cap stays interpolated from `maxNewLooseEnds`, as it is today.

## Rename carries through the app's own words

Renaming an entity keeps the old spelling as an alias and replaces the name wherever the app wrote it
itself. Entries are never edited. What the user wrote stays as written, and a misheard name still
reads as it was said, while the name tapped in read mode resolves through the alias to the renamed
entity.

**Rewritten** (the app's own sentences):

| Field | Found by |
|---|---|
| `Entity.bio` | one fetch of every entity, skipping `bioEditedByUser`. Any entity's bio can name any other. |
| `EntryInsights.summary` | the entries this entity links to, via `EntityLink.entityID` |
| `LooseEnd.text` | `LooseEnd.entityIDs` containing the id, resolved through `mergedIntoID` |

**Never touched**: `Entry.text`, `Entry.originalText`, `Entry.title` (see Open questions),
`EntryInsights.cleanedText` (the user's own words, tidied, and `cleanupAppliedHash` measures against
them), `EntryInsights.sourceTextHash` (so a rewrite never makes insights look stale),
`EntityLink.surface` and `writtenSurface`, and any bio the user edited by hand. A bio the user wrote is
the user's words, and the same rule that protects an entry protects it, matching
`EntityBioDrafter.mayWrite` (`:36-38`).

### The matching rule

`NameMatching` alone would corrupt the prose: it matches inside "Sarah Jane" and, being
case-insensitive, matches the ordinary words behind names like Mark, Will, Ray, Hope, and April. So
`EntityProseRewriter` uses `NameMatching.ranges` only as a candidate finder and then applies its own
rule, which errs toward leaving prose alone:

1. The matched substring must equal the old name **exactly, including case**. The app writes the name
   as the entity carries it, so this costs almost nothing and kills the common-word class outright.
2. A candidate immediately followed by a space and a capitalized word is skipped, which leaves
   "Sarah Jane" alone. It also skips "Sarah Monday", which is a harmless miss: not rewriting is the
   safe failure.
3. Same on the leading side: a candidate preceded by a capitalized word and a space is skipped.
4. Replacement runs **back to front** over the surviving ranges, so earlier indices stay valid.

```swift
nonisolated enum EntityProseRewriter {
    struct Counts: Equatable { var bios = 0; var summaries = 0; var looseEnds = 0 }
    static func rewrite(_ text: String, from old: String, to new: String) -> String?  // nil when nothing changed
}
```

### The store walk and the save

The store-walking half is `rewriteAll(oldName:newName:entityID:in:) -> (Counts, touched: [UUID])`,
returning the entry ids whose insights it edited. It follows the SwiftData rules in
`tasks/lessons.md`: one `fetch(FetchDescriptor<Entry>())` and one of `Entity`, filtering the id set in
memory on saved objects; `LooseEnd.all(in:)` filtered in memory on `entityIDs.contains`; merges
resolved from a single `[UUID: Entity]` map with the cycle guard, the way `EntityPeekPresentation.load`
already does (`:40-47`). **No `#Predicate` reaches through a relationship or over an array.**

It runs inside `GraphEditor.rename`, after the name actually changed. `GraphServices.rename` stops
using the generic `edit` and saves through the exempting path instead:

> Rewriting a summary marks its entry changed through the relationship, but it is not an edit to the
> entry. Every entry the rewrite touched is exempted from stamping, the same rule
> `GraphEditor.save(_:touchedBy:)` already follows for moved links.

One save, one revision bump, and no entry's `updatedAt` moves.

`graph.renameRewrote` logs `["id": .id(entity.id), "bios": .int, "summaries": .int, "looseEnds": .int]`.
No text, no names.

### The alias and the sheet

**The alias is always kept.** `keepingOldNameAsAlias` and the sheet's toggle go away: the plan states
the rule without an exception, and the alias is what makes old entries still resolve. The existing
guard stays, so a rename that normalizes to the same key (fixing capitalization) still adds no alias.
This touches `GraphServices.swift:55-56`, `GraphEditor.swift:32, 44`, `EntityView.swift:130-131`, and
the tests at `GraphEditorTests.swift:108, 112, 127, 136` and `EntityPageEditTests.swift:76`. It leaves
`EntityPagePresentation.hasVoiceSourcedLink` (`:36`) with no caller, so that and
`EntityPagePresentationTests.swift:28-31` are deleted. The id `entityRenameKeepOldName` has no UI-test
references.

The counts depend on the **old** name, not the typed one, so there is nothing to recompute per
keystroke. `EntityView` computes them once when the sheet opens (it has the `modelContext`;
`RenameEntitySheet` does not) and passes them in. The sheet reads "Also updates up to N summaries,
N bios, and N loose ends the app wrote." It says "up to" because a background insights pass or bio
draft can land while the sheet is open. The real numbers are counted again at commit and are what
`graph.renameRewrote` logs.

The rewrite is not undoable, like every other edit in the app.

## Contacts and places: one avatar slot

The peek card's content is kind-agnostic today. A map preview tall enough to read does not fit the
220 pt detent, and growing the detent after the async summary loads animates the card in the user's
face.

So both features land in the same place: the symbol at the head of the card becomes an **avatar slot**.
A person with a linked contact shows the contact's thumbnail. A place with a location shows a map
snapshot. Everything else shows today's kind symbol.

The head is restructured from `HStack(alignment: .firstTextBaseline)` to `HStack(alignment: .top)`
with the avatar leading a `VStack` of name and details, so a square image is not baseline-aligned
against the "Open" button. **The detent is measured, not assumed**: if 220 no longer holds, the avatar
drops to 32 pt and the bio's `lineLimit` drops to 1 when an avatar is present. A screenshot in the
simulator settles it before the unit is committed.

The entity page has room, so there the place gets a real 140 pt map and an "Open in Apple Maps"
button, and the person's photo sits in the header.

### Storage

`Entity` gains four properties, all optional, none unique, so `CloudKitSchemaRules.violations` stays
empty:

```swift
var contactIdentifier: String?   // CNContact.identifier. Never a copy of the contact's details.
var placeIdentifier: String?     // MKMapItem.Identifier.rawValue, when the search result has one.
var placeLatitude: Double?
var placeLongitude: Double?
```

A name, address, phone number, photo, or map thumbnail is never written to the store. The photo and
the snapshot are fetched at display time and held in memory only. The place's label on the map is the
entity's own name, which the app already had.

### The two directories

Neither framework is called from a view, and neither protocol is main-actor: `CNContactStore`'s
fetches are blocking and `MKMapSnapshotter` does real work, so holding the main actor for either
(once per card render) is exactly what CLAUDE.md's concurrency rule forbids. Both follow the shape
every injected I/O boundary in this codebase already uses (`HTTPClient.swift:15`,
`TextGenerator.swift:33`, `PageTranscriber.swift:19`):

```swift
nonisolated struct ContactMatch: Sendable, Equatable {
    let identifier: String
    let name: String
    let thumbnail: Data?      // held in memory, never persisted
}

nonisolated protocol ContactDirectory: Sendable {
    var access: ContactAccess { get async }          // notDetermined, limited, authorized, denied
    func requestAccess() async -> ContactAccess
    func search(_ query: String) async -> [ContactMatch]
    func contact(_ identifier: String) async -> ContactMatch?
}

nonisolated protocol PlaceDirectory: Sendable {
    func search(_ query: String) async -> [PlaceMatch]
    func thumbnail(for coordinate: PlaceCoordinate, size: CGSize) async -> Data?
}
```

`PlaceMatch` carries `identifier: String?`, `name`, `locality: String?` (shown in the picker only,
never stored), and `coordinate`. **No method returns an `MKMapItem`**, which is not `Sendable`: the
view builds and opens the item on the main actor from the identifier and coordinate.

`CNContactDirectory` fetches only `CNContactIdentifierKey`,
`CNContactFormatter.descriptorForRequiredKeys(for: .fullName)`, and `CNContactThumbnailImageDataKey`,
so nothing else can leak. Results are capped at 25, and a per-session in-memory cache holds at most 50
thumbnails. `MKPlaceDirectory` uses `MKLocalSearch` with no region bias and no location permission, so
the app never asks where the user is; `thumbnail` is `MKMapSnapshotter`, cached by rounded coordinate,
capped at 50.

Opening Apple Maps tries `MKMapItemRequest` by identifier first, so the real place opens with its
hours and reviews, and falls back to a coordinate-only item. Apple documents that an identifier can
stop resolving, so the fallback is load-bearing, not an edge case. Both are written against the iOS 26
construction API (`MKMapItem(location:address:)`), not the deprecated `MKPlacemark` initializer.

`RootView` builds both and passes them through the environment, beside `NetworkMonitor`.

### Linking and permission

Linking is always manual. The app never scans contacts in the background, never matches names on its
own, and never asks for contacts access until the user taps the row.

Contacts goes through **`CNContactStore` authorization with a custom sheet**, not
`CNContactPickerViewController`. The picker needs no permission, but it also grants no ongoing read
access, and the photo has to be read live on every render precisely because it is never stored. The
two cannot be mixed, so the app asks properly and handles what it is given:

- **Unlinked**: "Link to a contact" on a person, "Find this place" on a place. Tapping the contact row
  asks for access the first time.
- **Denied or restricted**: "Contacts access is off" with a button to Settings. The entity keeps
  working exactly as it does now.
- **Limited** (iOS 18+): the sheet shows only the contacts the user granted, with a line saying so and
  a button to grant more. `CNContact.predicateForContactsMatchingName` matches name components only
  and rejects an empty string, so the sheet requires at least one character and is seeded with the
  entity's name.
- **Linked**: the row shows the contact's name (read live) or the map, with "Unlink".
- **Unreadable**: a contact that cannot be read, whether it was deleted or access was narrowed, falls
  back to the kind symbol on the card silently. The entity page says "Mindlore can't read this
  contact" and offers Unlink. The identifier is never cleared automatically, because granting access
  again brings it back.

Only a `.person` can link a contact and only a `.place` a location. `GraphEditor.setKind` clears the
link when the kind changes away, **after** its collision guard (`GraphEditor.swift:63-70`), which
returns early before mutating anything.

### The edits

`GraphEditor` stays the only thing that changes an `Entity`:

```swift
func linkContact(_ entity: Entity, identifier: String) -> EditOutcome
func unlinkContact(_ entity: Entity) -> EditOutcome
func linkPlace(_ entity: Entity, identifier: String?, coordinate: PlaceCoordinate) -> EditOutcome
func unlinkPlace(_ entity: Entity) -> EditOutcome
```

with `GraphServices` wrappers over `edit`, so each is one save and one revision bump, and every view
refreshes off `.task(id: graph.revision)` as it already does.
`EntityPeekPresentation.Summary` gains `contactIdentifier: String?` and `place: PlaceCoordinate?`, so
the pure summary stays testable and the card does the fetching.

### Privacy

- `INFOPLIST_KEY_NSContactsUsageDescription` is added to **both** configurations
  (`project.pbxproj:417-419` and `453-455`): "Mindlore shows a contact's photo next to the people in
  your journal. It reads only the people you pick."
- No location permission key. `MKLocalSearch` and `MKMapSnapshotter` need none, and the app never asks
  for the user's position.
- **Two disclosures the app makes and should say out loud**: searching for a place sends the entity's
  name to Apple, and drawing the preview sends the coordinate. The place picker's footer says so, the
  way the name field's footer says the name goes to the AI provider. Nothing is stored and nothing is
  logged, but "nothing leaves the phone" would be false.
- `PrivacyInfo.xcprivacy` is unchanged: neither framework is on Apple's required-reasons list, and
  nothing new is collected. `PrivacyManifestTests` already covers this and needs no new case.
- Diagnostics carry ids and counts only: `graph.contactLinked`, `graph.contactUnlinked`,
  `graph.placeLinked`, `graph.placeUnlinked` with `["id": .id(entity.id)]`, and `graph.contactAccess`
  with the status's raw value. **No contact name, no contact identifier, no place name, and no
  coordinate ever reaches the log.** `DiagnosticValue` has a `.double` case, so a latitude is one
  careless call away, which is what the sentinel cases are for.

## The journal reads like a journal

### Grouping

`JournalGroups` is pure and takes dates, not models, so it stays `nonisolated` the way `JournalFilter`
does:

```swift
nonisolated enum JournalGroup: Equatable {
    case later          // dated after today, which the date picker allows
    case recent         // today
    case yesterday
    case thisWeek       // the current calendar week, minus today and yesterday
    case month(Int)     // an earlier month of the current year, named
    case year(Int)      // any earlier year, numbered
}

static func build(_ dated: [(id: UUID, date: Date)], now: Date, calendar: Calendar) -> [(JournalGroup, [UUID])]
```

**Every comparison is at `startOfDay` granularity.** An entry created at 8pm has `entryDate == now`;
comparing `> now` would flip it between Recent and Later on every re-render.

The groups partition cleanly and the query is already newest-first, so the order falls out with no
extra sorting. A year collapses into one group rather than months within years, which is what the plan
asks for and what a 365-day seed makes readable. The header is the group's name: "Later", "Recent",
"Yesterday", "This week", "August", "2025". In the first days of January, "This week" can carry dates
from late December while the rest of that December sits under its year; the order is still right and
the label is still true.

The filter row stays as the first `Section` with no header, above the groups. **`onDelete` moves per
section**, so the group-and-offset to entry mapping becomes a named pure function
(`JournalGroups.entryID(at:in:)`) that a unit test can exercise. A test cannot drive SwiftUI's
per-section `.onDelete`, so without that seam the "one real bug risk in this item" would have no
coverage at all.

### Shorter rows

`EntryRow` drops from up to five stacked elements to two lines:

1. source icon, title (headline, one line), then the status badge or the analyzing indicator.
2. up to two life-area dots (6 pt, replacing the chip row), the date, the preview (one line, down from
   two), and the "Added" suffix when the entry was backdated.

The date shortens to suit its group, which is where most of the height goes: time only inside Recent
and Yesterday, weekday and time in This week, the day number inside a month, month and day inside a
year. `EntryDateText` gains a `.row(JournalGroup)` style for it.

`entryRow`, `analyzingBadge`, and the "Draft" badge text stay, because UI tests match them.

### Multi-select areas

`pickedArea: LifeArea?` becomes `pickedAreas: Set<LifeArea>`, and `JournalFilter` goes set-based:

```swift
static func active(_ picked: Set<LifeArea>, hidden: Set<String>) -> Set<LifeArea>
static func matches(areasRaw: [String], areas: Set<LifeArea>) -> Bool   // empty set matches everything
```

An entry matching any selected area shows. Chips toggle in and out, and deselecting the last one
clears the filter. The empty state names what is selected: "Nothing in Work or Health", joining with
commas and "or", capped at three names plus "and N more". The selection is not persisted across
launches, which is what it does today.

### Decline

`EntryEditorView.swift:391` becomes `Button("Decline", role: .cancel)` and gains
`.accessibilityIdentifier("declineCleanupButton")`. The behaviour, `cleanupDismissed` and
`cleanup.dismissed`, is unchanged. `RepointView.swift:112`'s "Not now" is a different screen and is
left alone.

## Tests

Unit (Swift Testing, `iPhone 17 a8-polish`, id `0B8A87E2-B7F2-442B-A8A7-1E88BD03E9F6`):

- **`PromptVoiceTests`**: each setting's instruction; `.name` with an empty or whitespace name falls
  back to first person; the name is trimmed and capped; the name appears in the prompt under `.name`
  and in neither other setting.
- **`InsightsPromptBuilderTests`** (added): the system prompt carries the voice instruction; the word
  "writer" appears in no prompt the app sends; the loose-end guidance carries both the yes and the no
  examples and still interpolates the cap; the schema is unchanged by the voice setting; the entry-date
  sentence and the handle block survive the guidance rewrite.
- **`SettingsStoreTests`** (added): both new keys default correctly through a missing-value store, the
  name is trimmed and capped, and neither is written until set.
- **`EntityProseRewriterTests`**, written against the real rule, not an assumed one: an exact-case
  whole-word match is replaced; a differently-cased match is left ("mark" survives a Mark);
  "Sarah Jane" is left alone when renaming Sarah; a leading capitalized neighbour is left; two
  occurrences in one string are both replaced and the later index stays valid; no match returns nil;
  an empty or whitespace old name is a no-op.
- **`GraphEditorTests`** (added): a rename rewrites the bios, summaries, and loose ends that name the
  entity; **renaming A rewrites B's bio when B's bio names A**; `Entry.text`, `originalText`,
  `cleanedText`, `sourceTextHash`, and `EntityLink.surface` are untouched; **`updatedAt` does not move
  on a rewritten entry**; `insights.isCurrent(for:)` stays true; a user-edited bio is skipped; a
  summary on an entry that never linked the entity is skipped; the old name always becomes an alias
  and a capitalization-only rename adds none; a rename of a merged loser rewrites nothing; the dry-run
  counts match what the rename then does.
- **`EntityModelTests` / `CloudKitSchemaRulesTests`**: the four new fields are optional and the schema
  still has no violations.
- **`ContactLinkTests`** (a `FakeContactDirectory`): linking stores only the identifier; unlinking
  clears it; changing a person's kind clears the link, **including on the path where `setKind`
  collides and returns early without mutating**; a missing contact resolves to nil without clearing
  the identifier; denied and limited access both leave the entity usable.
- **`PlaceLinkTests`** (a `FakePlaceDirectory`): linking stores identifier and coordinate and no name;
  unlinking clears all three; a search result with no identifier still links by coordinate; only a
  `.place` can link.
- **`EntityPeekPresentationTests`** (added): the summary carries the contact identifier and the
  coordinate, and a merged loser resolves to the winner's link.
- **`JournalGroupsTests`**: today, yesterday, and the week boundary at the calendar's first weekday;
  an entry earlier in this month but outside this week lands in its month; **an entry dated later
  today lands in Recent, not Later, and one dated tomorrow lands in Later**; a week spanning the year
  boundary (today Jan 2, an entry Dec 30) lands in This week while the rest of December lands in its
  year; December 31 and January 1; DST days do not shift a group; the built order matches the input
  order; `entryID(at:in:)` returns the entry the user swiped with two groups present.
- **`JournalFilterTests`** (rewritten set-based): an empty set keeps everything; any-of matching; a
  hidden area drops out of the active set; offered areas unchanged.
- **`DiagnosticsLogTests`**: the sentinel is used as a contact name, a place name, and the user's name;
  each new event is added to the required-event loop **in the unit that adds the event**, since the
  loop fails the moment a name is listed without a call that produces it.

Live (`OpenAILiveTests`, the owner's key through `TEST_RUNNER_MINDLORE_OPENAI_KEY`, never written to a
file):

- **`looseEndsAreCommitmentsNotPassingRemarks`**: an entry with one real commitment (calling the
  landlord) and two throwaways (grabbing coffee after this, thinking more about the move) produces at
  most one new loose end, and its text names the landlord.
- **`summariesUseTheChosenVoice`**: the same entry under `.first` and under `.name`, matching "I" as a
  **word** through `NameMatching.range(of:in:)` rather than as a substring, asserting the name appears
  under `.name`, and "writer" under neither.

Both assert on model output, so they can wobble. Each keeps to one clear signal and prints the full
result the way the other live tests do.

UI (`iPhone 17 a8-polish`, stub AI), per unit rather than all at once:

- **`JournalListUITests`** (new): the group headers appear in order, and two area chips select together
  and keep entries matching either, with the empty state naming both. It builds its own entries rather
  than scrolling a 300-entry seed to find a year header: `JournalGroupsTests` already proves the
  grouping, and `DemoJournal`'s store (`demo-journal.store`, seeded only when empty) is shared with
  `GraphScreenshotTests`, so a class that deletes entries would leak state into the screenshots.
- **`InsightsUITests`** (added): the cleanup card shows, `declineCleanupButton` dismisses it, and it
  stays dismissed.
- **`JournalNavigationUITests`, `RecordingUITests`, `EntryDateUITests`, `DraftUITests`**: re-run
  unchanged, because sectioning changes what `app.cells` counts (`JournalNavigationUITests.swift:30`
  defines `rows` as `app.cells`, asserted at `:61` and `:92`; `RecordingUITests.swift:56`) and the
  shorter row changes which static texts exist.
- **`GraphUITests` / `GraphScreenshotTests`**: the peek card still opens and reads correctly with the
  avatar slot in place of the symbol, and the demo screenshots are retaken.

Contacts and places have no UI test: the picker needs a real permission prompt and real search
results, neither of which the simulator gives honestly. The protocols carry the unit coverage and the
device step carries the rest.

Device (ask before deploying), on the owner's own journal and with `-seedDemoJournal 300`:

- link a person to a real contact, see the photo on the card and the page, unlink, and relaunch
- deny contacts access once, and narrow it to limited once, and confirm the entity still works
- link a place, see the map on the card, open Apple Maps from the page
- rename an entity that appears in a summary, a bio, and a loose end: the three change, the entry text
  does not, the entry's "edited" time does not move, and the old name still resolves in read mode
- a week of real entries under the tightened bar, counting the loose ends it creates
- each voice setting on a regenerated entry
- the grouped list on a year of entries, and a two-area filter

## Units and commits

The draft PR opens on unit 1, so unit 1 is mechanical and wide rather than the riskiest thing in the
phase. Each unit carries its own diagnostics events and privacy cases.

1. `PromptVoice`, `JournalVoice`, the two settings keys, `JournalVoiceSettingsView`, and all fourteen
   "the writer" strings. Tests. **Draft PR here.**
2. The loose-end guidance (214-220 only). Tests, then the two live tests once the owner pastes the key.
3. `EntityProseRewriter`, the rewrite inside `GraphEditor.rename` with the exempting save, the
   always-kept alias and its dead-code cleanup, the sheet's count line, and `graph.renameRewrote`.
   Tests.
4. Contacts: the protocol, `CNContactDirectory`, the editor methods, the picker sheet, **the avatar
   slot and the measured detent**, the usage-description key. Tests.
5. Places: the protocol, `MKPlaceDirectory`, the editor methods, the picker, the map on card and page,
   Apple Maps. Tests. (Unit 4 builds the slot; this one fills it for places.)
6. Journal grouping, the shorter row, and the per-section delete through `entryID(at:in:)`. Tests.
7. Multi-select areas and Decline. Tests, and the UI classes above.
8. The device step, the review log, and ticking the plan.

For each unit: build, run the unit suite, commit, push. A sub-agent reviews the whole diff after unit
7, and its findings are fixed in separate commits.

## Not in scope

- Automatic contact matching, a background scan, or a "these look like the same person" suggestion.
- Writing anything back to Contacts or Maps, and any contact field beyond the identifier, the display
  name, and the thumbnail.
- The user's own location, region-biased place search, and any location permission.
- Rewriting `Entry.text`, `originalText`, `cleanedText`, or `EntityLink.surface` under any
  circumstance.
- Undo, or a diff preview, for a rename rewrite.
- Persisting the area filter across launches, and filtering by anything but areas.
- Months within past years in the grouped list.
- A contacts or places UI test.
- `CLAUDE.md`'s Graph section, which A10 rewrites.

## Open questions for the owner

1. **Does a rename rewrite entry titles?** A title is the app's own sentence and shows on every row, so
   a renamed person reading the old name there is exactly the wrinkle this item is fixing. The plan
   names bios, summaries, and loose ends only. Recommendation: include titles, treating a user-edited
   title the way a user-edited bio is treated. Custom insight cards are the same question;
   recommendation: include them, since the model wrote the text even though the user wrote the
   instruction.
2. **Dropping the "keep the old name" toggle** from the rename sheet, so the alias is always kept, and
   deleting `hasVoiceSourcedLink` with it. Recommendation: drop it. The rule has no exception in the
   plan, and the alias is what keeps old entries resolving.
3. **A conservative rewrite means some misses.** "Sarah Monday" and a lowercase "sarah" are left alone
   by design, because silently editing the wrong words is worse than leaving a stale name. Confirm
   that trade, or ask for a diff preview instead (which is not in this phase's budget).
4. **Default voice.** Recommendation: first person, since that is what a journal sounds like and it
   needs no name to work.

## Review fixes (sub-agent review of this spec, verdict "rework", 16 findings)

Folded in above:

1. **`NameMatching` is a whole-word matcher, not a whole-name one.** It matches inside "Sarah Jane" and,
   case-insensitively, matches the words behind Mark, Will, and Hope. The rewriter now has its own
   exact-case rule with capitalized-neighbour guards and back-to-front replacement, and the tests are
   written against the real semantics.
2. **The rewrite would have stamped `updatedAt` on every entry it touched**, recording edits the user
   never made. It now saves through the exempting path `GraphEditor.save(_:touchedBy:)` already uses,
   with a test.
3. **The contacts permission story was incoherent**: `CNContactPickerViewController` needs no
   permission but grants no ongoing read access, which a live-fetched photo requires. Settled on
   `CNContactStore` authorization with a custom sheet, with limited access written honestly and the
   "gone" copy corrected to "Mindlore can't read this contact".
4. **Both directory protocols were `@MainActor`**, which would hold the main actor through a blocking
   `CNContactStore` fetch once per card render. They are now `nonisolated ...: Sendable` like every
   other injected boundary, and no method returns a non-`Sendable` `MKMapItem`.
5. **MapKit**: the coordinate fallback is written against iOS 26's `MKMapItem(location:address:)`, and
   the two disclosures (the name to Apple on search, the coordinate on a snapshot) are now stated.
6. **The 220 pt detent was assumed, not measured**, and a 44 pt square baseline-aligned against the
   "Open" button would have grown the header. The head is restructured and the size is settled by a
   screenshot before the unit lands.
7. **The guidance replacement cited 214-231**, which would have deleted the entry-date sentence and the
   handle block it promised to leave alone, and hardcoded a cap that is interpolated. Now 214-220 only.
8. **Two more "the writer" strings**, both user-visible: the custom-prompt placeholder and the UI-test
   stub bio, which is what every stubbed run renders on screen.
9. **Dropping the rename toggle** has six call sites plus a helper and test that go dead. Listed.
10. **The dry-run count was specified off the typed name**, which does not affect it, on a sheet with no
    `modelContext`. It is computed once on open by `EntityView` and worded "up to N".
11. **Grouping**: comparisons are at `startOfDay`, the builder takes dates rather than models so it can
    be `nonisolated`, the year-boundary week is covered, and the delete mapping is a named function so
    its test proves something.
12. **SwiftData shapes** are spelled out, since `EntryInsights` has no `entryID` and the summary walk
    reaches its entry through a relationship.
13. **Test corrections**: the `PrivacyManifestTests` addition was already covered and is cut; "contains
    I" is matched as a word; the `setKind` collision path is covered; A-renames-B's-bio,
    `sourceTextHash`, and `updatedAt` gained cases; the 300-entry scroll test is dropped because it
    would leak state into the shared demo store.
14. **Sequencing**: the draft PR no longer opens on the rename rewrite. Voice goes first, the rewrite
    lands third, and each event's privacy coverage lands with the event rather than in a final unit.
15. **Privacy**: the user's name is sent only under `.name`, and the two MapKit disclosures are stated.
16. **Factual corrections**: 23 stored properties, `EntityPeekCard.swift:11`, `GraphEditor.swift:32-50`,
    both privacy suites in `DiagnosticsLogTests.swift`, `JournalNavigationUITests.swift:30`, and the
    `SettingsStore` `Key` enum conflicts textually with A7 regardless of the keys, so A8 rebases.
