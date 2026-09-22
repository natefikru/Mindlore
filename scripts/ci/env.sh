#!/bin/bash
# Shared settings for the CI scripts. Sourced, not run.
#
# The same scripts run on a GitHub macOS runner and in a terminal here, so the only things
# that differ are environment variables:
#   MINDLORE_SIM_NAME      simulator device name (default "iPhone 17")
#   MINDLORE_SIM_OS        iOS runtime version, e.g. "26.5". Unset picks the newest installed.
#   MINDLORE_DERIVED_DATA  where products go. The default sits outside the repo on purpose: the
#                          checkout lives under ~/Documents, whose iCloud Drive file attributes
#                          fail code signing ("resource fork, Finder information, or similar
#                          detritus not allowed"). CI sets it to a path in the workspace.
#   MINDLORE_RESULTS       where .xcresult bundles go (default build/results)

set -euo pipefail

CI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="$CI_ROOT/Mindlore.xcodeproj"
SCHEME="Mindlore"
SIM_NAME="${MINDLORE_SIM_NAME:-iPhone 17}"
SIM_OS="${MINDLORE_SIM_OS:-}"
DERIVED_DATA="${MINDLORE_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/Mindlore-ci}"
RESULTS="${MINDLORE_RESULTS:-$CI_ROOT/build/results}"

# Resolve the simulator to a UDID once. A runner image carries several iOS runtimes, each with
# its own "iPhone 17", and a name-only destination is ambiguous there. With MINDLORE_SIM_OS unset
# the newest runtime wins, which is what a development Mac wants.
simulator_udid() {
  xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
name, want = sys.argv[1], sys.argv[2]
devices = json.load(sys.stdin)["devices"]
found = []
for runtime, list in devices.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(p) for p in runtime.rsplit(".", 1)[-1].replace("iOS-", "").split("-"))
    if want and ".".join(str(p) for p in version) != want:
        continue
    for d in list:
        if d["name"] == name and d.get("isAvailable", True):
            found.append((version, d["udid"]))
if not found:
    sys.exit(f"no available simulator named {name!r}" + (f" on iOS {want}" if want else ""))
print(max(found)[1])
' "$SIM_NAME" "$SIM_OS"
}

# Boot if needed and wait until the simulator is ready. bootstatus -b boots a shut-down device
# itself and waits for one that is already booting (boot-simulator.sh --background).
boot_simulator() {
  local udid="$1"
  local started=$SECONDS
  xcrun simctl bootstatus "$udid" -b >/dev/null
  echo "Simulator $udid ready (waited $((SECONDS - started))s)"
}

# xcbeautify is on every GitHub macOS image and optional at home. pipefail (set above) keeps
# xcodebuild's exit code through the pipe.
run_xcodebuild() {
  if command -v xcbeautify >/dev/null 2>&1; then
    local renderer=()
    [ -n "${GITHUB_ACTIONS:-}" ] && renderer=(--renderer github-actions)
    xcodebuild "$@" 2>&1 | xcbeautify "${renderer[@]}"
  else
    xcodebuild "$@"
  fi
}
