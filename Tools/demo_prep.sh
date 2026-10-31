#!/bin/bash
# Gets both simulators into a clean, recordable state:
#   - latest build installed (and your API key, if Config/meta_api_key.txt is filled in)
#   - Apple-style status bars (9:41, full battery and signal), dark appearance, default text size
#   - the day's data wiped (not the API key, and the app is never uninstalled: that would reset the
#     speech permission), cloud switch on
#   - phone launched, then the watch launched WITHOUT autostart, ready for you to tap Start day
#
#   Tools/demo_prep.sh           prepare
#   Tools/demo_prep.sh --clear   remove the status bar overrides afterwards
set -uo pipefail
cd "$(dirname "$0")/.."
PHONE=3BDBF6CE-2235-4CFE-9437-1EB803417569   # iPhone 17 Pro
WATCH=373A257B-EB2B-4A7B-8E94-CFF47E52792D   # Apple Watch Series 11 (46mm)

if [ "${1:-}" = "--clear" ]; then
  xcrun simctl status_bar "$PHONE" clear 2>/dev/null; xcrun simctl status_bar "$WATCH" clear 2>/dev/null
  echo "Status bar overrides cleared."; exit 0
fi

Tools/run_sims.sh --no-launch-watch || exit 1
xcrun simctl bootstatus "$PHONE" -b >/dev/null 2>&1 || true
xcrun simctl bootstatus "$WATCH" -b >/dev/null 2>&1 || true

for D in "$PHONE" "$WATCH"; do
  xcrun simctl ui "$D" appearance dark 2>/dev/null || true
  xcrun simctl status_bar "$D" override --time "9:41" --batteryState charged --batteryLevel 100 2>/dev/null || true
done
xcrun simctl status_bar "$PHONE" override --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName "" 2>/dev/null || true
xcrun simctl ui "$PHONE" content_size large 2>/dev/null || true

# One-shot reset token: wipes the day on this launch only, even if the system relaunches the app later.
xcrun simctl terminate "$PHONE" levtech.Echo 2>/dev/null || true
xcrun simctl launch "$PHONE" levtech.Echo -reset-demo "$(date +%s)" >/dev/null
sleep 3
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp 2>/dev/null || true
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp >/dev/null

# Wait for the watch to see the phone.
LINKED=no
for _ in $(seq 1 20); do
  if xcrun simctl spawn "$WATCH" log show --info --last 40s --predicate 'subsystem == "echo"' --style compact 2>/dev/null \
      | grep -qE "reachable=true|reachability -> true"; then LINKED=yes; break; fi
  sleep 2
done

KEYFILE="$(xcrun simctl get_app_container "$PHONE" levtech.Echo data 2>/dev/null)/Library/Application Support/Echo/meta_api_key"
echo "----------------------------------------------"
echo "Simulators ready. Watch can see the phone: $LINKED"
if [ -f "$KEYFILE" ]; then echo "Muse Spark: LIVE (API key installed)"; else echo "Muse Spark: STUB (no API key; answers are labeled)"; fi
echo "Next: tap 'Start day' on the watch. Run 'Tools/demo_prep.sh --clear' when you're done recording."
