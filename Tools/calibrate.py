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
    "doctor patel": r"(doctor|dr)\s+patel",
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


# --- Per-scene word error rate (informational) -------------------------------------------------
ONES = "zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen".split()
TENS = {20: "twenty", 30: "thirty"}


def num_to_words(n):
    if n < 20:
        return ONES[n]
    if n < 40:
        t = TENS[n // 10 * 10]
        return t if n % 10 == 0 else f"{t} {ONES[n % 10]}"
    return str(n)


def norm_words(text):
    text = text.lower().replace("%", " percent ")
    text = re.sub(r"(\d+)(st|nd|rd|th)", r"\1", text)
    text = re.sub(r"\d+", lambda m: " " + num_to_words(int(m.group())) + " ", text)
    text = text.replace("mr ", "mister ").replace("mr.", "mister")
    return re.sub(r"[^a-z ]", " ", text).split()


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


print("per-scene word error rate (digits and 'Mr.' normalized; lower is better):")
total_err = total_ref = 0
for scene in manifest["scenes"]:
    ref = norm_words(" ".join(l["text"] for l in scene["lines"]))
    hyp_parts = []
    for idx, off, dur, status, conf, confirmed, text in rows:
        if text and scene["fileStart"] - 3 <= off + dur / 2 <= scene["fileEnd"] + 3:
            hyp_parts.append(text)
    hyp = norm_words(" ".join(hyp_parts))
    err = edit_distance(ref, hyp)
    total_err += err
    total_ref += len(ref)
    print(f"  {scene['label']:<24} WER {100 * err / max(1, len(ref)):5.1f}%  ({err} edits / {len(ref)} words)")
print(f"  overall WER {100 * total_err / max(1, total_ref):.1f}%")


# --- Per-speaker word error rate (which voices does the recognizer struggle with?) ---------------
def align_errors(ref, hyp):
    """Levenshtein alignment; returns, per reference word index, whether it was matched correctly."""
    n, m = len(ref), len(hyp)
    d = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n + 1): d[i][0] = i
    for j in range(m + 1): d[0][j] = j
    for i in range(1, n + 1):
        for j in range(1, m + 1):
            d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (ref[i - 1] != hyp[j - 1]))
    ok = [False] * n
    i, j = n, m
    while i > 0 and j > 0:
        if ref[i - 1] == hyp[j - 1] and d[i][j] == d[i - 1][j - 1]:
            ok[i - 1] = True; i -= 1; j -= 1
        elif d[i][j] == d[i - 1][j - 1] + 1: i -= 1; j -= 1
        elif d[i][j] == d[i - 1][j] + 1: i -= 1
        else: j -= 1
    return ok


speaker_words = {}
speaker_wrong = {}
for scene in manifest["scenes"]:
    ref, owners = [], []
    for line in scene["lines"]:
        words = norm_words(line["text"])
        ref += words
        owners += [line["speaker"]] * len(words)
    hyp = norm_words(" ".join(
        text for idx, off, dur, status, conf, confirmed, text in rows
        if text and scene["fileStart"] - 3 <= off + dur / 2 <= scene["fileEnd"] + 3))
    ok = align_errors(ref, hyp)
    for owner, good in zip(owners, ok):
        speaker_words[owner] = speaker_words.get(owner, 0) + 1
        speaker_wrong[owner] = speaker_wrong.get(owner, 0) + (0 if good else 1)

print("per-speaker word error rate (reference words not recognized correctly):")
for who in sorted(speaker_words, key=lambda w: -speaker_wrong[w] / speaker_words[w]):
    print(f"  {who:<10} {100 * speaker_wrong[who] / speaker_words[who]:5.1f}%  ({speaker_wrong[who]}/{speaker_words[who]} words)")
