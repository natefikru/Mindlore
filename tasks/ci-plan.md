# CI for the TestFlight beta

Status: proposed 2026-09-22, awaiting the owner's go. Nothing below is built.

## What was measured

- The repo is public, so GitHub-hosted macOS runners cost nothing and there is no minute budget.
  The limits that matter are wall-clock and the free plan's cap of 5 macOS jobs at once.
- `macos-26` runners ship Xcode 26.6 (17F113), the same build as the development Mac, with an
  iOS 26.5 runtime and an iPhone 17 simulator, plus xcbeautify 3.2.1.
- Unit suite: 1,531 tests in 188 suites, 61 seconds of test time on a warm build. The compile is
  the cost; on a cold runner expect 3 to 5 minutes of build before that minute of tests.
- UI suite: 52 tests in 26 classes, each launch 25 to 35 seconds (`tasks/lessons.md`), so about
  25 minutes serial. Five of the classes seed a 300-entry journal first.
- The scheme is auto-created, not shared: `xcodebuild -list` shows it locally, a fresh checkout
  has no scheme file. CI needs `Mindlore.xcodeproj/xcshareddata/xcschemes/Mindlore.xcscheme`.
- `CODE_SIGNING_ALLOWED=NO` makes `KeychainSecretStoreTests` fail with `errSecMissingEntitlement`
  (-34018): the simulator Keychain wants a signed app. Default ad-hoc simulator signing passes on
  a runner with no certificates, so CI leaves signing alone and never touches the team.
- `OpenAILiveTests` skips without `MINDLORE_OPENAI_KEY`; the on-device model tests skip when
  `FoundationModelsAvailability.isAvailable` is false. Both are naturally off on a runner.
- Known cold-start hazard: `AskIndexLemmaTests` can fail on a simulator's very first run while
  `NLTagger` loads its assets (`tasks/lessons.md`, "A fresh simulator has no lemmas"). Every
  hosted runner is a first run. Watch the first CI run; if it bites, warm the tagger in a
  setup step rather than retrying tests.

## Shape

One workflow, `ci.yml`, three stages. Build once, test many.

```
build (macos-26, ~5 min)
  xcodebuild build-for-testing, upload Build/Products as an artifact
  |
  +-- unit (1 runner, ~2 min)      test-without-building, MindloreTests
  |
  +-- ui   (5 runners, ~6 min)     test-without-building, one shard of UI classes each
```

- **Triggers.** `build` and `unit` run on every pull request and every push to `main`.
  `ui` runs on every push to `main`, on a pull request carrying the `ui` label, and on manual
  dispatch. A PR that touches views gets the label; a PR to a parser doesn't pay 10 minutes for it.
- **Concurrency.** One run per branch; a new push cancels the one in flight.
- **Shards are computed, not maintained.** `scripts/ci/ui-shards.sh N` reads
  `MindloreUITests/*.swift`, counts `func test` per class, and greedy-balances the classes into
  N lists printed as a JSON matrix. A new UI class joins a shard on its next run; nothing to
  forget. Each shard runs `-only-testing:MindloreUITests/<Class>` per class, serial, with the
  per-test time allowance from CLAUDE.md, against a booted `iPhone 17` on iOS 26.5.
- **Same commands locally.** `scripts/ci/build-for-testing.sh` and `scripts/ci/test.sh unit|ui`
  wrap xcodebuild so the CI run and the terminal run are one script, piped through xcbeautify
  when it is installed (GitHub annotations on the runner, plain output at home).
- **On failure** the `.xcresult` uploads (7-day retention) so a red run can be opened in Xcode.
- **Required check.** Make `unit` required on `main` in branch protection. `ui` stays advisory
  on PRs and is the gate for cutting a build.
- **Release** is `release.yml`: manual dispatch or a `v*` tag, gated on a repository variable
  `RELEASE_ENABLED` that stays unset until the paid team exists. Steps are real (import a
  certificate into a throwaway keychain, `xcodebuild archive`, export, upload with the App Store
  Connect API key) and every secret is a named placeholder. Build number comes from the run
  number so TestFlight never sees a duplicate.
- **Dependabot** watches the action versions weekly. Nothing else has dependencies.

## Not doing

- No DerivedData cache. There is no package graph to cache, restoring a cache costs about what
  the compile costs, and a stale cache is the classic source of "passes locally, fails in CI".
- No nightly schedule. Commits are sporadic; `ui` on every push to `main` covers it.
- No lint job. There is no lint config in the repo and adding one is a separate decision.
- No self-hosted runner. Worth it only if the repo goes private (macOS minutes then cost 10x).

## Tasks

