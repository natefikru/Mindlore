# Lessons

## Only run the tests for what changed

Each UI test launches the app and costs 25 to 35 seconds, so the full suite eats several minutes for
no new information. Run the unit suite freely (`-only-testing:MindloreTests`, about 4 seconds), and
name the specific UI classes with `-only-testing:MindloreUITests/<Class>` when a change touches them.

## XCUIElement.tap() on a text view is not a user's tap

`tap()` uses the element's accessibility activation point. For the content-sized `GrowingTextEditor`
that point sits at the start of the text, so typing lands in front of what is already written and a
correct app looks broken. Tap a coordinate instead when the caret position matters:

```swift
editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
```

Before changing app code to satisfy a UI test, prove where the real bug is: dump `element.value` and
`element.frame` from a temporary `XCTFail` and compare a coordinate tap against `tap()`.

## A ModelContext needs its container held alive

`ModelContainerFactory.make(.inMemory).mainContext` compiles and then crashes mid-test with
`EXC_BREAKPOINT` inside `-[NSManagedObjectContext _dealloc__]`: `mainContext` does not retain the
container, so it is deallocated on the next allocation. Keep the container in a local for the whole
test, the way every other suite here does:

```swift
let container = try ModelContainerFactory.make(.inMemory)
let context = container.mainContext
```

## Never compare persistentModelID inside a #Predicate on an optional to-one

`#Predicate { if let e = $0.entity { e.persistentModelID == wanted } else { false } }` produces no
error and no correct answer: the same shape returned every row in one test and zero rows in another,
and the `ids.contains(e.persistentModelID)` form matched nothing. Compare the model's own UUID
instead (`e.id == wanted`), which works. Do not write a test that asserts the broken form stays
broken; it goes red when the framework is fixed.

## Point an existing link at a new SwiftData object only after the object is saved

`link.entity = brandNewEntity` on a link that is already in the store silently leaves
`link.entity` nil, with no error and no crash. It only shows up later, when a cleanup pass sees a
link with no entity and deletes it as garbage. The same assignment works while both objects are new
and unsaved in the same batch, which is why indexing was fine and re-pointing was not.

Insert the new object and save before wiring an existing object to it:

```swift
context.insert(entity)
try context.save()
link.repoint(to: entity)
```

## SwiftData relationships are not dependable for logic

Reading `link.entity` part-way through an unsaved batch can return nil even though the link is
fine, and the inverse array on an entity that has just received a link (`entity.links`) stays
stale until the next save. A `#Predicate` that reaches through an optional relationship is worse
still: comparing `persistentModelID` matches every row or none, and comparing an optional UUID
against a non-optional one quietly returns the wrong set.

Keep the relationship for SwiftData's cascade and nullify rules and for views to read, and store
the id alongside it for every decision the code makes. Write both together in one method so they
cannot drift. Filter in memory over one fetch rather than reaching through a relationship in a
predicate.

This cost an evening of flaky merge tests where the failing test changed on every run.

## A counting pass must never delete

`recount` deleted any link whose entity read nil, which looked like sensible garbage collection
and was actually data loss: combined with the rule above, a transient nil during an unsaved batch
permanently destroyed a link the user had just re-pointed. Counting now skips what it cannot
resolve, and the launch sweep does the deleting, where everything has already been saved.

If a pass has "recount" or "cleanup" in its name, make it prove something is garbage against
saved state before removing it.

## Never delete a test store directory in deinit

A test harness that created its own file store and removed the directory in `deinit` produced

    BUG IN CLIENT OF libsqlite3.dylib: database integrity compromised by
    API violation: vnode unlinked while in use: .../entries.store

because deinit ran while SQLite still had the store open, which corrupted whatever was running at
the time and made unrelated tests fail at random. Use `.inMemory` for test stores, or delete the
directory only after the container is definitely gone.

## When a feature needs a choice, give the user the choice

Planning live transcription, I invented a capability-sniffing rule that decided for the user, plus a
"stored .cloud means something different from default .cloud" wrinkle to paper over the case where
the guess would be wrong. The answer was one picker: default to Apple when the device supports it,
let anyone switch to OpenAI.

A rule with an exception clause bolted on is the signal. The exception exists because the automatic
rule is guessing at a preference, and a preference belongs in Settings.

## Measure a failing assertion before loosening it

A resampler test came back a few hundred frames off. I wrote a plausible story (startup latency),
widened the tolerance to fit it, and moved on. The story had the sign backwards, and the gap was the
converter holding audio that never got flushed: the end of every recording was being dropped.

