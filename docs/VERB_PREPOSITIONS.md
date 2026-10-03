# Verben mit Präpositionen

42 verb + preposition pairs from Kyle's class sheet, studied for a class essay and quiz. Each pair
has a corrected entry, an example sentence and a 3D scene (39 scenes; three pairs share one).

- **Data:** `Resources/verb_prepositions.json`, decoded by `VerbPreposition.swift` and
  `VerbPrepositionService`. The Blender rig reads the same file.
- **Scenes:** `Resources/verb3d-*.usdz`, plus stills and `verb3d-manifest.json`, all written by
  `tools/blender/verben.py --ship`.
- **Background:** the design story and the props and gestures are in `docs/PREPOSITION_3D.md`,
  "Verben mit Präpositionen — scene backlog".

## Status (2026-10-03)

Kyle took every recommendation below. Shipped on main (uncommitted), sim-verified:

- **The hub's two tracks.** A segmented switch at the top of the Präpositionen hub: „Ort & Zeit“
  is the old hub, „Verb + Präposition“ the new one. The track is remembered
  (`prepositions.track`), and each track keeps its own progress and tricky count.
- **Verb-Karten** (`VerbPrepositionCardsView`):
  - Front: „warten ___“, with the scene frozen and the object uncolored.
  - Back: „auf + Akkusativ“ and the example with its object phrase in the case color, while the
    scene tints and plays.
  - Chips filter by case or by preposition. A preposition chip shows the bridge line: „über on
    its own: Wechsel… In these 8 pairs the verb fixes it: always Akkusativ.“
- **Practice:**
  - **Akkusativ oder Dativ?** reuses the Kasus drill with the pair's scene.
  - **Lückentext:** preposition + article in one pick, four choices.
  - **Die Falle:** 18 authored place-vs-pair items.
  - **Paare finden:** matching.
- **Recording:**
  - `GrammarFocus.verbenPraepositionen` (B1) is added to every switch, and routes to the hub.
  - Stats go in `PrepositionStat` / `PrepositionRound` under `verb:` keys and „Verben“ topics.
- **Tests:** `VerbPrepositionTests` covers the content, the scenes and stills in the bundle, the
  fill-in rounds, and recording apart from the 28 prepositions.
- **Asset budget:** 10 MB of USDZ (the dog decimated to a quarter) plus 7.7 MB of stills.

Still open:
- Check on device that the question side shows the key pose. On the sim it does: clips stopped,
  the pose frozen, and they play on the reveal.
- Smaller stills, if the 7.7 MB matters.
- The SRS deck.
- The Kasus lexicon.

This doc plans how the set joins the app's preposition experience, and how that experience
changes so the two kinds of preposition stop blurring together.

## The problem this solves

The preposition hub teaches one rule: the preposition decides the case. Fixed ones always take
one case, and the two-way ones take Akkusativ for Wohin? and Dativ for Wo?. That rule is right for
place and time, and wrong for verb pairs. In *warten auf den Bus* the verb fixes the case, nothing
moves, and it is still Akkusativ. A learner drilled on Wo/Wohin will get it wrong. Today the app
mentions verb pairs in only four places: one Kasus story target, one KasusCheckSheet line, one
fill-in item and two placement items.

So the goal is two things:
1. Add the 42 pairs.
2. Make the split visible: **„Ort & Zeit“** (the preposition decides) and **„Verb + Präposition“**
   (the verb decides), with a bridge that puts one preposition's two lives side by side.

## What already exists (so we reuse it)

