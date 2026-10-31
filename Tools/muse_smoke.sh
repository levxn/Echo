#!/bin/bash
# One tiny call to the Meta Model API to confirm the key works, which model your account can use,
# and that your region is allowed. Prints only the HTTP status, model, token usage and latency.
# Reads the key saved by Tools/set_api_key.sh, or $MODEL_API_KEY if set. Never prints the key.
set -uo pipefail
PHONE=3BDBF6CE-2235-4CFE-9437-1EB803417569

KEY="${MODEL_API_KEY:-}"
if [ -z "$KEY" ]; then
  CONTAINER=$(xcrun simctl get_app_container "$PHONE" levtech.Echo data 2>/dev/null || true)
  FILE="$CONTAINER/Library/Application Support/Echo/meta_api_key"
  [ -f "$FILE" ] && KEY=$(cat "$FILE")
fi
[ -n "$KEY" ] || { echo "No key found. Run Tools/set_api_key.sh or export MODEL_API_KEY." >&2; exit 1; }

for MODEL in muse-spark-1.3 muse-spark-1.2 muse-spark-1.1; do
  BODY=$(printf '{"model":"%s","messages":[{"role":"user","content":"Reply with the single word OK."}],"max_completion_tokens":50,"reasoning_effort":"low"}' "$MODEL")
  OUT=$(mktemp)
  # The key goes to curl on stdin (-H @-) so it never appears in the process list.
  META=$(printf 'Authorization: Bearer %s\n' "$KEY" | curl -sS -o "$OUT" -w '%{http_code} %{time_total}' \
    -X POST "https://api.meta.ai/v1/chat/completions" -H @- -H "Content-Type: application/json" -d "$BODY" 2>&1) || true
  CODE=${META%% *}; TIME=${META##* }
  python3 -I - "$OUT" "$MODEL" "$CODE" "$TIME" <<'PY'
import json, sys
path, model, code, t = sys.argv[1:5]
raw = open(path).read()
try: d = json.loads(raw)
except Exception: d = {}
if code.startswith("2"):
    u = d.get("usage", {})
    text = (d.get("choices") or [{}])[0].get("message", {}).get("content", "")
    print(f"OK  {model}: HTTP {code} in {float(t):.2f}s, model={d.get('model')}, "
          f"tokens in/out={u.get('prompt_tokens')}/{u.get('completion_tokens')}, reply={text[:40]!r}")
else:
    err = d.get("error", {})
    msg = err.get("message") if isinstance(err, dict) else str(err)
    print(f"FAIL {model}: HTTP {code}: {msg or raw[:160]}")
PY
  rm -f "$OUT"
  case "$CODE" in 2*) exit 0 ;; 401) echo "The key was rejected. Check it and rerun Tools/set_api_key.sh."; exit 1 ;; esac
done
echo "No Muse Spark model worked for this key (see messages above)." >&2
exit 1
