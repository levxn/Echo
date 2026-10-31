#!/usr/bin/env python3
"""Generate the Echo demo "day" of audio: 16 kHz mono 16-bit WAV plus a JSON manifest.

Run:  python3 -I Tools/make_demo_audio.py <output_dir>

Scenes are multi-voice conversations (macOS `say`) separated by ambient "dead air" that
includes noise bursts, so the stage-1 energy VAD has something to over-accept and the
phone's stage-2 classifier has something to reject.
"""
import array
import json
import math
import os
import random
import subprocess
import sys
import tempfile
import wave

RATE = 16000
random.seed(7)

# Chosen from per-speaker word error rates (Tools/calibrate.py). The first set scored: Ralph 22.7%, Kathy 19.6%,
# Fred 13.3%, Rishi 10%, Karen 6.2%, Samantha 4.1%, Daniel 2.8%. Jordan speaks ~58% of all words, so he gets
# a proven voice. People who share a scene must not share a voice.
VOICES = {
    "Jordan": "Daniel",
    "Maya": "Samantha",
    "Ravi": "Moira",
    "Priya": "Karen",
    "Brennan": "Reed (English (US))",
    "Mom": "Flo (English (US))",
    "Dad": "Eddy (English (US))",
}
SAY_RATE = 165   # words per minute for `say`; a little slower than the default helps the recognizer

# (label, wall-clock "HH:MM", [(speaker, line), ...])
SCENES = [
    ("Morning standup", "09:05", [
        ("Maya", "Okay, let's start. Jordan, where are we on the billing service?"),
        ("Jordan", "The migration is done in staging. I think we can deploy to production on Thursday morning."),
        ("Ravi", "Thursday works for me, but I still need the API specification for the invoices endpoint."),
        ("Jordan", "Right. I will send you the API specification by Wednesday noon, that's a promise."),
        ("Maya", "Great. I will review the design document on Tuesday and leave comments before the end of the day."),
        ("Ravi", "One risk. The payment provider changes their webhook format on November eighth."),
        ("Jordan", "Good catch. I will add a compatibility layer so both formats work during the switch."),
        ("Maya", "Perfect. Budget is tight, so let's not add new features before the launch."),
        ("Ravi", "Agreed. I will also ask finance about the extra cloud credits we discussed."),
        ("Maya", "Thanks everyone. Same time tomorrow."),
    ]),
    ("Lunch with Priya", "12:30", [
        ("Priya", "I finally booked the trip. Lisbon, the second week of March."),
        ("Jordan", "That sounds amazing, Priya. Which hotel did you pick?"),
        ("Priya", "A small place near the Alfama district. I will text you the link if you want to join."),
        ("Jordan", "Yes, please send it. I will think about taking leave from the fifteenth to the twentieth."),
        ("Priya", "By the way, you mentioned your tooth was bothering you. See Doctor Patel, she is excellent."),
        ("Jordan", "Thanks. I will call her office tomorrow morning and book an appointment."),
        ("Priya", "Also, what are you getting your mom for her birthday?"),
        ("Jordan", "I was thinking of a book about pottery, she has been wanting to take a class."),
        ("Priya", "Lovely idea. Pair it with a voucher for a beginner workshop."),
        ("Jordan", "Oh, that's good. I will order the book tonight and look up workshops this weekend."),
        ("Priya", "And tonight, don't forget to send me that recipe for the lentil soup."),
        ("Jordan", "I will send the lentil soup recipe this evening, I promise."),
    ]),
    ("Call with the landlord", "15:10", [
        ("Brennan", "Hello Jordan, this is Mister Brennan, calling about the apartment."),
        ("Jordan", "Hi Mister Brennan. Thanks for calling back. The bathroom ceiling is still leaking."),
        ("Brennan", "Yes, I received your photos. I have booked a plumber to come on Friday at ten in the morning."),
        ("Jordan", "Friday at ten works. I will make sure I am home to let them in."),
        ("Brennan", "Wonderful. Now, about your lease. It ends on December thirty first."),
        ("Jordan", "Right, I wanted to ask about renewing."),
        ("Brennan", "I can offer a twelve month renewal, with a four percent rent increase."),
        ("Jordan", "Four percent is a bit more than I expected. Can I think about it and let you know?"),
        ("Brennan", "Of course. I need your decision by November twentieth."),
        ("Jordan", "Understood. I will give you a final answer before November twentieth."),
        ("Brennan", "Excellent. Also, rent for this month is still outstanding."),
        ("Jordan", "Sorry about that. I will transfer it tomorrow, first thing."),
    ]),
    ("Family dinner", "18:40", [
        ("Mom", "Dinner is ready everyone. Jordan, can you bring the salad?"),
        ("Jordan", "Sure, Mom. Smells fantastic."),
        ("Dad", "Your mother's birthday is on November fourteenth, and I want to take her to the lake cabin for the weekend."),
        ("Jordan", "That's a great idea, Dad. I can drive you both on Saturday morning."),
        ("Mom", "You don't need to fuss. But I would love to see the lake in autumn."),
        ("Dad", "Jordan, remember to call Grandma on Sunday. She has been asking about you."),
        ("Jordan", "I will call Grandma this Sunday afternoon, I promise."),
        ("Mom", "We also need groceries. Eggs, olive oil, and oranges for the juice."),
        ("Jordan", "I will pick those up on my way home from work tomorrow."),
        ("Dad", "And bring an umbrella. They say it will rain all week."),
        ("Mom", "Alright, let's eat before it gets cold."),
    ]),
]


