#!/bin/bash
# End-to-end check of everything the demo shows, against the demo manifest. Run before recording
# and before submitting. Takes ~6 minutes. Exits non-zero if anything fails.
#
#   watch replay -> phone pipeline settles -> calibration vs ground truth -> 3 local + 2 cloud questions
#   -> day digest -> the privacy ledger tells the truth about each of them
set -uo pipefail
cd "$(dirname "$0")/.."
PHONE=3BDBF6CE-2235-4CFE-9437-1EB803417569
WATCH=373A257B-EB2B-4A7B-8E94-CFF47E52792D
KEYFILE="$(xcrun simctl get_app_container "$PHONE" levtech.Echo data 2>/dev/null)/Library/Application Support/Echo/meta_api_key"

echo "1/5 preparing the simulators…"
Tools/demo_prep.sh >/tmp/e2e_prep.log 2>&1 || { cat /tmp/e2e_prep.log; echo "FAIL: demo_prep"; exit 1; }
LIVE=0; [ -f "$(xcrun simctl get_app_container "$PHONE" levtech.Echo data)/Library/Application Support/Echo/meta_api_key" ] && LIVE=1

echo "2/5 replaying the day from the watch…"
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp >/dev/null 2>&1
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -autostart "$(date +%s)" >/dev/null
DB=""
for _ in $(seq 1 30); do
  DB=$(find ~/Library/Developer/CoreSimulator/Devices/$PHONE/data/Containers/Data/Application -name echo.sqlite 2>/dev/null | head -1); [ -n "$DB" ] && break; sleep 2
done
[ -n "$DB" ] || { echo "FAIL: the phone database never appeared"; exit 1; }
echo "$DB" > /tmp/echo_db_path
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
sleep 3

echo "3/5 asking the demo questions…"
Q1="When is the plumber coming?"; Q2="What did Mister Brennan say about the lease?"; Q3="Where is Priya going in March?"
Q4="What did I promise people today?"; Q5="Summarize my day"
for Q in "$Q1" "$Q2" "$Q3" "$Q4" "$Q5"; do
  xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1
  xcrun simctl launch "$PHONE" levtech.Echo -tab ask -ask "$Q" >/dev/null
  # local answers take ~1 s; a live cloud call can take a while, so wait for its completion line
  for _ in $(seq 1 40); do
    sleep 3
    xcrun simctl spawn "$PHONE" log show --info --last 60s --predicate 'subsystem == "echo" AND eventMessage CONTAINS "ask "' --style compact 2>/dev/null \
      | grep -F "ask \"$Q\"" | grep -qE -- "-> local| <- |failed|switched off|nothing to send" && break
  done
done

