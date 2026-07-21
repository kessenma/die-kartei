# Learner Memory & Learning History — Progress Tracker

A persistent, on-device "learner model" that turns the app's scattershot features into
one coach with continuity. It remembers what the learner keeps getting wrong (by grammar
concept), the words they're building, and their recurring slip-ups — then quietly uses
that to steer and sharpen future conversations, and surfaces it to the learner so they can
see (and correct) what the coach thinks of them.

Status legend: ✅ done · 🚧 in progress · ⬜ not started

---

## Vision

Language acquisition is a *cross-session* process. A good tutor remembers last week's
mistakes and deliberately brings them back this week (spaced retrieval + the noticing
hypothesis). Today each session is a self-contained event: chat → one-shot summary →
dismissed. The learner model is the through-line that connects sessions and makes the
whole app feel like one coach instead of eight tools.

## Core design principles

- **Bounded, structured — not a growing text log.** Memory is a small typed profile, never
  an append-only file. A closed grammar taxonomy (`GrammarFocus`, ~10 keys) + capped lists
  keep it from ballooning and from flooding the small on-device model.
- **The model only ever sees a ~60-token briefing.** The full profile lives in storage and
  is shown to the *user* in Settings. Only a prioritized top-slice is injected into prompts.
- **Self-cleaning via decay + caps, not deletion.** Grammar struggle decays each session;
  vocab/slips are LRU-capped and slips self-heal when used correctly.
- **Cleaning archives, never destroys.** Cleaned items move to an archive the user can view
  and restore; pinned items are exempt from cleaning. The archive is *never* injected into
  the model, so it can grow freely without any prompt cost.
- **Structured, not vectors.** The profile is keyed and retrieved by rule (top-N by
  struggle / recency), so embeddings would add an on-device model, opacity, and worse dedup
  to solve a retrieval problem we don't have. (Vectors are reserved for a possible future
  *semantic search over raw transcripts* — a separate feature.)

## Architecture

```
                 ┌─────────────────────────── ACTIVE PROFILE (bounded, in SwiftData) ──┐
 session end ──▶ │  grammar: [GrammarFocus.key: GrammarSkill]   (fixed keys, can't grow)│
 (endAndSummarize)│  vocab:   [VocabTouch]                       (LRU cap 60)           │
                 │  slips:   [LexicalSlip]                       (LRU cap 20, self-heal)│
                 └──────────────┬───────────────────────────────────┬──────────────────┘
                                │ render top-slice                   │ evict / heal
                                ▼                                     ▼
      session start ──▶  ~60-token briefing            ARCHIVE  [ArchivedMemoryItem] (SwiftData)
      (engine init)      injected into system &        (never injected; user-facing + restore)
                         correction prompts
```

- **Write** — `ConversationEngine.endAndSummarize()` already runs one summary LLM call; we
  piggyback structured `WEAK:`/`STRONG:` grammar tags onto it (no extra call) and derive
  vocab from saved words + single-token slip diffs from the turn corrections.
- **Read** — `ConversationEngine.init` builds the briefing/correction-hint from the profile
  and injects them via `ConversationConfig.learnerBriefing` / `.correctionMemoryHint`.
- **Storage** — SwiftData, following `ChatConversation`'s "Codable-blob inside `@Model`"
  pattern. Active profile = one singleton row; archive = one row per cleaned item (queried
  lazily so history never loads all at once).

---

## Phase 1 — Core memory + briefing + archive  ✅

The mostly-invisible engine: the coach starts remembering across sessions.

- ✅ `LearnerProfile` + `ArchivedMemoryItem` SwiftData models (`GrammarSkill`, `VocabTouch`,
  `LexicalSlip` value types; `pinned` flag on active items) — `Models/LearnerProfile.swift`
- ✅ `LearnerMemoryService`: fetch-or-create singleton, per-session decay + `WEAK`/`STRONG`
  delta, vocab merge, single-token slip extraction, slip self-heal, LRU eviction → archive,
  briefing + correction-hint renderers, restore/forget/pin/reset helpers — `Services/LearnerMemoryService.swift`
- ✅ Extend `summarySystemPrompt` with `WEAK:`/`STRONG:` lines + `parseProfileSignals`
- ✅ Inject briefing into `systemPrompt` (steering-only) and correction-hint into
  `correctionSystemPrompt` (watch-for) via new `ConversationConfig` fields
