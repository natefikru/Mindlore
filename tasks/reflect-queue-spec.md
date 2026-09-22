# Reflect, rebuilt as a queue

The owner's words, testing B7 on the phone: charts and graphs are ugly and unwanted. What's
wanted instead is "insights and questions like what shows up on the main page, kind of like a
running queue, and we can do things about it, like answer questions and prompt journal entries."
Scoping conversation settled two things: the queue draws on both reused signals (loose ends,
quiet names) and a new AI layer that turns the period's numbers into specific questions, and a
card's tap action is to open a new entry pre-filled with its prompt, not an inline answer field.

## The entry point gets a label

Testing on the phone found the real bug: the week strip was a button with nothing that said so,
no chevron, no text, on purpose (the original comment reads "no target, nothing to keep up," which
was about the dots not turning into a streak counter, not about hiding that the row opens
something). It hid a real feature. A small "Reflect ›" caption sits to the trailing side of the
strip, plain text and a chevron, same row, same tap target. Not "Reflect on this week": the sheet
that opens carries its own period control and isn't scoped to whatever week you tapped, so a label
implying otherwise would be a lie the first time someone stepped it back to a month.

## What stays

The presentation and the period. Tap the row, get a sheet with its own `NavigationStack`, no tab,
no `AppRouter` change. The period control (week/month segmented, step back/forward, never past
today) is untouched. `ReflectAggregator` keeps computing the same facts it does now (mood, area,
tag, loose-end counts for one `DateInterval`), because the AI layer below needs exactly those,
unchanged, and Ask's rollup still reads it too.

## What goes

`Charts` import, `areaBalance(_:)`, `moodOverTime()`, and the `trend` array that only fed the
mood chart. `ReflectSource.trend` goes with it, since nothing else calls it. The single narrative
paragraph goes too, replaced by the AI layer below, which does the same job in a more specific
shape.

## The queue

One list, no charts, ordered: reused signals first (they're facts, not guesses), then the AI's
questions. Each item:

```swift
struct ReflectQueueItem: Identifiable, Equatable {
    enum Source { case looseEnd(UUID), quietName(UUID), generated }
    let id: String          // stable across a period's re-fetch, for dismissal-keying
    let source: Source
    let title: String       // "Still open", "Been quiet", "Worth asking"
    let body: String        // the loose end's text, the name, or the AI's question
    let prompt: String       // what seeds the new entry when tapped
}
```

**Reused signals, scoped to the period, not to "now."** `TodayComposer` already has this shape
for "right now"; this is the same computation asked about a past interval instead:

- **Loose ends.** Every loose end whose `openedAt` falls in the period and is still open at the
  period's end, plus any overdue one that was live during it. Not `LooseEndPrompter.next`, which
  picks one at a time for an interruption (the recorder); a look-back can show several, since
  nothing here is asking mid-task.
- **Quiet names.** An entity `linkCount` above the map's own large-journal threshold whose
  `lastLinkedAt`, computed as of the period's end (the same `asOf` pattern `MindMap` and
  `EntityGraph` already take), sits more than 30 days before the period started. "Ana hasn't come
  up since May" is a fact about that week, not about today, so it has to freeze at the period's
  own end date or a look back at an old week would report *today's* silence.

**The AI layer**, replacing the paragraph: one request per period, same rules
`ReflectNarrator` already follows (not persisted, not retried, `AIServices.askGenerator`, fails
silently so the queue still renders without it). It reads only the aggregated facts
`ReflectAggregator` already computes, the same privacy boundary the paragraph kept, never entry
text. It returns a short list (2 to 4) of specific, answerable items, structured output parsed
tolerantly the way Insights parses moods and tags: an item with no usable text is dropped, not
retried, not defaulted to something invented. "Money entries dropped off after March, everything
else held steady. What changed?" is the kind of thing this can say from the numbers alone that
one paragraph couldn't ask as a question.

## Tapping a card

Opens a new entry, pre-filled with the item's `prompt` as its starting text, not an inline answer
field. There's no prefill mechanism in the app today: `JournalRoute.new()` just mints an id, and
"the editor creates the Entry with it on the first keystroke." A route that carries starting text
needs the entry created with that text already in it, so:

- `JournalRoute` gains `var startingText: String? = nil`. Equality stays on `entryID` alone; a
  route that differs only in starting text still replaces an open editor rather than reopening it.
- `Entry+Editing.swift` gets the one place that creates an entry with starting text, so every
  caller (this, and anything later) applies the rule the same way the rest of that file does.
- The editor seeds the text on creation, not lazily on the first keystroke, since the whole point
  is that it's already there.

## Dismissing a card

Same gesture the Today cards just got: swipe or the X. Scoped per `(period, item.id)`, not per
loose end or entity: dismissing "Ana hasn't come up" from March's queue says nothing about April's,
and doesn't touch the entity or resolve the loose end. Shape follows `TodayDismissal` (a day-scoped
JSON blob thrown away when the day changes), keyed by the period's identity instead of a day, and
never expiring on its own the way `TodayDismissal` does, since a week you looked back on stays
looked back on.

## Empty state

Kept, reworded: no chart to skip past, so "No entries in this week/month" is the whole of it, same
as today.

## Tests

`ReflectQueueTests`: reused-signal selection at a period's edges (a loose end opened the day
before the period starts, one still open past the period's end, an entity quiet as of the
period's end but not as of today). A fake-generator test mirroring `ReflectNarratorTests`'
pattern for the AI layer: tolerant parsing, a malformed item dropped not defaulted, silent failure
when the provider errors. UI: extend `TodayUITests` (or a new `ReflectUITests`) for a card's tap
landing on a pre-filled editor, and the swipe/X dismissal persisting across a relaunch the way
`TodayUITests.testTodayShowsCardsAndADismissalOutlivesALaunch` already proves for Today's.

## Out of scope

Today's own composer and its dismissal shape stay as they are; loose-end resolution rules don't
change; no inline "answer here" text field, per the scoping decision. `ReflectAggregator` isn't
touched, so `AskRollups`' read of it is unaffected.
