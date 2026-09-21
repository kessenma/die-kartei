# Short Stories — AI-generated reading & listening comprehension (Goethe-style)

**What:** the German Tutor model writes a short German story at a chosen CEFR level (A1–C1), then
generates comprehension questions about it. The learner either **reads** the story or **listens**
to it (TTS, exam-style), answers the questions, gets graded, and the results feed the stats/streak
system and the learner profile. Restricted to the in-house **German Tutor** models — any of them
(Gemma 4 E4B/E2B, Granite 4.1 3B, Granite 2B), not the hero alone since 2026-08-20.

The story text carries the app's signature reading gestures (double-tap a word to translate/save,
select a phrase to save — the conversation's `SelectableGermanText`), and an on-demand **English
translation** of the whole story. Stories always generate in German; English is a revealed view,
never the source.

**Why:** reading and listening comprehension are full exam sections (*Lesen*, *Hören*) at every
cert level, and neither is trained by the app yet. Flashcards train words, conversations train
production; stories train *sustained input at level* — with difficulty controlled by us, not by
whatever text the learner happens to import. Keeping it to the in-house tutors also gives the
fine-tunes a flagship feature where their prose quality is visibly the point.

**Question types (user-selectable mix):**
1. **Multiple choice** — question + 3–4 options (at A1/A2 this includes richtig/falsch statements,
   which are just 2-option MC).
2. **Fill in the blank** — a sentence about the story with a `______`; the learner types the word.
3. **Fill in the blank + choices** — same sentence, but with option buttons (the grammar-drill
   interaction, reused).
4. **Free response** — an open question; the learner writes an answer and the model grades it
   against a Musterantwort.

**Feasibility: high.** Recombination of parts that already ship:

| Need | Already exists |
|---|---|
| Generate German text + questions | `PaperStudyService` (phase machine, progress, prompts) |
| CEFR level + prompt injection | `CEFRLevel` in `Models/ConversationConfig.swift:40-74` (`promptInstruction`) |
| Level picker UI | `ConversationSetupView.levelSection` (segmented A1–C1) |
| Blank-fill + MC player/grading | `GrammarMultipleChoiceView` + `GrammarExercise` normalization |
| Multi-toggle "pick your mix" UI | `HomeView` tense toggles (`selectedTensesRaw`, at-least-one enforcement) |
| JSON prompt + tolerant parsing | `MLXGenerationService.extractJSON` / salvage / repair chain |
| Streaming progress + Stop | `streamingTokenCount` pattern (`AIGrammarCreateView` loading UI) |
| TTS for listening mode | `SpeechService` + `MLXModelManager.selectedVoiceIdentifier` |
| Word/phrase gestures on German text | `SelectableGermanText` (already feature-agnostic, pure callbacks) |
| Gesture tutorial sheet | `ConversationHelpSheet` (needs only a parameterized intro line) |
| Single-word translation + save | `ConversationEngine.inspectWord` / `translateSingleWord` (`ConversationEngine.swift:588-634`) + `ConversationPrompts.translation*` |
| Results → stats + streak | `DeckStore.saveGrammarQuizResult` pattern + `StudyLogService` |
| Hero gating precedent | `DeviceCapability.canRunHero`, `ModelPickerButton` suggest-hero flow |
| Learner profile read/write | `LearnerMemoryService` (`applyDrillResult`, `vocab` touches, `slips`) |

Genuinely new ground (no precedent in the app): **free-text grading** (§ Free response) and
**hiding text behind audio** (§ Listening). Both are specced below.

---

## Gating: the German Tutor family

Stories are restricted to the in-house tutors, and unlike `PaperStudyService.requiredModel` (a
recommendation the copy walks back), this is enforced. It was `.gemma4_E4B_german` alone until
2026-08-20; every tutor is trained on the same German material, so the pick is about what the
device can hold, not about whether the prose and answer keys can be trusted. Stock models stay out.

