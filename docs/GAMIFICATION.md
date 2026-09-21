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
  estimate. Each answer is marked right or wrong for half a second (1.1 s on a miss, which also
  shows the right choice) before the next item, and an "Answers on / Answers off" switch at the
  top of every question turns that off for the purer measurement — no teaching moment mid-check
  and no tuning your answers as you go. The switch is display only: `PlacementSession` and
  `PlacementService` never read it, so the same answers score the same run either way. Always
  offers "I'm starting from zero", which credits nothing. B2 is reachable on
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
- ✅ **Placement never writes `LearnerProfile.grammar`, and never writes anything automatically.**
  (Amended 2026-08-16, when the answer review added an opt-in hand-off — see Phase 8.) The pyramid's
  earned channel and the coach's grammar picture stay measured-in-app-only; `PyramidService`
  combines the two sources at read time. Placement *does* set `chatLevelRaw` / `storyLevelRaw`,
  which previously defaulted to a hardcoded A2 for everyone.

  What the rule protects, stated precisely so it survives the next edit: `PyramidService` reads
  `profile.grammar` and **nothing else** from the profile, and it reads it twice — a focus below
  `shakyThreshold` counts toward *earned* fill, and a focus merely *present* suppresses that
  focus's *provisional* credit. So a grammar write from a quiz would both complete a layer it
  didn't earn and shrink the outline it just produced. `.vocab` and `.slips` touch neither number.
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

## Phase 8 — The check keeps its answers (review + export + opt-in hand-off)  ✅

The probe asked 29 questions and kept eleven aggregate numbers. `PlacementSession.answers` held every
prompt, option and pick, and was deallocated when the sheet dismissed — so a learner could never see
what they missed, compare a retake, or get any of it out. (2026-08-16)

- ✅ **History.** `Models/PlacementAttempt.swift` (`PlacementRecord` + `PlacementAttempt`) and
  `Services/PlacementAttemptStore.swift` — a flat Codable twin of the live answer types, written to
  `Application Support/Placement/attempts.json`, newest first, capped at 40 (~6.8 KB/attempt
  measured, so ~270 KB). A file rather than UserDefaults because that plist is parsed on the launch
  path and one screen reads this; still **no SwiftData schema**, per the rule at the top. Storage
  twins rather than `Codable` on `PlacementItem`: its `let id = UUID()` would mint a fresh identity
  on every decode, and `Kind` is the scorer's language, not a durable shape.
- ✅ `placement.result` and every existing accessor are untouched, so `PyramidService`,
  `FortschrittView` and `LevelCardSection` needed no changes. `clear()` deliberately leaves history
  alone — 29 recorded questions are not the estimate.
- ✅ **The estimate stopped being a slot you have to clear.** The old placement section led with a
  destructive "Remove the estimate", which framed retaking as *replacing* and made deletion the only
  way to move on. Now that every check is kept whole, `placement.result` is just *which check is
  currently applied*, and that's fully reversible:
  - The history screen owns taking another check, switching which one applies ("Use this check's
    estimate", also a leading swipe), and a **non-destructive** "Stop applying an estimate". The
    destructive button is gone from both `PyramidView` and `GamificationSettingsView`.
  - Rows carry a `Now in use` badge and a comparison against the next-older check
    (`A1 → B1 · +21 pts`), skipped where either side is the "starting from zero" door, since that
    isn't a score and differencing it would manufacture a drop.
  - Adopting is the same two writes the quiz makes on finish (`save` + chat/story level), so it is
    lossless in both directions. Verified on the sim: `25 % estimated` → switch to the oldest check
    → switch back → `25 % estimated`, exactly; and `34 %` (B1 check) → `12 %` (an A1 check) → none →
    back, with `built` pinned at `0 %` throughout.
  - `PlacementAttemptStore.append` now re-sorts instead of inserting at the front. Real runs are
    always "now" so the bug was invisible in production, but the debug seeder backdates and
    `attempts()` hands the cache straight back — an out-of-order insert survived the whole launch
    and silently broke the newest-first contract.
- ✅ **Review screen** (`Features/Progress/PlacementReview*`), two tabs on a segmented control
  because there are two different questions and they want different shapes:
  - **Checks** (default) — one row per run: date, estimate chip, score bar, and how many of its
    misses are ones you keep making. Tapping opens that run's own results (summary, per-block
    tally, questions in ask-order). This is the front door; "how did March go vs. now" is the
    question a learner actually arrives with.
  - **Questions** — every run flattened into one filterable list (outcome / block / level /
    attempt / "missed 2+ times"). Only this shape can answer "what do I keep getting wrong",
    since that's a fact about the history rather than about any single check.

  "Missed N+" matches the **misses themselves**, not every encounter of a repeatedly-missed
  question — a row you got right isn't a "missed 2+" row, and the improvement arc lives in the
  question detail's "every time you were asked this", where it reads as progress instead of
  contradicting the pill. `FilterPill` was extracted from `StoryListFilterBar` to `Features/Shared/`.
  The screen finally surfaces the bank's authored `english` / `why`, which no UI had ever shown —
  looked up live via new `PlacementGrammarBank.item(id:)` / `.clozeGap(paragraphID:gap:)`, so
  re-authoring the bank improves old reviews. The post-quiz "See what you missed" goes straight to
  the run just finished, not the list.
