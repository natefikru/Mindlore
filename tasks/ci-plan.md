# CI for the TestFlight beta

Status: built and green on PR #40, 2026-09-22. The measurements behind every choice are in the
review log at the bottom, run by run.

## Shape

```
build (macos-26, about 2 minutes)      build-for-testing, no index store, products as an artifact
  |
  +-- unit (1 runner)                  every PR and push to main; the only required check
  +-- ui   (4 runners)                 push to main, PR labeled "ui", manual; continue-on-error
```

Five test jobs after one build is exactly the free plan's five concurrent macOS runners, so none
of them queues. Wall-clock on a pull request: the required check about 13 minutes after a push
(2 build, 11 unit), the UI shards about 18.

Where a test job's time goes, measured: about 2 minutes booting a fresh simulator, then about 3
more before the first test (xcodebuild starting, resolving the destination, installing the app,
its first launch on a cold simulator). None of it is the app's own startup, and a test job has
nothing to overlap it with. Unit tests themselves are under 4 minutes; each UI shard about 10.
Building in every job and booting during the compile was tried and was slower (the boot fought
the compiler: 6.5 to 11.5 minute builds).

- **Triggers.** `ui` runs on every push to `main`, on a PR carrying the `ui` label (dispatched by
  `ui-label.yml` as its own run), and on manual dispatch; a manual run with `only` runs named tests (`Class` or `Class/testMethod`) on one
  runner and skips unit. A PR's UI run leaves out the `*ScreenshotTests` classes.
- **Concurrency.** One run per branch; a new push cancels the one in flight.
- **Shards are computed, not maintained.** `ui-shards.sh` deals test methods, heaviest first, by
  the seconds each took on a runner (`ui-test-seconds.txt`, 60 when unknown). A new test needs
  nothing registered; `ui-test-seconds.sh <run-id>` refreshes the numbers.
- **CI-only settings.** A UI test gets five minutes and one retry (two minutes and none locally).
  `test.sh` ends with the result bundle's failures and retries, since the formatted log can show a
  green check for a killed test.
- **Live OpenAI is advisory.** `OpenAILiveTests` and `CreativeOpenAIQualityTests` run with the key in
  the `live` job after unit, never in the required check.
- **What skips on CI, and why.** Lemma tests (`LemmaAvailability`: runners have no NLTagger
  assets and `requestAssets` hangs), on-device model quality (`TestHost.canMeasureOnDeviceModel`:
  present on a runner but meaningless). Both run on every Mac.
- **Same commands locally.** `scripts/ci/build-for-testing.sh` and `scripts/ci/test.sh unit|ui`.
- **On failure** the `.xcresult` uploads (7-day retention) so a red run can be opened in Xcode.
- **Release** is `release.yml`: manual dispatch or a `v*` tag, gated on the repository variable
  `RELEASE_ENABLED` until the paid team exists. Build number comes from the run number.
- **Dependabot** watches the action versions weekly.

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
- [x] Open the PR, watch the first run, fix whatever a cold runner shows (lemmas, simulator boot).

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
- Fifth hosted run (35779396030): UI green in every shard, 43 tests, no retries, shards finishing
  within two minutes of each other (16 to 18). Unit: 1,517 passed and one failed,
  `CreativeOpenAIQualityTests` filing the haiku as life after 19/19 the run before, with no code
  change between; now skipped on CI. The raw xcodebuild lines showed the four minutes before the
  first unit test are xcodebuild startup (46 s), destination (21 s), install (80 s), and a cold
  first launch (2 min): the simulator's cost, not the app's.
- Merged as PR #40. The first run on main then failed the required check on
  `OpenAILiveTests.looseEndsAreCommitmentsNotPassingRemarks` (two commitments where one is allowed),
  a second live-model judgment varying with no code change. Both OpenAI suites moved out of the
  required unit job into an advisory `live` job that runs after unit on its runner.
- Dependabot's first PRs showed that a `labeled` trigger starts a run for every label, and that
  run cancelled the real one in flight. Making it skip instead would record a skipped "Unit tests",
  which counts as passed. `ci.yml` dropped `labeled`; `ui-label.yml` dispatches the UI suite for a
  labeled PR instead.
- `OnDeviceInsightsLiveTests` failed once locally (Apple's model returned no summary) and passed the
  run before. It is gated on `FoundationModelsAvailability`, so it skips on hosted runners; it is a
  flaky live test on a Mac with Apple Intelligence, not a CI concern.