| Need | Already in the app | Notes |
|---|---|---|
| Reference cards | `PrepositionCardsView`: one scene canvas above a flippable deck | Same shape works for verbs |
| Case drill | `PrepositionCaseGameView` + `PrepositionService.session` / `recordRound` | Its round model is `[PrepositionCase]`-typed |
| Fill-in-the-blank | `GrammarMultipleChoiceView` + `grammar_exercises.json` categories | A category can be built in memory from verb data |
| Matching | `MatchingSession` via `PrepositionService.matchingSession` | Matching records no grammar skill today |
| Per-word stats | `PrepositionStat` / `PrepositionRound` (@Model, iCloud-synced) | `key` is a free string |
| Skill + coaching | `GrammarFocus`, `LearnerMemoryService.applyDrillResult`, `GrammarRoute` | A new focus touches about 10 exhaustive switches |
| SRS deck | Perfekt verbs: `past_tense_verbs.json` → `DeckStore.pastTenseSession` | Built-in non-noun deck precedent |
| Kasus | `KasusReason.prepObject` exists, but no `KasusFrameKind` produces it | KASUS.md lists unchecked prepositional objects as a known gap |
| Scene runtime | `PrepositionSceneView`: tints the first `ModelEntity` under `subject`, plays clips on the reveal | **Goes live only if the manifest gives `akkOffset ≠ 0` or a `motion`**. A baked-only scene falls back to its still |

## The experience

### 1. The hub splits in two

The Präpositionen hub gets two clearly named tracks at the top, each with its own
cards / drill / matching:

- **Ort & Zeit · Place and time.** Everything that exists today, unchanged. The case comes from
  the preposition.
- **Verb + Präposition · Verbs with prepositions.** The new set. The case comes from the verb.

Under both sits a **bridge: „Eine Präposition, zwei Leben“** (one preposition, two lives). Pick
*auf* and see its place meaning (Wechsel, the existing scene) next to its six verb pairs (all
Akkusativ). Pick *an* and see the trap the other way: *denken an* is Akkusativ, *arbeiten an*
and *zweifeln an* are Dativ. All 12 prepositions the verbs use already exist in
`prepositions.json`, so the bridge needs no new content.

### 2. Activities for the verb track

| Activity | What it asks | Reuses |
|---|---|---|
| **Verb-Karten** (reference deck) | Front: the verb with a gap („warten ___“), the scene frozen on its key pose with the object uncolored. Back: „auf + Akkusativ“, meaning, the example with the object phrase highlighted, the note; the scene colors and plays | `PrepositionCardsView`'s canvas-above-deck layout |
| **Verb-Drill** | Two taps per question: which preposition (3–4 plausible ones), then which case. Never a single-case round: every round mixes Akk and Dat verbs (22 / 20 in the data) | `PrepositionCaseGameView`'s reveal and summary pattern; new session type |
| **Die Falle · The trap** | Akk or Dat? Sentences that mix one preposition's two lives: „Das Buch liegt **auf dem** Tisch“ next to „Ich warte **auf den** Bus“. The reveal says which rule decided it | Wechsel examples from `prepositions.json` + verb examples |
| **Lückentext** | „Der Mann wartet ______ Bus.“ → *auf den* | `GrammarMultipleChoiceView`, with a `GrammarCategory` built in memory |
| **Paare finden** | Match verb ↔ preposition + case | `MatchingSession` |
| **Wiederholen** (later) | A built-in SRS deck of the 42 pairs | The Perfekt-verbs deck pattern |

The trap round is the enhancement that separates the prepositions. It is the one activity that
only works because both kinds sit side by side.

## Data