- ✅ **JSON export** (`Services/PlacementExport.swift`) — the app's first export surface.
  `Transferable` + `DataRepresentation(.json)`, not a temp file (no lifetime to race against the
  share sheet). Choices export as **strings**, since indices are meaningless outside an app that
  reshuffles them per run; explanations are denormalized in; the active filter travels in `scope`,
  because exporting 40 checks while showing 6 rows would be a trust bug.
- ✅ **Opt-in coach hand-off** (`Services/PlacementCoachExport.swift`) — the amendment above. Word
  misses → `noteVocabEncounters` (recognition trouble, the Phase 5/8/10 rail); grammar and cloze
  misses → `LexicalSlip`s tagged `MemorySource.placement`. Never `profile.grammar`, no
  `sessionCount` bump, and a `placement.handoff.lastAttemptAt` high-water mark so a second tap
  can't inflate `timesSeen` with no new material.
  - `LexicalSlip.id` now folds in `source`, which is what stops a placement `die→der` from merging
    with a real conversation `die→der` and **overwriting the learner's own sentence and cloze card**.
    Backward compatible precisely because `source` defaults to nil: existing ids are byte-identical.
  - `correctionHint` filters to `source == nil`. A placement slip's wrong side is an authored
    *distractor* — telling the coach to watch for it would invent a mistake never made.
  - Four bank items have multi-word answers (`krank bin`, `auf dem`, `an die`, `fahre ich`; the
    first is an anchor, so it appears in **every** run). `blankIndex` addresses one token, so those
    get `sentence`/`blankIndex` left nil — an already-supported state. They still reach the coach,
    they're just not drillable. Nothing is dropped.
- ✅ **Verified on the simulator** (2026-08-16), which can run the probe since it's offline. New
  DEBUG args: `-placement.debugAttempts N -placement.debugAccuracy 0.6` seeds synthetic attempts by
  driving a real `PlacementSession`; `-placement.debugOpenReview 1` opens the screen (it's three
  taps deep and this harness can observe but not tap); `-placement.debugVerify 1` runs the hand-off
  and dumps the export. `-onboarding.resetWizard` now clears history and the high-water mark too.
  - **Channel-independence proof, from a clean install**: `0 % built · 34 % estimated` →
    hand-off writes 35 words + 17 slips → `0 % built · 34 % estimated`, byte-identical (identical
    screen hash). Profile after: `grammar` NULL, `sessionCount` 0.
  - Export verified: 4 attempts / 116 questions, all choices strings, all three outcomes present,
    52 questions carrying `why`.
  - Tapped through with `agent-device` (see the note in `LEARNER_MEMORY.md` / the environment
    memory — XcodeBuildMCP's own tap tools are not enabled here, agent-device's are): Lernpyramide
    → "See what you missed · 4 checks" → a check → its questions → one question's detail, with the
    bank's `english` + `why` and the cross-attempt history all rendering. Questions tab → "Missed
    2+" filtered 116 → 6, "Clear" restored it.
  - Three defects the tap-through caught that the build could not: "Missed 2+" was matching
    *correct* rows of repeatedly-missed questions; the newest-first ordering broke under the
    backdating seeder; and the decorative block symbols were announcing as "Text On A Closed Book" /
    "A Circle" / "Divide". On the last: `.accessibilityHidden(true)` on the symbol is **not enough**
    on a plain, non-tappable row — SwiftUI only folds children into one element automatically when
    the row is interactive (which is why the `NavigationLink` rows were already fine). The
    breakdown rows needed `.accessibilityElement(children: .ignore)` + an explicit label. Note that
    agent-device's tree dump still lists the descendant `[image]` nodes; read the **cell's** label,
    which is what VoiceOver focuses.
