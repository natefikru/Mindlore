# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Mindlore is an iOS app built with SwiftUI and SwiftData, scaffolded from Xcode's default template. It is early-stage: currently just the stock App/ContentView/Item skeleton with no domain logic yet. Deployment target is iOS 26.5, Swift 5.0.

## Commands

Build and run only through Xcode (`Mindlore.xcodeproj`) or `xcodebuild` from the CLI:

```bash
# Build for the iOS Simulator
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -sdk iphonesimulator build

# Run unit + UI tests
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -sdk iphonesimulator test

# Run a single test (Swift Testing syntax)
xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -sdk iphonesimulator test \
  -only-testing:MindloreTests/MindloreTests/example
```

There is no SwiftPM package, no separate lint config, and no CI setup in this repo yet.

## Architecture

- `Mindlore/MindloreApp.swift` — app entry point. Builds the SwiftData `ModelContainer` for the schema (currently just `Item`) and injects it into the view hierarchy via `.modelContainer(...)`.
- `Mindlore/Item.swift` — SwiftData `@Model` class. New persisted entities go here (or in their own files) and must be added to the `Schema([...])` list in `MindloreApp.swift`.
- `Mindlore/ContentView.swift` — root view. Reads/writes persisted data through `@Environment(\.modelContext)` and `@Query`, following the standard SwiftData pattern (insert/delete directly on `modelContext`, wrapped in `withAnimation`).
- `MindloreTests/` — unit tests using the **Swift Testing** framework (`import Testing`, `@Test`, `#expect`), not XCTest.
- `MindloreUITests/` — UI automation tests using `XCTest`/`XCUIApplication`.

When adding new persisted types, follow the `Item` pattern: a small `@Model` class plus registration in the app's `Schema`. When adding new screens, follow `ContentView`'s use of `@Query`/`modelContext` rather than introducing a separate persistence layer.
