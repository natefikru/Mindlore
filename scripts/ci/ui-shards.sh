#!/bin/bash
# Split the UI tests into N shards of about equal running time.
#
#   scripts/ci/ui-shards.sh 4                                 every shard, one line each
#   scripts/ci/ui-shards.sh 4 --skip-screenshots --shard 2    shard 2 only, what a CI job asks for
#
# The unit of work is one test method (Class/testMethod), not a class. Every UI test launches the
# app fresh, so splitting a class costs nothing, and GraphUITests alone runs over eleven minutes on
# a runner: whole classes left one shard twice as long as another.
#
# Each test is weighted by its measured seconds in ui-test-seconds.txt, 60 if it isn't there yet,
# and dealt heaviest first to whichever shard is lightest. Tests are found by scanning
# MindloreUITests/*.swift for `func test...`, so a new test joins a shard on the next run with
# nothing registered. The class name is the file name, a convention in this repo.
#
# --skip-screenshots leaves out the *ScreenshotTests classes, which exist to produce pictures for a
# person to look at. CI passes it for a pull request's run; pushes to main and manual runs keep them.

set -euo pipefail

count="${1:-4}"
shift || true
skip_screenshots=false
only_shard=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-screenshots) skip_screenshots=true ;;
    --shard) only_shard="$2"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

/usr/bin/python3 - "$root" "$count" "$skip_screenshots" "$only_shard" <<'EOF'
import glob, os, re, sys
root, count, skip_screenshots, only_shard = sys.argv[1], int(sys.argv[2]), sys.argv[3] == "true", sys.argv[4]

seconds = {}
timings = os.path.join(root, "scripts/ci/ui-test-seconds.txt")
if os.path.exists(timings):
    for line in open(timings):
        if line.strip() and not line.startswith("#"):
            value, test = line.split()
            seconds[test] = int(value)

tests = []
for path in sorted(glob.glob(os.path.join(root, "MindloreUITests/*.swift"))):
    cls = os.path.basename(path)[:-len(".swift")]
    if skip_screenshots and cls.endswith("ScreenshotTests"):
        continue
    for name in re.findall(r"func (test\w+)\s*\(", open(path).read()):
        test = f"{cls}/{name}"
        tests.append((seconds.get(test, 60), test))
if not tests:
    sys.exit("no UI tests found under MindloreUITests")

shards = [[0, []] for _ in range(count)]
for weight, test in sorted(tests, key=lambda t: (-t[0], t[1])):
    lightest = min(shards, key=lambda s: s[0])
    lightest[0] += weight
    lightest[1].append(test)

if only_shard:
    print(" ".join(shards[int(only_shard) - 1][1]))
else:
    for i, (load, members) in enumerate(shards, 1):
        print(f"shard {i}: {len(members)} tests, about {load // 60} min: {' '.join(members)}")
EOF