- ⬜ Not exercised: the ShareLink sheet itself (the document it hands over is verified) and the
  hand-off *button* (the code behind it is verified via `-placement.debugVerify`). Both need a
  human tap on the system sheet.

## Phase 9 — Der Bauplan: one number, a coach's-eye pyramid  ✅ code / ⬜ user review

The "N % built · M % estimated" header read as a contradiction — 0 % and 25 % complete at the
same time — and the pyramid wasn't yet the holistic "how the tutor sees the learner" view it was
meant to be. (2026-08-18; presentation + additive UI only — **no change to the credit math,
`isComplete`, reward gating, or the placement-never-writes-`LearnerProfile` rule.**)

- ✅ **The estimate is now "der Bauplan · the blueprint"** everywhere a learner sees it. The check
  *drafts a blueprint* (the dashed outline the glyph and scene already drew); studying *builds to
  it*. Switching checks = swapping blueprints; "Put the blueprint away" (ex "Stop applying an
  estimate") leaves every brick. "Estimated" no longer appears in pyramid copy.
- ✅ **One percentage.** The header shows earned only ("12 % gebaut · built") plus a sentence when
  a blueprint is applied; the blueprint's number lives in the Einstufung section beside its
  explanation ("blueprint covers about N % of the pyramid"), with a retake nudge once earned
  progress exists. Teasers (Home / Fortschritt) same pattern: "12 % built · blueprint from your
  check", never a second %.
- ✅ **Layer rows stopped contradicting the scene**: the single solid `ProgressView` drew *total*
  fill; the new `LayerFillBar` draws earned solid + blueprint as a faint dash-edged segment —
  the same two-channel language as glyph and canvas. Detail lines say "· N on the blueprint".
- ✅ **"Wo du stehst · Where You Stand"** (`Features/Progress/PyramidCoachSection.swift`): one row
  per skill area (Wortschatz / Artikel / Fälle & Präpositionen / Strukturen / Ausrutscher), each
  pairing a "Check N %" chip (placement snapshot) with the coach's live verdict (solid / needs
  work / watching / not yet measured; measured wins, mirroring the credit rule). Growth areas
  sort first; rows route to the same drills Coach's Picks uses; footer links to Coach's Notes and
  the placement review. Hidden until either source has content. Pure read, own queries.
- ✅ **Per-layer coach signals**: Grammatik-Kern rows carry four structure chips
  (solid / flame / dashed = unmeasured, `CoreStructureDots`); Fundament and Wortschatz A1 append
  "N tricky right now" from the live tricky lists (word tricky lists aren't level-tagged, so they
  surface on the A1 layer only — A2 too would double-report).
- ✅ **Next step**: the active layer (lowest unfinished — same rule as the breathing slab) gets a
  solid-tint icon chip, a "Hier weiterbauen" tag and a one-line concrete suggestion (due-card
  count, weakest structure, tricky count) above its existing destination.
- ✅ **The canvas answers taps**: slabs carry collision + input targets; tapping one freezes the
  turntable (angle continuity kept on resume), eases the camera to the slab (~0.55 s smoothstep;
  snap under Reduce Motion), dims the rest, and floats a chip (name, detail, Öffnen, close). All
  transition state is recorded in the tap handler — the update pass never mutates @State.
