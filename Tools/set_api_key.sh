#!/bin/bash
# Stores your Meta Model API key inside the iPhone simulator's Echo app container.
# The key never enters the repo, build settings or logs. Run this in your own terminal
# (not through a chat), then relaunch the app.
set -euo pipefail
PHONE=3BDBF6CE-2235-4CFE-9437-1EB803417569   # iPhone 17 Pro simulator

xcrun simctl boot "$PHONE" 2>/dev/null || true
CONTAINER=$(xcrun simctl get_app_container "$PHONE" levtech.Echo data 2>/dev/null) || {
  echo "Echo isn't installed on that simulator yet. Run Tools/run_sims.sh first." >&2; exit 1; }

printf "Paste your Meta Model API key (input is hidden): "
read -rs KEY
echo
[ -n "$KEY" ] || { echo "No key entered." >&2; exit 1; }

DIR="$CONTAINER/Library/Application Support/Echo"
mkdir -p "$DIR"
( umask 077; printf '%s' "$KEY" > "$DIR/meta_api_key" )
echo "Saved a ${#KEY}-character key for the simulator app. It is not stored in the repo."
