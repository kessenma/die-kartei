# Kasus · New Exercise & Explainer Ideas

**Status:** eight of the nine shipped (last checked 2026-10-22). This file stays as the
ideation record — the hooks and the reasoning behind each exercise — with a status line
on every idea pointing at what was actually built. Only idea 9 is still unbuilt, and
idea 4 shipped turned around (on the English sentence, as an option grid rather than a
drag-matching board); see its entry.

The exercise framework the shipped ones share is documented in `docs/GRAMMAR_EXERCISES.md`
(the registry, the drill shell, the modules); the case path itself in `docs/KASUS.md`.

**Companion file:** `wireframes.html` in this folder — iPhone-style wireframes of all
nine concepts, drawn with the app's real palette (`GrammarPalette`: Nom graphite,
Akk orange, Dat teal, Gen brown; der blue / die red / das green / plural gold) and
existing components (progress strip, option grid, feedback cards, gender tags).
Open it in a browser.

## Ideas at a glance

| # | Idea | Status | Shipped as |
|---|------|--------|-----------|
| 1 | Pronomen-Brücke | ✅ shipped | `.bridge` · `BridgeModule` — the three-stage ramp intact |
| 2 | Wer handelt? | ✅ shipped, renamed | `.wer` „Wer macht was?“ · `WerModule` |
| 3 | Finde den Fehler | ✅ shipped | `.fehler` · `FehlerModule` |
| 4 | Wer · Wen · Wem · Wessen | ⚠️ turned around | `.frage` / `.englischeFalle` · `FrageModule` — see the entry |
| 5 | Dativ-Verben | ✅ shipped | `.dativVerbs` · `EndingsModule` with a verb pool |
| 6 | Blitzrunde | ✅ shipped | `.blitz` · `EndingsModule`, timed |
| 7 | Coach confusion pairs | ✅ shipped | `KasusConfusion` + `KasusConfusionCard` + the `.pair` drill |
| 8 | Endings-table lenses | ✅ shipped, in full | `CaseEndingsView.Lens` — Formen / Sinn / Takt, Mandarin overlay, „nur der zuckt“ |
| 9 | Kasus in freier Wildbahn | ❌ not built | nothing in the repo; still the heaviest data lift |

The original recommended order was 7 → 8 → 3, and that is roughly how it went: 7 and 8
landed first with zero generated content, then the exercises followed in the phase-6 batch.

**Sibling note:** `ENGLISH_ANCHORS.md` (+ `english-anchors.html`) works idea 4 out in the other
direction: the four anchor questions asked on the **English** sentence, with the pools measured
against the shipped Verstehen items and the English-to-German mismatches made into a second
exercise rather than hidden.

---

## 1 · Die Pronomen-Brücke (pronoun bridge)

**Shipped** as `.bridge` · `Features/Grammar/Drill/BridgeModule.swift`. The three-stage ramp
survived whole: one frame, three picks (English pronoun → German pronoun → article) as a
multi-tap step whose scratch state is the picks so far. Try it with
`-kasus.debugOpen bridge:<topic>`.

**Hook:** English has cases — he/him/his, I/me/my — hidden in pronouns. Nobody says
"I see he." Rounds start on German pronouns (er/ihn/ihm), where intuition is instant,
then swap in articles on the same sentence frames. Three-stage ramp:
**he/him → er/ihn → der/den**. Feedback mnemonic: the "m" on *hi-m* is the same "n"
on *de-n*.

**Reuses:** `KasusOptionGrid`, `KasusFeedback` header, `GenderTag`, `EndingsFrame`.

## 2 · Wer handelt? (minimal pairs)

**Shipped** as `.wer` „Wer macht was? · Only the ending tells“ · `WerModule` in
`ConceptModules.swift`. It lives in the Verstehen section rather than as a standalone
exercise. The hook is enforced, not just intended: `KasusConcept`'s validator rejects an
item where „neither phrase is proven by its form“, so no item can be solved by word order
alone. `-kasus.debugOpen wer:<topic>`.

**Hook:** *Den Hund beißt der Mann* vs. *Der Hund beißt den Mann* — tap who acts.
Comprehension instead of production: case **is** the meaning, and word-order freedom
is what case endings buy. Cross-language framing for Chinese speakers: this is what
把 (bǎ) buys you — role marking that frees word order.