def say_to_pcm(voice: str, text: str, tmp: str) -> array.array:
    aiff = os.path.join(tmp, "line.aiff")
    wav = os.path.join(tmp, "line.wav")
    subprocess.run(["say", "-v", voice, "-r", str(SAY_RATE), "-o", aiff, text], check=True)
    subprocess.run(
        ["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}", "-c", "1", aiff, wav], check=True
    )
    with wave.open(wav, "rb") as w:
        assert w.getframerate() == RATE and w.getnchannels() == 1 and w.getsampwidth() == 2
        pcm = array.array("h")
        pcm.frombytes(w.readframes(w.getnframes()))
    return pcm


def ambient(seconds: float, level: int = 40, bursts: int = 0) -> array.array:
    """Low-level room noise with optional loud, non-speech bursts (clatter / door / wrist rustle)."""
    n = int(seconds * RATE)
    out = array.array("h", (int(random.gauss(0, level)) for _ in range(n)))
    for _ in range(bursts):
        start = random.randint(0, max(0, n - RATE))
        length = int(random.uniform(0.25, 0.7) * RATE)
        amp = random.uniform(2500, 6000)
        for i in range(length):
            if start + i >= n:
                break
            env = math.sin(math.pi * i / length)
            out[start + i] = int(max(-32000, min(32000, random.gauss(0, amp) * env)))
    return out


def pause(seconds: float) -> array.array:
    return ambient(seconds, level=25)


def main() -> None:
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    timeline = array.array("h")
    scenes_meta = []

    with tempfile.TemporaryDirectory() as tmp:
        timeline.extend(ambient(8, bursts=1))  # short lead-in dead air
        for scene_index, (label, wall, lines) in enumerate(SCENES):
            scene_start = len(timeline) / RATE
            lines_meta = []
            for speaker, text in lines:
                pcm = say_to_pcm(VOICES[speaker], text, tmp)
                start = len(timeline) / RATE
                timeline.extend(pcm)
                lines_meta.append(
                    {"speaker": speaker, "text": text, "start": round(start, 2),
                     "end": round(len(timeline) / RATE, 2)}
                )
                timeline.extend(pause(random.uniform(0.7, 1.6)))
            scene_end = len(timeline) / RATE
            scenes_meta.append(
                {"label": label, "wallClock": wall, "fileStart": round(scene_start, 2),
                 "fileEnd": round(scene_end, 2), "lines": lines_meta}
            )
            if scene_index < len(SCENES) - 1:   # dead air between scenes, none after the last
                timeline.extend(ambient(random.uniform(30, 45), bursts=4))

    wav_path = os.path.join(out_dir, "demo_day.wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(timeline.tobytes())

    manifest = {"sampleRate": RATE, "duration": round(len(timeline) / RATE, 2), "scenes": scenes_meta}
    with open(os.path.join(out_dir, "demo_day.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    speech = sum(l["end"] - l["start"] for s in scenes_meta for l in s["lines"])
    print(f"wrote {wav_path}: {manifest['duration']:.1f}s total, {speech:.1f}s speech "
          f"({100 * speech / manifest['duration']:.0f}%)")


if __name__ == "__main__":
    main()
