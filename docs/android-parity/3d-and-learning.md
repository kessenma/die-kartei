# Die Kartei parity audit: 3D rendering and learning features (iOS main vs Android port)

Scope: iOS `german-ai-flashcards` on `main` @ 42b1cc7 (2026-11-26). Android worktree `die-kartei-android`, branch
`android-port` @ ffd2307 (local refs show main 1 ahead and android-port 15 ahead; 42b1cc7 is not merged in yet).
I only read source. Nothing was built or run, Blender included. Android screens compared:
`DieKarteiAndroid/Sources/DieKartei/*.swift` (2,766 lines in total, against ~34k lines in the iOS modules below).

---

## Part A: 3D

### A.1 Assets and pipeline

| Set | Files | Authored in | Motion | Still fallback shipped |
|---|---|---|---|---|
| `figur.usdz`, `figur-aufbau`, `figur-gehen`, `figur-geh` | 4 | `tools/blender/figur.py` via `figur_all.sh` | **Baked** (aufbau: self-assembly, 2.5 s, played once; gehen: gait clip that loops). geh is a static pose | `figur-still` (Assets.xcassets, light and dark) |
| `prep3d-*.usdz` (37 relations, incl. `wohinwo`) | 37 | `prep_render.py` via `render_all.sh` | **Code-driven per frame**. The manifest gives `akkOffset` (11 two-way), `motion` kinds (shuttle 14, orbit 3, idle 4, through, bounce, carry, abandon, swap) and a runtime tint per case | `prep3d-<w>-{neutral,dat,akk}-dim.png` in Resources |
| `verb3d-*.usdz` | 35 (39 manifest keys) | `verben.py --ship` (reuses `figur.py` gestures and `prep_render.export_usdz`) | **Baked** (`baked: true` for all 39), clips play on reveal | `verb3d-<k>-{neutral,dat}-dim.png` |
| `kasus3d-*.usdz` | 5 (geben, helfen, jagen-hund, jagen-katze, leine) | `kasus_szenen.py --ship` | **Baked** | `kasus3d-<k>-{neutral,dat}-dim.png` |
| `tutor-fuellen.usdz` | 1 | `tutor_render.py` | Baked plus code-driven backdrop | none; only reached from the DEBUG `TutorSceneLab` |
| Procedural (no asset) | n/a | Swift `ModelEntity`/`MeshResource` | Code-driven | see the per-surface table |

Total: 86 USDZ (~26 MB) and 173 `*-dim.png` stills. Manifests: `prep3d-/verb3d-/kasus3d-manifest.json`.
`HangmanMotif` names `galgen3d-<raw>.usdz`, but none ships, so Hangman is flat-only on iOS too.

### A.2 Every 3D surface

