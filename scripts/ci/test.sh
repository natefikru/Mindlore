#!/bin/bash
# Run tests against products built by build-for-testing.sh (building first if they are missing).
#
#   scripts/ci/test.sh unit                       every MindloreTests suite
#   scripts/ci/test.sh ui GraphUITests AskUITests  the named MindloreUITests classes
#
# Both modes run serially (-parallel-testing-enabled NO, so no cloned simulators) with a per-test
# time allowance, because an awaited continuation that never resumes would otherwise hang the run
# silently. Unit tests get 60 seconds each, UI tests 120, the same numbers as CLAUDE.md.
#
# Results go to $RESULTS/<name>.xcresult, where CI uploads them on failure.

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

mode="${1:-}"
shift || true

case "$mode" in
  unit)
    only=(-only-testing:MindloreTests)
    allowance=60
    name="unit"
    ;;
  ui)
    if [ $# -eq 0 ]; then
      echo "usage: test.sh ui <UITestClass> [<UITestClass> ...]" >&2
      exit 2
    fi
    only=()
    for cls in "$@"; do only+=("-only-testing:MindloreUITests/$cls"); done
    allowance=120
    name="ui-$(echo "$1" | tr -c 'A-Za-z0-9\n' '-')"
    # On CI, five minutes a test instead of two, and one retry. A hosted runner is two to three
    # times slower than a Mac here, and a test that relaunches the app took 134 seconds there:
    # killed at the two-minute allowance, it failed, and the forced kill left the next launch
    # reporting "Failed to terminate com.natefikru.mindlore", which read like simulator trouble
    # until the result bundle showed the allowance. The retry is for the occasional real launch
    # hiccup; a retried test still shows in the result bundle. Locally nothing changes.
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      allowance=300
      only+=(-retry-tests-on-failure -test-iterations 2)
    fi
    ;;
  *)
    echo "usage: test.sh unit | test.sh ui <UITestClass> ..." >&2
    exit 2
    ;;
esac

xctestrun="$(ls "$DERIVED_DATA"/Build/Products/*iphonesimulator*.xctestrun 2>/dev/null | head -1 || true)"
if [ -z "$xctestrun" ]; then
  echo "No test products in $DERIVED_DATA; building first."
  "$(dirname "${BASH_SOURCE[0]}")/build-for-testing.sh"
  xctestrun="$(ls "$DERIVED_DATA"/Build/Products/*iphonesimulator*.xctestrun | head -1)"
fi

# Tells the tests they are on CI (TestHost.isCI), for the few measurements a runner can't make.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  export TEST_RUNNER_MINDLORE_CI=1
fi

udid="$(simulator_udid)"
boot_simulator "$udid"
mkdir -p "$RESULTS"
rm -rf "$RESULTS/$name.xcresult"

echo "Running $mode tests on simulator $udid from $(basename "$xctestrun")"
status=0
run_xcodebuild \
  test-without-building \
  -xctestrun "$xctestrun" \
  -destination "platform=iOS Simulator,id=$udid" \
  -resultBundlePath "$RESULTS/$name.xcresult" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance "$allowance" \
  "${only[@]}" || status=$?

# The formatted log can mislead: xcbeautify printed a green check for a test the allowance had
# killed. The result bundle is the record, so end with what it says failed and what needed a retry.
if [ -d "$RESULTS/$name.xcresult" ] && command -v jq >/dev/null 2>&1; then
  echo "Result bundle: $(xcrun xcresulttool get test-results summary --path "$RESULTS/$name.xcresult" \
    | jq -r '"\(.result), \(.passedTests) passed, \(.failedTests) failed, \(.skippedTests) skipped"')"
  xcrun xcresulttool get test-results summary --path "$RESULTS/$name.xcresult" \
    | jq -r '.testFailures[] | "  FAILED \(.testIdentifierString // .testName): \(.failureText)"'
  xcrun xcresulttool get test-results tests --path "$RESULTS/$name.xcresult" \
    | jq -r '.. | objects | select(.nodeType? == "Test Case" and .result == "Passed" and ([.children[]? | select(.nodeType == "Repetition")] | length) > 1) | "  RETRIED, then passed: \(.nodeIdentifier // .name)"'
fi
exit "$status"
