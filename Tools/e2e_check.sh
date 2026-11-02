#!/bin/bash
# End-to-end check of everything the demo shows, against the demo manifest. Run before recording
# and before submitting. Takes ~6 minutes. Exits non-zero if anything fails.
#
#   watch replay -> phone pipeline settles -> calibration vs ground truth -> 3 local + 2 cloud questions
#   -> day digest -> the privacy ledger tells the truth about each of them -> a question spoken on the phone and one
#   spoken on the watch (recorded questions through the real recorder and on-device understanding) -> the history
set -uo pipefail
cd "$(dirname "$0")/.."
PHONE=3BDBF6CE-2235-4CFE-9437-1EB803417569
WATCH=373A257B-EB2B-4A7B-8E94-CFF47E52792D
KEYFILE="$(xcrun simctl get_app_container "$PHONE" levtech.Echo data 2>/dev/null)/Library/Application Support/Echo/meta_api_key"

echo "1/8 preparing the simulators…"
Tools/demo_prep.sh >/tmp/e2e_prep.log 2>&1 || { cat /tmp/e2e_prep.log; echo "FAIL: demo_prep"; exit 1; }
LIVE=0; [ -f "$(xcrun simctl get_app_container "$PHONE" levtech.Echo data)/Library/Application Support/Echo/meta_api_key" ] && LIVE=1

echo "2/8 replaying last week, then today, from the watch…"
DB=""
for _ in $(seq 1 30); do
  DB=$(find ~/Library/Developer/CoreSimulator/Devices/$PHONE/data/Containers/Data/Application -name echo.sqlite 2>/dev/null | head -1); [ -n "$DB" ] && break; sleep 2