| # | Surface (where the user sees it) | View | Asset | Motion | Lightweight / Reduce Motion fallback | Android today |
|---|---|---|---|---|---|---|
| 1 | Onboarding placement: die Figur assembles herself | `PlacementQuizStages` → `FigurSceneView` | figur-aufbau / figur (RM) | baked clip, played once | ✅ `FigurScene.still` (no RealityKit context built) | no onboarding |
| 2 | Placement "declare level" door: „Die Treppe“ | `LevelClimbScene` | figur-gehen + procedural steps | baked gait + **runtime translation** speed-matched to the slide | ✅ `LightweightGraphics.isActive` branch; RM gives a static pose | no |
| 3 | Grammar ▸ Präpositionen ▸ case game, reveal | `PrepositionCaseGameView` → `PrepositionSceneView` | prep3d-* | per-frame offset, tint and assembly | ⚠️ RM or no `animates` → PNG still. **No LightweightGraphics check** | Android drill has no picture |
| 4 | Präpositionen flip cards | `PrepositionCardsView` | prep3d-* | same | same | missing screen |
| 5 | Präpositionen rules sheet (Wohin/Wo) | `PrepositionRulesSheet` | prep3d-wohinwo, loops | same | same | missing |
| 6 | Verben mit Präpositionen cards and SRS review | `VerbPrepositionCardsView`, `VerbPrepositionReviewView` | verb3d-* | baked clips; frozen on the question side | PNG still (RM) | missing |
| 7 | Kasus lesson example: Figur acts the sentence out | `KasusLessonView` → `KasusLessonSceneView` | kasus3d-* | baked. Still first, live only after tapping „Abspielen“ | ✅ still-first by design | `KasusLessonsView` shows text only, no picture |
| 8 | Endings drill (Schnellrunde / Bau das Wort), endings table, Endungs-Werkstatt | `EndingBlocksScene` in `EndingsModule`, `CaseEndingsView`, `EndungsWerkstattView` | procedural: letters extruded at runtime | per-frame `EndingBlocksPose` | ✅ `EndingBlocksFlat` (SwiftUI text, no Canvas) | all three screens missing |
| 9 | Lernpyramide (Home level card, Fortschritt) | `PyramidView` → `PyramidSceneView` | procedural slabs and ball | per-frame turntable, breathing, camera easing | ⚠️ RM only (clock 0). **No LightweightGraphics.** 2D `PyramidGlyph` (Canvas) is used in lists | missing |
| 10 | „Dein Weg“ journey header | `JourneyView` → `JourneyHeaderScene` | figur-gehen/geh + procedural ramps | baked gait + runtime path | ⚠️ RM gives a static geh pose, **still RealityKit**; no lightweight still | missing |
| 11 | Schreibblatt finish celebration | `SchreibblattCelebration` | verb3d-freuen_ueber, trophy tinted gold | baked `jubel` ×3 | ✅ scene still (LG or RM) | Schreibblatt not ported |
| 12 | DEBUG galleries (Figur, prep, verb, render test, TutorSceneLab) | `PrepositionHubView` `#if DEBUG` | all | n/a | n/a | not needed |

House rules that carry over to Android: at most one live scene per screen; stills in lists; a `TimelineView` runs only
while something moves; no cameras or lights inside assets.

### A.3 Facts that constrain the port

- **SkipUI stubs `Canvas` and `TimelineView` with `fatalError()`** (`.build/checkouts/skip-ui/.../Graphics/Canvas.swift`,
  `Animation/Timeline.swift`). This breaks more than the 3D views. The 2D twins `HangmanFlatView`, `PyramidGlyph` and
  `GrammarTaskArtView` are `Canvas` drawings, so they need rewrites using `Shape`/`Path` views, which SkipUI does
  implement, or a Compose `Canvas` inside a `ComposeView`. `EndingBlocksFlat` uses neither and should port as is.
- `rotation3DEffect` *is* implemented in SkipUI, so the iOS card flip can be mirrored.
- `ComposeView` + `ContentComposer` (Skip Fuse, transpiled `#if SKIP` block) is the documented way to embed any Compose
  view. It is the same shape as the existing `GermanVoice` bridge.
- Skip ships no 3D module. The relevant ones are `skip-motion` (Lottie) and `skip-av` (ExoPlayer).
- SceneView (`io.github.sceneview:sceneview:4.76.0`, Apache-2.0) is Compose-native Filament. It loads glTF/GLB and plays
  glTF animations by index or name. Nodes are found by name, materials can be tinted (`baseColorFactor`), and node
  transforms can be set from Compose state every frame. USDZ is not supported on Android.
- **GLB export is a small change.** Every shipped scene goes through one of two functions:
  `figur.py:export_usdz` and `prep_render.py:export_usdz`. `verben.py` and `kasus_szenen.py` call the second as
  `pr.export_usdz`. Both already strip cameras and lights before a plain `bpy.ops.wm.usd_export`. One
  `bpy.ops.export_scene.gltf(filepath=…glb, export_format='GLB', export_animations=True, export_cameras=False,
  export_lights=False)` next to each covers all 86 assets. Blender 5.3 is installed and the glTF exporter is a bundled
  add-on. What makes this easy:
  - motion is object-level TRS keyframes, not armatures, which is glTF's native animation channel;
  - glTF is +Y-up, the same convention as `convert_orientation=True`;
  - materials are Principled BSDF (dim look) or Emission (flat), which map to glTF PBR and `KHR_materials_emissive_strength`;
  - prim names such as `subject` (which the runtime tints and moves) survive as node names.

  Still to verify: multi-clip verb scenes (glTF export of NLA tracks vs actions), and a GLB check added to `verify()`,
  which today reads the `.usda` twin.
