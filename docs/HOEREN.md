# Hören — the listening room

A Home room (wide tile under Schreiben; a practice item in the Mac sidebar) for listening as a
skill of its own. It is section A of `docs/FSI_DLI_ROADMAP.md`: DLI's performance tests are mostly
listening tasks, and before this room the app only had Stories ▸ Hören.

| Exercise | Roadmap item | Source | Tutor needed |
|---|---|---|---|
| Zahlen-Diktat: hear a number once, type the digits | 1 | `DLI-FLO` "transcribe (single pass) numbers", bare and in context | No |
| Diktat: hear a sentence, write it, see it word by word | 2 | `DLI-FLO` "transcribe text in native script", `DLI-STRAT` 1c, `FSI-8` | No |
| Erst raten, dann hören: predict words, then listen | 4 | `DLI-STRAT` 1a, 1d | No |
| Worum geht's?: the gist in English, compared with key points | 3 | `DLI-FLO` "produce an English summary" | Key points only |

The old Home tile "Listening" was the phrase library; it is now titled "Phrasen"
(`ActivityCategory.listening` keeps its case name, so nothing routed or stored changed).

## Files

| What | Where |
|---|---|
| Tile, hub, round row, story picker, stats | `Features/Hoeren/HoerenTile.swift`, `HoerenHubView.swift` |
| Playback with replay counting | `Features/Hoeren/HoerenPlayer.swift` |
| Zahlen-Diktat screens | `Features/Hoeren/Zahlen/` |
| Diktat screens, word-by-word view | `Features/Hoeren/Diktat/` |
| Predict / hidden text / summary / compare | `Features/Hoeren/Gist/StoryGistFlow.swift`, hosted by `StoryDetailView` |
| Number speller, generator, answer parser, confusions | `Services/Hoeren/GermanNumberSpeller.swift`, `HoerenNumberGenerator.swift`, `HoerenNumberAnswer.swift` |
| Sentence bank, course source | `Services/Hoeren/DiktatSentenceBank.swift` |
| Scorer | `Services/Hoeren/DiktatScorer.swift` (aligns with `WritingDiff.alignment`) |
| Key points and judge prompts, parsers | `Services/Hoeren/GistPrompts.swift` (pure; compiled by `training/hoeren_cli`) |
| Saving, day credit, coach memory, stats | `Services/Hoeren/HoerenScoringService.swift` |
| The Hören deck | `Services/Hoeren/HoerenDeckStore.swift` |
| Model and sync | `Models/Hoeren/HoerenRound.swift`, `Services/Sync/Codecs/HoerenCodecs.swift` |
| Debug | `Features/Hoeren/HoerenDebug.swift` |
| Tests | `german-ai-flashcardsTests/Hoeren/HoerenCoreTests.swift` |

## Zahlen-Diktat

- **Kinds** (`HoerenNumberKind`): numbers to 100, hundreds and thousands, prices, official clock
  times (A1), everyday clock times (A2: halb, Viertel, fünf vor halb), dates (A2), years (B1),
  phone numbers. Levels add kinds and widen ranges (`HoerenNumberGenerator.make`).
- **Bare or in a sentence**, the two DLI objectives. Carrier templates keep the number where it
  stands alone or before a fixed word, so the spelled form never needs an inflected "eine"; a 1 is
  never put in a carrier sentence.
- **Single pass** is the default. A replay is allowed and counted; "first pass" means right with
  no replay. Study mode adds the slow voice.
- **The voice gets spelled text**, written by `GermanNumberSpeller`, never `NumberFormatter`'s
  `.spellOut` (it puts soft hyphens U+00AD inside words and says 1987 as "eintausendneunhundert…").
  Years 1100–1999 are hundreds, prices are "drei Euro fünfzig", phone numbers use "zwo" and read
  the area code digit by digit (pairs after it from A2), dates are ordinals ("am dritten Mai").
  A test pins that no output contains U+00AD.