- ✅ **Bauhaus icons from Blender** (`tools/blender/pyramid_icons.py`): nine icons (six layers +
  Wo-du-stehst / Bauplan / Weiterbauen marks), 512 px alpha stills in the prep scenes' material
  language, **two separately-lit variants each** (light: charcoal + key-heavy wash; dark: lifted
  grey + rim-heavy rig — a re-light, not a tint swap), landed as Any/Dark image sets
  (`pyramid-icon-<slug>`). Wired into layer rows, the focus chip, and the Einstufung row via
  `BauhausIcon`, which falls back to the SF Symbol wherever an asset is missing — the pipeline
  can trail the code safely. The Wo-du-stehst and Weiterbauen marks are rendered but not yet
  placed. Carried-over caveat from `render_all.sh`: dimensional shading muds below ~40pt, so
  review at real size; deleting an image set is a full rollback.
- ✅ **The quiz shows its payoff**: the result stage renders a `PyramidGlyph` of the blueprint the
  finished check just drew (same credit math, fed empty stats), titled "Dein Bauplan", before the
  learner ever reaches the pyramid.
- ⬜ User review on device/sim: header + Einstufung copy, coach section with and without a check,
  canvas focus feel, icon legibility at 38 pt (drop any that mud — the fallback covers them).

## Phase 10 — „Dein Weg": snapshots, the journey timeline & „Weißt du es noch?"  ✅ code / ⬜ user review

The comeback loop: see where you started and where you are now. (2026-08-19)

- ✅ **`Services/ProgressSnapshotStore.swift`** — `Application Support/Progress/journey.json`
  (PlacementAttemptStore's pattern: file not SwiftData/UserDefaults, ISO8601, atomic, cache,
  decode-failure = empty). Holds **weekly numeric snapshots** (per-layer *earned* fill, blueprint
  share, learned-word counts, solid structures, well-held conversations, streak, level, XP —
  small and fixed-size) plus **recorded milestones**: dated events nothing else dates. Recorder
  `ProgressSnapshotService.recordIfDue` rides the Home hub's existing gamification hook,
  self-throttled to ~7 days; the first run seeds detection state **silently** (badge-seeder
  precedent — no backlog of "vollendet!" rows dated install day).
- ✅ **Why snapshots must exist**: `SavedCard` has no created/reviewed dates, game stats only
  overwritten `lastSeenAt`, celebrations dedupe with booleans — matured words, comeback words
  ("forgotten once, re-proven": `lapses > 0 && repetitions >= 3`) and layer completions are
  **only datable going forward**. Everything else the timeline shows is derived from records
  that already carry dates.
- ✅ **`Services/JourneyService.swift` + `Features/Progress/JourneyView.swift`** („Dein Weg",
  entered from a new Fortschritt row wearing the previously-unplaced `weiterbauen` mark):
  month-grouped timeline of placement checks (blueprint framing, level-change comparisons),
  mastered slips (`ArchivedMemoryItem` `.mastered` + `archivedAt`), badges (seeded-date caveat
  noted in code), first story passed per level, first conversation held well, streak milestones
  and level-ups **replayed from the never-pruned `StudyDay` log** (levels capped: ≤10 + rank
  starts), and the store's recorded milestones. Header = then-vs-now (first check / first day →
  level + % built, trend line once ≥2 snapshots); a comeback-words summary card stays undated by
  design. **Earned-only invariant**: placement rows are blueprint events, never progress.
- ✅ **„Weißt du es noch?"** — at most one question a week (throttled on answer), drawn from
  mastered slips ≥30 days retired: the slip's own sentence with the blank restored, wrong/right
  as the two choices. Right → `stillSolid` milestone, archive untouched; wrong →
  `LearnerMemoryService.noteSlips` (the existing pre-built-slip rail) + archive row deleted +
  `backInTraining` milestone. Either way `StudyLogService.record(.cards(1))` — retrieval is
  study. Toggle in Settings ▸ Gamification (`gamificationRememberProbeEnabled`, default on).