- The stills can ship now. They are in `Resources/`, but `core_sync.py` copies only JSON to Android. The lookup goes
  through `UIImage(named:)` in `PrepositionScene.image`, which is iOS-only. `figur-still` is in the iOS xcassets with
  light and dark variants. On Android I'd put the 173 PNGs into `Module.xcassets` or Resources and load them with
  `Image(name, bundle: .module)`. I haven't checked whether Skip resolves dark-appearance image variants.

### A.4 Options

1. **Ship the stills and 2D twins first, i.e. treat Android as a permanent "Stills Only" device.** This is exactly the
   iOS `LightweightGraphics` path: no render context, and the same Blender renders. It covers surfaces 1, 3–7 and 11
   with existing PNGs, and 8 with `EndingBlocksFlat`. Gaps: 2, 9 and 10 have no lightweight still on iOS either; they
   need a Blender still (`figur.py --view dim`, `pyramid_render.py` exists) or a Shape-based rewrite of `PyramidGlyph`.
   - Cost: about S. Copy the PNGs, add a portable `SceneStill` lookup into the core (name logic only), and fall back on
     Android at the same branch points.
   - Gives up the motion. That costs the most for prepositions, where Akk vs Dat is *taught by* the move between poses.
     The `-akk-dim` stills only exist for the 11 two-way relations.
2. **GLB from the same Blender scripts, rendered by SceneView in a transpiled Skip module** (e.g. `Kartei3D`, a sibling of
   `GermanVoice`): a `ContentComposer` wrapping `SceneView { ModelNode(...) }`, plus a small Swift API
   (`SceneCanvas(asset:, tint:, clip:, nodeOffsets:)`).
   - Baked sets port almost for free: figur clips, all 39 verb3d, all 5 kasus3d, the celebration. Play a clip, tint one
     material.
   - prep3d needs the per-frame beats (`subjectOffset/moverOffset/tint/assembly(at:)`, ~200 lines in
     `PrepositionSceneView`). Move them into a Foundation-only `PrepositionChoreography.swift`. That is a
     behaviour-neutral split in the project's usual style, and both apps drive the same math (iOS RealityKit, Android
     Filament node transforms). Copying it into Kotlin would drift.
   - The procedural scenes (Pyramid, Journey ramps, LevelClimb steps, EndingBlocks extruded letters) have no asset.
     Either generate GLBs for them in Blender (`pyramid_render.py` is already planned) or keep their 2D twins.
     Extruded text at runtime isn't practical in Filament; keep `EndingBlocksFlat`.
   - Costs: the Filament and gltfio native libraries add APK size per ABI. I haven't measured it; it's commonly cited
     as several MB. SurfaceView sits under Compose. Low-end Android GPUs make the one-live-scene rule matter more.
   - Effort: M for the baked sets, L including prep choreography and the procedural scenes.
3. **Pre-rendered video, Lottie or sprite sheets.** This fights the design. The scenes are tinted at runtime (per case
   and per theme, light and dark), restart on reveal without reloading, and pose by state (neutral, dat, akk). The
   variants multiply to roughly 37 relations × 3 states × 4 case colours × 2 appearances. Lottie can't carry the
   shaded 3D look. Video adds MBs per clip and loses the settle and idle sync. The only reasonable use is a single
   one-off clip (onboarding self-assembly as an MP4 via `skip-av`), and the still already covers that.

**Recommendation:** do option 1 now, then option 2 in stages. Option 3 is rejected. Reasons are in the closing section.

---

## Part B: learning features

Legend: **P** Present · **Pa** Partial · **M** Missing · **A+** Android-only. Effort: S ≤ 1 day, M a few days, L a week or more.

### B.1 Cards (Features/Cards, CardDeck: 26 files, 6.3k lines) · **Pa**