`Resources/verb_prepositions.json` (formerly the prototype's `tools/blender/verben.json`), with a
model (`VerbPreposition`) and a service (`VerbPrepositionService`) next to `PrepositionService`.
Fields added on the way:

- `gap` per example: the text the Lückentext removes (`"auf den"`, `"vom"`, `"beim"`,
  `"zu den großen"`), authored rather than derived. Contractions and plural adjectives make
  derivation unreliable.
- `distractors`: 2–3 prepositions a learner plausibly confuses with the right one (for *warten
  auf*: für, an).
- `level`: A2 or B1, so rounds can follow the learner's declared level. The placement bank
  already files verb + preposition under B1.
- `reflexive` / `separable` stay derivable from `verb` and the note. No new fields.

Unit tests validate the file, so content mistakes fail CI instead of a round:
- every verb's preposition exists in `prepositions.json`;
- the case is akkusativ or dativ;
- each example contains its `object` phrase and its `gap`;
- every scene id has a manifest entry and assets;
- no distractor equals the right preposition.

## Scenes in the app

- **Runtime:** manifest entries for verb scenes carry `"baked": true`. `PrepositionScene.Pose.animates` treats
  that as live, and `PrepositionSceneView` skips the runtime idle bob for them. Everything else (tint
  under `subject`, clips only on the reveal, one canvas per screen) works as it is.
- **Question side:** clips are stopped, so the scene must sit on frame 0, the key pose. The export
  sets frame 1 before writing, but whether RealityKit shows the default value or the first
  TimeSample is unverified. Check it on device before relying on it.
- **Size:** the 39 USDZs are 24 MB today, mostly the dog (≈0.85 MB per copy, in 16 scenes).
  - A decimated dog for verb scenes, about 4k faces, should bring the set under 10 MB.
  - Stills (neutral + resolved) are the LightweightGraphics fallback, at roughly 39 × 2 PNGs.
  - Measure the app-size delta before shipping. Resources is 66 MB now.
- **Tooling:** `verben.py --ship` writes `verb3d-*.usdz`, the stills and a manifest block into
  `Resources/`, mirroring `render_all.sh`, and gates on the export check.

## Recording and coaching

- **Focus:** a new `GrammarFocus.verbenPraepositionen` (B1, "Verben mit Präpositionen"). A
  learner can be solid on *mit + Dativ* and lost on *warten auf*, and one shared focus would
  blur that.
  - Add it to every exhaustive switch (labels, explanation, steeringHint, introducedAt).
  - `GrammarRoute` maps it to the hub's verb track.
  - The pyramid files it under Strukturen, the default area.
- **Stats:** reuse `PrepositionStat` / `PrepositionRound`, with keys prefixed `verb:` and the
  topic prefixed „Verben:“. That means no new SwiftData model and no new iCloud codec. Tests then
  check that the Fundament mastery count (28 core prepositions) and `trickyPrepositions` ignore
  `verb:` keys.
- **Verlauf:** verb rounds show under the Präpositionen filter, labelled by topic.
- **Matching** keeps recording no skill, as today.
- **Kasus:** the verb list becomes a lexicon for the validator, so a prepositional object
  after a known verb is checked. That closes the known gap in KASUS.md ("wartet auf unserem
  Freund").

## Phases

| # | Work | Done when |
|---|---|---|
| 0 | This plan, and Kyle's calls on the open decisions below | Decisions recorded here |
| 1 | Data into `Resources/`, `VerbPreposition` + service, validation tests | Tests green |
| 2 | Scenes into the app: decimated dog, stills, `baked` manifest flag, `--ship` | Size delta measured; question pose and reveal verified on device |
| 3 | Hub split + Verb-Karten + the bridge | Both tracks reachable; cards flip with live scenes |
| 4 | Verb-Drill, Die Falle, Lückentext, Paare finden; recording + focus + Verlauf | Rounds record; coach reacts to the new focus |
| 5 | SRS deck, Today hook, Kasus lexicon | Due cards appear in review |
| 6 | What's New, docs, debug launch args | `whats_new.py check` passes |

## Decisions (Kyle took all four recommendations, 2026-10-03)

1. **Hub shape.** Recommended: two tracks inside the one Präpositionen hub, plus the bridge.
   The alternative is a separate Werkzeuge tile for verbs, which keeps the hub as it is but
   never puts the two lives side by side.
2. **Stats storage.** Recommended: reuse `PrepositionStat` with `verb:` keys, which needs no
   sync work. The alternative is a new synced model: cleaner, and one more codec.
3. **First ship.** Recommended: Phases 1–4 (cards and drills), with the SRS deck after.
4. **Assets.** Recommended: all 39 scenes with a ≤10 MB budget after decimation. The
   alternative is a subset that ships first.