- ✅ **Six milestone icons** added to `tools/blender/pyramid_icons.py` (grundstein, gemeistert,
  zurueckgeholt, sitzt-noch, flamme, rang — gold flag rebuilt as a rectangle: a 3-vert cone's
  vertex orientation is luck), light/dark pairs, landed as `pyramid-icon-<slug>` image sets;
  timeline rows use them via `BauhausIcon` with SF fallback.
- ✅ **Figur journey header** — JourneyView's one live canvas: the figure walking a charcoal path
  past accent milestone posts toward a mini pyramid, `SceneRig` camera/lights.
  - **The gait is a real baked clip** (2026-08-20): `figur.py --gehen` keyframes a seamless
    in-place stride (legs ±18° about the hip line — the geh pose's axis — arms counter-swing
    ±11°, torso+head bob 0.022 at the passing position so all six parts animate and
    `verify_animation`'s all-parts check keeps meaning something; first frame == last frame for
    `.repeat`). Exported as `figur-gehen.usdz` **with its plain-text `.usda` twin written from
    the same scene first** — the twin is the only proof of motion (the Blender importer drops
    USD transform animation; see the memory that round-trips false-pass). Verified: 6 prims,
    frames 1..25. Storyboard strip: `renders/figur/figur-gehen.png`.
  - **The walk is an endless switchback climb** (two reworks same day: the flat ping-pong read
    as walking backwards; the summit-and-fade version still reset — the user wanted a *lifetime
    learner*, no summit, no reset). The figure's tier index grows without bound and the camera
    rides her height (`SceneRig.aim` per frame); a fixed even-sized pool of ramp/bend-pad
    entities recycles around her — parity decides tilt, direction and depth once at build, and
    `layoutMountain` only ever moves pool entities in y, so the treadmill is invisible. Depth
    *alternates* between tiers instead of accumulating (the pattern must repeat for the climb
    to be endless). Proportions fixed after the first on-device screenshot (figure spanned
    three tiers): figure scaled to 0.5, tier rise 1.3 > her scaled height, slide slowed to
    ~0.4 units/s to match the scaled stride, camera target above her head so the climb still
    to come fills the upper frame. Trail-marker posts removed — they read as noise; if bend
    "pop-in" milestone icons are ever wanted, texture a small sign quad from the existing
    `pyramid-icon-*` PNGs. Turns swing yaw through front over the bend pad; clip found by
    `FigurSceneView`'s rule, looped via `repeat(duration: .infinity)`. Reduce Motion shows the
    static geh pose frozen mid-mountain (same layout code, fixed pseudo-clock).
- ✅ **Offscreen = paused** (2026-08-20): both live canvases (pyramid, journey header) get
  `onScrollVisibilityChange` — scrolled away freezes their `TimelineView` clocks (turntable,
  breathing, camera easing, slide) and the journey header additionally pauses the walk clip's
  `AnimationPlaybackController`, since that runs on RealityKit's own clock and would keep
  burning frames under the scrolled-away list. Scrolling back resumes both.
- ✅ **The whole screen is 3D now** (2026-08-20): the last SF Symbols in „Dein Weg"'s *icon*
  positions were replaced with 19 new Bauhaus renders — one per Abzeichen (16), plus
  `schicht-fertig` (layer complete), `zurueck-im-training` and `wegweiser` (the empty state at
  64pt). Badge slugs are derived, not stored: `Achievement.assetSlug` = `abzeichen-<id>`, so the
  catalog and the render set can only drift by renaming a badge, and a badge added before its
  icon still falls back to its SF Symbol.
  - `backInTraining` stopped borrowing the indigo `zurueckgeholt` icon under an orange tint (the
    baked accent ignored it, so a setback row read as a comeback) — it has its own mark: the
    block back at the foot of the ramp.
  - **Sixteen distinct forms, not one medal**: the timeline puts badge rows next to milestone
    rows, so a shared badge mark would have said only "a badge". Near-twins (three word tiers,
    two story badges) use unrelated objects rather than one form with a count on it.
  - **Reviewed at real size, not at 512**: `pyramid_icons.py --contact` composites the set onto
    the app's own light/dark grounds at 128px — a 44pt row icon at @3x — which is the only way
    the ~40pt mud caveat can actually be judged. Seven icons failed that review and were rebuilt
    (flat ground-plane forms vanish under the 15° camera; a small camera-facing disc renders as
    a sphere; the two story badges were twins). `--only <slugs>` re-renders just those.
  - `tools/blender/install_icons.sh` lands renders as `pyramid-icon-<slug>` Any/Dark image sets,
    so the hand-copy step can't half-happen. Deleting an image set is still a full rollback.
  - Deliberately left as SF Symbols: the trend line, the Start→Heute arrow, and the probe result
    tick — all under ~17pt, where dimensional shading muds, and all status marks rather than
    objects.