echo "4/5 asking Muse to summarize the day…"
xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1
xcrun simctl launch "$PHONE" levtech.Echo -digest >/dev/null
for _ in $(seq 1 40); do
  sleep 3
  n=$(python3 -I -c "
import sqlite3
c=sqlite3.connect('file:$DB?mode=ro',uri=True)
print(c.execute(\"select count(*) from ledger where kind='digest' and status in ('ok','error')\").fetchone()[0])" 2>/dev/null)
  [ "${n:-0}" -ge 1 ] && break
done
xcrun simctl spawn "$PHONE" log show --info --last 12m --predicate 'subsystem == "echo" AND eventMessage CONTAINS "ask "' --style compact > /tmp/e2e_asklog.txt 2>/dev/null

echo "5/5 checking results…"
python3 -I - "$DB" "$LIVE" "$Q1" "$Q2" "$Q3" "$Q4" "$Q5" <<'PY'
import json, re, sqlite3, subprocess, sys
db, live = sys.argv[1], sys.argv[2] == "1"
questions = sys.argv[3:8]
manifest = json.load(open("Echo Watch App/Resources/demo_day.json"))
lines = sum(len(s["lines"]) for s in manifest["scenes"])
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
results = []
def check(name, ok, detail=""): results.append((ok, name, detail))

# pipeline vs the manifest
stored = con.execute("select count(*) from chunk where status='stored'").fetchone()[0]
dropped = con.execute("select count(*) from chunk where status='dropped'").fetchone()[0]
failed = con.execute("select count(*) from chunk where status in ('failed','received','vad','asr')").fetchone()[0]
check("every spoken line became one stored moment", stored == lines, f"{stored} stored vs {lines} lines")
check("noise chunks were dropped", dropped >= 5, f"{dropped} dropped")
check("nothing stuck or failed in the pipeline", failed == 0, f"{failed} stuck/failed")
emb = con.execute("select count(*) from chunk where status='stored' and embedding is not null").fetchone()[0]
check("every stored moment is indexed", emb == stored, f"{emb}/{stored} with embeddings")

cal = subprocess.run(["python3", "-I", "Tools/calibrate.py", db], capture_output=True, text=True).stdout
m = re.search(r"speech accepted: (\d+)/(\d+).*noise rejected: (\d+)/(\d+)", cal)
if m:
    a, b, c, d = map(int, m.groups())
    check("stage 2 kept all speech", a == b, f"{a}/{b}")
    check("stage 2 rejected all noise", c == d, f"{c}/{d}")
w = re.search(r"overall WER ([\d.]+)%", cal)
check("transcription word error rate under 12%", bool(w) and float(w.group(1)) < 12, f"{w.group(1)}%" if w else "n/a")
p = re.search(r"phrases found: (\d+)/(\d+)", cal)
check("key phrases transcribed", bool(p) and int(p.group(1)) >= int(p.group(2)) - 1, f"{p.group(1)}/{p.group(2)}" if p else "n/a")

# the questions and what the ledger says about them
log = open("/tmp/e2e_asklog.txt").read()
def route(q):
    mm = re.findall(r'ask "' + re.escape(q) + r'" -> (local|cloud)', log)
    return mm[-1] if mm else None
for q in questions[:3]:
    check(f"local: {q}", route(q) == "local", str(route(q)))
for q in questions[3:]:
    check(f"cloud: {q}", route(q) == "cloud", str(route(q)))

rows = con.execute("select kind, tier, left_device, is_stub, body_bytes, snippets_json, status, model from ledger").fetchall()
local = [r for r in rows if r[0] == "ask" and r[1] == "local"]
cloud = [r for r in rows if r[1] == "cloud"]
check("local questions are logged as staying on the phone", len(local) >= 3 and all(r[2] == 0 and r[4] == 0 for r in local), f"{len(local)} rows")
check("cloud questions and the digest are logged", len(cloud) >= 3, f"{len(cloud)} rows")
if live:
    ok = [r for r in cloud if r[2] == 1 and r[3] == 0 and r[6] == "ok" and r[4] > 0 and len(json.loads(r[5])) > 0]
    check("LIVE: cloud calls reached Muse and recorded bytes and snippets", len(ok) == len(cloud) and len(cloud) >= 3, f"{len(ok)}/{len(cloud)} ok, models {sorted({r[7] for r in cloud})}")
else:
    check("STUB: cloud calls are labeled stubs and sent nothing", len(cloud) >= 3 and all(r[3] == 1 and r[2] == 0 and r[4] == 0 for r in cloud), f"{len(cloud)} rows")
digest = con.execute("select count(*) from day_digest").fetchone()[0]
check("the day digest was produced and saved", digest == 1, f"{digest} saved")

width = max(len(n) for _, n, _ in results)
print()
for ok, name, detail in results:
    print(f"  {'PASS' if ok else 'FAIL'}  {name.ljust(width)}  {detail}")
bad = sum(1 for ok, _, _ in results if not ok)
print(f"\n{len(results) - bad}/{len(results)} checks passed  ({'LIVE Muse' if live else 'STUB, no API key'})")
sys.exit(1 if bad else 0)
PY
