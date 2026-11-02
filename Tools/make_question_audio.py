#!/usr/bin/env python3
"""Generate the recorded questions that stand in for the microphone when you tap Ask by voice in a simulator.

Run:  python3 -I Tools/make_question_audio.py Shared/Questions

Writes q1.wav ... q5.wav (16 kHz mono 16-bit, spoken by the same voice as the demo day's wearer) and
questions.json (the text of each, and where the speech starts and ends inside the clip, so tests can check that the
recorder stops about a second after the speaker does). Each clip has a little room noise before and after the
speech, like a real recording.
"""
import array, json, os, random, subprocess, sys, tempfile, wave

RATE = 16000
VOICE = "Daniel"        # the voice for Levin in Tools/make_demo_audio.py (the best word error rate)
SAY_RATE = 165
LEAD_SECONDS = 0.5
TAIL_SECONDS = 2.0
random.seed(11)

QUESTIONS = [
    "When is the plumber coming?",
    "What did Mister Brennan say about the lease?",
    "Where is Priya going in March?",
    "What did I promise people today?",
    "Summarize my day",
]


def say_to_pcm(text, tmp):
    aiff, wav = os.path.join(tmp, "q.aiff"), os.path.join(tmp, "q.wav")
    subprocess.run(["say", "-v", VOICE, "-r", str(SAY_RATE), "-o", aiff, text], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}", "-c", "1", aiff, wav], check=True)
    with wave.open(wav, "rb") as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1 and w.getsampwidth() == 2
        pcm = array.array("h")
        pcm.frombytes(w.readframes(w.getnframes()))
    return pcm


def room(seconds):
    return array.array("h", (int(random.gauss(0, 25)) for _ in range(int(seconds * RATE))))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    manifest = []
    with tempfile.TemporaryDirectory() as tmp:
        for i, text in enumerate(QUESTIONS, start=1):
            speech = say_to_pcm(text, tmp)
            clip = array.array("h")
            clip.extend(room(LEAD_SECONDS))
            clip.extend(speech)
            clip.extend(room(TAIL_SECONDS))
            name = f"q{i}.wav"
            with wave.open(os.path.join(out, name), "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
                w.writeframes(clip.tobytes())
            manifest.append({"file": name, "text": text, "speechStart": LEAD_SECONDS,
                             "speechEnd": round(LEAD_SECONDS + len(speech) / RATE, 2),
                             "duration": round(len(clip) / RATE, 2)})
            print(f"{name}: {len(speech) / RATE:.1f} s of speech, {len(clip) / RATE:.1f} s in all  ({text})")
    with open(os.path.join(out, "questions.json"), "w") as f:
        json.dump({"voice": VOICE, "questions": manifest}, f, indent=2)


if __name__ == "__main__":
    main()