```swift
// StoryStudyService.swift — one place, as before
static var eligibleModels: [MLXModel] { MLXModel.germanTutors }   // best first
static var runnableModels: [MLXModel]                             // filtered by DeviceCapability.mayRun
static var readyModel: MLXModel?                                  // best runnable one already downloaded
static var defaultModel: MLXModel                                 // downloaded first, then best runnable
static var unattendedModel: MLXModel?                             // batch queue: the pick, if downloaded
static func resolve(_:) / followUpModel(wrote:fallback:)          // coercion + reader continuity
```

- The pick lives on `MLXModelManager.selectedStoryModel` (key `selectedStoryModel`) and is offered
  by `StoryModelPickerSection` / `StoryModelRow` — one row on the story setup screen and the same
  row in Settings ▸ Stories, both pushing the same picker.
- **Setup ladder** (`StorySetupView`):
  - no tutor this device can run (`runnableModels.isEmpty`) → the "too small" card, whose memory
    check names the *lightest* tutor and unlocks the screen once the user opts in;
  - selected tutor not downloaded → model row + a download card sized from that model;
  - otherwise → model row + the full setup form.
- Tutors too big for the device are still listed in the picker; tapping one opens `MemoryCheckSheet`
  instead of selecting it, with the best fitting tutor as the one-tap alternative.
- An existing story keeps the tutor that wrote it (`StudyStory.modelRaw` → `followUpModel`) for
  grading, translation, and word lookups — colors included — so reading never swaps gigabytes of
  weights, and falls back to a downloaded tutor when that model is gone.
- Batch story jobs run on `unattendedModel`: the learner's pick when it's on disk, else whichever
  tutor is. A background job never starts a multi-gigabyte download on its own.
- New prefs on `MLXModelManager` (same `didSet` pattern as the rest): `storyLevelRaw` (defaults
  from `chatLevelRaw` until changed), `storyQuestionTypesRaw` (comma-joined kinds, default
  `multipleChoice`), `storyQuestionCount`.

## Data model

New `@Model StudyStory`, modeled on `StudyPaper` (`Models/StudyPaper.swift`):

```swift
@Model final class StudyStory {
    var id: UUID
    var createdAt: Date
    var title: String            // model-generated, German
    var topic: String            // what the user asked for
    var levelRaw: String         // CEFRLevel
    var genreRaw: String?        // Alltag, Dialog, E-Mail/Brief, Krimi, Märchen…
    var storyText: String
    var englishText: String?     // on-demand translation, generated once and cached
    var glossaryData: Data?      // [GlossaryEntry] word = english
    var questionsData: Data?     // [StoryQuestion]
    var deckIDRaw: String?       // optional linked vocab deck (later phase)
    var generationComplete: Bool
    var bestScore: Int?          // list-row convenience; history via QuizResult
    var lastStudiedAsListening: Bool  // remember the mode the learner used
}

struct StoryQuestion: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case multipleChoice      // question + options, correctIndex
        case fillInBlank         // "sentence with ______", typed answer
        case fillInBlankChoices  // same sentence + options
        case freeResponse        // open question, Musterantwort, AI-graded
    }
    var kind: Kind
    var question: String         // question text, or the ______ sentence for FITB kinds
    var options: [String]        // MC / fitbChoices; empty otherwise
    var correctIndex: Int?       // MC kinds
    var answer: String?          // FITB solution word / free-response Musterantwort
    var evidence: String?        // story sentence proving the answer (see Risks)
}
```

Register in the schema array (`App/german_ai_flashcardsApp.swift:32-40`). Adding an entity is an
additive lightweight migration — `StudyDay`, `MatchingPairStat`, `MatchingRound` were added the
same way post-launch — but **verify upgrade-in-place on a device with existing data**, because the
container's failure path is a destructive store reset (`german_ai_flashcardsApp.swift:49-61`).

## Generation — `StoryStudyService`

`@Observable @MainActor`, mirroring `PaperStudyService`'s phase machine
(`idle → loadingModel → writingStory → questions → glossary → done/failed`) with `progress`,
`statusText`, and live `streamingTokenCount` during the writing phase. Auto-loads the hero model
like `GenerationCoordinator.generateWithMLX` does. Sequential calls:

