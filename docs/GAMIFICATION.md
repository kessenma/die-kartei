# Gamification — XP, Tagesziel, Abzeichen & die Lernpyramide

The reward loop on top of the learner-memory foundation (see `LEARNER_MEMORY.md`). One score
across every activity, a daily goal, celebrations, badges, and a 3D learning-path pyramid.
Design north stars: playful but tasteful; **growth, not vanity** (points are earned by *doing* —
reviewing due cards, finishing drills — never by opening the app); and **zero SwiftData schema** —
everything derives from `StudyDay` / `QuizResult` / `LearnerProfile` / the game stats models, with
prefs + celebration dedupe in UserDefaults, so the destructive-reset store is never touched.

Status legend: ✅ done · 🚧 in progress · ⬜ not started

---

## Architecture

```
 StudyDay / QuizResult / game stats / LearnerProfile   (already recorded, unchanged)
        │
        ├─ ExperienceService      XP per day → lifetime XP → LearnerLevel (rank curve)
        ├─ PyramidService         mastery signals → 6 layer fills (0…1)
        └─ AchievementService     badge rules over an AchievementSnapshot
        │
 CelebrationCenter (shared @Observable)  ── dedupe: UserDefaults "celebration.*"
        │
 ContentView.overlay { CelebrationOverlayHost() }   (above every tab)
```

- **Settings:** `MLXModelManager` flags — `gamificationEnabled` (master, default on),
  `dailyGoalMinutes` (5/10/15/20/30, default 10), `gamificationCelebrationsEnabled`,
  `gamificationBadgesEnabled`, `gamificationPyramidEnabled`. Screen:
  `Features/Settings/GamificationSettingsView.swift`, row in Settings ▸ App.
- **Home (For You):** `Features/Home/LevelCardSection.swift` — level card, Tagesziel ring,
  pyramid teaser. `HomeHubView` fires `CelebrationCenter.evaluate(studyDays:)` on appear and on
  log changes.
- **Fortschritt:** `Features/Progress/ProgressView.swift` — level detail, badge grid (evaluates
  badges on appear), pyramid entry. Pushed from the Home level card.
- **Pyramide:** `Features/Progress/PyramidView.swift` — the live 3D stack + tappable layers that
  route into each layer's activity.

## Phase 1 — XP, level & daily goal  ✅

- ✅ `Services/ExperienceService.swift` — XP weights (1/card, 2/grammar item, 5/story question,
  10/conversation, 1/study minute), all summed from `StudyDay`. Daily-goal helpers.
- ✅ `Models/LearnerLevel.swift` — quadratic curve (level n threshold `50·(n−1)·n`: L2 = 100,
  L3 = 300, L5 = 1 000, L10 = 4 500) + nine German ranks (Neuling → Großmeister) with per-rank
  tint.
- ✅ `Features/Home/LevelCardSection.swift` — level card (+ progress bar, "+N heute"),
  `DailyGoalRing` (minutes vs. goal, closes into a check), pyramid teaser row.

## Phase 2 — Celebrations  ✅

- ✅ `Services/CelebrationCenter.swift` — one shared observable; `ContentView` hosts the overlay
  above all tabs. Triggers: daily goal (once/day), level up (seeded silently on first run),
  streak milestones (7/14/30/50/100/200/365, once each), badge earned, pyramid layer complete.
