# Android parity audit

What the iOS app (main @ 42b1cc7) has that the Android port (android-port @ ffd2307) doesn't,
and an order to close the gap. Written 2026-11-27 from reading both codebases. Nothing was built
for this audit; the Android screenshots in `android-parity/shots/` are from the emulator today.

Detail per area, with files, storage keys and effort per item:

- [`android-parity/settings.md`](android-parity/settings.md): every Settings pane and control
- [`android-parity/home-library-onboarding.md`](android-parity/home-library-onboarding.md): tab shell, Home, Library, onboarding, placement quiz, progress/gamification
- [`android-parity/3d-and-learning.md`](android-parity/3d-and-learning.md): every 3D surface, the port options, and Cards / Wortschatz / Grammar / Hören / Spiele / Matching
- [`android-parity/ai-platform-infra.md`](android-parity/ai-platform-infra.md): tutor features, content import, ink, sync, notifications, themes, persistence, model download, speech

Effort: S ≈ a day or two, M ≈ a few days to two weeks, L ≈ three weeks or more.

## Where things stand

iOS is ~185k lines of Swift across 27 feature folders; Android is ~3k lines of screens on top of
91 shared core files. What Android has: the four tabs, Goethe flashcards (Anki-style SM-2), the
Wortschatz list, Kasus lessons (text), der/die/das, a Präpositionen drill, Lückensätze, Perfekt
haben/sein, Die vier Fälle, Zahlen-Diktat, Galgenmännchen, Wortsuche, and the tutor (typed
Gespräch, Satz prüfen, models copied in with adb).

Android is ahead in a few small places worth keeping: Wortsuche (iOS has the engine, no
screen), the haben/sein quiz, the System/Light/Dark picker, the slow voice sample, per-level
reset, the Version row.

## The four things you noticed

### 1. No 3D / Figur animations
iOS has 86 USDZ scenes (~26 MB) on 11 user-facing surfaces: die Figur in the placement check
and the Treppe, preposition scenes (case game, cards, rules sheet), verb-preposition cards,
Kasus lesson scenes, endings blocks, the Lernpyramide, Dein Weg, the Schreibblatt celebration.
Skip has no 3D module and Android can't read USDZ.

- iOS already has a "Stills Only" path (`LightweightGraphics`), with 173 Blender stills plus
  `figur-still`. Android can behave like an iOS device set to Stills Only: about a day's work,
  no new dependencies. Gaps: the pyramid, journey and Treppe have no still yet.
- Real 3D afterwards: export GLB next to the USDZ in the two Blender export functions
  (`figur.py`, `prep_render.py` cover all 86 assets), render with SceneView (Filament, Compose)
  in a small Kotlin-bridged Skip module, like `GermanVoice`. Baked scenes first (Figur, 39 verb,
  5 Kasus, celebration); preposition scenes after their per-frame motion moves into a shared
  Swift file so both apps run one choreography.
- Not recommended: video/Lottie/sprites. The scenes are tinted per case and theme at runtime,
  so the variants run into the hundreds.
- Related trap: SkipUI has no `Canvas` (the file is commented out) and its `TimelineView`
  schedules are `fatalError()` stubs. The 2D stand-ins that use `Canvas` (Hangman gallows,
  `PyramidGlyph`, grammar task art) need rewriting with `Shape`/`Path`.

### 2. No entry quiz / no quiz in Settings
iOS: a one-time onboarding wizard (welcome → tutor offer → the three-minute check), plus
"Take the three-minute check" in Settings ▸ Your Level and Gamification. Android opens on Home
at A1, and Your Level is an inline A1–B1 picker.

- The engine is nearly portable as is: `PlacementService`, `PlacementSession`,
  `PlacementAttemptStore` import only Foundation; `PlacementResult`/`PlacementAttempt` are
  already in the core. `PlacementGrammarBank` needs `Bundle.main` → `AppResources.bundle`, and
  `placement_grammar.json` isn't copied to Android yet.
