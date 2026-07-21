# Future Features — Learning Experience Roadmap

Ideas for making the app a richer, stickier learning tool, building on the learner-memory
foundation (see `LEARNER_MEMORY.md`). Each entry says *what*, *why it works pedagogically*,
*how it plugs into the existing code*, and a rough effort (S / M / L).

The through-line: the app now has a persistent **learner model** (`LearnerProfile`). Most of the
highest-value features are things that *read from* or *write to* that model — that's what turns a
pile of features into one coherent coach.

Legend: 💎 high impact · 🔨 effort S/M/L · 🔗 depends on

---

## Tier 1 — The named follow-ons (do these next)

### 1. The "Today" home screen  💎💎💎  🔨 M  — ✅ Shipped
**The single biggest anti-"scattershot" lever.**

> **Shipped:** `TodaySection` (pinned at the top of `HomeHubView`) reads the profile + SRS backlog +
> streak and renders a short, ordered plan via `TodayPlanner`. Recommendations are one tap:
> *Review N due cards* (cross-deck Anki review through `ActivityRouter`), *grammar practice* on a
> rotating weak spot (MC drill where one exists, else a `GrammarFocus.explanation` mini-lesson —
> seeds #4), and a streak-keeping *chat*. The streak is backed by a new per-day `StudyDay` log
> (the #6 prereq, below), recorded at every activity-completion point. The weak-spot rotation
> (`dayIndex % weaknesses.count`) delivers the "interleaving" nice touch.

Right now every feature is a peer entry in a flat list (`ConversationListView`, the Home tab), so
the learner has to decide *what* to do every time. A great tutor removes that decision: "here's the
one next thing." A **Today** section at the top of the Home tab reads `LearnerProfile` + due SRS
cards and recommends a short, ordered plan:

> **Today** · Review 8 due cards · 3-min drill on *Dativ* (your recurring weak spot) · 5-min chat to keep your streak

- **Why it works:** reduces decision friction (the #1 reason learning apps go unopened), and makes
  the app feel like it has a plan *for you* — the difference between a toolbox and a coach.
- **How it plugs in:** a new card/section in the Home feature, launched through the `ActivityRouter`
  you just built. Pull "what's shaky" from `LearnerMemoryService` (reuse the `briefing`/grammar
  sort), "what's due" from `SavedCard.nextReviewDate` via your SRS service, and "streak" from
  `LearnerProfile.lastSessionAt` + a small daily-session log. Each recommendation is a one-tap
  `router.launch(...)`.
- **Nice touch:** rotate the recommendation so it's never the same three days running (interleaving).
- 🔗 `LearnerProfile`, `SpacedRepetitionService`/`LeitnerService`, `ActivityRouter`, Home feature.
- **Prereq for a real streak:** a lightweight per-day session log (see #6).

### 2. Elicitation-style feedback  💎💎  🔨 M  — ✅ Shipped
**Let the learner self-correct instead of handing them the answer.**

> **Shipped:** a new `FeedbackStyle` axis (`.tellMe` / `.nudgeMe`) sits alongside `CorrectionStrictness`
> — a segmented **Feedback** picker in Conversation settings (`chatFeedbackStyleRaw`), threaded into
> `ConversationConfig` and persisted per-chat on `ChatConversation`. In **Nudge me**, the correction
> pass emits an extra `HINT:` line (a German question pointing at the error's category, no answer given);
> `parseCorrection` captures it into `CorrectionResult.hint` and stashes it (plus the hidden fix) on the
> message. The engine then **defers the AI reply** and raises a `RepairPrompt` — reusing the exact mic /
> try-again rail as `SayItPrompt`: the next spoken turn is judged against the corrected sentence via
> `phraseSimilarity`. A good-enough retry marks `ChatMessage.selfCorrected` (green "You fixed this
> yourself" card + a **Self-fixed** session stat) and continues the conversation; a miss reveals the
> answer (per "only after a miss, or on request") so they can try again, hear it, or skip. `NudgePromptCard`
> mirrors `SayItPromptCard`; the full correction stays hidden until the nudge resolves. The hint can name
> the learner's known weak tag because `correctionMemoryHint` already feeds the correction prompt. **Tell
> me** is unchanged (the default), so existing chats behave exactly as before.

There's a well-established hierarchy of corrective feedback: simply *reformulating* a mistake
(a "recast") is gentle but often not *noticed* and doesn't stick; **prompting the learner to repair
their own error** produces far more durable learning. Add a feedback *style* axis alongside your
existing `CorrectionStrictness`:

- **Tell me** (today's behavior): shows `FIX:` + `WHY:`.
- **Nudge me**: instead of the fix, the coach asks a targeted question — *"Fast! Welcher Fall kommt
  nach 'mit'?"* — and lets the learner try again. Only after a miss (or on request) does it reveal.

- **Why it works:** a learner who repairs their own error retains the rule dramatically better than
  one who's handed it. This is the difference between passive and active correction.
- **How it plugs in:** add a `FeedbackStyle` enum + setting (mirror `CorrectionStrictness` in
  `MLXModelManager`/`ConversationConfig`). Extend `correctionSystemPrompt` to emit a `HINT:` line
  (a question pointing at the error's category) instead of `FIX:` when in Nudge mode; parse it in
  `parseCorrection`. The **retry UI already exists** in spirit — `SayItView`'s "try again / matched"
  loop is the exact pattern to reuse for a second attempt at a corrected line.
- **Memory synergy:** the hint can name the learner's known weak tag ("remember, Dativ after *mit*")
  straight from `correctionMemoryHint`.
- 🔗 `ConversationPrompts.correctionSystemPrompt` + `parseCorrection`, `ConversationEngine` correction
  flow, `SayItView` (retry pattern), `LearnerProfile`.

### 3. v2 personalized cloze cards  💎💎  🔨 M  — ✅ Shipped
**Fill-in-the-blank cards made from the learner's *own* sentences.**

> **Shipped:** `LexicalSlip` now carries the learner's `sentence` (the corrected line) + `blankIndex`
> (the token to blank), captured in `LearnerMemoryService.applySlips` — `singleTokenDiff` already knew
> the differing token's position, so it just returns it. From those, `ClozeSession.build(from:)` makes
> a short round of `ClozeCard`s (the sentence with the fixed word blanked, punctuation preserved). A
> new `.cloze(ClozeSession)` `Activity` presents `ClozePracticeView` immersively through the existing
> `ActivityRouter` cover — a self-graded recall flow (reveal → *Got it* / *Missed it*), mirroring the
> matching game. **Closing the loop:** a correct fill retires that slip via
> `LearnerMemoryService.applyClozeResults` (archived `.mastered`, restorable — the same self-heal a
> clean production earns), a miss just refreshes it, and the round feeds the per-day streak
> (`StudyLogService.record(.cards(...))`). Launch point: a **Fix your sentences** row in Coach's Notes,
> shown once any slip has a stored sentence. No SwiftData schema change — the slip fields are additive
> `Codable` on `LearnerProfile.slipsData`, and the session is ephemeral like `MatchingSession`.

Today's Phase-3 drill cards are solid (word ↔ meaning; correct-form of a slip). The stickiest
possible card, though, is a **cloze from the sentence the learner actually got wrong**:

> You said: *"Ich gehe mit **der** Freund"* → card: *"Ich gehe mit ___ Freund"* (answer: **dem**)

- **Why it works:** it carries the learner's real context and their real error, so retrieval practice
  happens on exactly the gap that needs closing — far more memorable than an abstract rule card.
- **What it needs:** currently `LexicalSlip` stores only the single-token diff (`wrong → right`), not
  the sentence. Add `sentence` (the corrected full sentence) + the blanked token to the slip when it's
  created in `LearnerMemoryService.applySession` (the correction already has the full corrected line).
  Then a cloze card = the sentence with the target token blanked; the answer is the token.
- **How it plugs in:** either a new `FlashcardStyle`/card variant that renders a blank, or reuse
  `SavedCard.exampleSentence` to hold the sentence and store the blank position. `DrillDeckView` gets
  a third source: "Sentences to fix." *(Shipped as its own `.cloze` Activity + `ClozePracticeView`
  rather than a `DrillDeckView` source — a blank needs bespoke rendering the flashcard player doesn't
  do, and a dedicated immersive activity matches the matching-game precedent and keeps `CardDeckView`'s
  SRS state machine untouched.)*
- 🔗 `LexicalSlip` (+ new fields), `LearnerMemoryService.applySession`, `SavedCard`/`FlashcardStyle`,
  `DrillDeckView`.

---

## Tier 2 — Other high-value ideas

### 4. Just-in-time grammar mini-lessons  💎💎  🔨 S–M  ✅ Shipped
When a grammar tag crosses a struggle threshold, the coach offers a **30-second explanation + a
targeted micro-drill** — turning "you keep missing Dativ" into something actionable instead of just
diagnostic. You're *already carrying the explanation text*: `GrammarFocus.explanation` has a clear,
example-rich gloss for every structure. Surface it (in Coach's Notes next to a shaky bar, and/or on
the Today screen) with a "Practice this" button that launches a focused `GrammarExercise`.
- 🔗 `GrammarFocus.explanation` (exists), `GrammarExercise`/`GrammarExerciseService` (exists),
  `LearnerProfile` grammar map. **Low effort, high payoff** — mostly wiring existing pieces together.
- **Shipped:** shaky Coach's Notes grammar bars now expand into a "Quick lesson" (the `explanation`)
  with a **Practice this** button that launches the focused drill via `ActivityRouter`; Today
  already surfaced the lesson fallback. Shared `GrammarExerciseService.category(for:rotation:)` maps
  a `GrammarFocus` → its drill (Akkusativ/Dativ ship exercises today; others show the lesson + a
  "watch for it in your next chat" nudge), and `GrammarSkill.shakyThreshold` unifies the weakness
  cutoff across Today and Coach's Notes.

### 5. Spaced re-encounter *inside* conversation  💎💎  🔨 M  — ✅ Shipped
The memory already feeds recent vocab into the prompt. Make it *deliberately SRS-timed*: when a word
is "due" per its `SavedCard` schedule, steer the conversation so it comes up, and if the learner uses
it correctly, count that as a successful review and advance its interval. This is spaced repetition
happening naturally in dialogue — the holy grail of "sticky," and something flashcards alone can't do.
- 🔗 `SavedCard` SM-2 fields, `SpacedRepetitionService`, `LearnerMemoryService` briefing, correction
  pass (to detect correct usage). Bigger because it couples SRS scheduling to live conversation.

> **Shipped:** a session-scoped `ConversationReviewTracker` (built in `ConversationEngine.init`, next
> to the coach-memory injection) fetches genuinely-due cards — `nextReviewDate ≤ now` **and** already
> scheduled at least once, so a fresh unstudied deck doesn't flood it — most-overdue first, capped at
> 8. Their (article-prefixed) words go into `ConversationConfig.dueReviewWords`, which
> `ConversationPrompts.systemPrompt` turns into gentle "create openings for these; don't announce it"
> steering. Each turn, `registerTurn` reuses `matchedWords` to detect a due word the learner produced,
> and — when the turn was corrected — only credits words that *survived into the corrected sentence*
> (so a word the fix rewrote doesn't count). A credited card gets `SpacedRepetitionService.apply(.good)`,
> advancing its real interval and leaving the pending set. Feedback: a persistent `ChatMessage.reviewedWords`
> chip on the bubble ("🔁 reviewed: …") and a "Reviewed in conversation" section + `ConversationSummary.spacedReviews`
> in the report. Gated by a new **Spaced review** setting (`chatSpacedReview`, default on) with a
> `SpacedReviewScope` picker — *Everywhere* (library-wide, deck chats favor their own decks) /
> *Deck chats* / *Skip role-plays* (freestyle + decks; leaves scenario & paper alone).

### 6. Progress & streaks over time  💎💎  🔨 S–M  — 🚧 per-day log landed
The streak half is done: a `StudyDay` `@Model` (one row/day, counting cards / grammar /
conversations) now backs the Today streak, written via `StudyLogService.record(...)` from every
completion point. Still to build on top of it: the **growth view** ("self-corrections up 3× this
week", "12 words retained") and trend context on Coach's Notes.

The original idea — a lightweight **per-session log** (date, turns, corrections, self-corrections, new words retained)
unlocks: a real streak, a "growth" view ("self-corrections up 3× this week", "12 words retained"),
and trend context on the Coach's Notes stats. Frame stats as *growth*, not vanity counts — that's
what motivates. This is also a **prerequisite for the Today streak (#1)** and a natural home for the
"was that correction better than last time?" framing.
- 🔗 a small new `@Model SessionLog` (or extend `ConversationSummary` persistence), Coach's Notes,
  Today screen.

### 7. Weekly "recap" session  💎  🔨 S
A one-tap session type that deliberately recycles **this week's weak tags + saved words** into a
single conversation (interleaving + spaced retrieval in one sitting). It's mostly a pre-built
`ConversationConfig` seeded from `LearnerProfile` — small effort, and it gives the app a satisfying
weekly rhythm.
- 🔗 `LearnerProfile`, `ConversationConfig`, `ConversationSetupView`.

### 8. Adaptive difficulty (comprehensible input, i+1)  💎  🔨 M
Use the learner's known vocabulary (decks + `LearnerProfile.vocab`) to keep the AI's German mostly
within reach, sprinkling a few new words and flagging them. Optionally auto-nudge the CEFR `level`
up/down based on correction density. Keeps input in the "just hard enough" zone (Krashen's i+1).
- 🔗 `CEFRLevel`, `ConversationPrompts.systemPrompt`, `LearnerProfile`, deck words.

### 14. Card matching game  💎💎  🔨 S–M  ✅ Shipped
**A fast, gamified recognition drill over any deck — the "snackable" 2-minute activity.**

> **Shipped:** a new `.matching(MatchingSession)` `Activity` presented immersively through the
> existing `ActivityRouter` cover in `ContentView`, exactly like `.cardDeck`. `MatchingGameView` is
> the two-column tap-to-pair grid: independently shuffled German/English tiles, a match clears with a
> spring animation while a mismatch flashes red and stays, a live timer, success/error haptics via
> `.sensoryFeedback`, and a round summary (time + first-try accuracy + Play again). A Home ▸ Vocabulary
> **Card Matching** tile opens `MatchingDeckPickerView` (bundled Goethe levels + the learner's own
> decks with ≥4 pairs); `DeckStore.matchingSession(from:)` / `.goetheMatchingSession(level:)` sample
> ~8 valid pairs and carry the deck's `generatorRaw` for the brand tint. On finish it reuses
> `saveQuizResult(studyMode: .default, subDeckLabel: "Matching · N pairs")`, so results slot into
> per-deck stats and the streak/Today log with no schema change.

A timed grid: tap a German tile, then its English match; a correct pair clears with a little
animation, a wrong pair flashes and stays. One round is ~6–8 pairs from a deck; finish the grid,
see time + first-try accuracy, play again or leave. It's the recognition-based counterpart to
flashcards (which lean on recall).

- **Why it works:** it's still **retrieval practice**, but in a low-stakes, high-tempo form — many
  quick form↔meaning retrievals per minute, with immediate clear/flash feedback that creates flow.
  Matching exercises *recognition* (easier than free recall), which makes it a good **on-ramp for
  new or shaky vocab** and a warm-up before harder study. The short round length makes it the ideal
  "just 2 minutes" activity — exactly what a streak/Today plan wants to offer on a busy day.
- **How it plugs in** (most rails already exist after the hub-and-spoke refactor):
  - **New `Activity` case** — `.matching(MatchingSession)` in `App/Activity.swift`, presented
    immersively through the existing **`ActivityRouter`** `.fullScreenCover` in `ContentView`,
    exactly like `.cardDeck`. No new navigation plumbing.
  - **New `Models/MatchingSession.swift`** (mirrors `StudySession`): `cards: [VocabCard]` (cap ~6–8
    pairs/round), `deckID`, `topic`, `generatorRaw` (for the brand tint).
  - **New `Features/Matching/MatchingGameView.swift`** — the grid, tap-to-pair state machine, timer,
    and round summary. Reuse `CardDeckView`'s brand-accent pattern (`generatorModel?.theme.accent`)
    so a matched deck keeps its model's colors.
  - **Launch:** a deck picker → `router.launch(.matching(DeckStore(modelContext:).matchingSession(from: deck)))`.
    Add a **Home ▸ Vocabulary tile** ("Card Matching") in `HomeHubView`, and give `DeckStore` a
    `matchingSession(from: SavedDeck)` builder (mirror `session(for:)`). Optionally offer "Match" as a
    second launch from an open deck's setup screen.
  - **Persistence — no schema change.** On round complete, reuse **`DeckStore.saveQuizResult(...)`**
    with `studyMode: .default`, `totalCards = pairs`, `correctCount = firstTryMatches`,
    `subDeckLabel: "Matching · N pairs"`. It slots straight into per-deck stats **and** the
    `StudyLogService.record(.cards(...))` streak/Today log (which `saveQuizResult` already calls) — so
    matching counts toward the streak with zero extra wiring. (A dedicated `MatchingResult` `@Model`
    would be cleaner but would trip the app's destructive schema reset — avoid unless a real migration
    plan lands first.)
  - **Keep it a separate `Activity`, not a `FlashcardStyle`.** `FlashcardStyle` is default/anki/leitner
    and drives the SRS branches inside `CardDeckView`; a matching game isn't a flip mode and shouldn't
    pollute that state machine.
- **Nice touches / synergy:** seed a "matching warm-up" round from **due** (`SavedCard.nextReviewDate`)
  or **shaky** (`LearnerProfile.vocab`) words → a new `TodayIntent.matchWarmup` recommendation, making
  matching part of the coached plan rather than a standalone toy. Light haptics + a satisfying
  match animation. Optionally a "hard mode" that hides English until a German tile is tapped.
- 🔗 `Activity`/`ActivityRouter`, `StudySession`/`DeckStore` (mirror for matching), `VocabCard`,
  `QuizResult` + `DeckStore.saveQuizResult` (reuse — no schema change), `StudyLogService` (auto-streak),
  `HomeHubView` (one tile), optionally `TodayPlanner`/`TodaySection` for the warm-up intent.

### 15. Dual-purpose import sources (paper / scan → flashcards *and/or* chat)  💎💎  🔨 S–M  ✅ Shipped
**Make an imported text feed either study surface — not implicitly just a conversation input.**

> **Shipped:** `PaperDetailView` now leads with a **What next?** chooser — **Make flashcards ·
> Discuss this paper · Both** — instead of a primary "Discuss" button plus a passive "in your Library"
> deck. Deck generation moved **on-demand**: import (`PaperStudyService.generate`) now builds only the
> summary + questions, so a "just discuss it" import is cheap; the vocab deck is built the first time
> the learner taps **Make flashcards**, via a new `generateDeck(...)` behind a progress sheet, then
> launched through the shared `ActivityRouter` (`DeckStore.session(for:)`, the same path as the
> Library). The word/size picker (`ExtractedTextReviewView`, now flagged `collectDeckOptions`) simply
> moved from import time to that tap. **Both** opens the flashcards, then — detecting the session's
> dismissal via `router.active` — offers "ready to discuss?" to close the read → review → talk loop.
> No schema change (reuses `StudyPaper.deckIDRaw`). Both `PaperListView` (PDF/link) and
> `PhotoScanListView` (scans) share the deferred-deck import flow.

After importing a PDF/link or scanning a photo, the produced `StudyPaper` should offer a single
post-import chooser — **Make flashcards · Discuss it · Both** — rather than defaulting to one path.
This is the last piece of the hub-and-spoke reorg: papers/scans became first-class Home ▸ Reading
tiles (decoupled from the old Talk tab), but their *output* is still conversation-leaning.

- **Why it works:** papers/scans are the learner's **own real-world German** — a menu, an article, a
  class handout — the most motivating material there is. Letting one capture drive both vocab study
  (retrieval) *and* a discussion (production) doubles the value of a single import and mirrors how
  people actually study a text: learn the words, then use them.
- **How it plugs in** (both output rails already exist — this is mostly UX):
  - `PaperDetailView` already has **"Discuss this paper"** (→ `ConversationView`, mode `.paper`) and a
    generated vocab deck linked via **`StudyPaper.deckIDRaw`**. Phase 2 already made `PaperListView` /
    `PhotoScanListView` first-class Home ▸ Reading tiles and Library ▸ Reading sections.
  - The work: after `PaperStudyService` finishes a paper, present a chooser (a sheet, or an inline
    "What next?" card in `PaperDetailView`) with **Make flashcards** — open the linked deck via the
    **`ActivityRouter`** (`router.launch(.cardDeck(DeckStore(modelContext:).session(for: deck, style:)))`)
    — **Discuss it** (the existing `.paper` conversation cover), and **Both**.
  - Make vocab-deck generation **on-demand from the chooser** rather than always-eager, so a
    "just discuss it" path stays cheap (only build the `SavedDeck` when the learner picks flashcards).
  - Library needs nothing new — it already browses these under Reading.
- **Nice touch:** when a paper chat ends, offer *"turn the words you struggled with into a deck"* —
  routing the session's slips through `DrillDeckView`/`LearnerProfile`, closing the read → talk →
  review loop.
- 🔗 `StudyPaper` (+ `deckIDRaw`, no schema change), `PaperDetailView`, `PaperStudyService`,
  `ActivityRouter`/`DeckStore` (launch flashcards), `ConversationView` (`.paper` mode), optionally
  `DrillDeckView`/`LearnerProfile` for the follow-up drill.

---

## Tier 3 — Bigger bets / longer horizon

### 9. Searchable, error-tagged history (the one real vector use case)  🔨 L
"Find every past moment I struggled with two-way prepositions." Your raw **transcripts/papers/phrase
library** are large and unstructured — the legitimate place for embeddings (unlike the profile, which
stays structured). A semantic search over saved conversations, with corrections highlighted inline,
becomes a personal "study your own mistakes" corpus. Deliberately deferred from the profile design;
revisit as its own feature.

### 10. Pronunciation & listening modes  🔨 M–L
You already have `SpeechService` (TTS) and `SpeechRecognitionService`. Two complementary modes:
- **Pronunciation feedback:** compare what was recognized vs. intended and flag mispronunciations;
  track recurring ones in the profile as a new slip category. `SayItView` is the seed.
- **Dictation / listening:** the coach speaks a sentence, the learner types or repeats it — trains the
  ear, which conversation-by-text under-exercises.

### 11. CEFR "can-do" goal spine  🔨 M
A light curriculum of "I can…" statements ("order food", "describe my weekend", "handle a phone
call") mapped onto your existing `ConversationScenario`s. Gives the learner *direction* and a sense
of *completion* — the motivational scaffold a free-form app lacks. Progress is inferred from which
scenarios they've handled well (from the profile).

### 12. Persona continuity  🔨 S
Lena (the freestyle partner) greeting the learner with a genuine callback — *"Letztes Mal hast du von
deiner Reise erzählt — wie war's?"* — using `LearnerProfile.lastSessionAt` + a stored one-line "last
topic." Relationship builds motivation; this is nearly free given the memory already exists.

### 13. Fine-tune synergy  🔨 (research)
The anonymized, aggregate distribution of weak grammar tags across sessions could inform *which*
structures your Gemma grammar fine-tune emphasizes (see `training/PLAN.md`) — data-driven curriculum
for the model itself. Speculative, but a neat closed loop between "what learners actually miss" and
"what the model is trained to teach."

---

## Rough prioritization

| # | Feature | Impact | Effort | Notes |
|---|---------|--------|--------|-------|
| 1 | Today home screen | ★★★ | M | Biggest anti-scattershot win; needs #6 for streaks |
| 4 | JIT grammar mini-lessons | ★★★ | S–M | Mostly wiring existing `explanation` + `GrammarExercise` |
| 14 | Card matching game | ★★ | S–M | ✅ Shipped — new `.matching` Activity; reuses router + `saveQuizResult` (no schema change) |
| 15 | Dual-purpose import sources | ★★ | S–M | ✅ Shipped — What next? chooser + on-demand deck via `ActivityRouter`; no schema change |
| 2 | Elicitation feedback | ★★ | M | ✅ Shipped — `FeedbackStyle` axis; nudge defers reply + reuses `SayItPrompt` retry rail |
| 6 | Progress & streaks | ★★ | S–M | Unlocks #1's streak; motivational |
| 3 | v2 cloze cards | ★★ | M | ✅ Shipped — `.cloze` Activity + `ClozePracticeView`; slip stores sentence + blank; correct fills self-heal |
| 5 | Spaced re-encounter in chat | ★★★ | M–L | Couples SRS to live conversation |
| 7 | Weekly recap session | ★ | S | Cheap, pleasant rhythm |
| 12 | Persona continuity | ★ | S | Nearly free given the memory |
| 8 | Adaptive difficulty | ★★ | M | Comprehensible input |
| 9 | Searchable history | ★★ | L | The real embeddings use case |
| 10 | Pronunciation/listening | ★★ | M–L | Uses existing speech services |
| 11 | CEFR can-do spine | ★★ | M | Direction + completion |

**If I had to pick a next sprint:** #4 (fast, high payoff, reuses what's there) → #1 + #6 together
(the Today screen with a real streak). That trio makes the app feel coached and directed, which is
exactly the "scattershot" problem that started this whole thread.