- ✅ `chatPersonalizedCoaching` gating flag on `MLXModelManager` (default on) + toggle in
  `ConversationSettingsView`
- ✅ Register `LearnerProfile` + `ArchivedMemoryItem` in the app schema
- ✅ Builds clean on the simulator (2026-07-13)

### Not yet verified at runtime
The build compiles, but a live end-to-end run (memory populating after a real session) needs a
downloaded MLX model + mic, which the simulator can't exercise. Verify on device: have a chat,
end it, then confirm the next session's system prompt carries a COACH MEMORY block. The Phase 2
Coach's Notes screen will also make this directly inspectable.

## Phase 2 — Make it visible ("Coach's Notes")  ✅

`Features/Settings/CoachNotesView.swift`, reached via Settings → Conversation → Coaching → Coach's Notes.

- ✅ Read-only Settings screen: session count + last-practiced, grammar confidence bars
  (Solid / Getting there / Needs work, with a sample), "words you're building", "slip-ups it's watching"
- ✅ Archive sub-screen (`MemoryArchiveView`) with reason + relative date; swipe to restore
  (auto-pins) or forget; badge count on the entry row
- ✅ Pin/unpin + remove active vocab & slips via swipe
- ✅ "Reset what the coach remembers" (confirmed alert)
- ✅ Builds clean + app boots with the new schema (2026-07-13)
- ⬜ Not yet driven at runtime here (session can't tap-navigate); verify the screen on device/Xcode.
  Streak intentionally deferred — needs per-day session history we don't track yet.

## Phase 3 — Close the loop to flashcards  ✅

`Features/Settings/DrillDeckView.swift`, reached from Coach's Notes → "Build a drill deck".

- ✅ Builds `SavedCard`s from the profile's `vocab` (word/meaning) and `slips` (correct form +
  "you wrote «X»" hint), fully offline — no model needed since the memory is already structured
- ✅ Source picker (Words / Slip-ups / Both, auto-limited to what exists), per-card selection,
  new-deck-or-merge destination (dedupes, mirrors `ReviewDeckView`); new decks tagged
  `generatorRaw = "coach-drill"` and flow into the existing SRS/`CardDeckView`
- ✅ "Build a drill deck" entry in `CoachNotesView` (shown when there's anything to drill)
- ✅ Builds clean on the simulator (2026-07-13)
- ⬜ (v2) Personalized **cloze** cards from the learner's own sentences (needs the full sentence
  stored on slips + a new card variant — deferred)

## Phase 4 — The "Today" screen + streaks  ✅

