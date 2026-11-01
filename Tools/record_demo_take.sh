#!/bin/bash
# Records ONE continuous demo take of the whole app, with live Muse Spark if an API key is configured.
#
# The app performs the demo itself (the in-app DemoDriver, launched with -demo-script): it starts the watch,
# types each question, flips the cloud switch and opens the sheets, with a caption for each step. Both
# simulators are recorded, then composed side by side with the ~70 s sync section sped up.
#
#   Tools/record_demo_take.sh [OUTPUT.mp4]        default: docs/media/echo-demo-full.mp4   (takes about 6 minutes)
set -uo pipefail
cd "$(dirname "$0")/.."
PHONE=3BDBF6CE-2235-4CFE-9437-1EB803417569   # iPhone 17 Pro
OUT="${1:-docs/media/echo-demo-full.mp4}"
DIR=/tmp/echo-take
SPEEDUP=5
command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)" >&2; exit 1; }

echo "1/5 preparing clean simulators…"
Tools/demo_prep.sh >/tmp/take_prep.log 2>&1 || { cat /tmp/take_prep.log; echo "FAIL: demo_prep" >&2; exit 1; }
grep -q "Muse Spark: LIVE" /tmp/take_prep.log && echo "    Muse Spark: LIVE" || echo "    NOTE: no API key; cloud answers will be the labeled stub."

rm -rf "$DIR"; mkdir -p "$DIR"
echo "2/5 recording both simulators…"
ECHO_VIDEO_DIR="$DIR" Tools/record_demo.sh start >/dev/null || exit 1
T0=$(python3 -I -c "import time; print(f'{time.time():.3f}')")
START=$(date -r "${T0%.*}" '+%Y-%m-%d %H:%M:%S')
xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1
xcrun simctl launch "$PHONE" levtech.Echo -demo-script full -profile-name Jordan -profile-color 0 -review off -mask off >/dev/null

echo "3/5 the app is performing the demo (about 4 minutes)…"
FINISHED=0
for _ in $(seq 1 120); do
  sleep 5
  if xcrun simctl spawn "$PHONE" log show --info --start "$START" --predicate 'subsystem == "echo" AND eventMessage CONTAINS "demo-script: finished"' --style compact 2>/dev/null | grep -q "demo-script: finished"; then FINISHED=1; break; fi
done
sleep 1
ECHO_VIDEO_DIR="$DIR" Tools/record_demo.sh stop >/dev/null
[ "$FINISHED" = 1 ] || { echo "FAIL: the demo script never finished" >&2; exit 1; }

echo "4/5 finding the sync section…"
if xcrun simctl spawn "$PHONE" log show --info --start "$START" --predicate 'subsystem == "echo" AND eventMessage CONTAINS "demo-script"' --style compact 2>/dev/null | grep -qE "demo-script: (sync-timeout|watch-never-started)"; then
  echo "FAIL: the watch never delivered the day (sync did not complete), so this take is not usable." >&2
  echo "      Raw recordings are in $DIR. Run Tools/demo_prep.sh and try again." >&2
  exit 1
fi
xcrun simctl spawn "$PHONE" log show --info --start "$START" --predicate 'subsystem == "echo" AND eventMessage CONTAINS "demo-script"' --style compact > /tmp/take_markers.txt 2>/dev/null
TRIM=$(ECHO_VIDEO_DIR="$DIR" Tools/compose_video.sh --trim-start auto --print-trim)
# Start the video at the app's "begin" marker: anything before it (launch, waiting for the watch to connect) is dead time.
TRIM=$(python3 -I - "$T0" "$TRIM" /tmp/take_markers.txt <<'PY'
import datetime, re, sys
t0, trim = float(sys.argv[1]), float(sys.argv[2])
begin = None
for line in open(sys.argv[3]):
    g = re.match(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+).*demo-script: begin\b", line)
    if g: begin = datetime.datetime.strptime(g.group(1), "%Y-%m-%d %H:%M:%S.%f").timestamp() - t0
print(f"{max(trim, begin - 0.4):.2f}" if begin is not None else f"{trim:.2f}")
PY
)
read -r S E <<< "$(python3 -I - "$T0" "$TRIM" /tmp/take_markers.txt <<'PY'
import datetime, re, sys
t0, trim = float(sys.argv[1]), float(sys.argv[2])
m = {}
for line in open(sys.argv[3]):
    g = re.match(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+).*demo-script: (\S+)", line)
    if g: m[g.group(2)] = datetime.datetime.strptime(g.group(1), "%Y-%m-%d %H:%M:%S.%f").timestamp() - t0
b = m.get("sync-begin"); e = m.get("sync-end", m.get("sync-timeout"))
# speed up from 2 s after the sync starts to 1 s before it ends, in the trimmed timeline
print(f"{b - trim + 2:.2f} {e - trim - 1:.2f}" if b is not None and e is not None and e - b > 8 else "0 0")
PY
)"
echo "    launch flash trimmed: ${TRIM}s; sync section sped up ${SPEEDUP}x from ${S}s to ${E}s"

echo "5/5 composing the video…"
mkdir -p "$(dirname "$OUT")"
TMPOUT="$DIR/take.mp4"
if [ "$S" = "0" ]; then
  ECHO_VIDEO_DIR="$DIR" Tools/compose_video.sh --trim-start "$TRIM" --out "$TMPOUT" || exit 1
else
  ECHO_VIDEO_DIR="$DIR" Tools/compose_video.sh --trim-start "$TRIM" --speed "$S" "$E" "$SPEEDUP" --out "$TMPOUT" || exit 1
fi
mv "$TMPOUT" "$OUT" && echo "Saved $OUT"
echo "Status bar overrides are still on; run Tools/demo_prep.sh --clear when you're finished."