- ⬜ Follow-up: the Abzeichen grid in `FortschrittView.swift:280` still draws
  `achievement.systemImage`. The icons it needs now exist — swapping that `Image(systemName:)`
  for `BauhausIcon(assetName: "pyramid-icon-\(state.achievement.assetSlug)", …)` is the whole
  change, but the grid's tile size and earned/locked treatment want their own review first.
- ⬜ User review on device/sim: timeline contents with seeded checks, probe right/wrong paths,
  header walk direction (if the figure walks backwards, flip the ±π/2 yaw in
  `JourneyRealityScene.poseFigure` — one constant), milestone icon legibility at row size, and
  the 19 new marks against each other in a long timeline.

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
- **One percentage, and it means proven (2026-08-18).** The dual "N % built · M % estimated"
  header read as a contradiction, so the header carries earned only; the estimate's number moved
  into the Einstufung section, beside its explanation. Presentation only — the two-channel data
  model and the estimated≠earned invariant are untouched.
- **Blueprint, not estimate (2026-08-18).** The learner-facing name for placement credit is "der
  Bauplan": a blueprint is self-evidently not the building, which is the entire invariant said in
  one word. It also settles what the destructive-feeling actions actually do — swapping checks
  swaps blueprints, and putting the blueprint away demolishes nothing.
- **The timeline is earned-only (2026-08-19).** „Dein Weg" shows placement checks as blueprint
  events — drawn, redrawn, put away — never as progress. The moment a retake could manufacture a
  milestone, the timeline would stop meaning anything (the dual-percentage lesson, applied to
  history). Same discipline for dates: nothing is given a date the records can't support — the
  undatable (comeback words before the recorder existed) is shown undated rather than stamped
  with a plausible lie.
- **Declared is not measured (2026-09-03).** A learner can now hard-select their level outright —
  from the check's intro ("I already know my level"), from its result, or in Settings ▸ Learning ▸
  Your Level. It sets content difficulty everywhere and credits the pyramid **nothing**: no
  `PlacementResult` is written, so no provisional fill, no dashed outlines, no Bauplan.
  *Estimated ≠ earned* protects the pyramid from a quiz; this is its stricter sibling, protecting
  it from an assertion. Proved on the simulator with two opposed launch arguments —
  `-level.debugDeclare C1` moves the level and writes no result (Home stays "0 % built", no
  blueprint line); `-placement.debugLevel B2` writes a result and doesn't move the level (Home
  reads "0 % built · blueprint from your check"). Re-run both after touching either path.
- **One level, and it's an anchor (2026-09-03).** The same change collapsed `chatLevelRaw` +
  `storyLevelRaw` into a single `MLXModelManager.germanLevel`. The two of them were *last-used
  memories masquerading as defaults*: conversation setup wrote the per-chat pick back on Start, and
  the story picker bound straight to the stored setting, so one B2 story silently promoted the
  learner everywhere. That is precisely why no declared default could be respected. Setup sheets
  now **seed** from the anchor and never write back — a level chosen for one exercise stays with
  that exercise. The fallbacks had already drifted apart under the old scheme (`?? .a2` everywhere
  but `?? .b1` in `PaperDetailView`), which is the usual symptom of a default with no owner.

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
