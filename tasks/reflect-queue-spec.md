# Reflect, rebuilt as a cached scrolling queue

Where this landed after four rounds of testing it on the phone and talking through the tradeoffs.
Charts are gone. The period picker is gone. In their place: a scroll of weeks and months, each
one's questions generated once, cached, and read back rather than asked for again on every open.

## The entry point

Already built and merged: a plain "Reflect ›" caption under the week strip, right-aligned, same
tap target as the dots. Not "Reflect on this week" — the feed isn't scoped to whatever week you
tapped from.

## What goes

The period picker (segmented week/month, step back/forward). `Charts` import, `areaBalance(_:)`,
`moodOverTime()`, `ReflectSource.trend`. The single ephemeral narrative paragraph, and the rule
that went with it ("not persisted, not retried, reopening asks again") — this pass persists
everything it generates, on purpose, so a phone doesn't ask the same question about the same
settled week twice. `ReflectPeriodSelection` stays exactly as it is; it just stops being driven by
a picker.

## The feed

One scroll, no toolbar controls, newest at the top:

1. **The last `recentWeekCount` weeks** (default 8), each in full: a header and that week's queue
   items underneath. The current week — still open, not yet complete — shows only its live reused
   signals (loose ends, quiet names as of right now); it has no generated section, because nothing
   can honestly summarize a week that isn't over.
2. **Every month before that**, back to the journal's first entry, collapsed to one row: a title,
   a mood-chip strip, and a short generated line, not a chart. A month with zero entries is
   skipped.
3. **Tapping a month row expands it** into its constituent weeks — full sections, same as (1),
   every week whose start falls inside that month.

A week with entries but nothing to ask about shows one "all caught up" line, not a gap. No detail
pages for either grain — everything lives in this one scroll, at one of two densities.

## Mood chips, not charts

Small dots and words, the same visual language the Journal list's row footer already uses, not a
`Charts` bar graph. Sits in a week's header and on a collapsed month row. Grounded, glanceable,
and it doesn't need its own screen to earn its place.

## Generated once, cached, read back

The core change from every earlier draft of this spec. Nothing here asks the AI on open. A period
is summarized exactly once, the moment it's known to be complete, and the result is written to the
store:

```swift
@Model
final class ReflectSummary {
    var id: UUID?
    var periodKindRaw: String?      // "week" | "month", the enum-as-raw-string rule every model here follows
    var periodStart: Date?          // the interval's start; identifies which week or month
    var generatedAt: Date?
    var itemsData: Data?            // encoded [ReflectQueueItem]
}
```

Optional or defaulted throughout, nothing `@Attribute(.unique)` — the same CloudKit-readiness rule
`Entry`, `Entity`, and `LooseEnd` already follow, checked by the same `CloudKitSchemaRulesTests`.

**Two triggers, one operation.** This app has no background execution — no push, no scheduled
jobs; Personal Team signing rules it out, and `DailyReminder`'s local notifications are the only
thing here that's OS-scheduled at all. "Runs once a week" can't mean a silent midnight job. It
means:

- **Proactively, at launch.** `RootView`'s existing sweep lane (`graph.indexer.sweep`, then
  `LooseEnd.fade`, `tasks/reflect-queue-spec.md` — `RootView.swift:203-219`) gains one more step
  after the loose-end fade: check whether the most recently completed week and the most recently
  completed month each have a cached `ReflectSummary`. Generate whichever is missing. Nothing
  older is swept here — a launch isn't the place to backfill a year of history.
- **Lazily, on view.** A week reached by scrolling to it (in the recent eight) or by expanding an
  older month, and a month row scrolled into view: if it has no cached summary, generate one then,
  the same operation the launch sweep uses. This is the backfill path for everything the proactive
  check doesn't cover — older history, or a stretch generated while the phone was offline.

Both paths call the same "generate and cache if missing" function, so "only run once" is a cache
check, not a rule two different code paths have to agree on separately. A failed generation (AI
off, offline, provider error) writes nothing, fails silently the way `ReflectNarrator` always has,
and is tried again next launch or next view, whichever comes first.

## Tiered fidelity