- [x] Share the scheme (`xcshareddata/xcschemes/Mindlore.xcscheme`, all three targets).
- [x] `scripts/ci/build-for-testing.sh`, `scripts/ci/test.sh`, `scripts/ci/ui-shards.sh`.
- [x] `.github/workflows/ci.yml` (build, unit, ui matrix).
- [x] `.github/workflows/release.yml` with placeholders, gated off.
- [x] `.github/dependabot.yml`.
- [x] CLAUDE.md: a CI paragraph under Commands; `docs/remaining-work.md`: the branch-protection
      and secrets steps the owner does in the GitHub UI.
- [ ] Open the PR, watch the first run, fix whatever a cold runner shows (lemmas, simulator boot).

## Review

- The owner chose label-gated UI on pull requests. A PR's UI run also skips the six
  `*ScreenshotTests` classes (`ui-shards.sh --skip-screenshots`): about ten tests, three of them
  seeding 300 entries, that make pictures nobody opens in CI. Main and manual runs keep them.
- A survey of all 52 UI tests against the unit suite found none to cut: each checks something only
  a launched app shows. Eight could merge into a neighbour with the same setup, saving 8 of about
  68 launches (roughly a minute of wall-clock across five shards). Not done; a merged test hides its
  second failure behind its first.
- Local run of the scripts: build 36 s warm, unit 1,531 tests in 63 s, two UI classes green.
  The first attempt failed code signing because products went under `~/Documents` (iCloud file
  attributes); the local default now lives in `~/Library/Developer/Xcode/DerivedData/Mindlore-ci`.
- First full hosted run (35768127014): build 3m57s and green. Unit failed on the fresh-runner
  lemma cold start (8 `AskIndexLemmaTests`, 2 `AskRetrievalQualityTests`, and the live Ask test,
  whose only link from "dog's name" to "named Pepper" is a lemma). A new simulator on this Mac
  passes, since the assets live on the host, so it can't be reproduced here; the fix is
  `LanguageAssetsWarmUp`, which awaits `NLTagger.requestAssets` in a run of its own first.
  UI: four of five shards failed, one test each. Three were "Failed to terminate" and one a launch
  timeout, simulator trouble on a small runner with everything around them passing; answered with
  one retry on CI. The fourth was `PageOrderUITests`' reorder drag, which lifted before the list
  committed the move; now a slow drag with a hold, 3/3 locally. The unit job queued behind the
  shards (six jobs, five runners), so `ui` now needs `unit`.
- Second hosted run hung in the unit job's warm-up: `NLTagger.requestAssets` never returns on a
  runner. Replaced with `LemmaAvailability`, a capability check the lemma tests are enabled on.
- The shared build job is gone. Each of the five jobs builds for itself after starting its
  simulator's boot in the background, so the boot (minutes on a fresh runner) hides inside the
  compile instead of queuing after a four-minute build. UI went from five shards to four so unit
  plus UI is exactly the five concurrent runners, all starting together; UI shards are
  `continue-on-error` so they never set the run's result.
- Third hosted run (35773044814), jobs building for themselves: the background boot fought the
  compiler and builds took 6.5 to 11.5 minutes, so the shared build job is back. Unit failed on
  the on-device model quality tests (the model reports itself available in a runner's simulator;
  7 of 12 creative pieces misfiled, generation failing outright), now gated on
  `TestHost.canMeasureOnDeviceModel`, and on a race in `AskStreamingTests` (the fake's delta sent
  but not yet applied), now awaited. UI: the result bundles, not the log, showed the real cause.
  `testMindSearchOpenMergeAndUnmerge` (134 s) and `testKeySetupConnectionAndRemoval` exceeded the
  two-minute allowance, and the forced kill surfaced on the next launch as "Failed to terminate".
  CI now allows five minutes a UI test, and test.sh prints the bundle's failures and retries.
- Fourth hosted run (35776496508): everything green. Build 2m33s without the index store. Unit
  11 minutes: boot 108 s, 4.5 minutes before the first test, 3.7 minutes of tests (1,518 passed,
  13 skipped). UI shards 15 to 21 minutes, one retry (`PageTranscriptionUITests`, passed on it).
  Shards balanced by test count ran 8 to 16 minutes of tests because `GraphUITests` alone is 683 s,
  so shards now split by test method, weighted by the measured seconds in
  `scripts/ci/ui-test-seconds.txt`: about 9 minutes each for a pull request.
- `OnDeviceInsightsLiveTests` failed once locally (Apple's model returned no summary) and passed the
  run before. It is gated on `FoundationModelsAvailability`, so it skips on hosted runners; it is a
  flaky live test on a Mac with Apple Intelligence, not a CI concern.
