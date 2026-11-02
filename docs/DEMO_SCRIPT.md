# Demo script (about 3 minutes)

The easiest route: let the app perform the demo itself and record it, then add your voice.

```bash
Tools/muse_smoke.sh          # key, model and region all OK
Tools/e2e_check.sh           # everything PASS (about 8 minutes)
Tools/record_demo_take.sh    # one continuous take of both simulators, about 6 minutes, saved to docs/media/echo-demo-full.mp4
```

The take is the whole story in about 3:45 with live Muse Spark. The slow part (the watch syncing the day, about 90 seconds) is sped up 5x. Record your voiceover while watching it, then mux it in:

```bash
# Use the numbers the take script printed ("sync section sped up 5x from S s to E s"):
ECHO_VIDEO_DIR=/tmp/echo-take Tools/compose_video.sh --trim-start auto --speed S E 5 \
  --voice ~/Desktop/voiceover.m4a --out docs/media/echo-demo-final.mp4
```

## Before you record (pre-flight)

- Never uninstall the app: it resets the speech-recognition permission.
- The watch simulator ignores the status bar override, so its clock shows the real time. The compose step crops it.
- Close everything else on the Mac. Silence notifications.
- Do one dry run of the narration out loud against the video.
- The take uses your real key. If a Muse call fails, the card says why: fix the key and retake. Do not edit in the offline stub; it is labeled and a viewer will notice.

## Shot list and narration

Times are approximate (the take is about 3:45; the script prints the real marker times). The caption on screen names each step, so you can speak a little before or after it.

| Time | On screen | Say |
|---|---|---|
| 0:00 | **Moments** while the watch starts: "Waiting for your watch", then "Listening" with the ribbon growing and moments appearing (sped up) | "Every conversation you have in a day just disappears. Echo remembers it for you, and it never sends your voice to anyone. My watch listens. It keeps only speech and streams it to the phone." |
| 0:25 | Sync finishes. **Today**: the greeting, then "What Echo kept": "38% of the day was never stored" | "The phone checks again that it really is speech, and Apple's on-device recognizer transcribes it. Of six minutes it heard, thirty-eight percent was never stored. No cloud so far." |
| 0:35 | **Ask**: *When is the plumber coming?*, *What did Mister Brennan say about the lease?*, *Where is Priya going in March?* | "Now I can ask my day questions. These are answered on the phone in about thirty milliseconds, with the matching words highlighted and the original audio one tap away." |
| 0:58 | **Ask**: the mic. "Listening…" , "Understanding…", then *Where is Priya going in March?* is answered on the phone | "I can also just ask out loud. The phone understands it on-device, deletes the recording, and answers it the same way." |
| 1:12 | **Ask**: *What did I promise people today?* "Sending 27 snippets…", then the answer and the **What left your phone** strip, expanded | "Some questions need more than a lookup. Echo sends Muse Spark only the moments that contain promises: twenty-seven snippets, about four kilobytes of text, and no audio. And here is exactly what left the phone." |
| 1:30 | The first item plays its audio (the citation chip) | "Muse cites where each claim came from, and I can play that moment to check it." |
| 1:22 | **Today · Commitments**: the checklist, two ticked off | "Commitments are found on the phone with plain rules. No model, nothing sent. Echo doesn't tell speakers apart, so this is promises heard, not only mine." |
| 1:32 | **Ledger**: totals, "0 bytes of audio ever leave this phone", the three settings; then the cloud switch off and *Summarize my day* shows "Cloud is off" | "Everything is on the record: what stayed on the phone, what used Muse, and exactly what was sent. One switch turns the cloud off completely." |
| 1:50 | Masking on, the same question again; the strip says names were masked | "If I want, names are swapped for placeholders before anything is sent, and swapped back in the answer. It's best effort, and I say so." |
| 2:05 | **Review before sending** sheet for the digest, then Send | "Or I can review every request first: the exact text, then Send or Don't send." |
| 2:22 | **Today · Summary**: the digest | "One tap, and Muse writes the day: conversations, action items I owe people, and who was there." |
| 2:35 | **Ask**, with the watch beside it: the mic, "Heard: Summarize my day", then Muse's answer | "And from my wrist I tap the mic and ask. The phone understands it and answers, and Muse handles the broad ones." |
| 3:00 | **History** on the phone: the list, then one question opened with its citations | "Everything I ask is kept on the phone, with the answer and the audio it came from, until I clear it." |
| 3:15 | **Ledger**: Your data (export, clear history, forget) | "My data stays mine: I can export the ledger, clear my history, or forget the day." |
| 3:25 | **How Echo works** sheet | "That's Echo: a watch that listens, a phone that remembers, and Muse only when it has to." |

## If something goes wrong while recording

- The take script stops with an error if the watch never delivers the day: run `Tools/demo_prep.sh` and wait for "Watch can see the phone: yes", then retake.
- A Muse call fails: the card says why. Check the key with `Tools/muse_smoke.sh`, then retake.
- The sync is slow: that's expected (about 90 seconds); the take speeds it up.
- To redo only part of the video, record the pieces with `Tools/record_demo.sh start/stop` and edit with `Tools/compose_video.sh`.
