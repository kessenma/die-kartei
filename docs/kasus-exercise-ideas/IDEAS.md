# Kasus · New Exercise & Explainer Ideas

**Status:** ideation only — no code yet. Two other agents are currently working on
(1) 3D der/die/das assets + lesson visuals, and (2) the explainer sections of
`GrammarHubView.swift` + grammar navigation. These ideas should be reconciled with
that work before anything is built.

**Companion file:** `wireframes.html` in this folder — iPhone-style wireframes of all
nine concepts, drawn with the app's real palette (`GrammarPalette`: Nom graphite,
Akk orange, Dat teal, Gen brown; der blue / die red / das green / plural gold) and
existing components (progress strip, option grid, feedback cards, gender tags).
Open it in a browser.

## Ideas at a glance

| # | Idea | Kind | New content data needed | Test strategy |
|---|------|------|------------------------|---------------|
| 1 | Pronomen-Brücke | Exercise | ~15 hand-written frames | Rule-generated, unit tests on generator |
| 2 | Wer handelt? | Exercise | ~15 hand-written minimal pairs | Hand-checked list |
| 3 | Finde den Fehler | Exercise | none (reuses `EndingsQuestion`, injects a slip) | Existing generator tests |
| 4 | Wer · Wen · Wem · Wessen | Matching | ~20 phrases, from `GrammarCase.article()` | Programmatic + one hand check |
| 5 | Dativ-Verben | Exercise | ~15 verbs (bank already has the concept) | New `KasusRound` type, synthetic items |
| 6 | Blitzrunde | Exercise variant | none (reuses `EndingsQuestion.round`) | Existing generator tests |
| 7 | Coach confusion pairs | Analytics | **none** — pure analysis of `KasusItemResult` | Synthetic item arrays (below) |
| 8 | Endings-table lenses | Explainer UI | none — presentation of existing table | Previews across 4 themes |
| 9 | Kasus in freier Wildbahn | Ambient review | case-tagged phrases from real stories | Defer; heaviest data need |

**Recommended order:** 7 → 8 → 3. Two shipped improvements with zero LLM data
generation, then one exercise whose content comes free from the existing generator.

---

## 1 · Die Pronomen-Brücke (pronoun bridge)

**Hook:** English has cases — he/him/his, I/me/my — hidden in pronouns. Nobody says
"I see he." Rounds start on German pronouns (er/ihn/ihm), where intuition is instant,
then swap in articles on the same sentence frames. Three-stage ramp:
**he/him → er/ihn → der/den**. Feedback mnemonic: the "m" on *hi-m* is the same "n"
on *de-n*.

**Reuses:** `KasusOptionGrid`, `KasusFeedback` header, `GenderTag`, `EndingsFrame`.

## 2 · Wer handelt? (minimal pairs)

**Hook:** *Den Hund beißt der Mann* vs. *Der Hund beißt den Mann* — tap who acts.
Comprehension instead of production: case **is** the meaning, and word-order freedom
is what case endings buy. Cross-language framing for Chinese speakers: this is what
把 (bǎ) buys you — role marking that frees word order.

**Reuses:** `KasusProgressStrip`, `KasusFeedback`, `KasusRich` case-color markup.

## 3 · Finde den Fehler (error triage)

**Hook:** one word in the sentence has a wrong ending; tap it, then pick the fix.
Detecting errors is a deeper skill than producing answers and transfers to
proofreading and listening. Two taps per item: find, then fix.

**Reuses:** `EndingsQuestion` generation (inject one deliberate slip),
`KasusOptionGrid`, `KasusForms.isRightCaseWrongGender` for plausible errors.
**Best first exercise to build** — the data comes free.

## 4 · Wer · Wen · Wem · Wessen (anchor questions)

**Hook:** drag each phrase to the question it answers — the self-talk version of the
Kasus-Check, for learners to ask themselves while reading. Doubles as a pre-story
warmup.

**Reuses:** `MatchingGameView` drag mechanics, `MatchingTintLegendItem`, case colors.

## 5 · Dativ-Verben (verb valency trainer)

**Hook:** the ~15 high-frequency Dativ verbs (helfen, danken, gefallen, gehören,
antworten, folgen…) as a drill family with a group identity ("die Dativ-Bande").
Traps explained: *besuchen* feels like a receiver but takes Akkusativ (the content
bank already flags this).

**Reuses:** `EndingsFrame` (already has helfen/gehören frames). Would add a new
`KasusRound` type so the coach gets a sharper signal.

## 6 · Blitzrunde (60-second speed round)

**Hook:** Schnellrunde builds accuracy; this builds speed. No explanations mid-round —
misses queue silently and surface as a review list at the end. Personal-best chasing
for arcade pull.

**Reuses:** `EndingsQuestion.round` (arbitrary count), `KasusOptionGrid`, the
Schnellrunde summary miss list.

## 7 · Coach: Verwechslungs-Paare (confusion matrix) ⭐ top pick

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

## Coordination notes for the other agents

- If grammar navigation is being restructured, ideas 7 and 8 attach to existing
  screens (Coach notes / `CaseEndingsView`) rather than adding new top-level sections.
- Ideas 1–6 would register new activities in `ActivityRouter` alongside
  `.kasusStory` / `.kasusConcept` / `.caseEndings` — flag route additions early to
  avoid merge collisions with the navigation work.
- The 3D der/die/das assets could surface in idea 4's matching tiles and idea 2's
  minimal pairs (animal/person glyphs for who's acting).
