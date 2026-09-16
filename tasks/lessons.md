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
