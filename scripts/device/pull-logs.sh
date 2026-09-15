#!/bin/bash
# Copies the app's diagnostics log and any Mindlore crash reports off the phone, then prints a timeline.
# Usage: pull-logs.sh [run-id] [timeline options, e.g. --sessions 2]
#        (run-id defaults to the most recent run folder, or a new timestamp)
source "$(dirname "$0")/common.sh"
resolve_device

run_id="${1:-$(ls -1t "$SMOKE_DIR" 2>/dev/null | head -1)}"
shift || true
run_id="${run_id:-$(date +%Y%m%d-%H%M%S)}"
run_dir="$SMOKE_DIR/$run_id"
mkdir -p "$run_dir"

xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source Library/Logs/Mindlore \
    --destination "$run_dir/logs" >/dev/null

crash_dir="$run_dir/crashes"
mkdir -p "$crash_dir"
if xcrun devicectl device copy from \
    --device "$DEVICE_ID" \
    --domain-type systemCrashLogs \
    --source . \
    --destination "$crash_dir/all" >/dev/null 2>&1; then
    find "$crash_dir/all" -type f -iname "*Mindlore*" -exec mv {} "$crash_dir/" \; 2>/dev/null || true
fi
rm -rf "$crash_dir/all"

echo "run=$run_id logs=$run_dir/logs crashes=$(find "$crash_dir" -type f | wc -l | tr -d ' ')"
python3 "$(dirname "$0")/timeline.py" "$run_dir/logs" "$@"