The other real change: what the AI reads to write a period's questions.

- **A week reads its own entries in full.** Not a digest — the actual sanitized text, one fenced
  block per entry, the same `AskContextBuilder.sanitized` delimiter-stripping Ask already applies,
  gated by the same eligibility check Ask uses (`InsightsCoordinator.canRunAI(on:)`; a draft or an
  unapproved photo entry is never included). A week is small — a handful of entries — so full text
  is cheap, and it's the difference between the model reconstructing a week from fragments and
  actually reading what happened.
- **A month reads cached week-summaries plus digest lines for the rest, never full month text.**
  For any week inside that month with an existing `ReflectSummary`, its generated items feed the
  month's prompt directly — free, already paid for. Every other entry in the month gets an
  `AskDigests`-shaped line (title, date, 90 characters, the same sanitized pipeline Ask's own
  digests use). A month whose weeks were never individually visited or generated is built entirely
  from digests; a month reached after its weeks were expanded and summarized is built mostly from
  those. Never a whole month of entries in full at once.

**This makes Reflect the second place in the app, after Ask, where entry-derived text leaves the
device, and the first place it happens without an explicit question from the user** — it happens
because a period completed, not because anyone asked. That's a real, named departure from every
other automatic pass in this app (Insights writes structured fields from an entry's own text but
never ships the entry itself anywhere for a passive purpose; the old Reflect paragraph was counts
only). Caching is what keeps this bounded: a week's full text is read once, the moment it's
summarized, not once per visit. It stays behind the same AI-on toggle, and `AskContextBuilder`'s
fencing is unconditional, not opt-in per call.

## The queue item

```swift
struct ReflectQueueItem: Identifiable, Equatable, Codable {
    enum Source: Codable { case looseEnd(UUID), quietName(UUID), generated }
    let id: String          // stable across a re-fetch, for dismissal-keying
    let source: Source
    let title: String       // "Still open", "Been quiet", "Worth asking"
    let body: String
    let prompt: String      // what seeds the new entry when tapped
}
```

Reused signals (loose ends still open at a week's end, entities quiet as of that week's end, not
today's) are computed fresh every time, cheap and local, the same shape `TodayComposer` already
has for "right now" asked about a past week instead. Only the generated items are cached; the
reused ones don't need to be, and a stale cache of "still open" would be actively wrong once a
loose end resolves.

## Tapping a card

Opens a new entry pre-filled with the item's `prompt`. `JournalRoute` gains
`var startingText: String? = nil` (equality stays on `entryID` alone); `Entry+Editing.swift` gets
the one place that creates an entry with starting text already in it; the editor seeds it on
creation, not the first keystroke.

## Dismissing a card

Swipe or the X, same as Today's cards. A map from a week's stable key (kind plus interval start,
not an offset) to the set of dismissed item ids, persisted the way `TodayDismissal` is, never
expiring — a week you looked back on stays looked back on.

## Tests

`ReflectSummaryStoreTests`: generate-once-and-cache is idempotent (a second call finds the cache
and makes no request), the launch sweep only touches the most recent completed week and month, a
failed generation writes nothing and is retried next time. `ReflectFeedTests`: the week/month
boundary, a month with zero entries skipped, a month's fold-out producing exactly its weeks, an
all-caught-up week's one line. `ReflectQueueTests`: reused-signal edge cases (a loose end opened
the day before a week starts, an entity quiet as of the week's end but not today's). A fake-
generator test for both fidelity tiers: a week's prompt carries full sanitized entry text and
excludes an ineligible draft; a month's prompt carries cached week items plus digest lines and
never a whole month of raw text. UI: a card's tap landing on a pre-filled editor, a month row
expanding, dismissal surviving a relaunch.

## Out of scope

Today's own composer and dismissal shape; loose-end resolution rules; an inline "answer here"
field. `ReflectAggregator` is untouched, so `AskRollups`' read of it is unaffected. No manual
"regenerate this week" control in this pass — a stale summary waits for whatever would naturally
invalidate it, which this spec doesn't define yet and the next one should if it turns out to
matter. `recentWeekCount` defaults to 8, easy to change once it's actually lived with.
