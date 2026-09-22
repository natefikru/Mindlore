# Reflect, rebuilt as a scrolling queue

The owner's words, testing B7 on the phone: charts and graphs are ugly, unwanted, and "not
grounded." What's wanted instead is "insights and questions like what shows up on the main page,
kind of like a running queue, and we can do things about it, like answer questions and prompt
journal entries" — and, once charts were off the table, "a one pager that just scrolls down," not
a picker you set to one period at a time. The design that answers "show weeks or months" without
either burying old content or making a long journal a hundred-card scroll: recent weeks in full,
older stretches collapse into months, and a month unfolds into its own weeks on tap, so nothing is
ever out of reach, just out of the way until asked for.

## The entry point gets a label

Already built and merged onto this branch: a plain "Reflect ›" caption sits under the week strip,
right-aligned, same tap target as the dots. Not "Reflect on this week": the feed below isn't
scoped to whatever week you tapped from.

## What goes

The period picker (segmented week/month, step back/forward) is gone, not just the charts. `Charts`
import, `areaBalance(_:)`, `moodOverTime()`, `ReflectSource.trend`, and the single narrative
paragraph all go. `ReflectPeriodSelection` stays exactly as it is (kind, offset, `interval(now:)`,
`title(now:)`) — nothing about its own math changes, it just stops being driven by a picker and
starts being generated in a sequence.

## The feed

One scroll, no toolbar controls, newest at the top:

1. **The last `recentWeekCount` weeks** (default 8, easy to tune), each `ReflectPeriodSelection(kind: .week, offset: 0...-(recentWeekCount-1))`, in full: a header ("This week", "Last week", or the week's title further back) and that week's queue items underneath.
2. **Every month before that**, oldest bound by the journal's own first entry, one collapsed row each: a title and a plain one-line rollup ("14 entries, 2–28 September"), no chart, in the same fenced-plain-line spirit `AskDigests` and `AskRollups` already use elsewhere in this app for "count and coverage" without a graph. A month with zero entries is skipped outright — there's nothing to roll up.
3. **Tapping a month row expands it** into its own constituent weeks — the same full week section as (1), same items, same swipe/tap/dismiss — every week whose `ReflectPeriodSelection(kind: .week, ...)` start date falls inside that month's interval. Nothing is ever only reachable as a rolled-up number; the fold-out is how "we have access to all the data" stays true arbitrarily far back.

A week with entries but nothing to ask about ("all caught up") gets a one-line saying so, not an
empty gap that reads like something failed to load. A week with zero entries is skipped, same as
an empty month.

**Loading is per-row, not up front.** A local computation (loose ends, quiet names — see below) is
cheap and can run the moment a week's header is about to appear. The AI questions are a network
call and only fire from a `.task` on that specific week's row, the same lazy trigger that already
keeps `EntityPeekCard`'s bio from firing for every row in a list. A journal old enough to have forty
months of history never sends forty AI requests on open; it sends one per week actually scrolled
to or expanded, which for most sessions is a handful.

## The queue item

Unchanged from the first pass at this spec:

```swift
struct ReflectQueueItem: Identifiable, Equatable {
    enum Source { case looseEnd(UUID), quietName(UUID), generated }
    let id: String          // stable across a re-fetch, for dismissal-keying
    let source: Source
    let title: String       // "Still open", "Been quiet", "Worth asking"
    let body: String        // the loose end's text, the name, or the AI's question
    let prompt: String      // what seeds the new entry when tapped
}
```

**Reused signals, scoped to the week, not to "now."** `TodayComposer` already has this shape for
"right now"; this asks the same question about a past week instead:

- **Loose ends.** Every loose end whose `openedAt` falls in the week and is still open at the
  week's end, plus any overdue one that was live during it.
- **Quiet names.** An entity above the map's large-journal link-count threshold whose
  `lastLinkedAt`, computed as of the week's end (the `asOf` pattern `MindMap` and `EntityGraph`
  already take), sits more than 30 days before the week started. Frozen at the week's own end
  date, or a look back at an old week reports today's silence instead of that week's.

**The AI layer**, replacing the paragraph: one request per week (not per month — a collapsed month
row never calls it), same rules `ReflectNarrator` already follows (not persisted, not retried,
`AIServices.askGenerator`, fails silently so the week's reused signals still render without it).
Reads only that week's aggregated facts from `ReflectAggregator`, the same privacy boundary the
paragraph kept, never entry text. Returns 2 to 4 specific, answerable items, structured output
parsed tolerantly the way Insights parses moods and tags: an unusable item is dropped, not
defaulted to something invented.

## Tapping a card

Opens a new entry pre-filled with the item's `prompt`, not an inline answer field. `JournalRoute`
gains `var startingText: String? = nil` (equality stays on `entryID` alone); `Entry+Editing.swift`
gets the one place that creates an entry with starting text already in it, so every caller applies
the rule the same way; the editor seeds it on creation, not on the first keystroke.

## Dismissing a card

Swipe or the X, the same gesture Today's cards just got. The dismissal store changes shape now
that there's no single "current period": it's a map from a week's stable key (kind + its interval
start, not an offset, since an offset's meaning drifts as time passes) to the set of dismissed item
ids in that week, persisted as one JSON blob the way `TodayDismissal` is, but never expiring —
a week you looked back on stays looked back on, however long ago you looked.

## Empty state

Nothing in the journal at all: one `ContentUnavailableView`, same tone as today's. Otherwise the
feed always has something to show, even if every individual week says "all caught up."

## Tests

`ReflectFeedTests`: the week/month boundary (exactly `recentWeekCount` weeks stay weeks, the next
one is inside a month row), a month with zero entries skipped, a month's fold-out producing exactly
the weeks whose start falls inside it, an all-caught-up week rendering its one line instead of
nothing. `ReflectQueueTests`: the reused-signal edge cases from the first pass (a loose end opened
the day before a week starts, one still open past its end, an entity quiet as of the week's end
but not as of today). A fake-generator test mirroring `ReflectNarratorTests` for the AI layer:
tolerant parsing, a malformed item dropped, silent failure on a provider error. UI: a card's tap
landing on a pre-filled editor, a month row expanding to reveal its weeks, dismissal surviving a
relaunch the way `TodayUITests` already proves for Today's cards.

## Out of scope

Today's own composer and dismissal shape are untouched; loose-end resolution rules don't change;
no inline "answer here" field. `ReflectAggregator` isn't touched, so `AskRollups`' read of it is
unaffected. `recentWeekCount` defaults to 8 — a guess at what "recent" means here, easy to change
if it feels wrong once it's actually on the phone.
