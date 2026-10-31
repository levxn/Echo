#!/bin/bash
# Records the phone and the watch simulators at the same time, each to its own file.
#
#   Tools/record_demo.sh start     begin recording (output: $ECHO_VIDEO_DIR, default ~/Desktop/echo-demo)
#   Tools/record_demo.sh stop      stop both recordings and finalize the files
#   Tools/record_demo.sh status    show whether a recording is running
set -uo pipefail
PHONE=3BDBF6CE-2235-4CFE-9437-1EB803417569   # iPhone 17 Pro
WATCH=373A257B-EB2B-4A7B-8E94-CFF47E52792D   # Apple Watch Series 11 (46mm)
DIR="${ECHO_VIDEO_DIR:-$HOME/Desktop/echo-demo}"
PIDS=/tmp/echo_record.pids

running() { [ -f "$PIDS" ] && while read -r pid; do kill -0 "$pid" 2>/dev/null && return 0; done < "$PIDS"; return 1; }

case "${1:-}" in
  start)
    if running; then echo "Already recording. Run '$0 stop' first." >&2; exit 1; fi
    mkdir -p "$DIR"; : > "$PIDS"
    nohup xcrun simctl io "$PHONE" recordVideo --codec=h264 --force "$DIR/phone.mov" >/tmp/echo_rec_phone.log 2>&1 &
    echo $! >> "$PIDS"
    nohup xcrun simctl io "$WATCH" recordVideo --codec=h264 --force "$DIR/watch.mov" >/tmp/echo_rec_watch.log 2>&1 &
    echo $! >> "$PIDS"
    sleep 1.5
    if running; then echo "Recording both simulators to $DIR. Run '$0 stop' when you're done."
    else echo "The recorders exited immediately:" >&2; cat /tmp/echo_rec_phone.log /tmp/echo_rec_watch.log >&2; exit 1; fi ;;
  stop)
    [ -f "$PIDS" ] || { echo "Nothing is recording." >&2; exit 1; }
    while read -r pid; do kill -INT "$pid" 2>/dev/null; done < "$PIDS"
    for _ in $(seq 1 30); do running || break; sleep 1; done   # simctl finalizes the .mov after SIGINT
    if running; then echo "A recorder is still finalizing; wait a few seconds and check the files." >&2; fi
    rm -f "$PIDS"
    ls -la "$DIR"/phone.mov "$DIR"/watch.mov 2>/dev/null ;;
  status) if running; then echo "recording"; else echo "idle"; fi ;;
  *) echo "usage: $0 start|stop|status" >&2; exit 2 ;;
esac
