#!/bin/bash
# Fails if your API key (from Config/meta_api_key.txt or $MODEL_API_KEY) appears anywhere it could be
# published: tracked files, staged changes, untracked-but-not-ignored files, or git history.
# Also flags anything shaped like a bearer token. Run before every commit and push.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd); cd "$ROOT"
CONFIG="Config/meta_api_key.txt"

KEY="${MODEL_API_KEY:-}"
if [ -z "$KEY" ] && [ -f "$CONFIG" ]; then
  C=$(tr -d '[:space:]' < "$CONFIG"); case "$C" in ""|PASTE_*) ;; *) KEY="$C" ;; esac
fi

fail=0
if [ -n "$KEY" ]; then
  PATTERNS=$(mktemp); trap 'rm -f "$PATTERNS"' EXIT
  ( umask 077; printf '%s\n' "$KEY" > "$PATTERNS" )   # patterns come from a file, so the key never appears in argv
  if git grep -qF -f "$PATTERNS" -- . 2>/dev/null;                      then echo "FAIL: key found in tracked files:"; git grep -lF -f "$PATTERNS" -- .; fail=1; fi
  if git diff --cached | grep -qF -f "$PATTERNS";                       then echo "FAIL: key found in staged changes"; fail=1; fi
  if git ls-files --others --exclude-standard -z | xargs -0 grep -lF -f "$PATTERNS" 2>/dev/null | grep -q .; then
    echo "FAIL: key found in untracked files that are not ignored:"; git ls-files --others --exclude-standard -z | xargs -0 grep -lF -f "$PATTERNS"; fail=1; fi
  if [ -n "$(git rev-list --all 2>/dev/null)" ] && git grep -qF -f "$PATTERNS" $(git rev-list --all) -- . 2>/dev/null; then
    echo "FAIL: key found in git history"; fail=1; fi
  echo "checked for your key (${#KEY} characters)"
else
  echo "No real key configured; only the generic scan runs."
fi

if git grep -nE 'Bearer [A-Za-z0-9._-]{24,}' -- . ':!Tools/*.sh' 2>/dev/null | grep -v '\\(' ; then echo "FAIL: something shaped like a bearer token is tracked"; fail=1; fi
[ "$fail" = 0 ] && echo "OK: no secrets found"
exit $fail