- **iOS:**
  - Three review styles (`FlashcardStyle` default ✓/✗, Anki 4-button SM-2, Leitner boxes).
  - Setup screen with paused-session resume (Home ▸ Continue), deck mix, and options: German or English first,
    article quiz (article hidden until the flip), repeat missed, shuffle, phrase-gap cards (`PhraseGapPlanner`).
  - Ruled card with a 3D flip (`rotation3DEffect`), model or Goethe badge, AI picture face with image styles, full-screen
    image, illustrate-deck and the pictures pill.
  - Validation badges and review (AI-checked cards), correction sheet, word table (missed or forgotten per word,
    hide a column).
  - iPad write-it-after-miss (Pencil). Summary with Review Missed and Try Again. User decks (`SavedDeck`/`SavedCard`)
    with iCloud sync.
- **Android `KartenView`:**
  - Goethe level deck only. Anki 4-button with interval previews (shared `SRSScheduling`), progress as JSON in
    UserDefaults.
  - Flip is a tap toggle with no rotation. Gender-tinted border, TTS button. "Fertig: N Karten" in place of a summary.
- **Differences:** no Default or Leitner, no setup or resume, no article-quiz hiding (the article always shows), no
  phrase gaps, no repeat-missed, no summary or review-missed, no user decks, no images, no validation.
- **Blockers:**
  - `SavedCard`/`SavedDeck` are SwiftData.
  - MLX (pictures, validation, AI decks).
  - PencilKit (write-it).
  - The session logic is spread across the `CardDeckView+*.swift` extensions together with `modelContext`.
- **Approach:**
  - Lift the session engine (queue, repeat-missed re-insert, phrase-gap deal, result tally per mode) into a core
    `CardSession` over `SRSCardState`, whose Leitner math is already shared.
  - Mirror `FlashCardView` (`rotation3DEffect` works in SkipUI).
  - Add Leitner, Default and the summary.
  - User decks wait for the SQLite store protocol.
- **Effort:** M for modes, flip and summary; L with user decks.

### B.2 Wortschatz (7 files, 1.3k lines) · **Pa**

- **iOS hub:**
  - Scope chips: levels plus word classes, multi-select, the last chip can't be switched off.
  - Karteikasten chart (new → known) and „Fällig heute“ with new-per-day and a bonus "learn N more".
  - Paused session, today's results, options (study style, new per day, cards per session, front side).
  - Doors to Browse, Preview, Perfekt, Matching, der/die/das.
- **iOS Browse and word sheet:** Browse shows status badges (Neu, fällig, in 5 T., bekannt) and a word-type pill.
  `WortschatzWordSheet` shows a word's history across flashcards, der/die/das and matching.
- **Android:** `WortschatzView` is a searchable list with a level picker. Home "Today" row, `VocabularyView`
  (Karten + Wortschatz), Settings ▸ new per session. Nothing else.
- **Blockers:**
  - `WortschatzService` and its stats read SwiftData.
  - `WordClass`/`VocabListRow` split (listed in ANDROID_PORT "Next splits") is needed for word-class scope and pills.
- **Approach:** a hub on `StudyStore` stats (it already has seen, due and total), plus status badges from
  `CardProgress`. `KarteikastenChart` is plain SwiftUI with no Canvas, so it ports. Word classes come after the split.
- **Effort:** M.

### B.3 Grammar ▸ Hub (4 files) · **Pa** (layout differs a lot)

- **iOS `GrammarHubView`:**
  - Üben/Fortschritt picker.
  - Üben: Weiter (`KasusPath.next`), Verwechslungs-Paar card (`KasusConfusion`), the case path ① Nominativ → ⑤ Alle
    Fälle with dots, flame and level, Weitere Bereiche (`GrammarArea`: Präpositionen hub, Artikel & Endungen, Verben,
    Englisch via `GrammarBereichView`), and Nachschlagen (endings table, explainers, Merkhilfen, Kasus-Check,
    Werkstatt, rule sheets).
  - Toolbar „?“ opens the Kasus-Check.
- **Android `GrammatikView`:** one flat `List`. Artikel & Fälle (Kasus-Lektionen, der/die/das, Präpositionen, Die vier
  Fälle), Lückensätze (4 sets), Verben (Perfekt).
- **Blockers:**
  - `KasusPath`/`KasusConfusion` need `KasusRound` (a SwiftData model, listed in Next splits).
  - Flames come from `LearnerMemoryService` (SwiftData).
  - `GrammarArea`/`GrammarBereichView` aren't in the core list yet.