done
[ -n "$DB" ] || { echo "FAIL: the phone database never appeared"; exit 1; }
echo "$DB" > /tmp/echo_db_path
wait_settled() {   # wait until the phone has stopped receiving and processing chunks (and has at least $1 of them)
  local min=$1 prev=-1 stable=0 out
  for _ in $(seq 1 90); do
    out=$(python3 -I -c "
import sqlite3
c=sqlite3.connect('file:$DB?mode=ro',uri=True)
print(c.execute('select count(*) from chunk').fetchone()[0], c.execute(\"select count(*) from chunk where status in ('received','vad','asr')\").fetchone()[0])" 2>/dev/null)
    set -- $out
    if [ "${2:-x}" = "0" ] && [ "${1:-0}" = "$prev" ] && [ "${1:-0}" -gt "$min" ]; then stable=$((stable+1)); else stable=0; fi
    prev=${1:-0}; [ "$stable" -ge 3 ] && break; sleep 10
  done
  sleep 3
}
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp >/dev/null 2>&1
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -autostart "prev$(date +%s)" -day-offset -7 >/dev/null
sleep 20; wait_settled 20
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp >/dev/null 2>&1
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -autostart "today$(date +%s)" >/dev/null
sleep 20; wait_settled 60

echo "3/8 asking the demo questions…"
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

echo "3b/8 asking across days…"
for Q in "How much was the rent increase last week?" "What did Mister Brennan say about the lease?"; do
  xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1
  xcrun simctl launch "$PHONE" levtech.Echo -tab ask -ask "$Q" >/dev/null
  sleep 8
done

echo "4/8 asking Muse to summarize the day…"
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

echo "5/8 asking the broad question again with names masked…"
xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1
xcrun simctl launch "$PHONE" levtech.Echo -tab ask -mask on -review off -ask "$Q4" >/dev/null
for _ in $(seq 1 40); do
  sleep 3
  n=$(python3 -I -c "
import sqlite3
c=sqlite3.connect('file:$DB?mode=ro',uri=True)
print(c.execute(\"select count(*) from ledger where masked_names>0 and status in ('ok','error')\").fetchone()[0])" 2>/dev/null)
  [ "${n:-0}" -ge 1 ] && break
done
xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1
xcrun simctl launch "$PHONE" levtech.Echo -mask off -review off >/dev/null   # leave the preference off

echo "6/8 asking from the watch (quick-ask)…"
sleep 5
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp >/dev/null 2>&1
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -page ask -quick 0 "e2e$(date +%s)" >/dev/null
for _ in $(seq 1 40); do
  sleep 3
  xcrun simctl spawn "$PHONE" log show --info --last 90s --predicate 'subsystem == "echo" AND eventMessage CONTAINS "watch ask"' --style compact 2>/dev/null | grep -q "watch ask" && break
done

echo "7/8 asking by voice: on the phone, then on the watch…"
history_rows() {   # how many history rows were asked this way?
  python3 -I -c "
import sqlite3
c=sqlite3.connect('file:$DB?mode=ro',uri=True)
print(c.execute(\"select count(*) from ask_history where via='$1'\").fetchone()[0])" 2>/dev/null
}
xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1
xcrun simctl launch "$PHONE" levtech.Echo -tab ask -voice-ask 1 >/dev/null
for _ in $(seq 1 30); do sleep 2; [ "$(history_rows voice)" -ge 1 ] && break; done
xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1
xcrun simctl launch "$PHONE" levtech.Echo -tab ask >/dev/null
sleep 12   # the phone and the watch need a while to see each other after a relaunch
xcrun simctl terminate "$WATCH" levtech.Echo.watchkitapp >/dev/null 2>&1
xcrun simctl launch "$WATCH" levtech.Echo.watchkitapp -page ask -voice 3 "e2evoice$(date +%s)" >/dev/null
for _ in $(seq 1 45); do sleep 2; [ "$(history_rows watchVoice)" -ge 1 ] && break; done
xcrun simctl spawn "$PHONE" log show --info --last 20m --predicate 'subsystem == "echo" AND eventMessage CONTAINS "ask "' --style compact > /tmp/e2e_asklog.txt 2>/dev/null
xcrun simctl spawn "$PHONE" log show --info --last 20m --predicate 'subsystem == "echo" AND eventMessage CONTAINS "watch ask"' --style compact > /tmp/e2e_watchlog.txt 2>/dev/null

echo "7b/8 drafting a message and writing the evening's journal entry…"
ledger_rows() { python3 -I -c "
import sqlite3
c=sqlite3.connect('file:$DB?mode=ro',uri=True)
print(c.execute(\"select count(*) from ledger where kind='$1' and status in ('ok','error')\").fetchone()[0])" 2>/dev/null; }
xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1
xcrun simctl launch "$PHONE" levtech.Echo -tab today -today-section commitments -review off -draft-first -draft-run >/dev/null
for _ in $(seq 1 30); do sleep 3; [ "$(ledger_rows draft)" -ge 1 ] && break; done
xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1
xcrun simctl launch "$PHONE" levtech.Echo -tab today -review off -journal-run >/dev/null
for _ in $(seq 1 30); do sleep 3; [ "$(ledger_rows journal)" -ge 1 ] && break; done
xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1

echo "7c/8 forgetting the last ten minutes…"
BEFORE=/tmp/e2e_before.sqlite
cp "$DB" "$BEFORE"
xcrun simctl launch "$PHONE" levtech.Echo -forget-recent 10 >/dev/null
for _ in $(seq 1 20); do
  sleep 3
  xcrun simctl spawn "$PHONE" log show --info --last 60s --predicate 'subsystem == "echo" AND eventMessage CONTAINS "forget-recent"' --style compact 2>/dev/null | grep -q "forget-recent:" && break
done
sleep 2
xcrun simctl terminate "$PHONE" levtech.Echo >/dev/null 2>&1

echo "8/8 checking results…"
python3 -I - "$BEFORE" "$LIVE" "$DB" "$Q1" "$Q2" "$Q3" "$Q4" "$Q5" <<'PY'
import json, re, sqlite3, subprocess, sys
db, live, after_db = sys.argv[1], sys.argv[2] == "1", sys.argv[3]
questions = sys.argv[4:9]
manifest = json.load(open("Echo Watch App/Resources/demo_day.json"))
lines = sum(len(s["lines"]) for s in manifest["scenes"])
con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
import datetime, shutil, tempfile
today = datetime.date.today().isoformat()
lastweek = (datetime.date.today() - datetime.timedelta(days=7)).isoformat()
# the calibration checks are about today's recording only
copy = tempfile.mktemp(suffix=".sqlite"); shutil.copy(db, copy)
tc = sqlite3.connect(copy); tc.execute("delete from chunk where day_id != ?", (today,)); tc.commit(); tc.close()
results = []
def check(name, ok, detail=""): results.append((ok, name, detail))

# pipeline vs the manifest
stored = con.execute("select count(*) from chunk where status='stored' and day_id=?", (today,)).fetchone()[0]
dropped = con.execute("select count(*) from chunk where status='dropped' and day_id=?", (today,)).fetchone()[0]
failed = con.execute("select count(*) from chunk where status in ('failed','received','vad','asr')").fetchone()[0]
check("every spoken line became one stored moment", stored == lines, f"{stored} stored vs {lines} lines")
check("noise chunks were dropped", dropped >= 5, f"{dropped} dropped")
check("nothing stuck or failed in the pipeline", failed == 0, f"{failed} stuck/failed")
emb = con.execute("select count(*) from chunk where status='stored' and day_id=? and embedding is not null", (today,)).fetchone()[0]
check("every stored moment is indexed", emb == stored, f"{emb}/{stored} with embeddings")
prev_manifest = json.load(open("Echo Watch App/Resources/demo_day_prev.json"))
prev_lines = sum(len(sc["lines"]) for sc in prev_manifest["scenes"])
prev_stored = con.execute("select count(*) from chunk where status='stored' and day_id=?", (lastweek,)).fetchone()[0]
# in last week's late evening a "Hey Echo" command, an "off the record" stretch and its private talk are, by design, never kept
def kept_in_memory(l):
    t = l["text"].lower()
    return not ("hey echo" in t or "off the record" in t or "back on the record" in t or "surprise party" in t)
prev_kept = sum(1 for sc in prev_manifest["scenes"] for l in sc["lines"] if kept_in_memory(l))
check("memory: last week's day was kept alongside today's", prev_stored == prev_kept and stored == lines, f"{prev_stored}/{prev_kept} last week, {stored}/{lines} today")
days = [r[0] for r in con.execute("select distinct day_id from chunk order by 1")]
check("memory: the two days are different days", days == [lastweek, today], str(days))

cal = subprocess.run(["python3", "-I", "Tools/calibrate.py", copy], capture_output=True, text=True).stdout
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

# commitments: found on the phone with rules, so the day must contain first-person promises
promise = re.compile(r"\bI will\b|\bI'll\b|\bI promise\b|\bI am going to\b", re.I)
transcripts = [r[0] or "" for r in con.execute("select transcript from chunk where status='stored'")]
n_promises = sum(1 for t in transcripts if promise.search(t))
check("commitments: the day contains first-person promises to list", n_promises >= 10, f"{n_promises} moments")

# citations: every cited label points inside the request that was sent
asks = [r for r in con.execute("select kind, snippets_json, response, masked_names from ledger where tier='cloud' and left_device=1 and status='ok'")]
bad = 0; cited = 0
for kind, snips, resp, masked in asks:
    n = len(json.loads(snips))
    try: d = json.loads(resp)
    except Exception: continue
    items = d.get("items", []) if kind == "ask" else d.get("action_items", [])
    for it in items:
        label = it.get("source", "")
        m = re.fullmatch(r"[Ss](\d+)", label.strip()) if label else None
        if m:
            cited += 1
            if not (1 <= int(m.group(1)) <= n): bad += 1
if live:
    check("citations: Muse cites snippets that exist in the request", cited >= 5 and bad == 0, f"{cited} cited, {bad} out of range")

# masking: the masked request carried placeholders and none of the people's names
masked_rows = [r for r in asks if r[3] and r[3] > 0]
if live:
    names = ["Levin", "Priya", "Brennan", "Patel"]
    leaked = [n for r in masked_rows for n in names if n in r[1]]
    check("masking: a masked request was sent, with placeholders and no names", len(masked_rows) >= 1 and not leaked and any("[PERSON_" in r[1] for r in masked_rows),
          f"{len(masked_rows)} masked request(s), leaked {sorted(set(leaked))}")

# the watch: a question asked on the watch was answered by the phone
try: wlog = open("/tmp/e2e_watchlog.txt").read()
except OSError: wlog = ""
check("watch: a quick-ask from the watch was answered by the phone", "watch ask:" in wlog, "answered" if "watch ask:" in wlog else "no reply logged")

# voice: recorded questions were understood on the phone, answered, and kept in the history
def words(t): return re.findall(r"[a-z']+", t.lower().replace("mister", "mr"))
def similar(heard, expected):
    a, b = set(words(heard)), set(words(expected))
    return bool(b) and len(a & b) / len(b) >= 0.8
hist = con.execute("select question, via, source, short_answer from ask_history").fetchall()
for via, expected in (("voice", "When is the plumber coming?"), ("watchVoice", "Where is Priya going in March?")):
    rows = [r for r in hist if r[1] == via]
    ok = any(similar(r[0], expected) and r[3].strip() for r in rows)
    shown = f'heard "{rows[-1][0]}", {rows[-1][2]}' if rows else "no row"
    check(f"voice: {'phone' if via == 'voice' else 'watch'} question understood and answered", ok, shown)
check("voice: the watch's spoken question was answered by the phone", "(watchVoice)" in wlog, "logged" if "(watchVoice)" in wlog else "no reply logged")
kept = {r[0].lower() for r in hist}
missing = [q for q in questions if q.lower() not in kept]
check("history: every typed question is kept, with how it was answered", not missing and all(r[2] in ("local", "muse", "stub", "none") for r in hist), f"{len(hist)} rows" + (f", missing {missing}" if missing else ""))
has_detail = con.execute("select count(*) from ask_history where detail_json is not null and detail_json != ''").fetchone()[0]
check("history: each entry keeps its full answer for reopening", has_detail == len(hist) and hist, f"{has_detail}/{len(hist)}")

# memory across days: a day can be named, and with none named the newest fact wins
def short_answer(q):
    r = con.execute("select short_answer from ask_history where question=? order by ts desc limit 1", (q,)).fetchone()
    return r[0] if r else ""
named = short_answer("How much was the rent increase last week?")
check("memory: a question can name last week", "3%" in named or "three percent" in named.lower() or "increase" in named.lower(), named[:70] or "no answer")
latest = short_answer("What did Mister Brennan say about the lease?")
check("memory: with no day named, the newest fact wins", "December 31" in latest, latest[:70] or "no answer")

# wake word: "Hey Echo, ..." is a command, answered and then forgotten
heard = [r[0] or "" for r in con.execute("select transcript from chunk where status='stored'")]
check("wake word: the command itself is not in memory", not any(re.search(r"hey,? echo", t, re.I) for t in heard), "kept" if any(re.search(r"hey,? echo", t, re.I) for t in heard) else "not stored")
wake = con.execute("select question, source, short_answer from ask_history where via='wakeWord'").fetchall()
check("wake word: its question was answered like any other", any(similar(w[0], "what did Mister Brennan say about the rent?") and w[2].strip() for w in wake),
      f'heard "{wake[-1][0]}", {wake[-1][1]}' if wake else "no wake-word question in the history")

# off the record: what was said in between was understood only to hear the way back, and never kept
private = [t for t in heard if re.search(r"surprise|rooftop|chocolate", t, re.I)]
fts_private = con.execute("select count(*) from chunk_fts where chunk_fts match 'rooftop OR surprise OR chocolate'").fetchone()[0]
check("off the record: what was said while it was off is nowhere in memory", not private and fts_private == 0, f"{len(private)} moments, {fts_private} search entries")
check("off the record: speech after 'back on the record' is kept again", any("lock the back door" in t.lower() for t in heard), "")

# speakers: voices told apart on the phone
voiced = con.execute("select count(*) from chunk where status='stored' and speaker_id is not null and speaker_id != ''").fetchone()[0]
voices = con.execute("select count(distinct speaker_id) from chunk where status='stored' and speaker_id != ''").fetchone()[0]
allstored = con.execute("select count(*) from chunk where status='stored'").fetchone()[0]
check("voices: every moment has a voice, and about as many voices as people", voiced == allstored and 7 <= voices <= 12, f"{voiced}/{allstored} moments, {voices} voices")

# places: each moment says roughly where it happened
placed = con.execute("select count(*) from chunk where status='stored' and lat is not null").fetchone()[0]
check("places: every moment is stamped with where it happened", placed == allstored, f"{placed}/{allstored}")

# the proactive writing: a drafted message and the journal entry, each logged as its own kind
kinds = {k: (n, ok) for k, n, ok in con.execute("select kind, count(*), sum(status='ok') from ledger group by kind")}
for kind in ("draft", "journal"):
    n, ok = kinds.get(kind, (0, 0))
    check(f"proactive: a {kind} went through the ledger", n >= 1 and (not live or ok >= 1), f"{n} rows, {ok} ok")

# forgetting the last ten minutes removed moments, their search entries and the history that cited them
after = sqlite3.connect(f"file:{after_db}?mode=ro", uri=True)
a_chunks = after.execute("select count(*) from chunk").fetchone()[0]
b_chunks = con.execute("select count(*) from chunk").fetchone()[0]
a_fts = after.execute("select count(*) from chunk_fts").fetchone()[0]
a_stored = after.execute("select count(*) from chunk where status='stored'").fetchone()[0]
check("forget: the last ten minutes were removed", 0 < b_chunks - a_chunks < b_chunks, f"{b_chunks} -> {a_chunks} moments")
check("forget: search entries went with them", a_fts == a_stored, f"{a_fts} entries for {a_stored} stored moments")

width = max(len(n) for _, n, _ in results)
print()
for ok, name, detail in results:
    print(f"  {'PASS' if ok else 'FAIL'}  {name.ljust(width)}  {detail}")
bad = sum(1 for ok, _, _ in results if not ok)
print(f"\n{len(results) - bad}/{len(results)} checks passed  ({'LIVE Muse' if live else 'STUB, no API key'})")
sys.exit(1 if bad else 0)
PY