`Features/Home/TodayView.swift` (`TodaySection`), pinned at the top of `HomeHubView`. The first
of the named follow-ons (`FUTURE_FEATURES.md` #1) — turns the profile into a coach that says
"here's the one next thing."

- ✅ `TodayPlanner` (pure): builds a short, ordered, adaptive plan from a `TodaySnapshot` —
  *review due SRS cards* → *practice a rotating weak grammar spot* → *streak-keeping chat*, with
  cold-start (generate a deck) and no-due-but-has-memory (build a drill deck) fallbacks
- ✅ One-tap launches: due-card review = a cross-deck Anki `StudySession` via `ActivityRouter`
  (SRS advances per card, no deckID needed); grammar = MC drill where exercises exist
  (Akkusativ/Dativ), else a `GrammarFocus.explanation` mini-lesson sheet (seeds #4); chat pushes
  `ConversationListView`
- ✅ Weak-spot rotation (`dayIndex % weaknesses.count`) for day-to-day interleaving
- ✅ **Streak backing (#6 prereq):** new `StudyDay` `@Model` + `StudyLogService`; one row/day,
  incremented from `DeckStore.saveQuizResult` / `saveGrammarQuizResult` and
  `LearnerMemoryService.applySession`. Streak = run of consecutive days, "alive" from yesterday
- ✅ Registered `StudyDay` in the app schema; builds clean on the simulator
- ⬜ Not yet driven at runtime here (session can't tap-navigate / run MLX). Verify the plan,
  streak increment, and each launch on device.

## Phase 5 — Matching game feeds the profile  ✅

The card-matching game gets its own persistent memory (`Models/MatchingStats.swift` +
`Services/MatchingStatsService.swift`) and hands its recurring trouble words to the coach —
the first *non-conversation* writer into the learner profile.

- ✅ `MatchingPairStat` @Model — per word-pair lifetime stats: rounds seen/missed, first-try
  streak, and a confusion map (*which wrong meaning it keeps being paired with* — the "same
  mistake again" signal). `MatchingRound` @Model backs the progress strip + personal bests.
- ✅ `MatchingStatsService.recordRound` — folds each round in and returns history-aware summary
  feedback ("missed ×3", "you keep pairing it with …", personal best). A pair is *tricky* after
  2 missed rounds; it graduates after 3 first-try rounds in a row (self-healing, like slips).
- ✅ Coach hand-off: tricky words flow into `LearnerProfile.vocab` via
  `LearnerMemoryService.noteMatchingTrouble` (recognition trouble = "word they're building" —
  deliberately *not* a slip, which stays production-only). They ride the existing briefing
  ("naturally work in words they're learning"), appear in Coach's Notes, and are drillable.
  Gated by Settings → Cards → Card Matching → "Share tricky words with the coach" (default on).
- ✅ Rounds bias toward tricky pairs (up to half the board, `DeckStore.matchingSample`) —
  spaced re-encounter for recognition, toggleable ("Bring back tricky pairs", default on).
- ✅ Progress UI: picker header (rounds, recent first-try %, tricky count) + `TrickyPairsView`
  (per-pair history, swipe to remove, reset-all) — `Features/Matching/TrickyPairsView.swift`.
- ✅ Settings: pairs per round (6/8/10/12) + both toggles on `MLXModelManager`, surfaced in
  `CardSettingsView`. Registered both @Models in the app schema.
- ⬜ Verify on device: play two rounds missing the same pair → summary shows "missed ×2",
  pair appears in Tricky Pairs and (after the threshold) in Coach's Notes vocabulary.

## Phase 6 — Grammar hub: drills read *and write* the profile  ✅

`Features/Grammar/GrammarHubView.swift` (one consolidated Grammar screen) + `AIGrammarCreateView.swift`.

- ✅ **Read:** "Coach's Picks" section surfaces shaky structures (worst-first, cap 3) at the top of
  the consolidated grammar hub; Akkusativ/Dativ/Perfekt sections get a "Needs work" flame when the
  profile says so; the AI exercise creator preselects the weakest structure and flags weak ones in
  its picker; an optional toggle weaves the profile's recent vocab into generated sentences
- ✅ **Write:** `LearnerMemoryService.applyDrillResult` — a finished multiple-choice drill nudges
  that one structure's struggle (≥85 % correct lowers it, <60 % raises it; smaller steps than
  conversation WEAK/STRONG tags, no `sessionCount` bump). Wired in ContentView via
  `GrammarCategory.grammaticalCase`, which carries the `GrammarFocus` raw value for bundled and
  AI categories alike
- ✅ AI-generated exercises: `MLXGenerationService.generateGrammarExercises` (per-focus prompt
  seeds for all 10 `GrammarFocus` structures, tolerant JSON parse + normalization) + a bundled
  100-topic catalog (`grammar_topics.json`) with type-your-own / scroll / dice-roll selection —
  results run in the existing `GrammarMultipleChoiceView`
- ✅ `GrammarLessonSheet` extracted to `Features/Grammar/` and shared by Today + the hub
- ✅ Builds clean on the simulator (2026-07-14)
- ⬜ Generation quality needs on-device testing (sim can't run MLX): verify each focus produces
  sensible blanks/options, and that a completed drill moves the Coach's Notes confidence bar
- ⬜ (v2) Persist generated exercise sets so a good one can be replayed later without regenerating

## Phase 7 — Streak calendar (FUTURE_FEATURES #6)  ✅

`Features/Home/StreakCalendarView.swift` — a study-streak calendar with a range toggle, dropped in
at the top of the Home hub's "For You" screen (right by the streak flame) as a self-contained
`StreakCalendarSection`.

- ✅ `StreakCalendarSection`: owns its own `@Query<StudyDay>`, renders "Your Streak" + flame
  (reusing `StudyLogService.currentStreak`), a segmented `StreakRange` toggle
  (Week / Month / 3 Mo / Year, persisted via `@AppStorage("streak.calendarRange")`, default Month),
  and the shade legend. Intensity = the day's total `cardsReviewed + grammarExercises +
  conversations`, so a colored cell and a streak day are always the same thing.
- ✅ Finger-friendly `WeekStrip` + `MonthGrid`: big tappable day cells (48–50pt) with the day
  number, `‹ › ` paging (can't page into the future), today accent-ringed, future days faded.
- ✅ `StreakGrid` (the GitHub-style heatmap) serves both **3 Mo** (13 weeks, cell 17, tappable)
  and **Year** (53 weeks, cell 10, *not* tappable — a glance-only overview): weeks as columns
  (Mon…Sun rows), horizontally scrolled to land on today; month labels along the top, a *pinned*
  Mon/Wed/Fri key that survives the auto-scroll. Empty→deep-blue ramp in `StreakShade`
  (0 = `tertiarySystemFill`).
- ✅ `DayDetailSheet`: tap any day → a timeline of what was practiced that date, fetched on demand
  from the timestamped records (`QuizResult` for flashcards + grammar via `generatorRaw == "grammar"`,
  `ChatConversation`, `MatchingRound`, `StudyPaper`). Falls back to `StudyDay` totals for the one
  trail-less case (cross-deck Daily Review, which has no deck to hang a `QuizResult` on).
- ✅ Builds clean + renders on the simulator (2026-07-15; empty grid, since a fresh install has no
  history).
- ⬜ Verify on device with real history: the light→dark shading across days and the tapped-day
  breakdown. Matching-only / photo-only days show in the detail but don't yet tint the grid
  (they don't feed `StudyDay`) — revisit if that inconsistency bites.

## Phase 8 — Der/die/das article game reads *and* writes the profile  ✅

`Features/Grammar/ArticleGame/` (setup / game / rules sheet) + `Models/ArticleGame.swift`,
`ArticleRules.swift`, `ArticleStats.swift` + `Services/ArticleGameService.swift`. The second
non-conversation writer (2026-07-21), and the first to move a *grammar* skill from a game.

- ✅ New `GrammarFocus.artikel` key: every finished round nudges the profile's Artikel skill via
  the existing `applyDrillResult` rail (first-try accuracy = the drill score), so noun gender
  shows in Coach's Notes bars, gets a "Needs work" flame in the Grammar hub, surfaces as a
  Coach's Pick (which routes straight to the game), and steers conversations
- ✅ Vocab hand-off mirrors matching (Phase 5): a noun missed in ≥2 rounds (until 3 first-try
  rounds in a row) flows into `LearnerProfile.vocab` via `noteVocabEncounters`, gated by
  Settings → Cards → Der · Die · Das → "Share missed nouns with the coach" (default on)
- ✅ Read direction: a "Words You're Learning" round source drills the profile's own vocab, with
  articles resolved by the bundled Wiktionary (unambiguous-gender nouns only)
- ✅ Own stats mirror `MatchingStats`: `ArticleWordStat` (misses + *which wrong article keeps
  being picked*) and `ArticleRound` history; tricky nouns bias round sampling; both registered
  in the app schema
- ✅ Streak: rounds record as `.grammar(n)` through `StudyLogService` (→ `StudyDay` → flame +
  calendar shading), and `ArticleRound` rows appear in the streak calendar's day-detail timeline
- ⬜ Verify on device: a finished round moves the Artikel bar in Coach's Notes, missed nouns
  reach the coach's vocabulary, and the round shows up on the tapped calendar day

## Phase 9 — Stories become tracked study (time + questions)  ✅

`Models/StoryStats.swift`, `Services/StoryProgressService.swift`, `Services/StoryReadingTimer.swift`,
`Features/Settings/StorySettingsView.swift` + `StoryProgressView.swift`. Stories were the one big
feature that left almost no trace: reading one earned nothing unless you answered questions, and
those questions were logged as if they were flashcards. (2026-07-21)

- ✅ **Reading counts as study.** `StoryReadingTimer` (wall-clock stamps, not tick counting) runs
  while `StoryDetailView` is on screen and the app is in the foreground — including under the
  read-aloud player — and pauses/flushes on background, on leaving, and on a Lesen↔Hören switch so
  each stretch is tagged with the mode it was spent in. Flushed stretches become
  `StoryReadingSession` rows (<15 s dropped) and `StudyDay.storySeconds`; a day needs
  `StudyDay.storyStreakSeconds` (60 s) of reading to count on its own, so a glance can't keep a
  streak alive but a real read with no questions can. Gated by "Reading counts as study" (default on).
- ✅ **Questions are their own activity.** `StoryQuizAttempt` (score, duration, listening flag,
  written-answer count) + `StudyDay.storyQuestions`, replacing the old
  `StudyLogService.record(.cards(n))` fudge. New `StudyActivity` cases: `.storyReading(seconds)`,
  `.storyQuestions(n)`.
- ✅ **Calendar.** Story minutes + questions join the shade intensity (1 unit per minute read), and
  the day-detail timeline gains reading/listening stretches (with lookups + words saved) and quiz
  runs, plus a `StudyDay`-totals fallback row like the other trail-less cases.
- ✅ **Learning capture → the coach.** Words saved while reading already flowed in via
  `noteVocabEncounters`; added `LearnerMemoryService.noteWrittenCorrections` — single-token fixes
  from model-graded free-response answers become slips (with the corrected sentence, so they're
  cloze-ready), *without* the self-heal pass or a `sessionCount` bump (drill-style, like
  `applyDrillResult`). Missed blanks still feed vocabulary. All three hand-offs gated by
  Settings → Stories → "Share story words with the coach" (default on).
- ✅ **Surfaces.** A fourth Settings tab (Cards / Chat / Stories / Model — "Conversation" shortened
  to fit four segments) holding the tracking toggles, new-story defaults, and a "Reading progress"
  screen: total time, stories read, longest sitting, listening share, story-only day streak,
  question accuracy, perfect runs, lookups/saves, a per-CEFR-level breakdown, and recent sessions.
  Story rows in the list and the story header show time spent.
- ✅ Registered `StoryReadingSession` + `StoryQuizAttempt` in the app schema; `StudyDay`'s two new
  fields carry defaults for lightweight migration. Builds clean on the simulator (2026-07-21).
- ⬜ Verify on device: read a story for a minute without answering anything → the day tints in the
  calendar and the flame survives; a finished quiz shows as "Fragen · <title>" in the day detail;
  a graded written answer with a "Besser:" rewrite appears as a slip in Coach's Notes.
- ⬜ (next) Let the Today plan recommend a story — reading is now measurable, so "keep reading
  <title>" can be a first-class next action alongside due cards and a weak-grammar drill.

---

## Feature complete (Phases 1–3)

The loop is closed: conversation mistakes → structured, self-cleaning memory → (a) personalized
steering + sharper corrections next session, (b) a visible/editable Coach's Notes screen, and
(c) drillable flashcards feeding the existing SRS. Still to verify end-to-end on device (needs
MLX model + mic). Natural follow-ons: the "Today" home screen, elicitation-style feedback, and
v2 cloze cards.

---

## Decisions log

- **2026-07-13** — Chose structured profile over vector store (small keyed data, rule-based
  retrieval, must stay human-readable/editable). Embeddings deferred to possible transcript search.
- **2026-07-13** — Archive requirement tipped storage from UserDefaults → SwiftData (archive
  can grow; `@Model` pages it lazily). Active buckets stored as Codable `Data` blobs, mirroring
  `ChatConversation`.
- **2026-07-13** — Split injected memory into two flavors: steering-only for the conversation
  prompt (which must NOT correct) and watch-for for the separate correction pass.

## Open questions / future ideas

Full roadmap with designs, code hooks, and prioritization: **`FUTURE_FEATURES.md`**. Highlights:

- "Today" home screen that recommends the next action from the profile (biggest anti-scattershot win).
- Just-in-time grammar mini-lessons (reuse `GrammarFocus.explanation` + `GrammarExercise`).
- Elicitation-style feedback mode (nudge self-correction vs. handing the answer).
- v2 personalized cloze cards from the learner's own sentences.
- Feed anonymized aggregate weak-area distribution into the Gemma grammar fine-tune (see
  `training/PLAN.md`) to emphasize what learners actually struggle with.
