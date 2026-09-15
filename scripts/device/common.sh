# Shared setup for device scripts. Source it; don't run it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUNDLE_ID="com.natefikru.mindlore"
# Outside ~/Documents: iCloud Drive adds extended attributes there, and codesign rejects the app bundle.
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/Mindlore-device"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/Mindlore.app"
SMOKE_DIR="$REPO_ROOT/.smoke"

# Picks the first paired, connected iPhone unless MINDLORE_DEVICE names one.
# Sets DEVICE_ID (CoreDevice identifier, for devicectl) and DEVICE_UDID (hardware UDID, for xcodebuild).
resolve_device() {
    local json
    json="$(mktemp)"
    xcrun devicectl list devices --json-output "$json" >/dev/null
    local resolved
    resolved="$(python3 - "$json" "${MINDLORE_DEVICE:-}" <<'PY'
import json, sys
path, wanted = sys.argv[1], sys.argv[2]
devices = json.load(open(path))["result"]["devices"]
for device in devices:
    hardware = device.get("hardwareProperties", {})
    connection = device.get("connectionProperties", {})
    name = device.get("deviceProperties", {}).get("name", "")
    if hardware.get("deviceType") != "iPhone" or connection.get("pairingState") != "paired":
        continue
    if connection.get("tunnelState") != "connected":
        continue
    if wanted and wanted not in (name, device["identifier"], hardware.get("udid")):
        continue
    print(device["identifier"], hardware["udid"], name, sep="\t")
    break
PY
)"
    rm -f "$json"
    if [[ -z "$resolved" ]]; then
        echo "No connected, paired iPhone found. Unlock the phone, connect it, and run the app from Xcode once." >&2
        exit 1
    fi
    IFS=$'\t' read -r DEVICE_ID DEVICE_UDID DEVICE_NAME <<<"$resolved"
    export DEVICE_ID DEVICE_UDID DEVICE_NAME
}
