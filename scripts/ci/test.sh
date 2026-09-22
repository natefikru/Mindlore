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
    # On CI a failed UI test gets one more try. Shared runners occasionally fail to terminate the
    # previous app instance ("Failed to terminate com.natefikru.mindlore") before a relaunch,
    # which is the simulator, not the app. A retried test still shows in the log and the
    # result bundle. Locally a failure stays a failure.
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
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

udid="$(simulator_udid)"
boot_simulator "$udid"
mkdir -p "$RESULTS"
rm -rf "$RESULTS/$name.xcresult"

echo "Running $mode tests on simulator $udid from $(basename "$xctestrun")"
run_xcodebuild \
  test-without-building \
  -xctestrun "$xctestrun" \
  -destination "platform=iOS Simulator,id=$udid" \
  -resultBundlePath "$RESULTS/$name.xcresult" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance "$allowance" \
  "${only[@]}"