**Reuses:** `KasusProgressStrip`, `KasusFeedback`, `KasusRich` case-color markup.

## 3 · Finde den Fehler (error triage)

**Shipped** as `.fehler` · `Features/Grammar/Drill/FehlerModule.swift`, two taps per item
(find the wrong word, then pick the fix) as drawn. `-kasus.debugOpen fehler:<topic>`.

**Hook:** one word in the sentence has a wrong ending; tap it, then pick the fix.
Detecting errors is a deeper skill than producing answers and transfers to
proofreading and listening. Two taps per item: find, then fix.

**Reuses:** `EndingsQuestion` generation (inject one deliberate slip),
`KasusOptionGrid`, `KasusForms.isRightCaseWrongGender` for plausible errors.
**Best first exercise to build** — the data comes free.

## 4 · Wer · Wen · Wem · Wessen (anchor questions)

**Shipped turned around, and not as a matching board.** The four anchor questions reached
the app through the sibling file `ENGLISH_ANCHORS.md`: `.frage` („Welche Frage?“) and
`.englischeFalle` („Die englische Falle“), one `FrageModule` over two pools, in the
Englisch & Fälle room. Both ask the question about the **English** sentence and answer with
an option grid (`EnglishQuestionGrid`), so neither moves the coach (`coachPolicy: .never`).

What is *not* built is this entry's own mechanic: German phrases dragged onto the four
questions on `MatchingGameView`. A third kind, `.findeFall` („Finde den Fall“ — the question
is given, tap the part that answers it), is registered in `KasusDrillKind` but wired to
`UnbuiltModule`, whose `compose` returns nil: a reserved slot, not a playable round.

**Hook:** drag each phrase to the question it answers — the self-talk version of the
Kasus-Check, for learners to ask themselves while reading. Doubles as a pre-story
warmup.

**Reuses:** `MatchingGameView` drag mechanics, `MatchingTintLegendItem`, case colors.

## 5 · Dativ-Verben (verb valency trainer)

**Shipped** as `.dativVerbs`, played by `EndingsModule` over a Dativ-verb pool and filed as
its own `KasusRoundStep` so the coach gets the sharper signal this entry asked for.
`-kasus.debugOpen dativverben:<topic>`.

**Hook:** the ~15 high-frequency Dativ verbs (helfen, danken, gefallen, gehören,
antworten, folgen…) as a drill family with a group identity ("die Dativ-Bande").
Traps explained: *besuchen* feels like a receiver but takes Akkusativ (the content
bank already flags this).

**Reuses:** `EndingsFrame` (already has helfen/gehören frames). Would add a new
`KasusRound` type so the coach gets a sharper signal.

## 6 · Blitzrunde (60-second speed round)

**Shipped** as `.blitz`, `EndingsModule` with a clock (`GrammarDrillSession.seconds`; nil
means untimed, which is how every other kind runs). Misses queue for the summary as drawn.
`-kasus.debugOpen blitz:<topic>`.

**Hook:** Schnellrunde builds accuracy; this builds speed. No explanations mid-round —
misses queue silently and surface as a review list at the end. Personal-best chasing
for arcade pull.

**Reuses:** `EndingsQuestion.round` (arbitrary count), `KasusOptionGrid`, the
Schnellrunde summary miss list.

## 7 · Coach: Verwechslungs-Paare (confusion matrix) ⭐ top pick

**Shipped** — `Services/Grammar/Kasus/KasusConfusion.swift` does the group-by,
`KasusConfusionCard` is the hero card (on the Grammar hub and in Coach notes), and the
prescribed drill is the `.pair` kind. The synthetic-test plan held: the seeder grew a
`-kasus.debugConfusion` path as this entry suggested.

