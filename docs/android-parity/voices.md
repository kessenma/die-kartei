# Die Kartei: German voices audit (iOS vs Android, in-app voices)

Date: 2026-11-27. Scope: source read of `~/ws/die-kartei` (iOS) and `~/ws/die-kartei-android` (read only),
a listen test on this Mac (M-series, CPU) and the Android emulator `emulator-5554` (arm64, API 37,
Google TTS `googletts.google-speech-apk_20251028.02`). Nothing in either repo was edited.
Work dir: `parity-audit/voice-work/` (scripts, venv, spike app, WAVs); samples in `voice-work/samples/`.

**Bottom line**
1. **Android can already do in-app voice choice and download, using the system engine.** Google TTS
   has 4 German voices (2 female, 2 male), each `-local` (offline) and `-network`. On the emulator,
   `setVoice()` on a voice flagged `notInstalled` started Google's download from the app (logcat:
   `VoiceDataManager: Explicitly adding voicepack to downloads … Download of es-us started`), and the
   flag was gone 10 s later. `onRangeStart` gives word ranges with `speak()`. Phase 1 is cheap (S–M)
   and puts Android ahead of iOS.
2. **For voices that sound better than the stock ones on both platforms: Supertonic 3 through
   sherpa-onnx 2.x (C API).** 10 German voices (5 F / 5 M) in one 129 MB download (int8). It reads
   from letters, so no espeak-ng (GPL) is needed. Model licence is OpenRAIL-M (commercial use
   allowed, use restrictions you must pass on). It hosts fine on Hugging Face. On the Mac: RTF 0.15
   with 2 threads. Phone speed is not measured yet.
3. **Piper voices are a second choice:** licences are a minefield, and sherpa-onnx 2.0 dropped
   espeak-ng, so Piper needs a phonemizer that isn't GPL. Only `thorsten-medium` (CC0 chain) and
   `kerstin-medium` (CC BY 4.0 chain) are commercially clean.
4. Cloud TTS isn't worth it here: it costs money per character, puts a key in the app or needs a
   proxy server (which counts as self-hosting), and doesn't work offline.

---

## 1. iOS today (what the voice UX is)

Files: `Services/SpeechService.swift` (326 l), `Services/VoiceSetup.swift` (192 l),
`Features/Settings/VoiceSettingsView.swift`, `DialogueVoicePickerSection.swift` (+ `GermanVoiceCatalog`),
`CardSettingsView.swift` L195+ (`VoiceGuideSheet`), `Features/Stories/StoryReadAloudView.swift`.

- **Engine:** one `AVSpeechSynthesizer` singleton that speaks a queue of `Segment(text, voiceIdentifier,
  rangeOffset)`. A single string is a one-segment queue. Rate: `AVSpeechUtteranceDefaultSpeechRate × 0.85`
  normally, `× 0.5` for slow ("turtle"). `.playback` audio session with `.duckOthers`.
- **Voice choice:** Settings ▸ Voice ▸ *Pronunciation* picker (`selectedVoiceIdentifier`, "System Default"
  + every installed `de*` voice, sorted Premium > Enhanced > Basic and labelled that way) with a
  *Preview Voice* button. *Dialogue Voices* section: Man / Woman / Boy / Girl
  (`voiceMale/Female/Boy/GirlIdentifier` on `MLXModelManager`). If only one is set, that voice reads
  every speaker. The same section appears in the Listen-mode voices sheet, and the story player has
  a voice menu (`StoryReadAloudView` L393).
- **Downloading voices happens outside the app.** Apple gives apps no API to download a voice or
  open Settings ▸ Accessibility. The app does three things instead: (a) a hint that "No natural
  German voices downloaded yet", based on quality (`.enhanced/.premium` means the user downloaded
  it); (b) `VoiceGuideSheet` *Download Voices*: 7 screenshots (`voice-guide-settings-search`,
  `-voice-search`, `-accessibility`, `-live-speech`, `-add-voice`, `-german`, `-voice-picker`)
  showing Settings ▸ Accessibility ▸ Live Speech ▸ Preferred Voices ▸ German ▸ cloud icon; it
  suggests Yannick, Petra, Viktor, Anna, warns that Siri voices are off-limits to apps, says to
  force-quit after download, and has an *Open Settings* button (it can only open the app's own
  page); (c) missing-voice detection.
