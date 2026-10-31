# Demo script (about 3 minutes)

The numbers below are from the live run (promises question: 27 snippets, 4.2 KB, about 6 s).

## Before you record (pre-flight)

```bash
Tools/muse_smoke.sh        # key, model and region all OK
Tools/e2e_check.sh         # everything PASS (about 6 minutes)
Tools/demo_prep.sh         # clean simulators: 9:41 status bar, dark mode, fresh day, watch NOT started
```

- Never uninstall the app: it resets the speech-recognition permission.
- The watch simulator ignores the status bar override, so its clock shows the real time. Either crop it in the edit or accept it.
- Close everything else on the Mac. Silence notifications. Arrange the two simulator windows if you also want a screen recording as a backup.
- Do one dry run of the whole script out loud.

## Recording

```bash
Tools/record_demo.sh start      # records the phone and the watch simulators separately
# ... perform the demo ...
Tools/record_demo.sh stop
Tools/compose_video.sh          # side-by-side, sped-up sync, voiceover mux
```

Record the voiceover separately from this script (QuickTime, File > New Audio Recording), in a quiet room.

## Shot list and narration

| Time | On screen | Say |
|---|---|---|
| 0:00 | Phone **Today** (empty, "Your day starts on the watch"), watch beside it showing **Start day** | "Every conversation you have in a day just disappears. Echo remembers it for you, and it never sends your voice to anyone." |
| 0:15 | Tap **Start day** on the watch. Switch the phone to **Pipeline**; chunks arrive and move through the stages (sped up 4x in the edit) | "My watch listens. Here the microphone is a recorded day so you can see exactly what happens. It keeps only speech, compresses it, and sends it to the phone. The phone checks again that it really is speech, and Apple's on-device recognizer transcribes it. No cloud so far." |
| 0:50 | **Today**: the funnel settles; scroll to the conversation timeline | "Of the six minutes recorded, thirty-eight percent was never stored. And the day turns into four conversations, with the topics pulled out locally." |
| 1:15 | **Ask**: tap *When is the plumber coming?*; then *What did Mister Brennan say about the lease?*; then *Where is Priya going in March?* Show the highlighted words and tap play on a source | "Now I can ask my day questions. These are answered on the phone in about thirty milliseconds, the matching words are highlighted, and I can play the original moment to check it." |
| 1:50 | **Ask**: tap *What did I promise people today?* Show "Sending 27 snippets (4.2 KB) to Muse Spark…", then the structured answer; expand **What left your phone** | "Some questions need more than a lookup. Echo sends Muse Spark only the moments that contain promises: twenty-seven snippets, about four kilobytes of text, and no audio. Muse comes back with a structured answer, and it even repaired a transcription slip." |
| 2:30 | **Ledger**: totals, "0 bytes of audio ever leave this phone", open an entry, flip the cloud switch off and ask again to show "Cloud is off" | "Everything is on the record: which questions stayed on the phone, which used Muse, and exactly what was sent. There is a switch to turn the cloud off completely." |
| 2:50 | **How Echo works** sheet | "The microphone here is simulated and the on-device Muse tier is a design, but everything between them is real. That's Echo." |

## If something goes wrong while recording

- Watch shows "No phone": run `Tools/demo_prep.sh` again and wait for "Watch can see the phone: yes".
- A Muse call fails: the card says why. Check the key with `Tools/muse_smoke.sh`, then retry the take. Do not edit in a stub: it is labeled and judges will notice.
- The sync is slow: that's expected (about 70 seconds); it is sped up in the edit.