**Hook:** every round already logs case + genus per answer (`KasusItemResult`). A
group-by turns "Dativ needs work" into "you confuse *dem* and *den* 3× more than
anything else," with a targeted two-option drill button. Also upgrades the existing
gender-slip ("Fast!") signal into advice ("a gender round would help more than
another case round").

**Why first:** zero new content, zero LLM data. Testing is fully synthetic — build
`KasusItemResult` arrays with a known bias via the existing
`KasusRecordingTests.item(_:_:_:right:slip:)` helper and assert the analysis surfaces
the right pair. Extend `KasusDebugSeeder` with a `-kasus.debugConfusion` flag to see
the card live in the simulator.

**Reuses:** `KasusItemResult` data, `LearnerMemoryService.shakyFocuses`, the 🔥
flame convention from Today/Pyramid.

## 8 · Endings table: two new lenses

**Shipped in full** — `CaseEndingsView.Lens` is Formen · Sinn · Takt. Both hooks landed,
including the parts that were optional: the Mandarin overlay is an opt-in toggle
(`@AppStorage("kasus.tableChinese")`, never the default) and the honest headline is in the
copy as „Nur der zuckt · Only der flinches“.

**Hooks:**
- **Particle lens** — each cell gets a plain-English meaning label (the / acts-on /
  to / of). Optional Chinese overlay for learners who read Mandarin: 把 bǎ = acts-on,
  给 gěi = to, 的 de = of — German endings are these particles glued onto the article.
  Shipped as opt-in overlay or behind a disclosure, never the default.
- **Rhythm lens** — the table as four chantable beats
  (*der·die·das·die / den·die·das·die / dem·der·dem·den / des·der·des·der*),
  optional haptic tap per beat; rese·nese·mrmn·srsr with the sound attached.
- Honest headline: **"only der flinches"** — 75% of Akkusativ is identical to
  Nominativ.

**Reuses:** `CaseEndingsTable` with a third cell line, `codeText` coloring,
`sensoryFeedback` haptics. Pure UI — validated by previews across the 4 themes.

## 9 · Kasus in freier Wildbahn (case in the wild)

**Not built.** Nothing in the repo references it. The reason this entry gave is still the
reason: it needs case-tagged phrase segmentation over the learner's own stories and chats,
which is the only idea of the nine whose content cannot be generated from the
`GrammarCase` table or an authored list. The eight that shipped are the deterministic ones.

**Hook:** sentences from the learner's own story rounds and chats, noun phrases
pre-highlighted in case colors; tap any phrase to see which Kasus-Check question
decided it. Zero new content authoring — but needs case-tagged phrase segmentation,
the heaviest data/validation lift of the nine. Defer until 7/8/3 land.

**Reuses:** `KasusRich` markup, `StoryGlossaryHighlighter`'s highlight approach,
`KasusCheckSheet` steps.

---

## Test-data strategy

- Prefer **rule-generated content** (from the `GrammarCase` table, like
  `CaseEndingsView`'s drill) over authored content wherever possible.
- Prefer **synthetic analytics input** (constructed `KasusItemResult` arrays in
  tests) over recorded fixtures — the test constructs the ground truth.
- When authored sentences are needed, keep them to **hand-reviewable lists of
  10–20 items** (the existing `EndingsFrame.all` is the pattern).
- LLM-generated data (the previous Claude Sonnet workflow) only for idea 9, and only
  after the deterministic pieces ship.
- Debug/simulator visibility: extend `KasusDebugSeeder` + `-kasus.debugOpen` launch
  arguments rather than screenshotting by hand.

The strategy held. Every shipped exercise draws its items from the `GrammarCase` table,
an authored hand-reviewable list, or the existing `EndingsQuestion` generator; no LLM ran
for ideas 1–8. Idea 9 remains the only one that would need generated content.

## What the build changed about these ideas

- **Ideas 1–6 did not each become an activity.** They became kinds in one registry
  (`KasusDrillKind` + `KasusRoundStep.meta`) played by a shared drill shell with a module
  per interaction — so several ideas share a module (`.quick`, `.build`, `.blitz`, `.pair`
  and `.dativVerbs` are all `EndingsModule`) and `ActivityRouter` gained one route,
  `.grammarDrill`, rather than six. `docs/GRAMMAR_EXERCISES.md` is the reference.
- **Ideas 7 and 8 attached to existing screens**, as this file recommended: the coach card
  to the hub and Coach notes, the lenses to `CaseEndingsView`.
- **Idea 4 moved to its sibling file.** `ENGLISH_ANCHORS.md` won the argument about which
  direction to ask the anchor questions in, and that is what shipped.
- **The 3D der/die/das assets** went to the endings table and `Bau das Wort` (`.build`)
  instead of to idea 4's tiles.