- **Missing-voice detection (`VoiceSetup`):** watches `availableVoicesDidChangeNotification` and
  compares the 5 chosen identifiers (synced between devices by `VoicesSyncDocument` over iCloud)
  with the installed voices. When speech falls back (missing dialogue voice → main voice →
  `de-DE`), it shows a "Download your voices" alert once per launch (*Show Me How* / *Don't Ask
  Again* / *Not Now*). The settings screen lists what's missing. A stand-in voice never overwrites
  the choice.
- **Features that use the voice:** word highlighting (`willSpeakRangeOfSpeechString` → `onWord` in
  full-text UTF-16 coordinates) in Story read-aloud, StoryDetailView and tutor chat
  (`ConversationEngine.play` → `spokenRange`); slow mode everywhere (Hören Diktat/Zahlen,
  Conversation "hear slow", cards); per-speaker dialogue voices (Dialogue/E-Mail stories); a player
  with pause/resume/skip segment plus lock screen / Dynamic Island (`MPNowPlayingInfoCenter`,
  `MPRemoteCommandCenter`, duration estimated at 14 chars/s, or 7 when slow); the Stammtisch pub
  noise bed under the tutor's voice only (`StammtischNoise`); about 25 other call sites speak a
  word or line (cards, cloze, prepositions, Wortschatz, WordInspector, Hören player).
- Core already has `protocol SpeechOutput` (`Services/Tutor/ConversationHost.swift` L100: speak(text,
  slow, onWord, onFinish), stop, start/stopBackgroundNoise) and `SilentSpeechOutput`. The protocol is
  tutor-only and has no segments, voices or transport.

## 2. Android today

- `DieKarteiAndroid/Sources/GermanVoice/GermanVoice.swift` (transpiled Kotlin): lazily creates
  `TextToSpeech(context, listener)` (the **system default engine**), calls `setLanguage(Locale.GERMANY)`,
  `speak(text, QUEUE_FLUSH)` at rate 0.95 / 0.6 (slow), `stop()`, and
  `openSystemVoiceSettings()` (`com.android.settings.TTS_SETTINGS`). No voice selection, ranges,
  queue, pause or MediaSession.
- Settings ▸ Voice (`SettingsView.swift` L65-95): *Probehören*, *Langsam*, "Android voice
  settings" button. The voice used is whatever the system default engine picks for de-DE.
- `ai-platform-infra.md` §2.3 already lists the gaps: onRangeStart, segment queue with per-segment
  Voice, pause/resume/seek, MediaSession, Stammtisch noise, getVoices() picker → "implement the
  shared SpeechOutput protocol, M".

## 3. Research

### 3a. Android system TTS: what works in-app (verified on emulator unless marked)

Spike app `voice-work/voicespike` (package `com.kessenma.voicespike`, AGP 9.2, Kotlin, 90 lines),
logs in `voicespike/spike_log1.txt`.

| Voice (Google TTS) | Pitch | quality / latency | network | Notes |
|---|---|---|---|---|
| `de-de-x-dea-local` (= `de-DE-language` default) | ~222 Hz, female | 400 HIGH / 200 LOW | no | 24 kHz |
| `de-de-x-deb-local` | ~115 Hz, male | 400 / 200 | no | 24 kHz |
| `de-de-x-deg-local` | ~127 Hz, male | 400 / 200 | no | 24 kHz |
| `de-de-x-nfh-local` | ~212 Hz, female | 400 / 200 | no | 24 kHz |
| `…-network` of each | same speakers | 400 / 200 | yes | 48 kHz output, slightly slower pace |

- `getVoices()` returned 473 voices, 9 German. Features seen: `networkTimeoutMs`,
  `networkRetriesCount`, `notInstalled`, `legacySetLanguageVoice`. German was already installed on
  this image. 447 voices in other languages were `notInstalled`.
- **Per-app voice:** `setVoice(v)` returns 0 (SUCCESS) and affects only this `TextToSpeech`
  instance; the system default is untouched. A specific engine can be bound with
  `TextToSpeech(ctx, listener, "com.google.android.tts")`. The spike accepts this as `--es engine`,
  but it wasn't exercised because Google is already the default on the emulator.