1. **Story.** The level knob is the feature, so don't rely on "write at B1" alone. Compose:
   `CEFRLevel.promptInstruction` + per-level hard constraints (length target, tense whitelist,
   sentence-length cap) + topic/genre. `TITEL:` / `GESCHICHTE:` line format (header parsing like
   `parseSummary`). Temperature ~0.75, `maxTokens` per level (note `generateText` defaults to 32 —
   always pass real budgets).

   | Level | Length | Constraint sketch |
   |---|---|---|
   | A1 | 80–120 words | Präsens only, main clauses, top-500 vocab |
   | A2 | 120–180 | + Perfekt, weil/dass clauses |
   | B1 | 200–280 | + Präteritum (narrative), everyday abstraction |
   | B2 | 300–400 | + Konjunktiv II, opinion in the text |
   | C1 | 400–550 | natural prose, idiom, implicit meaning |

2. **Questions.** Feed the story back with the learner's selected kinds. Split the requested
   count across selected kinds (e.g. 6 questions, 3 kinds → 2 each), one generation call per kind
   so each prompt carries a single JSON example (the `GrammarExerciseSeed` trick — per-kind seeds
   with example JSON and blank rules). Normalize like `normalizeGrammarExercises`: valid
   `correctIndex`, distinct options, exactly one `______` in FITB sentences (or blank the answer
   word if the model wrote it filled in — that helper exists), dedupe, over-generate by 1–2 and
   keep N.

3. **Glossary.** Reuse the `deutsch = english` line format from `PaperStudyService.makeDeck` for
   5–8 hard words (skippable at C1).

