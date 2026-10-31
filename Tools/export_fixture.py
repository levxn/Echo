#!/usr/bin/env python3
"""Snapshot the simulator's stored transcripts into a test fixture.

Run:  python3 -I Tools/export_fixture.py <echo.sqlite> [out.json]

Retrieval tests run against this fixture so they are deterministic and don't depend on the
simulator. Re-export after changing the demo audio, the VAD, or the clock mapping.
"""
import json
import sqlite3
import sys

db_path = sys.argv[1]
out_path = sys.argv[2] if len(sys.argv) > 2 else "EchoTests/Fixtures/demo_transcripts.json"
con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
rows = con.execute(
    "select id, idx, wall_start, file_offset, duration, peak_db, mean_db, audio_file, speech_conf, "
    "confirmed_seconds, transcript from chunk where status = 'stored' and transcript is not null order by idx"
).fetchall()
keys = ["id", "index", "wallStart", "fileOffset", "duration", "peakDb", "meanDb", "audioFile",
        "speechConfidence", "confirmedSeconds", "transcript"]
data = [dict(zip(keys, r)) for r in rows]
with open(out_path, "w") as f:
    json.dump(data, f, indent=1)
print(f"wrote {len(data)} chunks to {out_path}")
