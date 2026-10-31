#!/usr/bin/env python3
"""Compare the phone's pipeline output with the demo manifest's ground truth.

Run:  python3 -I Tools/calibrate.py <echo.sqlite> [demo_day.json]

Reports, per chunk, whether it truly overlaps scripted speech, what stage 2 decided, and how the
speech-confidence scores separate the two classes, so the threshold can be calibrated. Also checks
that key phrases from the script survive ASR.
"""
import json
import re
import sqlite3
import sys

db_path = sys.argv[1]
manifest_path = sys.argv[2] if len(sys.argv) > 2 else "Echo Watch App/Resources/demo_day.json"
manifest = json.load(open(manifest_path))
lines = [(l["start"], l["end"]) for s in manifest["scenes"] for l in s["lines"]]

SPEECH_MIN_OVERLAP = 0.5  # seconds of scripted speech for a chunk to count as speech


def speech_overlap(start, end):
    return sum(max(0.0, min(end, b) - max(start, a)) for a, b in lines)


con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
rows = con.execute(
    "select idx, file_offset, duration, status, speech_conf, confirmed_seconds, transcript from chunk order by idx"
).fetchall()

tp = fp = tn = fn = 0
speech_conf, noise_conf = [], []
mistakes = []
for idx, off, dur, status, conf, confirmed, text in rows:
    truth = speech_overlap(off, off + dur) >= SPEECH_MIN_OVERLAP
    kept = status not in ("dropped", "failed", "received")
    (speech_conf if truth else noise_conf).append(conf if conf is not None else 0.0)
    if truth and kept: tp += 1
    elif truth and not kept: fn += 1; mistakes.append(("MISSED SPEECH", idx, off, dur, conf, text))
    elif not truth and kept: fp += 1; mistakes.append(("KEPT NOISE", idx, off, dur, conf, text))
    else: tn += 1

total = len(rows)
speech_n, noise_n = tp + fn, tn + fp
print(f"chunks: {total}  (speech {speech_n}, noise-only {noise_n})")
print(f"speech accepted: {tp}/{speech_n} ({100 * tp / max(1, speech_n):.0f}%)   "
      f"noise rejected: {tn}/{noise_n} ({100 * tn / max(1, noise_n):.0f}%)")


def dist(xs):
    xs = sorted(xs)
    return "n/a" if not xs else f"min {xs[0]:.2f}  median {xs[len(xs) // 2]:.2f}  max {xs[-1]:.2f}"


print(f"speech-chunk confidence: {dist(speech_conf)}")
print(f"noise-chunk  confidence: {dist(noise_conf)}")
for kind, idx, off, dur, conf, text in mistakes:
    c = "none" if conf is None else f"{conf:.2f}"
    print(f"  {kind}: #{idx} @{off:.1f}s dur {dur:.1f}s conf {c}  {text or ''}")

recorded = manifest["duration"]
kept_watch = sum(r[2] for r in rows)
confirmed = sum(r[5] for r in rows)
print(f"funnel: recorded {recorded:.1f}s -> watch kept {kept_watch:.1f}s -> phone confirmed {confirmed:.1f}s "
      f"({100 * (1 - confirmed / recorded):.0f}% not kept)")

# Key phrases that matter for the demo questions.
blob = " ".join((r[6] or "") for r in rows).lower()
blob = re.sub(r"[^a-z0-9% ]", " ", blob)
checks = {
    "wednesday noon": r"wednesday\s+noon",
    "november twentieth": r"november\s+(20|20th|twentieth)",
    "friday at ten": r"friday\s+at\s+(10|ten)",
    "four percent": r"(4|four)\s*(percent|%)",
    "lentil soup": r"lentil\s+soup",
    "lisbon": r"lisbon",
    "thursday": r"thursday",
    "doctor okafor": r"(doctor|dr)\s+(okafor|o\s?kafor|oh\s?kafor)",
    "november fourteenth": r"november\s+(14|14th|fourteenth)",
    "grandma": r"grandma",
    "api spec": r"api\s+spec",
}
hit = 0
for name, pat in checks.items():
    ok = re.search(pat, blob) is not None
    hit += ok
    print(f"  phrase {'OK  ' if ok else 'MISS'} {name}")
print(f"phrases found: {hit}/{len(checks)}")