**Free-response grading** is a separate, at-answer-time call (the app's first free-text grader):

```
System: Du bist Prüfer. Bewerte die Antwort des Lernenden auf eine Frage zu einer Geschichte.
User:   GESCHICHTE: … FRAGE: … MUSTERANTWORT: … ANTWORT DES LERNENDEN: …
        Antworte NUR mit JSON: {"score": 0|1|2, "feedback": "<ein Satz, ermutigend>",
                                "korrektur": "<verbesserte Version oder ''>"}
```

Score 2 = correct, 1 = partially (content right, language shaky — count as correct for the quiz
score, but log the slip), 0 = wrong. Show the Musterantwort + feedback either way. Grading needs
the hero model loaded at quiz time; auto-load with a brief "Modell wird geladen" state when the
quiz is opened later from the Library. Content-first grading (meaning over grammar) keeps it fair
at A1/A2.

## UI

- **Home ▸ Reading**: "Short Story" row next to Papers and Photo Scans (`HomeHubView:117-132`) →
  **`StorySetupView`**: topic field + suggestion chips (the `HomeView` chip pattern), level
  segmented control (reuse `levelSection`), optional genre, question count, and the **question-type
  toggles** — multi-select with at-least-one enforcement, exactly the `selectedTensesRaw` pattern
  from `HomeView:203-221`, each with an info line ("Free response: you write answers, the AI
  grades them"). Then Generate → streaming progress + Stop.
- **`StoryDetailView`** (mirror `PaperDetailView`): title, level chip, hero badge, then the mode
  choice: **Read** (story text + glossary) or **Listen** (below). The German text renders through
  `SelectableGermanText` so both gestures work (§ Reading toolkit), a toolbar info button shows the
  shared gesture help sheet, and a Deutsch/Englisch toggle reveals the cached translation. "Start
  Questions" launches the quiz; footer offers regenerate-questions with a different mix (story
  stays, only step 2 reruns).
- **Picture layout (`StoryReadingLayout`)** — a toolbar menu on `StoryDetailView`, shown only for
  illustrated stories, with the pick kept in `@AppStorage("storyReadingLayout")` across stories:
  - `ganz` (**default**) — every picture whole: full row width, height from the image's own
    proportions. Nothing is cropped.
  - `kompakt` — the old cropped banners between paragraphs, for less scrolling. Banner heights grow
    with a regular horizontal size class (260/240 vs 200/180), because a fixed height across an iPad
    row cuts a square picture down to a strip.
  - `umfluss` — magazine style: the picture sits half-width in the corner of its paragraph and the
    lines flow around it. Sides alternate down the story.
  `StoryImageFit` (`.banner(height:)` / `.full`) is what `StoryIllustrationView` takes; the story
  list rows and the read-aloud player stay on `.banner`.
- **Text wrapping (`WrappingTextView`)** — `Features/Shared/WrappingTextView.swift`. Wrapping is
  `NSTextContainer.exclusionPaths` plus plain `UIImageView` subviews positioned to match; an
  `NSTextAttachment` cannot do it (it sits in the line like one very large character). Two rules to
  keep:
  - Exclusion paths are laid out by **TextKit 1**, so a wrapping text view is created with
    `usingTextLayoutManager: false`. `SelectableGermanText` only does that when
    `usesImageWrapping` is set, so every other call site (conversation, job prep, the transcript)
    keeps the system default engine untouched.
  - **Never build the subclass with `UITextView(usingTextLayoutManager:)`.** That convenience
    initializer does not run a subclass's designated initializer, so every Swift stored property on
    `WrappingTextView` is left uninitialized and the first read of `wrappedImages` faults
    (`EXC_BAD_ACCESS … at 0x10`, inside `_ArrayBuffer.count`). It builds its TextKit 1 stack by hand
    and calls `init(frame:textContainer:)`, which is the designated initializer.
  - Subviews are **never** added or removed from the `wrappedImages` setter — `didSet` only sets a
    flag and the rebuild happens in `layoutSubviews`. `addSubview` can drive layout straight back
    into the view, which re-enters the setter mid-rebuild.
  - The engine is chosen at view-creation time, so `StoryDetailView` hangs `.id(layout)` on the text
    stack: switching layout rebuilds the views instead of updating them in place.
  - **Never write `exclusionPaths` while measuring.** The setter invalidates layout *and* the
    intrinsic content size, so a `sizeThatFits` that wrote would ask SwiftUI to measure again, and
    measure and layout re-trigger each other until the app dies. `sizeThatFits` measures on a
    detached `sizer` twin; only `layoutSubviews` writes to the live container, only from
    `bounds.width`, and only when the rectangles actually changed.
  - The overrides are **inert unless wrapping is in use** (`wrapsText`), and more importantly
    `SelectableGermanText.makeUIView` only *instantiates* the subclass when `usesImageWrapping` is
    set — its `UIViewType` stays `UITextView`. Chat, job prep, the listen-mode transcript and the
    `kompakt`/`ganz` layouts get a plain `UITextView`, so the wrapping code cannot reach them at all.

### Testing the reader without the model

Illustrations come from on-device diffusion, which the simulator can't run, so the three layouts had
nothing to be checked against. `StoryDebugSeeder` (DEBUG only) writes one story with a header image
and three anchored inline pictures — drawn as flat shapes at the generator's own 768×768, through
the same `StoryImageStore`, numbered so it's obvious which landed where.

- `-stories.debugOpen 1` — seed (if needed) and open the reader straight away.
- `-stories.debugSeed 1` / `-stories.debugRemove 1` — just create or delete it.
- `-storyReadingLayout kompakt|ganz|umfluss` — the layout is `@AppStorage`, so a launch argument
  picks it without tapping the toolbar menu.
  `WrappedText` is the same wrapping without the gestures, used for the English translation (the
  word gestures are deliberately German-only). `StoryImageCache` decodes the files up front, because
  the text view needs the pictures' proportions before it can lay out around them — it only runs in
  `umfluss`; the stacked layouts let each `StoryIllustrationView` read its own file.
- **Picture memory.** An illustration is 512×512, which is 1 MB of RAM once decoded *however
  small it is drawn*, and `MemoryBudget.reserveMB` leaves only 250 MB for everything that is not the
  model. So:
  - `StoryImageStore.loadImage(fileName:storyID:maxPixelSize:)` decodes through ImageIO at the size
    actually drawn (clamped so it never upscales past the file). `StoryIllustrationView` asks for
    its banner height or a reading-width cap; `StoryImageCache` asks for 700 px.
  - `StoryImageCache.load` decides what to decode from `images` itself, never from a separate
    "claimed" set, and it does **not** check `Task.isCancelled`. Its caller is a `.task(id:)` that
    is cancelled by any change to its id, including ones that stay in Umfluss; a claim released on
    that cancellation lost the race against the next caller, which saw the files as already loaded,
    decoded nothing, and left the layout blank until a purge reset it. `generation` (bumped by
    `purge`) is the only thing that invalidates a finished decode.
  - `StoryIllustrationView` drops its bitmap in `onDisappear`, and `StoryImageCache.purge()` runs
    when the reader leaves `umfluss`, when the screen goes away, and on a system memory warning.
    Switching layout is the moment both layouts' pictures would otherwise be resident at once — the
    purge on the layout change is what stops that, and it is load-bearing, not tidiness.
  - The cache honours cancellation and a purge that lands mid-decode (a generation counter), and
    only ever has one decode in flight; only crossing into or out of `umfluss` rebuilds the text
    views (`.id(layout == .umfluss)`). The whole picture is in `docs/MEMORY.md`.
- **`StoryQuizView`** — a sibling of `GrammarMultipleChoiceView` (same shuffle → answer → grade →
  missed-review → summary state machine), with per-kind answer surfaces:
  - *multipleChoice / fillInBlankChoices*: option buttons, green/red recolor, exact-index grading
    (straight from the grammar view).
  - *fillInBlank (typed)*: a `TextField` + check button; grading is trimmed, case-insensitive
    match (article-tolerant: accept "Hund" for "der Hund"); on miss show the answer.
  - *freeResponse*: multiline field + "Bewerten" → grading call → score, feedback, Musterantwort.
    Optional later: answer by voice via `SpeechRecognitionService` (the `SayItView` seed).
  - "Zum Text" disclosure keeps the story reachable mid-quiz (the real exam is open-book) — in
    listening mode this replays audio instead of showing text (Hören plays twice; track replays).
  - On completion: `DeckStore.saveStoryQuizResult(...)` (mirror `saveGrammarQuizResult`,
    `DeckStore.swift:241-256`) → `StudyLogService.record(...)` → streak/Today for free. Stamp
    `bestScore`.
- **Library ▸ Reading**: "Short Stories" row alongside Papers & Links (`UnifiedLibraryView.readingList`)
  → list with level chips, read/listen icon, best score; swipe to delete.

Navigation stays a `NavigationLink` push like Paper/PhotoScan — no new `Activity` case (only
immersive card-deck-style sessions use the `ActivityRouter` cover).

## Listening mode (Hören)

Same story, same questions — presentation-layer only, so it costs no extra generation:

- **Listen** on `StoryDetailView` hides the story text and shows a player: play/pause, restart,
  and a **speech-rate control** (langsam / normal — `AVSpeechUtterance.rate`; default langsam at
  A1/A2). Uses `SpeechService` with the existing `selectedVoiceIdentifier`.
- Exam realism: the Hören section plays each text twice — surface that as the norm ("Du kannst
  die Geschichte zweimal hören") but don't hard-block a third play; this is practice, not
  proctoring. Count plays and show them on the summary.
- Text reveal: hidden during listening and the quiz; after the quiz ("Jetzt mitlesen"), show the
  transcript for review — listening-then-reading is a well-established comprehension loop.
- Sentence-by-sentence highlight-along on the transcript (via
  `AVSpeechSynthesizerDelegate.willSpeakRangeOfSpeechString`) is a later nice-to-have, not v1.
- Store `lastStudiedAsListening` so quiz results can be labeled ("Hören · B1") in stats, and the
  learner profile can distinguish the two skills eventually.

## Reading toolkit — gestures & English translation

**Gestures.** The story text gets the exact conversation interactions, because the component is
already generic: `SelectableGermanText` (`Features/Conversation/SelectableGermanText.swift`) is a
`UIViewRepresentable` with pure callbacks (`onTapWord`, `onTranslateSelection`, `onSavePhrase`) and
zero conversation dependencies. Wiring for stories:

- **Double-tap a word** → the word inspector (translation + save to the flashcard library). Today
  that inspector is coupled to `ConversationEngine` (`inspectedWord` / `inspectWord` /
  `translateSingleWord` / `saveInspectedWord`, `ConversationEngine.swift:588-634`, rendered by
  `WordInspectorSheet` inside `ConversationView.swift:886`). Extract the reusable core: a small
  `WordInspectorModel` (word, translation, loading, saved + a translate call built on
  `mlxService.generateText` with `ConversationPrompts.translationSystemPrompt/UserPrompt/cleanTranslation`
  and a save closure) plus a standalone `WordInspectorSheet(model:)`. The conversation engine
  keeps its API and delegates to the shared core; stories provide a save closure that writes to
  the library and logs a `VocabTouch`.
- **Select a phrase → Save phrase** → reuse the `PhraseDraft` sheet flow from `ConversationView`
  so story phrases land in the same phrase library the coach already draws from.
- Bonus alignment: `SelectableGermanText` already supports `savedWords` highlighting (saved words
  get a subtle wash in the story too) and a `highlightRange` read-along decoration — the listening
  mode's transcript highlight-along is half-built already.

**Shared location.** Once stories consume them, three files move out of `Features/Conversation/`
into a new `Features/Shared/` group (no behavior change, do it as the prep step):
- `SelectableGermanText.swift` — as is.
- `ConversationHelpSheet.swift` → rename **`GestureHelpSheet`**, with the intro line parameterized
  (`"Two quick gestures help you learn while you chat."` vs. `"…while you read."`); the two demo
  cards and the flashcard footer already apply verbatim to stories. Shown from the info button on
  both `ConversationView` and `StoryDetailView`.
- The extracted `WordInspectorSheet` + `WordInspectorModel`.

**English translation.** Stories are always generated in German; English is a view the learner
reveals, not a source. On first toggle to Englisch, `StoryStudyService.translate(story:)` runs one
hero-model call (paragraph-marked format — `ABSATZ 1: …` — so paragraphs stay aligned; fall back
to whole-text if markers come back mangled), caches the result in `StudyStory.englishText`, and
every later toggle is instant. Display rules:

- A Deutsch/Englisch segmented toggle above the story text in read mode. English renders as plain
  `Text` (gestures are for German; double-tap already covers word-level translation, the toggle is
  the whole-story comprehension check after reading).
- Not available during listening-mode question answering or before the transcript reveal — same
  spirit as hiding the German text: comprehension first, confirmation second.
- The glossary and per-word inspector cover the "I'm stuck on one word" case, so the full
  translation can afford to live one deliberate tap away.

## Learner profile tie-ins

All through the existing `LearnerMemoryService` shapes — no new profile schema:

- **Streak/Today (free):** `saveStoryQuizResult` calls `StudyLogService.record(...)` like every
  other completion point.
- **Vocab touches:** words the learner double-taps in the story, glossary words they reveal, and
  FITB words they miss become `VocabTouch`es in `LearnerProfile.vocab` (the LRU the coach already
  reads); saved phrases land in the same phrase library conversations feed.
- **Slips:** free-response answers scored 1 (content right, language shaky) log a `LexicalSlip`
  with the correction — same category the conversation corrections feed.
- **Seeding (the reverse direction):** story generation weaves in 3–5 due/shaky words from
  `LearnerProfile.vocab` (the `generateGrammarExercises(learnerWords:)` precedent) and can steer
  one weak `GrammarFocus` into the prose via its `steeringHint` — the story becomes spaced
  re-encounter in disguise.
- **Today screen:** a `TodayIntent`-style recommendation ("Read a short story at your level" /
  "Listen to a story") once the feature has results to draw on; rotate read vs. listen.

## Phases

0. **Shared-component prep (S, no behavior change).** Create `Features/Shared/`; move
   `SelectableGermanText`; rename `ConversationHelpSheet` → `GestureHelpSheet` with a
   parameterized intro; extract `WordInspectorModel` + `WordInspectorSheet` from
   `ConversationView`/`ConversationEngine`. Verify the conversation still behaves identically —
   this is the risk-free refactor to land first.
1. **Generate + read (M).** `StudyStory` model, `StoryStudyService` (story + glossary +
   questions), hero gating + tile ladder, `StorySetupView` with the question-type toggles,
   `StoryDetailView` with read mode — story text through `SelectableGermanText` with both
   gestures + the help sheet from day one — and read-only questions (paper-style disclosures).
   Shippable.
2. **Graded quiz (M).** `StoryQuizView` with the three locally-gradeable kinds (MC, FITB typed,
   FITB choices), results → `QuizResult`/streak/`bestScore`.
3. **English translation (S).** `translate(story:)`, `englishText` caching, the Deutsch/Englisch
   toggle and its listening-mode guard.
4. **Listening mode (S–M).** Player on the detail view, text hiding, play counting, transcript
   reveal, "Hören" labeling on results.
5. **Free response (M).** The grading call, quiz surface, auto-load-at-quiz-time, slip logging.
6. **Profile depth + tie-ins (S each, independent).** Shaky-word/grammar seeding into stories,
   Today recommendation, story→vocab-deck (`makeDeck` pattern, `generatorRaw: "story"`),
   "Discuss the story" chat (mode `.paper` with the story as `conversationContext` — the examiner
   persona already exists). (Gesture saves → `VocabTouch`/phrase library land earlier, with
   Phase 1, since the inspector's save closure is where they're logged.)

## Risks & mitigations

- **Wrong answer keys.** Even the hero model will occasionally mark a wrong option correct.
  Cheapest-first: (1) the `evidence` field — quoting the supporting story sentence reduces
  fabricated questions and becomes an "Im Text: …" reveal after answering; (2) normalization drops
  questions whose evidence doesn't fuzzy-match the story or whose answer word (FITB) doesn't
  appear in a sensible form; (3) over-generate and keep the survivors. Defer any second-pass
  self-verification (doubles latency) unless reports demand it.
- **Free-response grading reliability.** The grader sees story + Musterantwort + answer, which is
  a much easier task than open grading, and the 0/1/2 scale with "1 counts as correct" is
  forgiving by design. Always show the Musterantwort so a misgrade never hides the truth.
- **Level drift** (C1 request, B1 output). Hard constraints (tense whitelist, sentence caps) do
  more than the CEFR label; length checked post-hoc, one re-prompt if wildly short.
- **TTS quality.** System German voices are solid but the learner may have a low-quality default
  voice; link the existing voice picker (Card settings) from the player and suggest downloading
  an enhanced German voice.
- **Latency.** Story + questions + glossary ≈ 1,200–1,800 output tokens on the hero model —
  ballpark of a 15-card conjugation deck today; the streaming + Stop pattern already sets
  expectations. Free-response adds a per-answer grading call (a few seconds; show a spinner on
  the Bewerten button).
- **Schema migration.** Additive entity, but test upgrade-in-place before release (the failure
  path wipes the store).

## Open decisions

- Genre list for v1 (suggest: Alltagsgeschichte, Dialog, E-Mail/Brief, Krimi, Märchen — Brief/E-Mail
  doubles as *Schreiben*-format exposure).
- Whether richtig/falsch deserves its own toggle or stays folded into multiple choice at A1/A2.
- Voice answers for free response (via `SpeechRecognitionService`) — natural extension of
  listening mode, but adds a failure surface; suggest after Phase 4 ships.