- **Answers are values, not strings.** `HoerenNumberAnswer.parse` reads "1.000", "1 000", "14.30
  Uhr", "08:05", "3,5" (= 3,50 €), "99 Cent", "3. Mai"; phone numbers keep leading zeros. The
  everyday clock accepts h and h+12. Input that can't be read as the kind asked shows the format
  hint and does **not** use the attempt: a format slip is not a listening slip.
- **Confusions** (`HoerenConfusion`): tens and units swapped (24 ↔ 42, 1987 ↔ 1978), -zehn vs
  -zig (13 ↔ 30), halb (the coming hour), zwei vs drei. Stats list the top pairs.

## Diktat

- **Sentences are bundled or the learner's own, never generated** (a dictation must be right word
  for word): Goethe A1/A2 example sentences (B1 has none), Tatoeba Perfekt examples
  (`exampleSource == "tatoeba"` only), the Kasus stories' sentences (which carry their targets'
  cases). Filters: 3+ words, a capital first, a full stop last, no digits, brackets, dashes or
  abbreviations; at most 8 / 12 / 16 words for A1 / A2 / B1. Pools at the time of writing:
  A1 808 · A2 1160 · B1 162 (`-hoeren.debugVerify 1` prints them). B1 is thin.
- **A course as the source**: German sentences from the handouts of the last 14 days (else the last
  three entries) plus the example sentences on the course deck. Under 5, the row is greyed.
- **Scoring** (`DiktatScorer`): punctuation is shown, never scored. Words align on a folded key
  (lowercase, ä→a, ß→ss) so a missed capital or umlaut still lines up; removed/inserted runs
  between matches pair up as substitutions. Each word is the worst that applies:
  word > ending > umlaut/ß > capital > right.
  - **Capital** counts as heard (capitals are spelling) and is listed apart; the first word's case
    is ignored.
  - **Umlaut or ß** counts wrong, following the Spiele rule (`docs/SPIELE.md`: Ä is not A).
  - **Ending**: same determiner family (der/den/dem…, ein-, kein-, possessives, dies-, jed-…), a
    pronoun case pair (ihn/ihm, mich/mir…), or a shared stem of 3+ letters with both tails in a
    short ending list. Tagged with a grammar point when one is safe to name: the Kasus target's
    case (Nominativ → Artikel), a Perfekt participle or auxiliary, a determiner (Artikel), an
    adjective between a determiner and a capitalised noun (Adjektivendungen).
  - Extra words are shown and not counted. Score = right ÷ the sentence's words.
