#!/bin/bash
# Regenerates the story seed's insights through the real pipeline (MindloreTests/StorySeedRegeneration)
# and writes them into Mindlore/Debug/DemoStory+Chapter*.swift. About 200 OpenAI calls.
#
#   MINDLORE_OPENAI_KEY=sk-... scripts/demo/regenerate-story.sh [--fresh] [--limit N] [--simulator "iPhone 17"]
#   scripts/demo/regenerate-story.sh --key-file <path> ...   (the key read from a file instead)
#
# A run that stops (a failed call, a timeout) keeps what it finished; running again continues from
# there. --fresh throws that away and starts the year over. --limit N stops after N new calls, for a
# trial; the merge only runs once all 200 are done.
set -euo pipefail

cd "$(dirname "$0")/../.."
simulator="iPhone 17"
fresh=0
limit=""
while [ $# -gt 0 ]; do
  case "$1" in
    --fresh) fresh=1 ;;
    --limit) limit="$2"; shift ;;
    --simulator) simulator="$2"; shift ;;
    --key-file) MINDLORE_OPENAI_KEY="$(tr -d '[:space:]' < "$2")"; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
: "${MINDLORE_OPENAI_KEY:?set MINDLORE_OPENAI_KEY}"

bundle=com.natefikru.mindlore
derived="$HOME/Library/Developer/Xcode/DerivedData/Mindlore-demo"
udid=$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
name = sys.argv[1]
devices = [d for runtime in json.load(sys.stdin)["devices"].values() for d in runtime if d["name"] == name]
print(devices[0]["udid"] if devices else "")' "$simulator")
[ -n "$udid" ] || { echo "no simulator named $simulator" >&2; exit 1; }
xcrun simctl boot "$udid" 2>/dev/null || true

container() { xcrun simctl get_app_container "$udid" "$bundle" data 2>/dev/null || true; }
if [ "$fresh" = 1 ] && [ -n "$(container)" ]; then
  rm -f "$(container)/tmp/story-insights.jsonl"
fi

# The key reaches the hosted test through xcodebuild's TEST_RUNNER_ prefix. Only progress lines
# and failures are shown; the log never carries entry text.
set +e
TEST_RUNNER_MINDLORE_OPENAI_KEY="$MINDLORE_OPENAI_KEY" TEST_RUNNER_MINDLORE_REGENERATE_STORY=1 \
  TEST_RUNNER_MINDLORE_REGENERATE_STORY_LIMIT="$limit" \
  xcodebuild -project Mindlore.xcodeproj -scheme Mindlore -destination "id=$udid" \
  -derivedDataPath "$derived" test -only-testing:MindloreTests/StorySeedRegeneration \
  -parallel-testing-enabled NO -test-timeouts-enabled YES 2>&1 \
  | grep --line-buffered -E "REGEN|error:|✘|TEST (SUCCEEDED|FAILED)"
status=${PIPESTATUS[0]}
set -e

output="$(container)/tmp/story-insights.jsonl"
[ -f "$output" ] || { echo "no output at $output" >&2; exit 1; }
lines=$(grep -c . "$output")
echo "regenerated $lines entries"
if [ "$status" != 0 ] || [ "$lines" -lt 200 ]; then
  echo "the run stopped early; run the script again to continue" >&2
  exit 1
fi
cp "$output" "$derived/story-insights.jsonl"
/usr/bin/python3 scripts/demo/merge-story-insights.py "$derived/story-insights.jsonl"
