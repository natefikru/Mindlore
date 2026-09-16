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
