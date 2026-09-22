#!/bin/bash
# Compile the app and both test bundles once, for the simulator, without running anything.
# The products (and the .xctestrun that describes them) land in $DERIVED_DATA/Build/Products,
# which test.sh then runs against as many times as it likes. CI uploads that folder so the
# unit job and every UI shard test the same binaries without compiling again.
#
# Signing is left at the project's defaults on purpose: a simulator build ad-hoc signs without
# a certificate, and the Keychain tests need the app signed (CODE_SIGNING_ALLOWED=NO fails
# them with errSecMissingEntitlement).

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

udid="$(simulator_udid)"
echo "Building for testing on simulator $udid ($SIM_NAME${SIM_OS:+, iOS $SIM_OS})"

run_xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$udid" \
  -derivedDataPath "$DERIVED_DATA" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  build-for-testing
