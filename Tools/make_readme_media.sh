#!/bin/bash
# Regenerates the README media in docs/media/: a screenshot of every screen, a short preview video
# (phone and watch side by side), an inline-friendly GIF, and a hero image.
#
# It runs the real app on the simulators: a clean day, the watch replaying it, then each screen. If no API
# key is configured the cloud answers are the labeled offline stub, and the screenshots say so. Re-run it
# after adding your key (Config/meta_api_key.txt) to refresh them with live Muse answers.
#
#   Tools/make_readme_media.sh                full run (about 10 minutes)
#   Tools/make_readme_media.sh --compose-only re-edit the video, GIF and hero from the last run's recordings
set -uo pipefail
cd "$(dirname "$0")/.."
PHONE=3BDBF6CE-2235-4CFE-9437-1EB803417569   # iPhone 17 Pro
WATCH=373A257B-EB2B-4A7B-8E94-CFF47E52792D   # Apple Watch Series 11 (46mm)
OUT=docs/media; SHOTS=$OUT/screenshots; TMP=/tmp/echo-media
command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)" >&2; exit 1; }
COMPOSE_ONLY=0; [ "${1:-}" = "--compose-only" ] && COMPOSE_ONLY=1
# Each scene relaunches the app, so every recording starts with a launch flash (home screen, black launch
# screen). compose_video.sh --trim-start auto cuts it off by detecting where the black ends.
if [ "$COMPOSE_ONLY" = 0 ]; then rm -rf "$TMP"; mkdir -p "$SHOTS" "$TMP"; rm -f "$SHOTS"/*.png "$SHOTS"/*.jpg; fi
mkdir -p "$SHOTS" "$TMP"

shot_phone() {   # name  -> docs/media/screenshots/phone-<name>.png (600 px wide), full-res kept in $TMP
  xcrun simctl io "$PHONE" screenshot "$TMP/raw_phone_$1.png" >/dev/null 2>&1
  sips --resampleWidth 600 "$TMP/raw_phone_$1.png" --out "$SHOTS/phone-$1.png" >/dev/null 2>&1
}
shot_watch() {   # name  -> docs/media/screenshots/watch-<name>.png, with the real-time clock strip cropped off
  xcrun simctl io "$WATCH" screenshot "$TMP/raw_watch_$1.png" >/dev/null 2>&1
  ffmpeg -loglevel error -y -i "$TMP/raw_watch_$1.png" -vf "crop=iw:ih-72:0:72" "$SHOTS/watch-$1.png"
  cp "$SHOTS/watch-$1.png" "$TMP/raw_watchcrop_$1.png"
}
launch_phone() { xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1; xcrun simctl launch "$PHONE" levtech.Echo -profile-name Levin -profile-color 0 "$@" >/dev/null; }

# scene NAME SECONDS ARGS...: record both simulators, open the phone with ARGS, wait, screenshot, stop.
scene() {
  local name=$1 secs=$2; shift 2
  local dir="$TMP/clip_$name"; mkdir -p "$dir"
  ECHO_VIDEO_DIR="$dir" Tools/record_demo.sh start >/dev/null || return 1
  launch_phone "$@"
  sleep "$secs"
  shot_phone "$name"
  ECHO_VIDEO_DIR="$dir" Tools/record_demo.sh stop >/dev/null
}

# compose_clip NAME [--speed START END FACTOR]: phone and watch side by side, launch flash trimmed off.
compose_clip() {
  local name=$1; shift
  ECHO_VIDEO_DIR="$TMP/clip_$name" Tools/compose_video.sh --trim-start auto --out "$TMP/clip_$name/out.mp4" "$@" >/dev/null
}

if [ "$COMPOSE_ONLY" = 0 ]; then
echo "1/6 clean simulators…"
Tools/demo_prep.sh >/tmp/echo_media_prep.log 2>&1 || { cat /tmp/echo_media_prep.log; exit 1; }
sleep 2; shot_phone empty; shot_watch ready

echo "2/6 the watch replays last week, then today (today is recorded)…"
launch_phone -tab moments
sleep 3
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp >/dev/null 2>&1
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -autostart "prev$(date +%s)" -day-offset -7 >/dev/null
sleep 25
DBP=""; for _ in $(seq 1 30); do DBP=$(find ~/Library/Developer/CoreSimulator/Devices/$PHONE/data/Containers/Data/Application -name echo.sqlite 2>/dev/null | head -1); [ -n "$DBP" ] && break; sleep 2; done
pp=-1; ss=0
for _ in $(seq 1 60); do
  o=$(python3 -I -c "
import sqlite3
c=sqlite3.connect('file:$DBP?mode=ro',uri=True)
print(c.execute('select count(*) from chunk').fetchone()[0], c.execute(\"select count(*) from chunk where status in ('received','vad','asr')\").fetchone()[0])" 2>/dev/null)
  set -- $o
  if [ "${2:-x}" = "0" ] && [ "${1:-0}" = "$pp" ] && [ "${1:-0}" -gt 10 ]; then ss=$((ss+1)); else ss=0; fi
  pp=${1:-0}; [ "$ss" -ge 3 ] && break; sleep 10
done
sleep 3
dir="$TMP/clip_replay"; mkdir -p "$dir"
ECHO_VIDEO_DIR="$dir" Tools/record_demo.sh start >/dev/null
launch_phone -tab moments
sleep 2
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp >/dev/null 2>&1
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -autostart "$(date +%s)" >/dev/null
sleep 13; shot_phone moments-live; shot_watch listening
sleep 10
ECHO_VIDEO_DIR="$dir" Tools/record_demo.sh stop >/dev/null

echo "3/6 waiting for the phone to finish processing…"
DB=""; for _ in $(seq 1 30); do DB=$(find ~/Library/Developer/CoreSimulator/Devices/$PHONE/data/Containers/Data/Application -name echo.sqlite 2>/dev/null | head -1); [ -n "$DB" ] && break; sleep 2; done
prev=-1; stable=0
for _ in $(seq 1 90); do
  out=$(python3 -I -c "
import sqlite3
c=sqlite3.connect('file:$DB?mode=ro',uri=True)
print(c.execute('select count(*) from chunk').fetchone()[0], c.execute(\"select count(*) from chunk where status in ('received','vad','asr')\").fetchone()[0])" 2>/dev/null)
  set -- $out
  if [ "${2:-x}" = "0" ] && [ "${1:-0}" = "$prev" ] && [ "${1:-0}" -gt 20 ]; then stable=$((stable+1)); else stable=0; fi
  prev=${1:-0}; [ "$stable" -ge 3 ] && break; sleep 10
done
sleep 3; shot_watch done

echo "4/6 each screen (recorded)…"
# Every scene passes the settings it needs, because they persist between launches.
scene today 7.5 -tab today -today-section day -voice-me -name-places -review off -mask off      # also a clip in the preview video
scene places 8 -tab today -today-section day -today-scroll places -name-places
scene voices 8 -tab today -today-section people -voice-me
scene moments 6.5 -tab moments
scene ask-lookup 7.5 -tab ask -ask "When is the plumber coming?"
scene ask-cloud 14 -tab ask -ask "What did I promise people today?"   # a live Muse call takes ~6 s
scene ask-followup 24 -tab ask -ask "What did I promise people today?" -then "Which of those is due first?"   # two live calls

# A spoken question: a recorded one stands in for the microphone. Listening is brief, so its screenshot is taken early.
dir="$TMP/clip_voice-answer"; mkdir -p "$dir"
ECHO_VIDEO_DIR="$dir" Tools/record_demo.sh start >/dev/null
launch_phone -tab ask -voice-ask 4
sleep 1.0; shot_phone ask-listening
sleep 15; shot_phone ask-voice
ECHO_VIDEO_DIR="$dir" Tools/record_demo.sh stop >/dev/null
scene history-detail 7 -tab ask -history first   # the newest question reopened: its answer and citations

scene today-commitments 7.5 -tab today -today-section commitments -notify-provisional -remind-first   # the first one has a reminder
# "Lee" is the recognizer mishearing "leave"; hiding it is exactly what the Not a person button does.
scene people 8 -tab today -today-section people -people-open -echo.peopleIgnored lee
scene draft 24 -tab today -today-section commitments -draft-first -draft-run -review off   # a live Muse call
scene digest 17 -digest -today-section summary                      # the digest takes ~11 s live (also a preview clip)
scene ledger 7.5 -tab ledger
scene ledger-data 7.5 -tab ledger -ledger-focus data
launch_phone -review off -mask off; sleep 3
scene architecture 8.5 -tab ledger -architecture

echo "   the watch's Ask page…"
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp >/dev/null 2>&1
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -page ask >/dev/null; sleep 5; shot_watch ask
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp >/dev/null 2>&1
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -page ask -ask-focus recent >/dev/null; sleep 9; shot_watch recent
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp >/dev/null 2>&1
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -page ask -voice 4 "media$(date +%s)" >/dev/null; sleep 34; shot_watch answer   # a spoken question, answered by Muse


# Phone screenshots as JPEG: the aurora gradients make PNGs several times larger for no visible gain.
for f in "$SHOTS"/phone-*.png; do
  sips -s format jpeg -s formatOptions 86 "$f" --out "${f%.png}.jpg" >/dev/null 2>&1 && rm -f "$f"
done
fi

echo "5/6 the preview video and GIF…"
compose_clip replay --speed 3 22 3
for c in today ask-lookup voice-answer digest ledger architecture; do compose_clip "$c"; done
: > "$TMP/list.txt"
for c in replay today ask-lookup voice-answer digest ledger architecture; do echo "file '$TMP/clip_$c/out.mp4'" >> "$TMP/list.txt"; done
ffmpeg -loglevel error -y -f concat -safe 0 -i "$TMP/list.txt" -c copy "$OUT/echo-demo-preview.mp4"
ffmpeg -loglevel error -y -i "$OUT/echo-demo-preview.mp4" \
  -vf "fps=8,scale=800:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  -loop 0 "$OUT/echo-demo.gif"

echo "6/6 the hero image…"
ffmpeg -loglevel error -y -f lavfi -i "color=c=0x070914:s=1920x1080" -i "$TMP/raw_phone_ask-lookup.png" -i "$TMP/raw_watchcrop_done.png" \
  -filter_complex "[1:v]scale=-2:1000[p];[2:v]scale=-2:560[w];[0:v][p]overlay=x=380:y=40[t];[t][w]overlay=x=1000:y=260" \
  -frames:v 1 "$OUT/hero.png"

# Keep only the screenshots the README shows.
for f in "$SHOTS"/*; do grep -q "$(basename "$f")" README.md || rm -f "$f"; done

echo; ls -la "$OUT" "$SHOTS" | grep -v '^total'
echo; echo "Status bar overrides are still on; run Tools/demo_prep.sh --clear when you're finished."
