#!/bin/bash
# Boot the test simulator.
#
#   scripts/ci/boot-simulator.sh               boot and wait until it is ready
#   scripts/ci/boot-simulator.sh --background  start the boot and return at once
#
# CI starts the boot in the background before compiling, so the minutes a fresh runner spends
# booting happen during the build instead of after it. test.sh waits for the boot to finish
# (simctl bootstatus) before running anything, whichever way it was started.

source "$(dirname "${BASH_SOURCE[0]}")/env.sh"

udid="$(simulator_udid)"
if [ "${1:-}" = "--background" ]; then
  echo "Booting simulator $udid in the background"
  nohup xcrun simctl boot "$udid" >/dev/null 2>&1 &
else
  boot_simulator "$udid"
fi
