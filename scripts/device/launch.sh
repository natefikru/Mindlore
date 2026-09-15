#!/bin/bash
# Launches the app on the phone with its console attached. Runs until the app exits or is killed.
# Usage: launch.sh [run-id]   (defaults to a timestamp; the id is logged in app.launch)
source "$(dirname "$0")/common.sh"
resolve_device

run_id="${1:-$(date +%Y%m%d-%H%M%S)}"
run_dir="$SMOKE_DIR/$run_id"
mkdir -p "$run_dir"
echo "run=$run_id device=$DEVICE_NAME console=$run_dir/console.log"

# Only lines from DiagnosticsLog are worth streaming; framework chatter goes to the file only.
xcrun devicectl device process launch \
    --device "$DEVICE_ID" \
    --terminate-existing \
    --console \
    -- "$BUNDLE_ID" -diagnosticsRun "$run_id" 2>&1 \
    | tee "$run_dir/console.log" \
    | grep --line-buffered -E "^MINDLORE |error|Error|crash|Terminated|exited" \
    | grep --line-buffered -v '"trigger":"throttle"' || true
echo "app exited (run=$run_id)"
