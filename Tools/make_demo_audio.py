#!/usr/bin/env python3
"""Generate the Echo demo "day" of audio: 16 kHz mono 16-bit WAV plus a JSON manifest.

Run:  python3 -I Tools/make_demo_audio.py <output_dir> [--prev]

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
# Fred 13.3%, Rishi 10%, Karen 6.2%, Samantha 4.1%, Daniel 2.8%. The wearer speaks ~58% of all words, so he gets
# a proven voice. People who share a scene must not share a voice.
# Note: Apple's on-device recognizer writes the name "Levin" as "11", so nobody addresses the wearer by name here.
VOICES = {
    "Levin": "Daniel",
    "Maya": "Samantha",
    "Ravi": "Moira",
    "Priya": "Karen",
    "Brennan": "Reed (English (US))",
    "Mom": "Flo (English (US))",
    "Dad": "Eddy (English (US))",
    "Mehta": "Rishi",      # only in last week's recording
}
SAY_RATE = 165   # words per minute for `say`; a little slower than the default helps the recognizer

# (label, wall-clock "HH:MM", [(speaker, line), ...])
SCENES = [
    ("Morning standup", "09:05", [
        ("Maya", "Okay, let's start. Where are we on the billing service?"),
        ("Levin", "The migration is done in staging. I think we can deploy to production on Thursday morning."),
        ("Ravi", "Thursday works for me, but I still need the API specification for the invoices endpoint."),
        ("Levin", "Right. I will send you the API specification by Wednesday noon, that's a promise."),
        ("Maya", "Great. I will review the design document on Tuesday and leave comments before the end of the day."),
        ("Ravi", "One risk. The payment provider changes their webhook format on November eighth."),
        ("Levin", "Good catch. I will add a compatibility layer so both formats work during the switch."),
        ("Maya", "Perfect. Budget is tight, so let's not add new features before the launch."),
        ("Ravi", "Agreed. I will also ask finance about the extra cloud credits we discussed."),
        ("Maya", "Thanks everyone. Same time tomorrow."),
    ]),
    ("Lunch with Priya", "12:30", [
        ("Priya", "I finally booked the trip. Lisbon, the second week of March."),
        ("Levin", "That sounds amazing, Priya. Which hotel did you pick?"),
        ("Priya", "A small place near the Alfama district. I will text you the link if you want to join."),
        ("Levin", "Yes, please send it. I will think about taking leave from the fifteenth to the twentieth."),
        ("Priya", "By the way, you mentioned your tooth was bothering you. See Doctor Patel, she is excellent."),
        ("Levin", "Thanks. I will call her office tomorrow morning and book an appointment."),
        ("Priya", "Also, what are you getting your mom for her birthday?"),
        ("Levin", "I was thinking of a book about pottery, she has been wanting to take a class."),
        ("Priya", "Lovely idea. Pair it with a voucher for a beginner workshop."),
        ("Levin", "Oh, that's good. I will order the book tonight and look up workshops this weekend."),
        ("Priya", "And tonight, don't forget to send me that recipe for the lentil soup."),
        ("Levin", "I will send the lentil soup recipe this evening, I promise."),
    ]),
    ("Call with the landlord", "15:10", [
        ("Brennan", "Hello, this is Mister Brennan, calling about the apartment."),
        ("Levin", "Hi Mister Brennan. Thanks for calling back. The bathroom ceiling is still leaking."),
        ("Brennan", "Yes, I received your photos. I have booked a plumber to come on Friday at ten in the morning."),
        ("Levin", "Friday at ten works. I will make sure I am home to let them in."),
        ("Brennan", "Wonderful. Now, about your lease. It ends on December thirty first."),
        ("Levin", "Right, I wanted to ask about renewing."),
        ("Brennan", "I can offer a twelve month renewal, with a four percent rent increase."),
        ("Levin", "Four percent is a bit more than I expected. Can I think about it and let you know?"),
        ("Brennan", "Of course. I need your decision by November twentieth."),
        ("Levin", "Understood. I will give you a final answer before November twentieth."),
        ("Brennan", "Excellent. Also, rent for this month is still outstanding."),
        ("Levin", "Sorry about that. I will transfer it tomorrow, first thing."),
    ]),
    ("Family dinner", "18:40", [
        ("Mom", "Dinner is ready everyone. Can you bring the salad, sweetheart?"),
        ("Levin", "Sure, Mom. Smells fantastic."),
        ("Dad", "Your mother's birthday is on November fourteenth, and I want to take her to the lake cabin for the weekend."),
        ("Levin", "That's a great idea, Dad. I can drive you both on Saturday morning."),
        ("Mom", "You don't need to fuss. But I would love to see the lake in autumn."),
        ("Dad", "Remember to call Grandma on Sunday. She has been asking about you."),
        ("Levin", "I will call Grandma this Sunday afternoon, I promise."),
        ("Mom", "We also need groceries. Eggs, olive oil, and oranges for the juice."),
        ("Levin", "I will pick those up on my way home from work tomorrow."),
        ("Dad", "And bring an umbrella. They say it will rain all week."),
        ("Mom", "Alright, let's eat before it gets cold."),
    ]),
]


# Last week's recording (`--prev`): another day for the same life, so a question can reach back to it. Some facts
# are updated today (the rent rise is three percent here and four today), which is what "newest wins" is for.
SCENES_PREV = [
    ("Dentist", "08:40", [
        ("Mehta", "Good morning. Please sit down. What seems to be the problem?"),
        ("Levin", "Good morning. My back tooth has been hurting for a week, especially with cold water."),
        ("Mehta", "I can see it. It needs a filling. I can do it next Tuesday at three in the afternoon."),
        ("Levin", "Tuesday at three works for me. Do I need to stop eating before that?"),
        ("Mehta", "No, just brush well. I will send you the booking confirmation today."),
        ("Levin", "Thank you. I will pay the deposit at the front desk on my way out."),
    ]),
    ("Lease renewal call", "11:15", [
        ("Brennan", "Hello, this is Mister Brennan, calling about your lease."),
        ("Levin", "Hi Mister Brennan. Thanks for calling. What are the new terms?"),
        ("Brennan", "The rent will increase by three percent from January, and the lease runs for one more year."),
        ("Levin", "Three percent is fair. I will think about it and send you my answer by next Friday."),
        ("Brennan", "That is fine. Also, a plumber will come next week to look at the bathroom ceiling."),
        ("Levin", "Good. I will make sure someone is home."),
    ]),
    ("Vendor decision", "15:30", [
        ("Maya", "We need to pick a vendor for the payment service. Ravi, what did you find?"),
        ("Ravi", "The second vendor has fixed pricing and better support. The first one is cheaper, but its fees change every month."),
        ("Levin", "Fixed pricing is what we need. I think we should go with the second vendor."),
        ("Maya", "Agreed. We decided to go with the second vendor, and Ravi will send the contract by Friday."),
        ("Ravi", "I will send the contract by Friday morning and set up the kickoff call."),
        ("Levin", "I will review the pricing sheet tonight and share my notes tomorrow."),
    ]),
    ("Evening with Priya", "19:20", [
        ("Priya", "Have you thought about the Lisbon trip? I am planning the second week of March."),
        ("Levin", "Yes, I would love to go. Which hotel are you thinking of?"),
        ("Priya", "A small place near the Alma district. I will send you the link tomorrow."),
        ("Levin", "Great. I will book the flights this weekend once you confirm the dates."),
        ("Priya", "Perfect. We should also work out who will drive from the airport."),
        ("Levin", "I can drive. I will rent a small car."),
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
    prev = "--prev" in sys.argv          # last week's recording: demo_day_prev.wav / .json
    stem = "demo_day_prev" if prev else "demo_day"
    scenes = SCENES_PREV if prev else SCENES
    if prev:
        random.seed(11)
    os.makedirs(out_dir, exist_ok=True)
    timeline = array.array("h")
    scenes_meta = []

    with tempfile.TemporaryDirectory() as tmp:
        timeline.extend(ambient(8, bursts=1))  # short lead-in dead air
        for scene_index, (label, wall, lines) in enumerate(scenes):
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
            if scene_index < len(scenes) - 1:   # dead air between scenes, none after the last
                timeline.extend(ambient(random.uniform(30, 45), bursts=4))

    wav_path = os.path.join(out_dir, f"{stem}.wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(timeline.tobytes())

    manifest = {"sampleRate": RATE, "duration": round(len(timeline) / RATE, 2), "scenes": scenes_meta}
    with open(os.path.join(out_dir, f"{stem}.json"), "w") as f:
        json.dump(manifest, f, indent=2)

    speech = sum(l["end"] - l["start"] for s in scenes_meta for l in s["lines"])
    print(f"wrote {wav_path}: {manifest['duration']:.1f}s total, {speech:.1f}s speech "
          f"({100 * speech / manifest['duration']:.0f}%)")


if __name__ == "__main__":
    main()