- **To the coach**: `noteSlips` only, tagged `MemorySource.diktat` (at most two ending slips a
  round, so the 20-slip LRU keeps the learner's conversation slips), plus missed headwords as
  vocabulary touches (at most three). Each slip carries the sentence and the blank index, so it
  is a cloze card. Sourced slips stay out of the correction hint (`LearnerMemoryService.correctionHint`).
- **Invariant: Diktat never calls `applyDrillResult`.** A dictation miss is listening evidence, and
  an unstressed -en or -em is close to inaudible in a synthetic voice. Writing `profile.grammar`
  would turn an estimate into earned pyramid fill.
- **Save to the Hören deck**: the sentence's headword when one was missed, else up to three missed
  content words the dictionary knows (never "ist" or "und"). Through `DeckCardAdder.add`, so the
  one-word-or-phrase rule holds (`docs/PHRASES.md`).
- The field has autocorrect and auto-capitals off (they would fix the learner's spelling) and an
  ä ö ü ß strip.

## Stories ▸ Hören (predict, listen, summary, compare)

Every story's listen mode now runs `StoryGistSession`'s phases; the Hören room's Worum geht's? row
opens a story straight into it (`StoryDetailView(initialMode: .listen)`).

1. **Erst raten**: title and topic, a field for German words the learner expects. "Überspringen"
   skips.
2. **Hören with the text hidden** (decided 2026-11-20). "Text zeigen" reveals it early and the
   attempt records `revealedEarly`; so does opening "Vorlesen & mitlesen". The story playing to its
   end (not a stop or a mode switch: `manualStop`) or "Fertig gehört" moves on.
3. **Worum geht's?**: one or two English sentences; skippable.
4. **Vergleichen**: the summary, which guesses came up (`StoryGlossaryHighlighter.hits`: exact,
   lemma, inflection endings, verb stem; compounds never match; a split separable verb is missed),
   and the key points ticked Ja · Teilweise · Nein by the learner. The app computes the score
   (ja + ½ teilweise). Fertig saves a gist `HoerenRound` and credits one item. The transcript
   shows from here on.

- **Key points** (`StudyStory.keyPointsData`, synced as `keyPoints`): 3–4 English points written
  with the story after the questions (`StoryStudyService.makeKeyPoints`, non-fatal). The gate
  wants 2–5 points of 3–20 words in English. Stories made before key points existed get a "Make
  key points" button (needs the tutor) and the English translation as the fallback reference.
- **News report** (`StoryGenre.nachrichten`, appended last): a short radio report, so both DLI
  text types (conversation via Dialog, broadcast) exist.
- **The tutor judge is DEBUG-only.** `judgeSummary` asks for one line per point (`n: ja ; why`),
  parsed by `GistPrompts.parseJudge` (an echoed format line is unreadable, not "ja"), scored by the
  app. Release ships the learner's own ticks until `training/GIST_PROBE.md` has been read and a
  decision made. `-hoeren.debugCannedJudge 1` returns a fixed pattern in the simulator.

## Data, sync, day credit

- `HoerenRound` (kind zahlen | diktat | gist), every field defaulted, items as one JSON blob
  (`HoerenItem`, optional fields per kind). Synced append-only by `HoerenRoundCodec` keyed on
  `roundKey`; a new kind on the generic `KarteiItem` record, so no CloudKit schema deploy.
- `StudyDay.hoerenItems` / `hoerenSeconds`: per-device counters in `StudyDayCodec.counterFields`,
  summed by `SyncCanonicalizer.foldStudyDayTwins`, 1 XP per item (`ExperienceService`), a "Hören"
  slice and day rows in the streak calendar. Items count right or wrong; listening is the work.
- A round is saved once, on finishing or on leaving with at least one answer.

## Hör-Check (roadmap item 11)

Every four weeks, for someone who uses Hören, Today offers a Hör-Check (`HoerenCheckView`): eight
numbers in sentences and three dictated sentences at the learner's level (B1 at most), single pass.
They are ordinary rounds tagged `check:` in `sourceRaw`. Hören ▸ Statistik shows a **Hörprofil**
(numbers and Diktat words right, per level) and the **Hör-Checks** over time. The app names no
listening level: that rule waits for the numbers. DLI's ODA, the roadmap's model, could not be
reached to read, so nothing cites it. `-today.debugHoerCheck 1` offers the check now.

## Debug launch arguments (DEBUG only)

| Argument | Does |
|---|---|
| `-hoeren.debugSeed 1` | A Zahlen and a Diktat round, and a news story with key points (the sim can't run a tutor). Refuses while sync runs. |
| `-hoeren.debugOpen hub\|zahlen\|diktat\|gist\|stats\|speller\|story` | Opens that screen in a sheet. `story` is the seeded story in Hören mode; `speller` plays each kind as digits and as spelled text. |
| `-hoeren.debugVerify 1` | Prints "Hören ALL OK" and the pool sizes, or the failures. |
| `-hoeren.debugCannedJudge 1` | The DEBUG judge answers ja / teilweise / nein in turn without a model. |

## Still open

- Listen to the speller A/B on a device's premium voice; give digits to a kind only if the voice
  reads them right.
- Read `training/GIST_PROBE.md` and decide whether any tutor's judge ships.
- Answering a Diktat with the Pencil ("Read my handwriting" from Schreiben).
- Read `CASL` before citing it in the app.
- Item 11 (listening in the diagnosis) builds on these rounds.
