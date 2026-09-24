# CI speed

Status: phases 1 and 2 built 2026-09-24 on `ci/speed`. Phase 3 (money) is the owner's call; prices are below.

## Where the 20 minutes go

A typical PR run (36013241760):

```
build            0.2 -> 4.0 min   compile 3.3 min, pack, upload
unit             4.1 -> 12.3 min  required check done here
live            12.4 -> 19.8 min  advisory, waits for unit so it can reuse unit's runner
```

The required check finishes at about 12 minutes. The last 7 to 9 minutes of every run are the
advisory `live` job, stacked after unit on purpose so it never needs a sixth runner.

Inside the 8.2 minute unit job:

| Phase | Time |
|---|---|
| Runner setup, download, unpack | 8 s |
| Simulator boot | 113 s |
| xcodebuild start, install, cold first launch | 157 s |
| Tests (1,772) | 175 s |

Of the 175 s of tests, 15 tests take about 125 s. The other 1,757 take about 50 s. Cutting unit
tests by count saves almost nothing; cutting those 15 halves the test time.

| Test | Suite | CI s |
|---|---|---|
| aLargeJournalIsIndexedInReasonableTime | GraphUpgradeTests | 28.5 |
| threeHundredNodesSettleWithinBudget | GraphSimulationTests | 12.6 |
| threeHundredNodesActuallyConverge | GraphSimulationTests | 12.1 |
| theDemoGraphSettlesWithFinitePositions | GraphSimulationTests | 8.0 |
| theLargeSeedStillMakesABusyMap | DemoJournalTests | 6.5 |
| theParaphraseGap | AskRetrievalParaphraseTests | 6.3 |
| everyThreadTheStorySettlesIsResolvedNotFaded | DemoStoryTests | 4.9 |
| looseEndsAreSpreadAcrossTheJournalInEveryState | DemoJournalTests | 4.6 |
| lemmatizationExperiment | AskRetrievalParaphraseTests | 4.5 |
| threeHundredEntriesGiveAGraphOfRoughlyThreeHundredNodes | DemoJournalTests | 4.4 |
| seedingWritesTheJournalTheGraphAndTheLooseEnds | DemoStoryTests | 4.3 |
| theStorysHeadlineArc | DemoStoryTests | 4.0 |
| heicFromThePhotoLibraryIsReadable | PageTranscriptionClientTests | 3.6 |
| chunkedAndOnePassSweepsBuildTheSameGraph | GraphUpgradeTests | 3.6 |
| theEstimateKnowsAboutTheYearPath | AskRollupsTests | 2.4 |

Pushes to main are the other problem. Each one starts build, unit, live, and four UI shards of
15 to 20 minutes: seven macOS jobs against an account-wide limit of five. Any PR pushed in the
next 20 minutes queues; `live` started 20 minutes late in runs 35949296868 and 35951093789. And
the UI shards on main have been red on the same tests run after run
(`testEntriesWithNothingInThemDoNotStickAround`, `testClearingANewEntryAndGoingBackLeavesNothing`,
"application is not running"), which nobody acts on because the shards are advisory.

## Phase 1: free, config only (PR run 20 -> about 9 minutes)

Done. The owner chose to gate the slow tests rather than delete them, apart from the experiment.

- [x] `live` leaves PR and main runs. It runs nightly on a schedule (skipped when main hasn't
      moved), on manual dispatch, and on a `live` label. Saves 7 to 9 minutes of wall-clock per run.
- [x] UI leaves pushes to main. It runs nightly and on the `ui` label, as now. Frees four runners
      for 20 minutes after every merge, which is what makes PRs queue.
- [x] A `slow` gate (`TestHost.runsSlowTests`, false when `TEST_RUNNER_MINDLORE_CI=1` unless
      `MINDLORE_SLOW=1`) on the 15 tests above; the nightly run sets it. About 2 minutes off unit.
- [x] Delete `lemmatizationExperiment`: it answered its question when lemmas shipped.
- [x] Fix or delete the two UI tests that fail every main run.

## Phase 2: cut the UI suite (52 tests, 47 min of test time -> 16 tests, about 18 min)

Done, and harder than the tiers below: P0 plus one path per tab, sixteen tests, three shards of
about six minutes. The owner asked for as few as possible (2026-09-24).

The two tests red on every main run were deleted, not fixed. On a runner the app died right after
the step that types an empty string into a new entry's editor ("Unable to monitor event loop",
then "application is not running"); the same test passes on a Mac (checked 2026-09-24). Worth
trying on the phone: type into a new entry, delete it all, go back. `EditorLifecycleTests` covers
the blank-entry delete itself but not UITextView being cleared.

The tiers the cut was made from:

Priority by what only a launched app can prove, highest first.

**P0 keep: data survives.** ContinuousSaveUITests (force-quit), EntryDateUITests (relaunch),
DraftUITests, RecordingUITests, PageOrderUITests, PageTranscriptionUITests, WelcomeUITests,
MindloreUITestsLaunchTests.

**P1 keep one happy path per tab.** AskUITests/testAskAnswersWithACitationAndKeepsHistory,
GraphUITests/testMindSearchOpenMergeAndUnmerge, InsightsUITests, AIConfigurationUITests,
AISettingsUITests, TodayUITests/testTodayShowsCardsAndADismissalOutlivesALaunch,
ReflectUITests/testADismissalOutlivesARelaunch, ReadModeUITests/testAFinishedEntryOpensForReadingAndEditReturnsToIt,
JournalNavigationUITests/testACancelledBackSwipeKeepsTheEntryOpen.

**P2 move to local-only or fold into P1.** The other five GraphUITests (lenses, replay, area
tile, bio, show in Mind: 330 s), the other five AskUITests (keyboard, search-as-you-type,
suggestions: 180 s), ReflectUITests' month expansion and card tap, TodayThreadActionUITests,
the rest of Today, ReadMode's name tap, TitleUITests, JournalNavigation's other two.

**P3 out of CI.** All six `*ScreenshotTests` classes (10 tests, about 600 s): they make pictures
nobody opens in CI. SettingsTabUITests (checks a one-time redesign).

## Phase 3: money

- **Self-hosted Mac mini (recommended).** An M4 mini with a warm simulator and warm DerivedData
  runs the unit tests in about 64 s here, so the required check would land in 3 to 5 minutes, and
  it sits outside the five-runner limit. The repo is public, so it only takes jobs from this repo
  (`head.repo.full_name == github.repository`), fork PRs need approval in the repo settings, and
  its work directory stays outside `~/Documents` (signing).
- **GitHub macOS xlarge runners** (`macos-26-xlarge`: M2 Pro, 5 cores plus 8 GPU cores, 14 GB).
  $0.102 a minute, billed even on a public repo. `macos-26-large` is 12-core Intel at $0.077.
  The standard `macos-26` (3-core M1) is $0.062 and free here because the repo is public.
  Would roughly halve boot, install, and tests; put only build and unit on them. A PR run of
  about six xlarge minutes is about $0.60. GitHub's docs don't say which plans get larger macOS
  runners; they went GA for Team and Enterprise Cloud.
- **Self-hosted platform fee.** GitHub announced $0.002 a minute for self-hosted runners from
  March 2026, then shelved it; public repositories were exempt either way.
- **Third-party M-series runners** (Cirrus Runners, Namespace, WarpBuild): flat monthly price per
  runner. Check current pricing.
