# Demo script (about 4½ minutes)

The easiest route: let the app perform the demo itself and record it, then add your voice.

```bash
Tools/muse_smoke.sh          # key, model and region all OK
Tools/e2e_check.sh           # everything PASS (about 15 minutes, 40 checks)
Tools/record_demo_take.sh    # one continuous take of both simulators, about 6 minutes, saved to docs/media/echo-demo-full.mp4
```

The take is the whole story in about 4:30 with live Muse Spark. The slow part (the watch syncing last week's day and then today's, a few minutes) is sped up 5x. Record your voiceover while watching it, then mux it in:

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
| 0:00 | **Moments** while the watch starts: last week's day replays first, then today's (sped up) | "Every conversation you have just disappears. Echo remembers it for you, and it never sends your voice to anyone. The watch keeps only speech and sends it to the phone. Last week's day is kept alongside today's." |
| 0:50 | Sync finishes. Captions: voices told apart, where each moment happened | "The phone checks it is speech, transcribes it on the device, tells the voices apart and notes roughly where each moment happened. All of it stays on the phone." |
| 1:00 | **Today**: "What Echo kept", the share of the day never stored | "Of the day it heard, more than a third was never stored at all." |
| 1:10 | **Ask**: *When is the plumber coming?*, *What did Mister Brennan say about the lease?*, then *How much was the rent increase last week?* | "Lookups are answered on the phone in about thirty milliseconds, and I can name any day: last week is remembered too." |
| 1:40 | **Ask**: the mic; a spoken question answered on the phone | "I can also just ask out loud. It is understood on-device, the recording is deleted, and it is answered the same way." |
| 1:55 | **Ask**: *What did I promise people today?*, "What left your phone", the first citation plays | "Some questions need synthesis. Echo sends Muse Spark only the moments that contain promises, as text, shows exactly what it sent, and every claim plays its source." |
| 2:25 | **Today · Promises**, two ticked off, then **Draft a message** written by Muse | "Promises are found on the phone with plain rules. For any of them Echo can draft the follow-up, sending Muse only that moment and the line before it." |
| 2:50 | **Today · Day**: the places map | "And where it happened, to about a hundred metres. It stays on the phone and is never sent." |
| 3:00 | **Ledger**: totals; cloud off, *Summarize my day* says "Cloud is off"; back on; masking on; review before sending | "Everything is on the record. One switch turns the cloud off; names can be masked; and I can review every request first." |
| 3:40 | **Today · Summary**: the digest; then the watch asks *Summarize my day* | "One tap and Muse writes the day. From my wrist I ask by voice and the phone answers." |
| 4:00 | **History**, then **Moments** while "Forget the last ten minutes" runs, then **Ledger · Your data** | "Everything I ask is kept on the phone until I clear it. I can forget the last ten minutes, export the ledger or forget the day." |
| 4:20 | **How Echo works** sheet | "That's Echo: a watch that listens, a phone that remembers, and Muse only when it has to." |

Not in the take (they need real hardware or a person): "Hey Echo" on a real microphone, off the record said aloud (both are checked end to end on the recorded day by `Tools/e2e_check.sh`), the Siri phrases, the widgets and the watch complication. Say so if you mention them.

## If something goes wrong while recording

- The take script stops with an error if the watch never delivers the day: run `Tools/demo_prep.sh` and wait for "Watch can see the phone: yes", then retake.
- A Muse call fails: the card says why. Check the key with `Tools/muse_smoke.sh`, then retake.
- The sync is slow: that is expected (a few minutes for two days); the take speeds it up.
- To redo only part of the video, record the pieces with `Tools/record_demo.sh start/stop` and edit with `Tools/compose_video.sh`.