- **Approach:** move `GrammarArea` into the core (it's display-only), mirror the Üben structure with rows that exist
  today, and add path and progress once a KasusRound value twin and store exist.
- **Effort:** S for structure, M with path and flames.

### B.4 Grammar ▸ Topics (Kasus units, lessons, explainers, mnemonics, Reflexiv, Englisch/Tabelle setup) · **Pa**

- **iOS:**
  - `KasusUnitView` per case: Verstehen (lesson, Rollen, Wer macht was?, Probe, with ✓) and Üben rows. The AI-story
    section is in the same unit (see B.7).
  - `KasusLessonView`: pager with dots, EN twins, check steps, mnemonic, and the **kasus3d scene, still first then
    Abspielen**.
  - Explainer library, Merkhilfen, `ReflexivTopicView`, `EnglischSetupView`, `TabelleSetupView`.
- **Android `KasusLessonsView`:** lesson cards (RichText, check steps, mnemonic), no scenes, and no unit screen,
  explainers or Reflexiv.
- **Blockers:** Kasus value types split (`KasusService.swift`), `KasusConceptPlayable` split, `kasus_concepts.json` and
  `kasus_triggers.json` not copied to Android Resources.
- **Approach:** add the kasus3d stills now (S). Unit screens follow the Drill port.
- **Effort:** S (stills), M (units).

### B.5 Grammar ▸ Drill (14 files: `GrammarDrillShell` + modules) · **M**

- **iOS:** a single shell (hero, answer panel in the thumb zone, verdict with why, Weiter slot) plays 19
  `KasusDrillKind`s: find, fill, quick, build, roles, wer, probe, lesson, blitz, pair, dativVerbs, fehler,
  reflexCase, reflexPerson, bridge, frage, englischeFalle, findeFall, tabelle. Endings variants use `EndingBlocksScene`.
  Feedback rule (`KasusFeedback`): never green or red; case and gender colours instead.
- **Android:** none. Its `AnswerButtons` (der/die/das, Präpositionen, Lückensätze) use green and red. That matches iOS's
  article and preposition games, but must **not** be reused for Kasus drills.
- **Blockers:**
  - The Kasus cluster split: `KasusHintLevel`/`KasusPickOutcome`/`KasusTipp`/`KasusRoundResult`/`KasusPrefill`,
    `KasusConceptPlayable`, and `KasusRound.CaseTally`.
  - `gap_choice_items.json` not copied.
  - `KasusService.recordRound` (SwiftData).
  - EndingBlocks 3D (use the Flat twin). Drag-and-drop in `ArticleTableBoardView` (tap-to-place is a supported path).
- **Approach:** do the split ANDROID_PORT already names, then put a `KasusRoundStore` protocol (JSON on Android) behind
  `recordRound`. The shell and modules are SwiftUI; check them for `TimelineView` (EndingsModule uses one for its
  timer, so replace it with a `Task` tick).
- **Effort:** L. This is the biggest single grammar gap.

### B.6 Grammar ▸ Quiz (`GrammarMultipleChoiceView`) · **P** (simplified)

- **Android:** `LueckenView` plays the same `grammar_exercises.json` categories with why and rule note.
- **Missing on Android:** hints toggle, haptic mode, timing and `onComplete` result recording. On iOS these sets live
  under the Präpositionen hub; Android lists them top-level.
- **Effort:** S.

### B.7 Grammar ▸ Story (9 files: KasusStory, Markieren, Endungen, Kasus-Check, AI stories) · **M**

- **iOS:** two class worksheets on one text. `KasusMarkView` (tap every word in the asked case) and `KasusEndingsView`
  (gap endings) are scored like the sheet. The Kasus-Check sheet gives the decision order. Tutor-written stories:
  Planen → Schreiben → Prüfen validator (`KasusGenerationSheet`), saved as `GeneratedKasusStory`.
- **Blockers:** Kasus split, `kasus_stories.json` not copied, `GeneratedKasusStory` SwiftData, MLX. llama.cpp now runs
  on Android, so AI stories become possible later through `TutorGenerating`.
- **Approach:** bundled stories once the Drill port's types are in the core. AI stories follow the tutor-features plan.
- **Effort:** M (bundled), L (AI).

### B.8 Grammar ▸ Reference (CaseEndingsView, EndungsWerkstatt, ReflexivPronounTable) · **Pa**

- **iOS:** endings table (rese/nese/mrmn/srsr, ein-words, gender-coloured letters, tap a cell to build the word in 3D
  blocks), Werkstatt (stem × gender × case, Durchblättern), reflexive pronoun table.
- **Android:** `FaelleView` shows only the definite-article grid and „Wozu?“.
- **Blockers:**
  - EndingBlocks 3D: use `EndingBlocksFlat`, plus `EndingBlocksState`, which is Foundation-only but not yet in
    `core_files.txt`.
  - `CaseEndingsView` imports SwiftData.
- **Approach:** add `EndingBlocksState` and the Flat twin to the core, then port the table and Werkstatt.
- **Effort:** S–M.

### B.9 Grammar ▸ Prepositions (10 files) · **Pa**

- **iOS `PrepositionHubView`:**
  - Case game with 3D reveal and stats (`PrepositionStats`).
  - Flip-card deck, rules sheet with Wohin/Wo scene and contractions.
  - Verben mit Präpositionen cards, plus an SRS review (`VerbPrepositionService.reviewQueue`).
  - Meaning-matching via Matching, fill-in sets, the AI source rows.
- **Android `PraepositionenView`:** 10 random core prepositions, case buttons, examples and contraction line. No
  picture, no stats, no cards, no rules sheet, no verb-prepositions (`verb_prepositions.json` is already copied, and
  `VerbPrepositionService`'s model is in the core).
- **Blockers:** `PrepositionStats` and the verb review store are SwiftData. 3D (stills first).
- **Approach:** stills in the drill reveal, then port `PrepositionCardsView`, `PrepositionRulesSheet` and
  `VerbPrepositionCardsView`. These are pure SwiftUI around `PrepositionSceneView`, so swap in a still view.
- **Effort:** M.

### B.10 Grammar ▸ ArticleGame (3 files) · **Pa**

- **iOS setup sources:** the on-device dictionary (`wiktionary_de.db`), coach words, saved decks, AI topic. Stats go to
  `ArticleStats`, there's a rules sheet, and a correct answer auto-advances.
- **Android `ArtikelView`:** 15 Goethe nouns at the current level, `ArticleRules` hints. No setup, stats or rules sheet,
  and every answer needs a Weiter tap.
- **Blockers:** `ArticleStats` SwiftData, the `wiktionary_de.db` SQLite (SkipSQL could read it), MLX for topics.
  `ArticleRulesSheet` is portable.
- **Effort:** S (rules sheet, auto-advance), M (sources and stats).

### B.11 Grammar ▸ EndingBlocks · **M** (3D; Flat twin portable). Covered in A.2 #8 and B.8. **Effort:** S for Flat.

### B.12 Grammar ▸ Progress and History (5 files) · **M**

- **iOS:** grammar day strip (shared `StreakGrid`), time per exercise, per-case bars, Verlauf (filter pills, all-time
  strip, round detail with every answer and its why).
- **Blockers:** `KasusRound`, `StudyDay` (SwiftData); value twins are needed. ANDROID_PORT lists `StudyDay`.
- **Effort:** M, after the Drill port (nothing records rounds until then).

### B.13 Grammar ▸ Shared (6 files) · **Pa**

- **Partly mirrored on Android:** its own `RichText` (AttributedString), `AnswerButtons` and `ScoreLine`.
- **Missing:** `GrammarLauncherRow` (theme-aware rows), `KasusFeedback` verdicts (right, almost, not quite), and
  `KasusSentences` word chips.
- **Blocker:** `GrammarTaskArtView` is a `Canvas` drawing and SkipUI's `Canvas` is a stub, so rewrite it with `Shape`s
  or drop the art on Android.
- **Effort:** S–M, alongside the Drill port.

### B.14 Hören (10 files, 2.4k lines) · **Pa**

- **iOS hub:** DLI-based intro, Zuletzt, Statistik (right, first pass, alone vs in a sentence, mix-ups), iCloud note.
- **iOS Zahlen:** multi-kind setup, bare or **carrier-sentence** mode, count. Replays are counted, so "first pass" is
  measured. Results saved as `HoerenRound`.
- **iOS Diktat:** bundled or class sentences, pass or study mode, scored "ending only vs word" (`DiktatScorer`, in the
  core).
- **iOS Gist:** guess words, hear the story with the text hidden, write the gist, compare with key points (tutor).
- **iOS HoerenCheck:** a level probe.
- **Android:** Zahlen-Diktat only. One kind per round, `.bare`, 10 items, Langsam button, Android TTS via `GermanVoice`.
  No stats or history.
- **Blockers:**
  - `HoerenRound` SwiftData.
  - `DiktatSentenceBank.swift` imports SwiftData for the class-material source, so the bundled bank needs splitting out.
  - Gist needs stories and the tutor.
  - `HoerenPlayer` sits on iOS `SpeechService`; `GermanVoice` needs an `onFinish` callback to count plays.
- **Approach:**
  1. Zahlen setup with carrier mode (S).
  2. Split `DiktatSentenceBank` (bundled half to the core) and port `DiktatView` with `GermanVoice` (M).
  3. Stats store (M).
  4. Gist later (L).

### B.15 Spiele (9 files) · **Pa** / **A+**

- **iOS:**
  - Galgenmännchen with `GameSetupView` (source picker: Goethe, saved decks; `GameShortfallSheet` tops a thin deck up
    and marks borrowed words).
  - Clue and hint, umlaut keyboard, gallows drawing (`HangmanFlatView`), summary.
  - Wortsuche and the fill-in crossword are only in `SpielKind`, the engines and the Home subtitle. **iOS has no view
    for either.**
- **Android:** Galgenmännchen (Goethe level, text-only, no gallows) and **Wortsuche, a working screen iOS lacks**.
- **Blockers:**
  - `HangmanFlatView` is `Canvas` (rewrite with `Path` shapes).
  - The setup sources need `SavedDeck`.
- **Effort:** S (gallows with shapes, umlaut keys, summary), M (sources). Worth porting the Android Wortsuche flow back
  to iOS.

### B.16 Matching (3 files) · **M**

- **iOS:** a timed form↔meaning pairs game (`MatchingGameView`, no SwiftData). The deck picker offers Goethe levels and
  saved decks. `TrickyPairsView` lists pairs you keep missing, which graduate after a streak (`MatchingStats`
  SwiftData). It also powers the preposition meaning-match.
- **Blockers:**
  - The game itself is portable, but it imports `Combine` (timer): replace it with a `Task` loop.
  - Stats need a JSON store.
- **Effort:** S–M. High value for little work: it's linked from Wortschatz and Präpositionen.

### B.17 Cloze (1 file) · **M**

- **iOS:** recall your own slipped word in your own sentence (`LexicalSlip`, `ClozeSession`). A correct fill retires the
  slip.
- **Blocker:** slips come from Schreiben and tutor corrections (SwiftData plus MLX), so there's nothing to show until
  Schreiben or the tutor writes slips on Android.
- **Effort:** S for the view, but it depends on Schreiben.

### B.18 PastTense (2 files) · **Pa** (different shape)

- **iOS:** `PastTenseLevelView` is an **SRS deck of Perfekt verbs** (due today, up to N new a day, paused session,
  today's right and missed with a list). `SeinHabenGuideView` is a pure-SwiftUI guide.
- **Android:** `PerfektView` is a haben/sein multiple-choice round with the Partizip reveal. That game doesn't exist on
  iOS.
- **Blockers:** SwiftData `SavedCard` for the verb deck.
- **Approach:** reuse `StudyStore` with `PastTenseVerbEntry` cards (same SM-2), and port `SeinHabenGuideView` (S).
  Keep the quiz as an extra.
- **Effort:** S–M.

### B.19 Cross-cutting

- **Data files not copied to Android** (needed by the above): `kasus_concepts.json`, `kasus_stories.json`,
  `kasus_triggers.json`, `gap_choice_items.json`, `placement_grammar.json`, `writing_prompts.json`, the
  `prep3d/verb3d/kasus3d` manifests, the 173 stills and `wiktionary_de.db`.
- **Persistence:** every "stats / history / flame / due" feature waits on the SwiftData → store-protocol work (SkipSQL).
  `StudyStore` (JSON in UserDefaults) is the pattern so far. It works for cards, but won't scale to round histories.
- **Speech:** recognition (`SpeechRecognitionService`) is only used by Conversation ▸ SayIt, so it blocks nothing in
  this scope. TTS is covered by `GermanVoice`.

---

## Top gaps by user impact

1. **Kasus drills, stories and the case path (B.5, B.7, B.3).** The core of the app's grammar teaching is missing. Most
   of it is blocked by one split (KasusService value types + KasusConceptPlayable + KasusRound twin). Effort L, highest
   payoff.
2. **Flashcard parity (B.1).** No Leitner or Default modes, no article-hiding quiz, no repeat-missed or summary, no
   user decks. The everyday screen feels thinner than iOS. Effort M to get modes, flip and summary.
3. **Matching (B.16).** Missing on Android although it's a portable view. A cheap win that also unlocks the
   preposition meaning-match.
4. **Präpositionen depth (B.9) and pictures (A).** The drill has no scene or still, and the cards, rules sheet and
   Verben mit Präpositionen are all missing, although the data is already on Android.
5. **Hören beyond numbers (B.14).** Diktat is mostly portable (scorer in the core; the bank needs a split). Carrier mode
   and stats are missing.
6. **Wortschatz hub (B.2).** Scope, Karteikasten, due today, word history. Learners can't see their progress per word.
7. **Progress and history (B.12) and endings reference (B.8).** Medium. The endings reference ports quickly through the
   Flat twin.
8. **Unsupported 2D drawing.** `Canvas`/`TimelineView` are stubs in SkipUI. That affects Hangman's gallows, the
   pyramid glyph and the task art, and needs Shape-based rewrites before those screens port.

(Android ahead of iOS: Wortsuche, and the haben/sein quiz.)

## Recommended 3D approach

**Ship stills now (option 1). Then add GLB with SceneView in a transpiled `Kartei3D` Skip module (option 2) in stages.
Reject video, Lottie and sprite sheets.**

- **Why stills first:**
  - It's the iOS app's own `LightweightGraphics` contract, the same code path and the same Blender renders. Android
    behaves like an iOS device set to "Stills Only".
  - The assets already exist: 173 PNGs plus `figur-still`. That covers every ported or about-to-port surface (case
    game reveal, Kasus lessons, preposition and verb cards, celebration).
  - It costs about a day and adds no native dependency or APK weight.
  - Two gaps need new stills or 2D twins first, because iOS never gave them a lightweight still: Pyramid (Shape-based
    `PyramidGlyph`) and Journey/Treppe (a `figur-geh` Blender still).
- **Why GLB and SceneView next:**
  - One function change in each of `figur.py` and `prep_render.py` exports all 86 scenes as GLB from the same rigs, so
    Blender stays the single source of truth.
  - The motion is object-TRS keyframes, which is native glTF animation. Materials are Principled or Emission, which map
    to glTF PBR.
  - SceneView is the maintained Compose-native Filament wrapper. Skip's `ComposeView`/`ContentComposer` hosts it the
    same way `GermanVoice` hosts TextToSpeech.
- **Stage order** (easy first):
  1. Baked scenes: 44 verb3d and kasus3d scenes, the figur clips and the celebration. Play a clip, tint one material.
  2. prep3d: first move the per-frame beats out of `PrepositionSceneView` into a Foundation-only core file, so iOS
     (RealityKit) and Android (Filament node transforms) run one choreography.
  3. Procedural scenes (Pyramid, Treppe, Journey): only once they have Blender GLBs. EndingBlocks stays Flat on Android.
- Keep the one-live-scene and pause-when-idle rules, and keep the stills as the Android low-memory fallback.
- **Why not video or Lottie:** runtime case and theme tinting, multiple pose states and restart-on-reveal would multiply
  pre-rendered variants into the hundreds and lose the shading.
- **Verify before committing to stage 2:**
  - APK size added by Filament and gltfio per ABI;
  - glTF export of the multi-clip verb scenes;
  - frame rate on a low-end phone (the emulator isn't representative);
  - whether Skip resolves dark-appearance image variants for `figur-still`.
