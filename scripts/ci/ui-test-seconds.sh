#!/bin/bash
# Rewrite scripts/ci/ui-test-seconds.txt from a CI run's UI shard logs.
#
#   scripts/ci/ui-test-seconds.sh 35776496508
#
# Use a run on main (it includes the screenshot classes a pull request's run leaves out). Tests the
# run didn't include keep their old numbers, so a pull request's run can refresh the rest.

set -euo pipefail

run="${1:?usage: ui-test-seconds.sh <run-id>}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$root/scripts/ci/ui-test-seconds.txt"
logs="$(mktemp -d)"
trap 'rm -rf "$logs"' EXIT

for job in $(gh run view "$run" --json jobs -q '.jobs[] | select(.name | startswith("UI tests")) | .databaseId'); do
  gh api "repos/{owner}/{repo}/actions/jobs/$job/logs" > "$logs/$job.log"
done

/usr/bin/python3 - "$out" "$run" "$logs" <<'EOF'
import glob, re, sys
out, run, logs = sys.argv[1], sys.argv[2], sys.argv[3]
ansi = re.compile(r'\x1b\[[0-9;]*m')
seconds = {}
try:
    for line in open(out):
        if line.strip() and not line.startswith('#'):
            value, test = line.split()
            seconds[test] = int(value)
except FileNotFoundError:
    pass
current = None
for path in glob.glob(f"{logs}/*.log"):
    for line in open(path, errors='ignore'):
        line = ansi.sub('', line)
        m = re.search(r"Test Suite '(\w+)' started", line)
        if m and m.group(1) not in ('Selected', 'MindloreUITests'):
            current = m.group(1)
            continue
        m = re.search(r"✔ (test\w+) \(([0-9.]+) seconds\)", line)
        if m and current:
            seconds[f"{current}/{m.group(1)}"] = round(float(m.group(2)))
with open(out, 'w') as f:
    f.write(f"# Seconds each UI test took on a GitHub macos-26 runner (last refreshed from run {run}).\n")
    f.write("# ui-shards.sh balances shards by these; a test missing here counts as 60. Refresh when\n")
    f.write("# shards drift apart: scripts/ci/ui-test-seconds.sh <run-id> rewrites this file.\n")
    for test in sorted(seconds):
        f.write(f"{seconds[test]} {test}\n")
print(f"{len(seconds)} tests in {out}")
EOF