- The UI (`PlacementQuizStages`, 830 lines) is SwiftUI without SwiftData, so it adapts to Skip.
- No model needed: every item comes from bundled data. The cheapest large win in this audit.
- The level itself needs to change on Android: iOS stores CEFR A1–C1 under `german.level`
  (on `MLXModelManager`, which Android doesn't share); Android stores Goethe A1–B1 under
  `level`. Split the level setting into a Foundation-only file both apps use.

### 3. Settings is way off
Android has 6 of iOS's 17 panes, all of them partial; it has no icons, no grey summaries,
no `SettingsHeader`, no themes, and different grouping (App/Learning/About vs
Account/App/Learning/Model/About/Developer).

| iOS pane | Android |
| --- | --- |
| iCloud Sync | Missing (Auto Backup → Drive per `sync.mdx`) |
| Appearance (4 themes + 3D scenes) | Partial: System/Light/Dark only |
| Reminders | Missing |
| Voice (voice picker, dialogue voices) | Partial: sample + link to Android TTS settings |
| Keyboard | Missing (Android IME is its own project; `PROCESS_TEXT` is a cheap stand-in) |
| Gamification | Missing (the features behind it are missing too) |
| Your Level + placement check | Partial: A1–B1 picker, no check |
| Flashcards (style, front side, der/die/das first, repeat missed, haptics, matching…) | Partial: new words per session, reset |
| Conversation (name, strictness, corrections, hints, translations…) | Missing, though Gespräch runs on the shared `ConversationConfig` with hard-coded defaults |
| Stories | Missing (Stories not ported) |
| Model & Downloads | Partial as "Tutor Model": no download, RAM check, delete |
| Speicher · Memory | Missing |
| What's New, Send Feedback, Rate | Missing (all S) |
| Sources & Credits | Partial: 3 of 8 sections (the Kasus teaching sources are owed, Kasus lessons ship) |
| Developer | Missing (debug only) |

Fix: rebuild Settings on the `SettingsPane` structure (one list of panes with group, title, icon,
summary), add a Skip-safe `SettingsHeader` (no `symbolEffect`), and use the iOS storage keys so
sync can line up later. Key mismatches today: `german.level` vs `level`,
`wortschatz.newPerDay`/`sessionCap` vs `flashcards.newPerSession`, `selectedMLXModel` vs
`tutor.model`, `app.theme` vs `appearance`.

### 4. Library looks like an old version
It does, for a specific reason: Android lists the three Goethe decks, which iOS's
`UnifiedLibraryView` deliberately hides as activity plumbing. iOS's Library is an archive of
what the learner made: Decks · Chats · Reading · Phrases, with mix decks, deck stats, share,
course assignment and delete.

Android can't show that yet because it has no store for user content (`SavedDeck`,
`ChatConversation`, etc. are SwiftData), nothing to create decks with (generation needs the
tutor download; document/photo import needs OCR/PDF), and Gespräch keeps chats in memory only.

- Now (S): the iOS shell: segmented Decks/Chats/Reading/Phrases with iOS's empty states; move
  the Goethe levels to Home ▸ Vocabulary / Wortschatz where iOS has them.
- Then (M): a deck store plus `.kartei` import, so decks shared from an iPhone open on Android;
  splitting `DeckTransferEnvelope` out of `DeckTransfer.swift` makes that possible. Saved chats
  fill the Chats segment.

## Other gaps, by area

- **Home:** iOS has For You (Today plan, level card, streak calendar, week in review, Monatsbericht)
  and All Activities (7 tiles, 6 wide cards). Android has one due-cards row and a list.
  `TodayPlanner.plan` is a pure function three small splits away from the core.
- **Activity log:** nothing on Android records study days, so there's no streak, XP, badges or
  daily new-word budget. Android hands out new words per session, so reopening Karten gives
  another 10; iOS budgets per day. `StudyDay` needs a plain-value twin.
- **Gamification:** XP/rank, Tagesziel ring, 16 badges, celebrations, Fortschritt, Lernpyramide,
  Dein Weg: all missing.
- **Grammar:** the 19 Kasus drill types, Kasus stories and the case path are missing: the core
  of the grammar teaching. One split unblocks most of it (the value types in `KasusService.swift`,
  `KasusConceptPlayable`, a `KasusRound` twin; already listed in ANDROID_PORT.md). The Grammar
  hub layout (Üben/Fortschritt, Weiter, case path, areas, Nachschlagen) differs; Android is one list.
  Also missing: endings table and Werkstatt, Präpositionen cards / rules sheet / verb-prepositions,
  grammar progress and history.
- **Flashcards:** no Default or Leitner styles, no article-hiding quiz, no repeat-missed, no
  summary, no 3D flip (`rotation3DEffect` works in Skip), no user decks or pictures.
- **Matching:** missing, though the game view is portable (swap its Combine timer for a Task).
- **Hören:** numbers only; Diktat, carrier sentences, stats, Gist and Hör-Check missing.
- **Tutor:** typed only, nothing saved. Missing: voice input, autoplay with word highlight,
  Stammtisch, phrase library, review deck, quality stats.
- **Not started:** Stories, Schreiben, Schreibblatt, Deutschkurs/ClassNotes and worksheets, Job
  prep and Lebenslauf, Zeichnen, flashcards from a document, PhotoScan/Paper, the overnight queue,
  AI deck generation, the keyboard, reminders, sync/backup, themes.