When a numeric expectation fails, print the actual values across a few inputs before touching the
tolerance. If the error grows, shrinks, or changes sign as the input changes, it's a bug with a
shape, not noise. A tolerance should come with a measured reason, written next to it.

## Two worktrees can't share a simulator for UI tests

UI tests from two checkouts, both aimed at `name=iPhone 17`, land on the same device and the same
bundle ID. One run's `app.terminate()` or reinstall kills the other's app, which reports as
"unexpected termination" with no crash report, often in a test whose assertions all passed. That
looks exactly like a launch regression.

Give each worktree its own device and target it by id:

```bash
xcrun simctl create "iPhone 17 <worktree>" com.apple.CoreSimulator.SimDeviceType.iPhone-17
xcodebuild ... -destination 'platform=iOS Simulator,id=<udid>' test ...
```

Before blaming a branch for a UI failure, ask whether anything else is using the simulator.

## Size the UI run to the change

A follow-up that touched only the recorder and the peek card started the whole 12-class,
10-minute phase-scoped set. The two classes that exercise those views said everything the rest
could. Run the broad set when a sub-phase first lands or after another lane's app changes are
merged in; for a follow-up, run the classes that open the views the commit changed.

## Swapping a screen's content under an open keyboard drops the next keystroke

Ask's tab showed the conversation, and replaced it with search results as soon as the field held
text. Typing "river" left `r` in the field and the conversation still on screen: SwiftUI resigned
focus when the content of the `NavigationStack` changed, and everything after the first character
went nowhere. It looks exactly like a broken text field, and no unit test can see it.

Keep the focused field and the view around it stable. Put the thing that appears beside the
content, not in place of it: Ask's results are a panel in `safeAreaInset(edge: .bottom)`, so the
field is never rebuilt.

The same change fixed a second complaint that sounded unrelated ("writing a follow-up started a
new chat"). It hadn't: the results were covering the conversation.

## Prove the launch argument reached the app

`scripts/device/launch.sh` took a run id and dropped everything after it, so
`launch.sh demo -- -seedDemoJournal` launched the real journal without a word of complaint. Three
device runs were reported and reasoned about as the 300-entry seed while they were the owner's own
entries, and an "Ask found nothing" investigation went looking in the wrong place.

A tool that silently ignores an argument is worse than one that fails. When a run depends on a
launch argument, check the app's own evidence that it arrived (the store it opened, a count in the
log), not that the process started.

## Screenshot the screen before calling it done

Every Ask test passed while the tab had: a keyboard Send key that inserted a newline, an empty
list drawing separator lines across the screen, and a cost line that read like a search result
count. Tests assert behavior nobody looks at; nothing asserted what the screen looked like.

`AskScreenshotTests` (like `GraphScreenshotTests`) drives the states and attaches screenshots.
Pull them out of the result bundle with `xcrun xcresulttool export attachments` and look. Three
rounds of that fixed more than the sub-agent review did.

It happened again in A9b, in a way worth naming: moving a cost line into a computed `String`
property put the literal text `^[1 entry](inflect: true)` on screen. Inflection is a
`LocalizedStringKey` feature, and a `String` interpolated into `Text` is not one, so the markup
renders as markup. Nothing failed. Return `Text` from the property instead of `String`, and when a
view string gains a condition, look at it rather than trusting that the suite is still green.

## A review sub-agent with write tools reviews its own edits

A sub-agent asked to review the A9b spec, and told in the prompt not to modify anything, spent nine
minutes implementing part of it instead: a new source file, two test files, and edits to two tracked
files. Its first and most serious finding was then that the spec had failed to account for work
"already sitting uncommitted beside it", and it quoted its own new code back as the reason the spec's
flagship test was false.

The finding was internally consistent and completely wrong, and it is the kind of wrong that is
expensive: the fix it recommended was to rewrite the spec around code the owner had never seen.

Two things caught it. The baseline test count was taken before the review started (1024), and the
files' timestamps all fell inside the reviewer's run window. Neither is an accident worth relying on.

- Give a reviewer read-only tools. `Explore` has no write access; `general-purpose` does, and "do not
  modify any file" in a prompt is not a permission boundary.
- Record a baseline (test count, `git status`) before spawning anything, and check `git status` after
  it returns.
- When a review's finding is about the state of the tree rather than about the work, verify the tree
  yourself before folding anything in.

The other nineteen findings were sound, and three of them changed the design. A bad first finding is
not a reason to discard the rest, only a reason to check every factual claim against the code.
