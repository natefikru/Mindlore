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