- **Data not copied to Android yet:** `placement_grammar.json`, `kasus_concepts.json`,
  `kasus_stories.json`, `kasus_triggers.json`, `gap_choice_items.json`, `writing_prompts.json`,
  the 3D manifests, the 173 stills, `wiktionary_de.db`.

## What's in the way

Most gaps trace back to a few foundations, not to the screens themselves:

1. **Persistence.** ~35 SwiftData `@Model` types; Android has a JSON blob in UserDefaults whose
   card ids (`A1:word`) don't match iOS's. Plan: a SkipSQL store holding records in the same shape
   as the 30 sync codecs, behind per-feature store protocols. That is also step 1 of the sync plan.
2. **Model download.** The GGUFs aren't on Hugging Face yet, so the tutor only works via adb.
   Every AI feature is effectively missing for a real user until this lands.
3. **Speech.** TTS speaks; no word ranges, voice picker or background playback. No speech-to-text
   (Android `SpeechRecognizer` behind the core's existing `SpeechInput` protocol).
4. **Design system.** The theme tokens port; the Apple fonts (Noteworthy, Marker Felt, Futura)
   don't, so bundle open-licence substitutes. Do this before porting many more screens, or each
   one gets re-themed later.
5. **3D and 2D drawing.** As in #1 above.
6. **Platform modules** (Kotlin-bridged, like `GermanVoice`): notifications/WorkManager, text
   intake (ML Kit OCR, PDF text, URLs; five features need it), ink (four features).

## Phases

Each phase ends with something visible on the emulator. iOS behaviour doesn't change: splits on
the iOS side are moves into Foundation-only files, landed on main early so the branches don't drift.

**Phase 0: Line up (S).** Merge main into android-port (1 behind) and land the branch's iOS-side
splits on main (15 ahead). Copy the missing data files and stills into Android Resources.

**Phase 1: Placement check and onboarding (M).** Placement engine into the core; one shared level
setting (CEFR, `german.level`); the quiz UI; a two-step onboarding (welcome, check); Settings ▸
Your Level as its own screen with "Take the three-minute check". Die Figur appears as her still.

**Phase 2: Settings, Library and Home look like iOS (M).** Settings on the `SettingsPane`
structure with icons, summaries and header; the cheap panes (Conversation settings wired into
Gespräch, fuller Flashcards options, Feedback, Rate, What's New, full Sources). Library shell with
iOS's segments and empty states; Goethe decks back under Vocabulary. Home For You / All Activities.
Theme tokens and two themes with bundled fonts. Re-tap a tab to pop to root.

**Phase 3: Stills everywhere, then a 3D spike (S, then M).** Android as a Stills Only device: case
game reveal, Kasus lessons, preposition and verb cards. Rewrite the `Canvas` stand-ins with shapes.
Then a spike: GLB export of die Figur's assembly, played in SceneView on the emulator, with APK
size and frame rate measured on a real phone before committing to more.

**Phase 4: Persistence spine (M–L).** SkipSQL record store; study-day log (streak, daily new-word
budget); deck store with `.kartei` import; saved chats; card ids migrated to iOS's. Unlocks the
Library's content, the Today plan, streaks and Auto Backup. Reminders come at the end of this
phase, since they key off the last study day.

**Phase 5: Learning depth (L).** The Kasus split, then drills, stories, path and grammar progress.
Matching. Flashcard styles, flip and summary. Präpositionen cards, rules sheet and
verb-prepositions. Endings table and Werkstatt. Diktat. Wortschatz hub. XP, goal ring, badges,
celebrations, a 2D pyramid. Real 3D for the baked scenes, if the spike was good.

**Phase 6: The tutor for real users (M–L).** GGUFs on Hugging Face; in-app download with progress,
RAM check and delete (Model & Downloads). Speech-to-text and fuller TTS. Voice Gespräch,
Stammtisch, saved phrases. Stories. Typed Schreiben. AI deck generation.

**Phase 7: Import, ink, sync (L).** Text intake module → flashcards from a document, PhotoScan,
Paper, Deutschkurs, Job prep. Ink module → Schreibblatt, Zeichnen, handwriting. Overnight queue.
Google Drive sync. Keyboard via `PROCESS_TEXT` first.

Phases 1–3 need none of the foundations and can start now. Phase 3's spike can run alongside 1–2.

## Still to verify

- Filament/SceneView APK size and frame rate on a low-end phone; glTF export of the multi-clip verb scenes.
- Whether Skip picks the dark variant of an image asset (`figur-still`).
- `core_sync.py --prune` on the placement and TodayPlanner splits (portability above is from reading imports).
- Skip's file/photo pickers, skip-sql and skip-web specifics; ML Kit Digital Ink for German.
