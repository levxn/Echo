#!/bin/bash
# Build both apps, reinstall on the paired simulators, launch phone first then watch.
# Usage: Tools/run_sims.sh [--no-launch-watch | --autostart]
set -euo pipefail
cd "$(dirname "$0")/.."
PHONE=3BDBF6CE-2235-4CFE-9437-1EB803417569   # iPhone 17 Pro
WATCH=373A257B-EB2B-4A7B-8E94-CFF47E52792D   # Apple Watch Series 11 (46mm)
DD=/tmp/echo-dd
xcodebuild -project Echo.xcodeproj -scheme Echo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath "$DD" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
xcrun simctl boot "$PHONE" 2>/dev/null || true
xcrun simctl boot "$WATCH" 2>/dev/null || true
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp 2>/dev/null || true
xcrun simctl terminate "$PHONE" levtech.Echo 2>/dev/null || true
xcrun simctl install "$PHONE" "$DD/Build/Products/Debug-iphonesimulator/Echo.app"
xcrun simctl install "$WATCH" "$DD/Build/Products/Debug-watchsimulator/Echo Watch App.app"
xcrun simctl launch "$PHONE" levtech.Echo
sleep 3
case "${1:-}" in
  --no-launch-watch) ;;
  --autostart) xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -autostart ;;
  *) xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp ;;
esac