- **In-app download: works.** `setVoice()` on a `notInstalled` voice made Google TTS start the voice
  pack download. This matches the documented behaviour of `KEY_FEATURE_NOT_INSTALLED` ("the
  download will be triggered by calling setVoice or setLanguage"):
  https://learn.microsoft.com/en-us/dotnet/api/android.speech.tts.texttospeech.engine.keyfeaturenotinstalled
  and https://developer.android.com/reference/android/speech/tts/TextToSpeech.Engine. You get no
  progress callback, so poll `getVoices()` or listen for `ACTION_TTS_DATA_INSTALLED`.
  `Engine.ACTION_INSTALL_TTS_DATA` opens the engine's own install screen, which is a fallback.
  Today's `GermanVoice.setLanguage(GERMANY)` probably already triggers the German download on a
  phone that lacks it (not tested on such a phone).
- **Word highlighting:** `onRangeStart(id, start, end, frame)` fired for each of the 18 words with
  `speak()`, for both -local and -network
  (https://developer.android.com/reference/android/speech/tts/UtteranceProgressListener, API 26+).
  It did **not** fire during `synthesizeToFile()`.
- **Rate:** `setSpeechRate()` works per instance (0.6 used for slow).
- **What can't be done:** no voice previews before download, no sizes, no gender metadata (the names
  are opaque codes; label them from our own table), and German has only 4 speakers. Google decides
  what quality the voices have; it's "fine", not natural. Fire OS, Huawei and some Chinese ROMs ship
  without Google TTS. `-network` voices need data and send text to Google.
- **Samsung (not tested, no device):** Galaxy phones often default to Samsung TTS
  (`com.samsung.SMT`, German packs such as `com.samsung.SMT.lang_de_de_f00` "German Default voice 1 -
  Classic", https://sysapps.bayton.org/packages/com.samsung.SMT). Google TTS is normally also
  installed. Prefer Google explicitly, fall back to the default engine, and check onRangeStart
  support at runtime (if the first utterance reports no ranges, use estimated highlighting).

### 3b. On-device neural TTS (one C/C++ engine for iOS and Android)

**sherpa-onnx** (k2-fsa, Apache-2.0, v2.0.3, 2026-11-22) has a C API with Swift/Kotlin bindings and
supports VITS/Piper, Matcha, Kokoro, Kitten, ZipVoice, Pocket and Supertonic models.
**Breaking change in 2.0.0 (PR #4055, 2026-10):** espeak-ng and piper-phonemize were removed "to keep
sherpa-onnx fully compatible with Apache-2.0" (https://github.com/k2-fsa/sherpa-onnx/issues/3731,
https://k2-fsa.github.io/sherpa/onnx/faqs/update-v1.x-to-v2.x-espeak-ng.html). Piper models now need
the caller to supply phonemes (`GenerationConfig.phoneme_codepoints`) or a lexicon. I reproduced
this: a plain-text Piper call fails with "phoneme_codepoints is empty, no lexicon", and works
when fed phonemes.
Prebuilt Android: `sherpa-onnx-2.0.3.aar` (52 MB, all ABIs). arm64 libs are `libonnxruntime.so`
22.2 MB + `libsherpa-onnx-c-api.so` 5.1 MB. iOS: SwiftPM from the repo or `build-ios.sh`
xcframework (no prebuilt iOS asset in the release).

**espeak-ng is GPL-3.0** (so is Piper's engine, `OHF-Voice/piper1-gpl`). Statically linking it into a
closed-source App Store app is the classic GPL/App Store conflict (e.g. the react-native-piper-tts
README: https://github.com/kilarsky/react-native-piper-tts). So Piper voices need either a
permissive German G2P or a lexicon. Not solved here: **open item**.

German models available (all downloadable from Hugging Face or GitHub releases, no self-hosting):

| Model | Size | Speakers | Licence chain (commercial?) | Notes |
|---|---|---|---|---|
| **Supertonic 3** int8 (sherpa release `sherpa-onnx-supertonic-3-tts-int8-2026-05-11`, HF `Supertone/supertonic-3` fp32 398 MB) | 129 MB dl / 145 MB disk | 10 (F1–F5 sid0–4, M1–M5 sid5–9) shared by 31 languages | OpenRAIL-M weights (commercial OK, use restrictions must be passed on); MIT code | Reads from letters (unicode indexer), **no G2P/espeak**. 44.1 kHz. speed + num_steps |
| Piper `de_DE-thorsten-medium` (2026 retrain, Piper ≥1.5) | 63 MB | 1 M | **CC0, rdh base CC0: clean** | Copies downloaded before the late-2026 retrain (incl. csukuangfj's 2023 sherpa package) are lessac-derived |
| Piper `de_DE-kerstin-medium` | 63 MB | 1 F | **CC0 + hifi_tts_92 base CC BY 4.0: clean, attribution** | |
| Piper `thorsten-high` | 114 MB | 1 M | lessac base: Blizzard 2013, research only. **No** | Piper's COMMERCIAL_USE.md says so |
| Piper `thorsten_emotional-medium` | 77 MB | 8 emotions | CC0 data, but fine-tuned from the old (lessac) thorsten. **No** until retrained | amused/angry/whisper/… |
| Piper `mls-medium` | 77 MB | 236 | CC BY 4.0, from scratch: OK | Quality poor (see listen test) |
| Piper `eva_k-x_low`, `ramona-low` | 21 / 63 MB | 1 F | M-AILABS (BSD-style, permissive per mirrors; Piper: "not reviewed") | 16 kHz, older phoneme map (drops `ç`) |
| Piper `karlsson-low`, `kerstin-low`, `thorsten-low`, `pavoque-low` | 63 MB | 1 | Ryan base CC BY-NC-SA; pavoque data NC. **No** | |
| `miro-high`, `dii-high` (OpenVoiceOS, csukuangfj HF) | 63 MB | 1 | **CC BY-NC-SA: No** | not sampled |
| Kokoro-82M v1.0/1.1 | — | — | Apache | **No German** (en, es, fr, hi, it, ja, pt, zh) |
| Matcha (sherpa) | — | — | — | No German model published (zh, en, fa) |
| Coqui XTTS-v2 / Chatterbox-multilingual | 1.8 GB / ~0.5B params | cloning | CPML non-commercial / MIT | too big and slow for phones |

Sources: rhasspy/piper-voices MODEL_CARDs (HF revision `5ec43b1`, 2026-11-24);
https://github.com/OHF-Voice/piper1-gpl/blob/main/docs/LICENSING.md and `COMMERCIAL_USE.md` (lists
`de_DE-thorsten-medium` under rdh and `de_DE-kerstin-medium` under hifi_tts_92; says
`de_DE-thorsten-high` still descends from lessac); https://huggingface.co/Supertone/supertonic-3
(languages, OpenRAIL-M); https://k2-fsa.github.io/sherpa/onnx/tts/all/German/supertonic-3-de.html.

Speed (this Mac, M-series CPU, not a phone; RTF = synthesis time / audio time, lower is faster):
Piper medium 0.02–0.05 (1 thread, piper-tts 1.8); sherpa-onnx VITS thorsten-medium 0.047 (1 thread),
0.028 (2), 0.022 (4); Supertonic 3 int8 0.27 (1 thread, 8 steps), 0.14–0.15 (2 threads, 8 steps),
0.14 (1 thread, 4 steps). Phones are probably 2–5× slower (not measured). Even then Piper is easily
real-time. Supertonic should still be real-time if it renders one sentence ahead, with roughly
0.5–2 s before the first word.

**Word timing / highlighting:** sherpa-onnx returns only samples plus a per-sentence progress
callback, with no per-word timing. Piper 1.8 can return phoneme alignments
(`include_alignments=True`), which group into words exactly
(`voice-work/word_timing_demo.json`: 10/10 words with start/end). Getting the same from sherpa
would need the model patched with an alignment output, run by our own ONNX code. Practical plan
for both models: render per sentence, then spread the sentence time over its words by character
count (or by phoneme count for Piper). Supertonic's duration predictor output isn't exposed (not
checked further).
**Rate:** Piper `length_scale` (1.45 in the slow sample), sherpa `speed` (0.7 in the slow sample).
Both slow down without changing pitch.
**Dialogue roles:** Supertonic covers Man/Woman with 5+5 voices. There are **no child voices**
anywhere (iOS has none either; the Boy/Girl roles just pick any voice).

### 3c. Cloud TTS (for comparison)

| Service | German quality | Price | Notes |
|---|---|---|---|
| Google Cloud TTS | Chirp 3 HD very natural; Neural2/WaveNet good | Standard/WaveNet $4/1M chars, Neural2 $16, Chirp 3 HD $30 (https://cloud.google.com/text-to-speech/pricing) | word timepoints only via SSML `<mark>` (voice-dependent, unverified for Chirp) |
| Azure Neural | very good, many de-DE voices, word-boundary events | $15/1M chars, 0.5M free/month | |
| ElevenLabs | best expressiveness | Flash $0.04, Multilingual v2 $0.08 per 1K chars (https://elevenlabs.io/pricing/api) | ~10–20× Google |
| OpenAI gpt-4o-mini-tts | good, English-accented at times | about $0.015/min | marked deprecated in OpenAI docs |

What rules them out: an API key in the app gets extracted, so you need a token-vending proxy, which
is a server (self-hosting). You pay per character for every story the app re-reads, unless audio is
cached. Nothing works offline (the app is on-device-first: tutors via MLX / llama.cpp). Text also
leaves the device. At most, keep this as a future option for pre-rendered story audio.

## 4. Listen test (real files)

Same text everywhere: *"Guten Tag! Ich lerne Deutsch mit der Kartei. Die Brötchen vom Bäcker
gegenüber schmecken am Wochenende besonders gut."* MP3, 64 kbps mono, 45–98 KB each.
**Intelligibility check (not a naturalness score):** each file was transcribed with a German ASR model
(NeMo FastConformer, sherpa-onnx) and scored by WER over 18 words (`asr_check.py`, `asr_wer.json`).
Most voices lose exactly one word, "Kartei" heard as "Karte"/"Partei". That is a language-model bias
in the ASR, so **0.06 ≈ perfect**. I could not listen to the files. Judge naturalness by ear.

| File | WER | Licence | Notes |
|---|---|---|---|
| `android-google-de-x-{dea,deb,deg,nfh}-local.mp3` | 0.06 | Google, system | the current Android voice is dea-local |
| `android-google-de-x-{dea,deb,deg,nfh}-network.mp3` | 0.06 | Google, system | 48 kHz network versions |
| `macos-anna.mp3`, `macos-anna-slow.mp3` | 0.00 | Apple, system | Anna (default quality; no Enhanced/Premium German installed on this Mac) |
| `macos-eddy/flo/reed/sandy.mp3` | 0.56–0.89 | Apple | Eloquence voices, the "robot" end of the iOS list |
| `supertonic3-de-F1…F5-sid0…4.mp3` | 0.00–0.17 | OpenRAIL-M | female styles; F4 0.00 |
| `supertonic3-de-M1…M5-sid5…9.mp3` | 0.00–0.11 | OpenRAIL-M | male styles; M3 0.00 |
| `supertonic3-de-F1-sid0-slow.mp3` | 0.06 | | speed 0.7 |
| `piper-thorsten-medium.mp3`, `-slow.mp3` | 0.06 | CC0 | 2026 retrain; slow = length_scale 1.45 |
| `piper-kerstin-medium.mp3` | 0.11 | CC0 + CC BY | "Kartei" misheard as "Becker Tal" |
| `sherpa-onnx-thorsten-medium-2023.mp3` | 0.06 | lessac-derived | proves the sherpa 2.x + external-phonemes path |
| `piper-thorsten-high.mp3` | 0.06 | research only | reference only |
| `piper-thorsten_emotional-{neutral,amused}.mp3` | 0.39 / 0.17 | lessac-derived | words run together |
| `piper-mls-{male-spk150,female-spk163,highpitch-spk102}.mp3` | 0.44–0.56 | CC BY 4.0 | first sentence garbled in all 3, **reject** |
| `piper-ramona-low`, `piper-eva_k-x_low`, `piper-karlsson-low` | 0.06 / 0.17 / 0.06 | M-AILABS / NC | 16 kHz, telephone-like |

## 5. Recommendation

### Voices screen (both platforms, same layout)
```
Settings ▸ Voice
 ├ Pronunciation voice   [Kartei Natural · Lena ▸]   ▶ Probehören   🐢 Langsam
 ├ Dialogue voices       Mann ▸ · Frau ▸ · (Kinder: Junge ▸ · Mädchen ▸)
 ├ Natural voices (Die Kartei)        — one pack, 129 MB, offline
 │    [Download] / progress / [Delete]   "10 voices · works offline · licence"
 │    rows: Lena (F1) ▶  Mia (F4) ▶ … Jonas (M3) ▶ …   ← sample MP3 streamed from HF before download
 ├ System voices
 │    Android: Google: Frau A (dea) ✓ · Mann B (deb) ⤓ · … ; per row ▶ and [Download] → setVoice()
 │    iOS: installed AVSpeech voices (Premium/Enhanced/Basic) + existing "How to download" guide
 └ Engine (Android, advanced): Google ▸ | Samsung | system default
```
- One `VoiceID` string per choice: `system:<platform id>` or `kartei:<pack>/<sid>`, e.g.
  `kartei:supertonic3-de/7`. Kartei voices are the same on both platforms, so iCloud/sync choices
  carry over. A `system:` choice from the other platform reads as "not on this device" and
  `VoiceSetup`'s missing-voice logic still applies.
- Default stays the system voice, so nothing is downloaded until the learner asks. The first time a
  story or Hören starts, a one-time banner offers "Natürliche Stimmen laden (129 MB)", and that
  replaces the iOS Settings screenshots for most users.
- Downloads reuse the core GGUF downloader (resume, SHA-256, size check) and run Wi-Fi-only by
  default. Use the pinned HF revision plus a sha256 manifest **compiled into the app**. Piper retrains
  voices under the same file names, so never fetch `main`.
- Hosting: Supertonic int8 is on k2-fsa GitHub releases. Better to mirror it into Kyle's HF org next
  to the tutor models (OpenRAIL-M allows redistribution; ship LICENSE + use restrictions, add an
  in-app "Voice licences" page and add the use restrictions to the terms). Sample MP3s go in the
  same HF repo.

### Engine shape (Swift, in the shared core)
```swift
public struct VoiceID: Hashable, Codable, Sendable { public let raw: String }   // "system:…" | "kartei:pack/sid"
public struct VoiceInfo { id: VoiceID; name: String; gender: Gender?; quality: Quality;
                          installed: Bool; sizeBytes: Int?; sampleURL: URL?; licence: String? }
@MainActor public protocol SpeechBackend: AnyObject {
    var voices: [VoiceInfo] { get }                       // refreshes, posts change
    func canSpeak(_ id: VoiceID) -> Bool
    func install(_ id: VoiceID) async throws              // Android setVoice / pack download / iOS: throws .needsSystemSettings
    func speak(_ seg: Segment, rate: Rate, events: SpeechEvents)   // onStart/onWord(NSRange)/onDone
    func pause(); func resume(); func stop()
}
public final class SpeechPlayer { // = today's SpeechService queue logic moved to core: segments, skip,
    // fallback chain (segment voice → main voice → system de-DE), slow rate, Now-Playing hooks via a
    // small NowPlaying protocol (MPNowPlayingInfoCenter on iOS, MediaSession module on Android)
}
```
Backends: `AVSpeechBackend` (iOS; today's code), `AndroidTTSBackend` (grows `GermanVoice`: getVoices,
setVoice, onRangeStart, QUEUE_ADD, explicit engine), `NeuralBackend` (sherpa-onnx C API via a
`CSherpa` module like `CLlama`). It renders one sentence ahead to PCM and plays it through
`AVAudioEngine`/`AVAudioPlayerNode` (iOS) or `AudioTrack` (small Kotlin module). Word ranges come
from per-sentence playback position spread by character count, so highlighting works the same as
today. The tutor `SpeechOutput` becomes a thin adapter over `SpeechPlayer`. Stammtisch noise stays
outside it.

### Phases and effort
| Phase | What | Effort |
|---|---|---|
| 1 | Android system voices: picker from `getVoices()` (de, friendly names + gender from a table), per-role dialogue voices, preview, in-app download through `setVoice` with polling, explicit Google engine with fallback, onRangeStart highlight, segment queue, rate. **Already beats iOS UX.** | S–M |
| 2 | Move `SpeechService` queue/fallback logic into the core `SpeechPlayer` + `SpeechBackend` (iOS behaviour unchanged, it's a move). Android MediaSession for lock-screen story playback | M |
| 3 | `NeuralBackend` with Supertonic 3 on Android (sherpa AAR .so or built from source with the NDK, like llama). Voices screen download/delete/samples, HF mirror + manifest | M–L |
| 4 | Same backend on iOS (SwiftPM/xcframework). Keep AVSpeech as default/fallback; the iOS guide becomes optional | M |
| 5 (opt.) | Piper thorsten/kerstin-medium as extra voices, only once a non-GPL German phonemizer or lexicon is chosen and checked | M |

**App-size impact:** onnxruntime + sherpa C API ≈ 27 MB uncompressed arm64 on Android (about 10–12 MB
compressed in an AAB split, estimated). iOS is similar (not measured). onnxruntime can't share code
with the llama.cpp already in the app. The voice pack is downloaded, not bundled (129 MB).

## 6. Running alongside the tutor (measured on the Mac mini, M6 2P+4E cores, 2026-11-27)

`tools/voices/tts_bench.py` + `contention.sh` (run from the voice work dir): Gemma 4 E2B tutor Q4_K_M in `llama-bench` (64 tokens,
3 runs) while Supertonic speaks a three-line tutor reply in a loop. The emulator was running, so
expect a few % noise.

| | Tutor tokens/s | Voice speed (lower is faster; < 1 = faster than real time) |
| --- | --- | --- |
| Tutor alone, CPU 4 threads (Android-like) | 46.2 | – |
| + voice on 2 threads | 37.4 (−19%) | 0.19 median, 0.35 worst |
| + voice on 1 thread | 44.2 (−4%) | 0.37 median, 0.53 worst |
| Tutor alone, GPU/Metal (iOS-like, MLX also runs on the GPU) | 57.6 | – |
| + voice on 2 threads | 56.7 (−2%) | 0.24 median, 0.74 worst |

- Supertonic's peak memory: ~405 MB (419 MB footprint minus 13 MB for Python). Loading takes
  0.2–0.3 s once the files are cached.
- System voices run in the OS speech service (Android: Google TTS's own process; iOS: the system
  speech service), so today they cost the app nothing. Supertonic runs inside the app and its
  ~400 MB counts against the app's limit, next to the tutor (E2B: ~1.7 GB llama.cpp footprint on
  Android, ~2.7 GB MLX peak on iOS, where a 6 GB iPhone allows roughly 3.4 GB).

## 7. Unverified / open
- Speed, memory and first-word latency on real phones (all timings above are from an M-series Mac).
  Memory while a Gemma tutor is loaded (tutor chat speaks replies), and battery.
- Whether Supertonic 3's German sounds natural enough to be worth 129 MB compared with Google's 4
  voices. **Kyle should listen** to `supertonic3-de-*` against `android-google-*` and `macos-anna`.
- OpenRAIL-M obligations for an App Store/Play app (pass the use restrictions on in the terms): needs
  a quick legal read. M-AILABS-voice licences.
- A German G2P for Piper that isn't GPL (sherpa lexicon frontend + an OOV fallback). espeak-ng is
  GPL-3, so it's out for the App Store.
- Samsung TTS: onRangeStart, voice list and quality. Devices without Google TTS. Whether
  `-network` sounds better than `-local` (it's 48 kHz; judge by ear) and its data use.
- Whether `setLanguage(GERMANY)` alone downloads German on a device without it (shown only for
  `setVoice` with es-US on the emulator; the emulator now has es-US data).
- iOS 17+ `AVSpeechSynthesisProviderAudioUnit` could expose Kartei voices as *system* voices.
  Interesting, but not needed for the in-app path.

## 8. Reproduce
`voice-work/`: `.venv` (uv, py3.12: sherpa-onnx 2.0.3, piper-tts 1.8.0, onnx), `synth_piper.py`,
`synth_supertonic.py`, `asr_check.py`, `piper_log.json`, `supertonic_log.json`, `mls_pitch.json`,
`word_timing_demo.json`, `voicespike/` (adb: `am start -n com.kessenma.voicespike/.MainActivity
[--es speak <voice> | --es tryDownload any]`, WAVs in `/sdcard/Android/data/com.kessenma.voicespike/files`).