- ✅ `Features/Shared/CelebrationOverlay.swift` — dim scrim, Bauhaus confetti rain (square /
  circle / triangle — the preposition scenes' shape vocabulary), German-headline card,
  auto-dismiss ~3 s, tap to dismiss, Reduce Motion keeps the card and skips the rain.

## Phase 3 — Abzeichen  ✅

- ✅ `Models/Achievement.swift` + `Services/AchievementService.swift` — 16 badges as pure rules
  over an `AchievementSnapshot` (streaks 7/30/100, library 100/500/1000 words, 500 reviews,
  perfect matching/article/preposition rounds, story first/perfect, 10 chats, half of grammar
  Solid, pyramid foundation complete). Earned dates in one UserDefaults dict; first-ever
  evaluation seeds silently (no overdue confetti ambush).
- ✅ Badge grid on Fortschritt — earned in accent color, unearned grey; tap an earned badge for
  its date.

## Phase 4 — Die Lernpyramide  ✅ code / ⬜ Blender assets

- ✅ `Models/PyramidLayer.swift` + `Services/PyramidService.swift` — six layers, bottom → top:
  1. **Fundament** — core prepositions mastered (`PrepositionStat`: graduated or clean ×3)
  2. **Wortschatz A1** — A1 Goethe words *learned* (see Phase 6), matched against the bundled list
  3. **Geschichten A1** — 3 distinct A1 stories passed at ≥ 80 % (`StoryQuizAttempt`)
  4. **Grammatik-Kern** — Akkusativ / Dativ / Artikel / Präpositionen below the shaky threshold
     (`LearnerProfile.grammar`)
  5. **Vertiefung A2** — A2 words learned (goal 200) + A2 stories (goal 3), half each
  6. **Spitze** — conversations *held well* (see Phase 7), falling back to the plain count until
     there are summaries to judge
- ✅ `PyramidView` — live canvas + overall % + layer rows (fill bar, "was noch fehlt" detail,
  checkmark when complete) routing to Prepositionen / Goethe A1·A2 / Stories / Grammar /
  Conversation — the same destinations as the Activity hub.
- ✅ `PyramidSceneView` — procedural RealityKit stack (six charcoal slabs + capstone ball),
  same camera/light rig as `PrepositionSceneView`; ghost layers at low opacity, partial layers
  lerp, the active (lowest unfinished) layer breathes; turntable rotation paused off-screen,
  frozen under Reduce Motion. The ball caps the peak when all six stand.
- ✅ `PyramidGlyph` — the flat trapezoid-stack rendering for rows/teasers (the "stills in
  lists" rule).
- ⬜ **Blender renders** — `tools/blender/pyramid_render.py` carries the asset spec (naming
  `pyramid-layer-<n>-<state>`, charcoal + per-layer accent, `dim` look). When the USDZ/PNGs land,
  they swap into `PyramidSceneView` under the same canvas; the procedural stack is the fallback.

## Phase 5 — Settings  ✅

- ✅ `GamificationSettingsView` (Settings ▸ App ▸ Gamification): master toggle, goal picker,
  celebrations / badges / pyramid switches. Master off = Home renders exactly as before; data
  accrues silently either way.

## Phase 6 — Die Einstufung: the pyramid as an estimate, not a stopwatch  ✅

The pyramid's six layers all read real mastery signals, but every one of those signals was
**longitudinal**: 21 days of SRS spacing, three clean game rounds, a grammar focus that only exists
in the profile once it's been drilled. That measures *time in the app*, not German. A B2 speaker who
already knew all 585 A1 words still started at 0 % and got there barely faster than a beginner.

- ✅ **Two-channel fill.** `PyramidLayerState` carries `earnedFill` (proven here) and
  `provisionalFill` (credited by the placement estimate). `fill` is their clamped sum for the bars;
  **`isComplete` reads `earnedFill` alone**, so celebrations and Abzeichen can never fire for
  answering a quiz. Solid = proven, dashed outline = estimated, in both `PyramidGlyph` and the
  RealityKit stack (opacity from total, colour from earned — present but drained).
- ✅ **"Learned" widened past SRS maturity** (`PyramidService.learnedWords`): `interval ≥ 21d`
  **or** `repetitions ≥ 3` **or** graduated by the article/matching games. `repetitions` already
  resets on a lapse, so no separate `lapses == 0` test — that would wrongly exclude a word forgotten
  once and relearned.
- ✅ **`Services/PlacementService.swift` + `PlacementSession` + `Features/Onboarding/PlacementQuizView.swift`**
  — a ~29-answer, ~3-minute, fully offline probe (it must run before any model is downloaded):
  two A2 grammar anchors, a vocabulary staircase over the Goethe lists, gender,
  case-after-preposition, a second staircase over the authored grammar bank
  (`placement_grammar.json`, A1–B2), and a three-gap cloze finale that confirms or demotes the
  estimate. No right/wrong feedback between items or on the finale: it's a measurement, not a
  lesson. Always offers "I'm starting from zero", which credits nothing. B2 is reachable on
  grammar evidence only (held B1 vocab + held B2 grammar + confirmed cloze); vocabulary evidence
  still stops at the B1 list.
- ✅ **Cutoffs set by simulation, not by feel.** 4 000 simulated learners per profile through the
  real staircases and scorer: beginner classified correctly 100 %, A1 84 %, A2 76 %, B1 74 %,
  B2 77 %, every error one level away. Two bugs the harness caught that review would not have:
  uncorrected guessing plus Laplace smoothing credited a *true beginner* 210 of 585 A1 words; and
  applying the conservative credit estimator to *classification* made a true B1 read as A1 83 % of
  the time. Credit and classification are computed separately — raw rates classify, guess-
  corrected and block-shrunk figures credit. A narrow vocab miss (raw ≥ 50 %) is rescued when the
  grammar staircase held that level, the way telc pools Sprachbausteine into the written total.
- ✅ **Credit ceilings near 76 %** by construction (the shrinkage prior). Nobody can place their way
  to a finished layer; the last quarter is always earned. Kept deliberately.
- ✅ **Provisional credit only ever shrinks.** `provisional = max(0, target − earned − refuted)`, so
  an item is never counted twice, and words the app has watched the learner miss
  (`PyramidService.refutedWords`) are subtracted back out.
- ✅ **Placement never writes to `LearnerProfile`.** The coach's briefing stays measured-in-app-only;
  `PyramidService` combines the two sources at read time. Placement *does* set `chatLevelRaw` /
  `storyLevelRaw`, which previously defaulted to a hardcoded A2 for everyone.
- ✅ Pyramid credit capped at B1 — the bundled Goethe lists stop there. The *estimate* can read B2
  (grammar staircase + cloze), which sets chat/story levels; `vocabKnown` never gains a B2 key.
- ✅ Retake / remove from the Lernpyramide and Settings ▸ Gamification. Storage is a Codable blob in
  UserDefaults (`placement.result`) — **no SwiftData schema**, per the rule at the top of this doc.

## Phase 7 — Spitze on quality, not count  ✅

- ✅ `Services/ConversationQualityService.swift` — the peak counted finished chats, which rewards
  showing up: twenty abandoned two-turn sessions would have crowned the pyramid. It now counts
  conversations **held well** (at least 4 turns, corrections-per-turn at or below the bar), from
  `ConversationSummary`. Production is the one thing no placement quiz can shortcut, which is what
  makes it the honest summit.
- ✅ `Features/Progress/ConversationQualityView.swift` (Fortschritt ▸ Gespräche) — the real
  distribution of correction density plus how many conversations clear each candidate bar.
  **`qualityDensityBar` is provisional**: unlike the placement cutoffs it could not be simulated,
  because it depends on how the coach model actually corrects real speech. Settle it against this
  screen's numbers; it's one constant.
- ✅ Falls back to the old count while there are no summaries to judge, so a learner mid-way through
  the previous rule doesn't watch their peak empty out.

## Decisions log

- **Derived, not stored.** XP/level/badges/pyramid all read existing records; only prefs,
  celebration dedupe keys, and badge earned-dates live in UserDefaults. No schema change → the
  destructive-reset store stays safe.
- **First-run seeding.** Level and badges record their current state silently the first time, so
  a learner with history gets *future* wins celebrated, not a backlog.
- **Bilingual by rule (2026-08-12).** The app teaches German to English speakers, so a German-only
  reward reads as noise to a beginner. German terms keep the identity (they're also a learning
  moment), but every one carries a visible English gloss: titles render "Deutsch · English",
  dynamic status lines ("0 of 10 minutes today") are English-primary, badge cells show the German
  name over the English description, and celebration cards keep a German headline with an English
  subtitle.
- **One live canvas.** The 3D pyramid exists only on its own screen; Home/Fortschritt get the
  flat glyph — the same rule the preposition scenes follow.
- **Estimated is not earned (2026-08-14).** The pyramid reports two numbers and never merges them:
  "built" always means proven. `isComplete`, the Abzeichen rules and every celebration read
  `earnedFill` only. An estimate is a starting point, not an achievement — the moment a quiz can
  earn confetti, the pyramid stops being a picture of what you know.
- **Measure before gating (2026-08-14).** Every numeric cutoff in placement was chosen from 4 000
  simulated learners per profile, not intuition — and the simulation caught two real bugs before a
  line of UI existed. The one bar that couldn't be simulated (conversation correction density) ships
  provisional with a readout attached rather than pretending to be settled.

## Verification status

- ✅ Builds clean on the iPhone 17 simulator (iOS 26.5), zero warnings in the new files
  (2026-08-11). The DerivedData had to be cleared once for a stale `.pcm` cache — unrelated to
  these changes.
- ✅ Home renders the Fortschritt section on a fresh install (Level 1 · Neuling, ring 0/10,
  pyramid 0 %) — screenshot-verified on the simulator.
- ⬜ Not yet driven at runtime: Fortschritt + Pyramide screens (queries, RealityKit canvas) and
  the celebration triggers. Verify on device: review cards → "+N heute" and the ring move;
  cross the daily goal → confetti exactly once; level-up at a boundary; Fortschritt badge grid
  fills; pyramid canvas rotates and layer rows match real stats; layer complete celebrates once;
  Settings ▸ Gamification off → Home renders exactly as before.

### Placement (Phases 6–7), verified on the simulator 2026-08-14

The probe is deliberately offline, so unlike most of this app **it is simulator-testable**.

- ✅ Fresh install → the placement sheet presents on first launch and renders correctly. It appeared
  *without* the hero intro, confirming it doesn't inherit the `DeviceCapability.canRunHero` gate.
- ✅ Seeded as B1 (`-placement.debugLevel B1`, a DEBUG-only launch argument, since the simulator
  can't tap through 23 questions) → Home reads **"4 % built · 33 % estimated"** and the glyph draws
  its dashed outlines. The 33 % matches a hand-calculation of the credit math exactly.
- ✅ Reseeded as `beginner` → **"4 % built" byte-identical, "33 % estimated" gone**, outlines
  dropped. That is the channel-independence proof: changing the estimate leaves everything proven
  untouched, and `declaredBeginner` credits nothing.
- ✅ No celebration fired on either seeding, and no layer reported complete.
- ⬜ Still needs a device: tapping through the real quiz end to end, ghost → solid conversion after a
  drill (total fill must not jump — earned should *replace* provisional), and the Gespräche readout
  against real conversation history (which is what settles `qualityDensityBar`).
