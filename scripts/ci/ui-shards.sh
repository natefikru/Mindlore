#!/bin/bash
# Split the UI test classes into N balanced shards and print them as a GitHub Actions matrix.
#
#   scripts/ci/ui-shards.sh 5
#   {"include":[{"shard":1,"classes":"GraphUITests TodayUITests ..."}, ...]}
#
# Every file in MindloreUITests/ whose class has at least one test is a unit of work weighted by
# its test count (each UI test launches the app, so the count is a fair proxy for time). Classes
# are dealt largest first to whichever shard is lightest. Nothing is maintained by hand: a new
# test class joins a shard on the next run, and a file with no tests (a helper) is ignored.
#
# The class name is the file name; that is a convention in this repo, and test.sh passes each
# one as -only-testing:MindloreUITests/<Class>.

#   scripts/ci/ui-shards.sh 4 --skip-screenshots
#   scripts/ci/ui-shards.sh 4 --skip-screenshots --shard 2
#
# --skip-screenshots leaves out the *ScreenshotTests classes, which exist to produce pictures
# for a person to look at. CI passes it for a pull request's label-triggered run; pushes to
# main and manual runs keep them. --shard N prints only shard N's classes, space-separated
# (nothing if that shard is empty), which is what each CI job asks for.

set -euo pipefail

count="${1:-5}"
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

# "weight class" per line, heaviest first.
weighted=()
for file in "$root"/MindloreUITests/*.swift; do
  class="$(basename "$file" .swift)"
  if $skip_screenshots && [[ "$class" == *ScreenshotTests ]]; then continue; fi
  tests="$(grep -c 'func test' "$file" || true)"
  [ "$tests" -gt 0 ] && weighted+=("$tests $class")
done
if [ ${#weighted[@]} -eq 0 ]; then
  echo "no UI test classes found under $root/MindloreUITests" >&2
  exit 1
fi

loads=()
members=()
for ((i = 0; i < count; i++)); do loads[i]=0; members[i]=""; done

while read -r tests class; do
  lightest=0
  for ((i = 1; i < count; i++)); do
    [ "${loads[i]}" -lt "${loads[lightest]}" ] && lightest=$i
  done
  loads[lightest]=$(( loads[lightest] + tests ))
  members[lightest]="${members[lightest]:+${members[lightest]} }$class"
done < <(printf '%s\n' "${weighted[@]}" | sort -rn -k1,1 -k2,2)

if [ -n "$only_shard" ]; then
  echo "${members[only_shard - 1]:-}"
  exit 0
fi

json='{"include":['
for ((i = 0; i < count; i++)); do
  [ -z "${members[i]}" ] && continue
  [ "$json" != '{"include":[' ] && json+=','
  json+="{\"shard\":$((i + 1)),\"tests\":${loads[i]},\"classes\":\"${members[i]}\"}"
done
json+=']}'
echo "$json"
