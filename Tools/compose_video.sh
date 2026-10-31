#!/bin/bash
# Builds the demo video from the two simulator recordings: the phone and the watch side by side on a dark
# canvas, optionally with one section sped up (the ~70 s sync), and optionally with a voiceover.
#
#   Tools/compose_video.sh [--dir DIR] [--speed START END FACTOR] [--voice FILE] [--out FILE]
#
# Typical workflow: first compose a silent cut with the speed-up, record the voiceover against it, then
# run again with --voice. START and END are seconds in the *recorded* footage.
set -euo pipefail
DIR="${ECHO_VIDEO_DIR:-$HOME/Desktop/echo-demo}"
SPEED=""; VOICE=""; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DIR="$2"; shift 2 ;;
    --speed) SPEED="$2 $3 $4"; shift 4 ;;
    --voice) VOICE="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
OUT="${OUT:-$DIR/echo_demo.mp4}"
command -v ffmpeg >/dev/null || { echo "ffmpeg is not installed (brew install ffmpeg)" >&2; exit 1; }
[ -f "$DIR/phone.mov" ] && [ -f "$DIR/watch.mov" ] || { echo "Missing $DIR/phone.mov or watch.mov. Record with Tools/record_demo.sh first." >&2; exit 1; }

dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
LEN=$(python3 -I -c "print(min($(dur "$DIR/phone.mov"), $(dur "$DIR/watch.mov")))")

# Phone on the left, watch on the right, centered as a pair on the app's dark background. The watch
# simulator ignores the status bar override, so its real clock would disagree with the phone's 9:41:
# the top strip holding the clock is cropped off (72 of 496 px).
GRAPH="[0:v]fps=30,scale=-2:1000[p];[1:v]fps=30,crop=iw:ih-72:0:72,scale=-2:560[w];\
color=c=0x070914:s=1920x1080:r=30[bg];[bg][p]overlay=x=380:y=40:shortest=1[t];[t][w]overlay=x=1000:y=260:shortest=1[v0]"
if [ -n "$SPEED" ]; then
  set -- $SPEED
  GRAPH="$GRAPH;[v0]split=3[a][b][c];\
[a]trim=0:$1,setpts=PTS-STARTPTS[a1];\
[b]trim=$1:$2,setpts=(PTS-STARTPTS)/$3[b1];\
[c]trim=start=$2,setpts=PTS-STARTPTS[c1];\
[a1][b1][c1]concat=n=3:v=1:a=0[v]"
else
  GRAPH="$GRAPH;[v0]null[v]"
fi

ARGS=(-y -i "$DIR/phone.mov" -i "$DIR/watch.mov")
if [ -n "$VOICE" ]; then ARGS+=(-i "$VOICE"); fi
ARGS+=(-t "$LEN" -filter_complex "$GRAPH" -map "[v]")
if [ -n "$VOICE" ]; then ARGS+=(-map 2:a -c:a aac -b:a 160k); fi
ARGS+=(-c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p -movflags +faststart "$OUT")

ffmpeg -hide_banner -loglevel error "${ARGS[@]}"
echo "Wrote $OUT  ($(dur "$OUT" | cut -d. -f1) s, $(du -h "$OUT" | cut -f1))"
