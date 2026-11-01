<div align="center">

# Echo

### A private memory for your day

*Your watch listens. Your phone remembers. Meta's Muse Spark helps only when it has to.*

![iOS 26](https://img.shields.io/badge/iOS-26-111111?logo=apple&logoColor=white)
![watchOS 26](https://img.shields.io/badge/watchOS-26-111111?logo=apple&logoColor=white)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Liquid%20Glass-2DD4BF)
![Muse Spark](https://img.shields.io/badge/Meta-Muse%20Spark-7C5CFA)
![Tests](https://img.shields.io/badge/unit%20tests-152%20passing-34D399)
![Hackathon](https://img.shields.io/badge/Meta%20Global%20AI%20Developer%20Hackathon-Indie%20track-5B8CFF)

<img src="docs/media/hero.png" alt="Echo on an iPhone and an Apple Watch" width="880">

</div>

Echo turns a day of conversations into something you can ask questions of, **without handing your voice to anyone**. The speech is transcribed and searched on your phone. Only the rare question that needs real synthesis goes to **Meta's Muse Spark**, and when it does, Echo sends a handful of text snippets, never audio, and records exactly what left the device in a privacy ledger.

> **What is real and what is simulated.** The watch and phone are Xcode simulators, and the "microphone" is a pre-recorded, synthetic-voice day replayed through the real pipeline. Everything after the microphone is real. See [What's real](#whats-real-simulated-and-design-only).

## See it work

<p align="center">
  <img src="docs/media/echo-demo.gif" alt="Echo working: the watch replays a day, the phone processes it, then answers questions" width="760">
</p>

<p align="center">
  <a href="docs/media/echo-demo-preview.mp4"><b>▶ Watch the full-quality preview (MP4)</b></a>
  &nbsp;·&nbsp;
  <a href="docs/media/echo-demo-full.mp4"><b>▶ One continuous take, about 3 min (MP4)</b></a>
</p>

<p align="center"><sub>The watch replays a day, the phone checks, transcribes and indexes it, and then questions are answered: lookups on the phone, and the synthesis questions by <b>live Muse Spark</b> (<code>muse-spark-1.3</code>), with the exact text that was sent shown on screen. Everything in this preview was captured from the running app; regenerate it with <code>Tools/make_readme_media.sh</code>. The continuous take (the app performs the whole demo itself: lookups, a live Muse answer with its citations, commitments, name masking, review before sending, a question asked from the watch, the kill switch and the architecture sheet, with the ~70 s sync sped up 5x) comes from <code>Tools/record_demo_take.sh</code>.</sub></p>

## A tour of the screens

### Apple Watch

The watch is mostly a silent sensor, so its first screen is a proof of life: a ring that traces the replay and breathes with the microphone level, three counters, and one control. Swipe up for **quick-ask**: four preset questions that the phone answers (on its own, or with Muse for the broad ones) and sends back as a sentence or two.

<table align="center">
  <tr>
    <td align="center"><img src="docs/media/screenshots/watch-ready.png" width="200" alt="Watch, ready to start"><br><sub><b>Ready</b><br>Phone linked, demo audio</sub></td>
    <td align="center"><img src="docs/media/screenshots/watch-listening.png" width="200" alt="Watch, listening"><br><sub><b>Listening</b><br>Chunks stream to the phone</sub></td>
    <td align="center"><img src="docs/media/screenshots/watch-done.png" width="200" alt="Watch, day captured"><br><sub><b>Day captured</b><br>Everything synced</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/media/screenshots/watch-ask.png" width="200" alt="Watch, quick-ask presets"><br><sub><b>Quick-ask</b><br>Lock = on the phone, cloud = Muse</sub></td>
    <td align="center"><img src="docs/media/screenshots/watch-answer.png" width="200" alt="Watch, an answer from Muse Spark"><br><sub><b>An answer</b><br>With where it came from</sub></td>
    <td></td>
  </tr>
</table>

### iPhone

<table align="center">
  <tr>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-empty.jpg" width="250" alt="Today, before anything is captured"><br><sub><b>First launch</b><br>A clean slate</sub></td>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-pipeline-live.jpg" width="250" alt="Pipeline, chunks arriving"><br><sub><b>Pipeline, live</b><br>Each chunk is checked, transcribed and stored</sub></td>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-pipeline.jpg" width="250" alt="Pipeline, settled"><br><sub><b>Pipeline, settled</b><br>Speech kept, noise dropped</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-today.jpg" width="250" alt="Today, the day timeline"><br><sub><b>Today · Day</b><br>The funnel, then the day as conversations</sub></td>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-today-commitments.jpg" width="250" alt="Today, commitments"><br><sub><b>Today · Commitments</b><br>Found on the phone with plain rules; tap to hear the moment</sub></td>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-today-summary.jpg" width="250" alt="Today, the day digest"><br><sub><b>Today · Summary</b><br>Written by Muse, with action items you can play back</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-ask-lookup.jpg" width="250" alt="Ask, answered on the phone"><br><sub><b>Ask, answered locally</b><br>Highlighted words, source audio, ~30 ms</sub></td>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-ask-lease.jpg" width="250" alt="Ask, a second local answer"><br><sub><b>Ask, another lookup</b><br>The headline is the sentence that answers</sub></td>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-ask-cloud.jpg" width="250" alt="Ask, a synthesis question routed to Tier 2"><br><sub><b>Ask, synthesis</b><br>Live Muse Spark, with the proof of what left the phone</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-ask-masked.jpg" width="250" alt="Ask, with names masked"><br><sub><b>Names masked</b><br>Muse sees placeholders; you see real names</sub></td>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-review.jpg" width="250" alt="Review before sending"><br><sub><b>Review before sending</b><br>The exact text, then Send or Don't send</sub></td>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-ledger.jpg" width="250" alt="Privacy ledger"><br><sub><b>Privacy ledger</b><br>What stayed, what left, and the settings</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-ledger-data.jpg" width="250" alt="Your data"><br><sub><b>Your data</b><br>Export the ledger, or forget the day</sub></td>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-digest.jpg" width="250" alt="Generating the digest"><br><sub><b>Day digest</b><br>One tap, one structured call</sub></td>
    <td align="center" valign="top"><img src="docs/media/screenshots/phone-architecture.jpg" width="250" alt="How Echo works"><br><sub><b>How Echo works</b><br>The system with live numbers and honesty labels</sub></td>
  </tr>
</table>

## What it does

1. **Watch.** Listens, keeps only speech (a lenient voice detector with a 2-second pre-roll so the first word is never clipped), compresses it and streams it to the phone.
2. **Phone, all on-device.** A second speech check (Apple SoundAnalysis) rejects what isn't speech, Apple's on-device recognizer transcribes it, and the text is indexed in SQLite (FTS5 keyword search plus word-vector similarity).
3. **Ask your day.** A rules-based router decides where each question is answered:
   - **Lookups** ("When is the plumber coming?") are answered on the phone in about 30 ms, with the matching words highlighted and the original audio one tap away.
   - **Synthesis** ("What did I promise people today?", "Summarize my day") goes to **Muse Spark** through the Meta Model API. Echo plans the smallest set of snippets the question needs, sends text only, and asks for a structured answer.
4. **Commitments.** Things people said they will do ("I will send the spec by Wednesday noon") are collected on the phone with plain rules, no model: a checklist with who and when where known, and the audio of each one tap away. Echo doesn't tell speakers apart, so it lists commitments heard, not only yours.
5. **Citations you can hear.** Muse cites the snippets its answer comes from by label, and Echo maps each label back to the audio on the phone, so every claim plays its source. Answers suggest follow-up questions.
6. **Quick-ask on the watch.** Four preset questions on the watch are answered by the phone, with Muse for the broad ones.
7. **Privacy ledger and controls.** Every question is recorded with where it was answered, the exact text and bytes sent, tokens and latency. You can turn the cloud off, **review each request before it is sent**, **mask people's names** (placeholders on the way out, real names on the way back), export the ledger as JSON, or forget the day.

## What's real, simulated, and design-only

| Part | Status |
|---|---|
| Voice detection on the watch, chunking, AAC compression, streaming to the phone | **Real** (running in the watchOS simulator) |
| Stage-2 speech check, on-device transcription, SQLite FTS5 + word-vector index, retriever, router, answers | **Real** |
| Muse Spark calls (structured output, text-only snippets, ledger, error handling) | **Real**: live calls to `muse-spark-1.3` through the Meta Model API (the screenshots above are live answers), plus a mocked-network test suite. Without an API key in `Config/meta_api_key.txt` Echo falls back to a **labeled offline stub** |
| The microphone | **Simulated**: a pre-recorded day (text-to-speech voices, 4 conversations) replayed as the mic |
| Watch ↔ phone link | **Simulated hardware**: WatchConnectivity messages between two simulators |
| Muse Glimmer on-device (Tier 1) | **Design only**: shown in the UI as not available, never run |

## Architecture

```mermaid
flowchart LR
  subgraph Watch["Apple Watch (simulator)"]
    A["Pre-recorded day<br/>replayed as the mic"] --> B["Stage 1: energy voice detector<br/>+ 2 s pre-roll"]
    B --> C["AAC chunks"]
  end
  C -- "WatchConnectivity" --> D
  subgraph Phone["iPhone: everything here is on-device"]
    D["Stage 2: speech check<br/>(SoundAnalysis)"] --> E["Speech recognition<br/>(Apple, on-device)"]
    E --> F[("SQLite<br/>FTS5 + word vectors")]
    Q["Question"] --> R{"Router<br/>(rules)"}
    F --> R
    R -->|lookup| T0["Tier 0: answer from your<br/>transcripts, about 30 ms"]
    R -.->|"design only"| T1["Tier 1: Muse Glimmer<br/>on-device"]
    R -->|synthesis| P["Planner: the minimum<br/>text snippets needed"]
    P --> L[("Privacy ledger")]
  end
  P -- "text only, never audio" --> M["Tier 2: Muse Spark<br/>(Meta Model API)"]
```

## Measured on the demo day

| | |
|---|---|
| Recorded → kept by the watch → confirmed on the phone | 6:15 → 4:48 → 3:53 (38% of the day never stored) |
| Stage 2 | 45 of 45 speech chunks kept, 11 of 11 noise chunks rejected (the noise is synthetic, so this flatters it) |
| Transcription word error rate | 7.2% overall (every scene under 10%) on text-to-speech voices; it will be worse on real speech |
| Retrieval | right moment ranked first for 12 of 12 questions; median search about 26 ms |
| Live Muse Spark (`muse-spark-1.3`) | "What did I promise people today?" about 5-6 s (27 snippets, 4.9 KB sent); "Summarize my day" about 6-7 s; the day digest about 10 s (45 snippets, about 5.9 KB) |
| Tests | 152 unit tests, including a retrieval and routing eval over a fixed transcript fixture, a mocked-network suite for the Muse client, and tests for commitments, citations, masking, the review gate and the watch quick-ask; plus an end-to-end script (`Tools/e2e_check.sh`) that checks the whole demo against live Muse |

## The privacy model

- **Audio never leaves the phone.** The cloud client's request type holds text only, and a test asserts that no audio, file name or local identifier appears in the request body.
- **Only what a question needs is sent.** Commitments send the moments that contain promises or plans; a summary sends the day; a question that matches nothing sends nothing.
- **Everything is on the record.** The Privacy Ledger lists each question, which tier answered, and the exact snippets and bytes sent. Local answers are logged with zero bytes.
- **You are in control.** One switch turns the cloud off; those questions then show the closest moments on the phone. **Review before sending** holds each request behind a sheet that shows the exact text. **Mask names** swaps people's names for placeholders (`[PERSON_1]`) on the phone and restores them in the answer; it is best effort, relies on Apple's on-device name tagger, and is off by default because a misheard word that looks like a name is masked too. You can export the ledger as JSON (what was sent, never Muse's replies or your key) and **forget the day** at any time.
- **No hidden fallback.** If Muse can't be reached, Echo says so (key rejected, rate limited, timed out, offline: "nothing left your phone"). The offline stub only appears when no key exists, and it labels itself.

## How Echo uses Muse Spark

Echo calls `POST https://api.meta.ai/v1/chat/completions` with model `muse-spark-1.3`, a `developer` message with the rules, a `user` message with the question and time-labelled snippets, `reasoning_effort: "minimal"`, and a JSON-schema `response_format`. Snippets are labelled `S1`, `S2`… within the request (never the phone's own identifiers), and the answer comes back as structured data: an answer, items with a due date and the label of the snippet each came from, and follow-up questions. Echo maps each label back to the audio on the phone, so a citation plays its source. The prompt tells Muse that the transcripts are noisy speech recognition and to say so only when it actually corrected something. The same path produces the one-tap "Summarize my day" digest of conversations, action items and people.

Two things the live API taught us, both now handled and tested: **reasoning tokens count against `max_completion_tokens`** (at 800 tokens Muse spent 798 thinking and returned an empty reply, so Echo uses a 3000-token budget and retries once with double if a reply is cut off), and `minimal` reasoning answers the real questions in about 6 s versus 11 s at `low`. If the account can't use the model the client falls back to 1.2 then 1.1, and if structured output is refused it retries once with the schema in the instructions.

## Run it

Requirements: macOS with Xcode 26.1.1 and the iOS 26.1 and watchOS 26.1 simulators.

```bash
# 1. Pair a phone and a watch simulator (once) and put their IDs at the top of the scripts in Tools/
xcrun simctl list devices available
xcrun simctl pair <WATCH_UDID> <PHONE_UDID>

# 2. (Optional) add your Meta Model API key. Without it Echo uses its labeled offline stub.
#    Edit Config/meta_api_key.txt and replace the placeholder line. It is gitignored.

# 3. Build, install both apps and launch
Tools/run_sims.sh --autostart      # the watch starts replaying the day immediately
```

The first launch asks for speech-recognition permission on the phone; tap Allow once. Then open **Today**, **Pipeline**, **Ask** and **Ledger**.

| Script | What it does |
|---|---|
| `Tools/demo_prep.sh` | Clean, recordable simulators (9:41 status bar, dark mode, fresh day) |
| `Tools/e2e_check.sh` | Replays the day and checks the whole demo against ground truth (PASS/FAIL) |
| `Tools/muse_smoke.sh` | Checks your API key, model and region with one tiny call |
| `Tools/check_no_secrets.sh` | Fails if your key appears anywhere it could be published |
| `Tools/record_demo_take.sh` | Records one continuous, self-driving demo take of both simulators (live Muse if a key is set) |
| `Tools/make_readme_media.sh` | Regenerates the screenshots, video and GIF in this README |

```bash
# Unit tests
xcodebuild test -project Echo.xcodeproj -scheme Echo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:EchoTests
```

## Repo map

| Path | What's there |
|---|---|
| `Echo Watch App/` | Watch app: replay engine, uploader, status screen, the demo audio |
| `Echo/` | Phone app: receiver, pipeline, screens |
| `Echo/Search/` | Normalizer, embeddings, hybrid retriever, router, answer extraction, commitments, citations |
| `Echo/Components/` | The shared UI parts: section headers, chips with wrapping layout, buttons, rows, segmented control |
| `Echo/Cloud/` | Muse client, planner and prompts, labeled stub, key handling |
| `Echo/Ledger/` | The privacy ledger and the cloud switch |
| `Shared/` | Code shared by both apps: voice detector, wire format, clock, theme |
| `EchoTests/` | Unit tests and the transcript fixture |
| `Tools/` | Demo audio generator, calibration, simulator, demo and media scripts |
| `docs/media/` | The screenshots, preview video, GIF and hero image above |

## Limitations and what's next

- The microphone is simulated; a real watch needs a foreground session and `AVAudioEngine`, and WatchConnectivity file transfer in place of the simulator's message transport.
- Muse Glimmer on-device (Tier 1) is a design, not an implementation.
- Retrieval uses averaged word vectors because sentence embeddings aren't available in the simulator; a sentence model would be the next upgrade. It does not use `sqlite-vec`.
- Transcription quality on real, noisy speech is untested.
- The router is rules, not a model; it is easy to explain and test, but a learned router could handle more phrasing.
- Echo doesn't identify speakers, so Commitments lists promises heard rather than only the wearer's.
- Name masking is best effort (it only masks names the on-device tagger recognizes) and is off by default.
- Quick-ask needs the phone reachable; a question that needs Muse waits for approval on the phone when Review before sending is on.
