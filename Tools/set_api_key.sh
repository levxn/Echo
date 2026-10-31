#!/bin/bash
# Installs your Meta Model API key into the iPhone simulator's Echo app container.
#
# The key is read from Config/meta_api_key.txt (gitignored). If that file still holds the placeholder,
# you are prompted for it instead (input hidden). The key never enters the repo, build settings or logs.
#
#   Tools/set_api_key.sh          install, prompting if the Config file isn't filled in
#   Tools/set_api_key.sh --auto   never prompt; quietly do nothing if no key is configured
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CONFIG="$ROOT/Config/meta_api_key.txt"
PHONE=3BDBF6CE-2235-4CFE-9437-1EB803417569   # iPhone 17 Pro simulator
AUTO=0; [ "${1:-}" = "--auto" ] && AUTO=1

KEY=""
if [ -f "$CONFIG" ]; then
  CANDIDATE=$(tr -d '[:space:]' < "$CONFIG")
  case "$CANDIDATE" in ""|PASTE_*) ;; *) KEY="$CANDIDATE" ;; esac
fi

if [ -z "$KEY" ]; then
  if [ "$AUTO" = 1 ]; then echo "No API key configured in Config/meta_api_key.txt (Echo will use its labeled stub)."; exit 0; fi
  if [ ! -t 0 ]; then echo "Config/meta_api_key.txt still holds the placeholder. Edit it, then rerun." >&2; exit 2; fi
  printf "Paste your Meta Model API key (input is hidden): "
  read -rs KEY; echo
  [ -n "$KEY" ] || { echo "No key entered." >&2; exit 1; }
fi

xcrun simctl boot "$PHONE" 2>/dev/null || true
CONTAINER=$(xcrun simctl get_app_container "$PHONE" levtech.Echo data 2>/dev/null) || {
  echo "Echo isn't installed on that simulator yet. Run Tools/run_sims.sh first." >&2; exit 1; }
DIR="$CONTAINER/Library/Application Support/Echo"
mkdir -p "$DIR"
( umask 077; printf '%s' "$KEY" > "$DIR/meta_api_key" )
echo "Installed a ${#KEY}-character key into the simulator app. It is not stored in the repo."
