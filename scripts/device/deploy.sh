#!/bin/bash
# Builds a Debug build for the connected iPhone and installs it. App data on the phone is kept.
source "$(dirname "$0")/common.sh"
resolve_device

echo "Building for $DEVICE_NAME ($DEVICE_UDID)..."
build_log="$DERIVED_DATA/last-build.log"
mkdir -p "$DERIVED_DATA"
if ! xcodebuild \
    -project "$REPO_ROOT/Mindlore.xcodeproj" \
    -scheme Mindlore \
    -configuration Debug \
    -destination "id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    build >"$build_log" 2>&1; then
    grep -E "error:|BUILD FAILED" "$build_log" | head -20 >&2
    echo "Build failed. Full log: $build_log" >&2
    exit 1
fi

echo "Installing..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" >/dev/null
echo "Installed $BUNDLE_ID on $DEVICE_NAME."
