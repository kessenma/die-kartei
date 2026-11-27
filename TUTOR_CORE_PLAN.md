# One tutor, two apps: plan

Goal: the tutor's logic (prompts, turn flow, parsing, sampling, model catalog) lives once in
`DieKarteiCore` and both apps run it. Each app keeps only its runtime (MLX on iOS, llama.cpp on
Android), its storage and its screens. Not in scope: moving iOS off MLX (revisit after phase 2,
with iPhone measurements).

## Where it stands (2026-11-26)

- Shared already: `ConversationPrompts` (prompts + FIX/WHY parser), `ConversationConfig`,
  `GrammarFocus`, `MLXModel` (`Models/ModelConfiguration.swift`), `ClassTutorContext`'s prompt text.
- iOS only: `MLXGenerationService` (1,716 lines: load, memory governors, three generate calls),
  `ConversationEngine` (1,429 lines: the whole Gespräch flow, on SwiftData), `ChatTurnNormalizer`,
  and 15 files that call the model directly (StoryStudyService 10 calls, ConversationEngine 8,
  PaperStudy 4, Resume 4, …).
- Android only: `TutorEngine` (llama.cpp), `TutorStore`, its own model table (`TutorModelFile`),
  a hand-written Gemma chat template, and a thin copy of the Gespräch flow in `GespraechView`.
- Branch: `android-port` is 12 commits ahead of `main`, 0 behind.

## Progress

- 2026-11-26: phase 0 (except the merge) and phase 1 done; phase 2 done for Gespräch.
  - `check_prompt_sync.py` runs again. It found the app now has 14 focus areas (verbenPraepositionen
    and reflexivverben were added 2026-10-09); training data built before then had 12.
  - Shared: `TutorGenerating` + `TutorBudget`, `ConversationSession` (was ConversationEngine; iOS
    keeps the name as a typealias), `ConversationHost` / `SpeechInput` / `SpeechOutput` /
    `ConversationReviewing`, `ChatTurnNormalizer`, `ChatRole`, `ConversationSummary`,
    `SingleWordTranslator`, `PhraseMatch`. In-memory host and `ChatPromptFormat` live in the core
    only (Tutor/).
  - Tests: 6 session tests on a scripted tutor; Android prompt format matches all four tutors'
    templates byte for byte (7 fixtures).
  - Android Gespräch runs the shared session: opener, correction or nudge, reply, translation,
    hints, summary. Verified on the emulator with E2B.
- Next: the other features (Lebenslauf, stories, paper study, Schreiben check, …), same pattern.

## Phase 0: guards (small)

1. Fix `training/scripts/check_prompt_sync.py`: it still reads `Models/GrammarFocus.swift`, which
   moved to `Models/Grammar/` in 4ae78a9, so it crashes and guards nothing (on main too).
2. Move `ChatTurnNormalizer` into core and use it on Android (Gemma's template needs strict
   user/assistant alternation; Android doesn't enforce it today).
3. Chat-template golden test. Move the template formatting into core (pure Swift). A script
   renders fixed histories with each model's real `chat_template.jinja` (jinja2) into fixtures;
   a core test formats the same histories and must match byte for byte. The evals ran through
   the real template, so this proves the app sends what was scored.
4. Merge `android-port` into `main` before phase 1, so the iOS refactor doesn't happen on a
   side branch.

## Phase 1: one engine interface

- `protocol TutorGenerating` in core, matching the three calls iOS already uses:
  `generateText(system:user:maxTokens:temperature:)`,
  `streamReply(history:system:maxTokens:temperature:onPartial:)`, plus `isReady(for:)`,
  `load(_:)`, `unload()`. An optional `slot` argument lets llama.cpp keep a prompt cache per
  task (chat / correction); MLX ignores it for now.
- `GenerationProfile` in core: temperature, token budget, stop rules per kind of call
  (correction, reply, cards, story…), so both runtimes sample the same way. Today 0.7 for replies
  is written at each call site.
- iOS: `MLXGenerationService` conforms through a thin adapter. Memory governors, stall timeouts
  and the Apple Intelligence path stay where they are.
- Android: `TutorStore` conforms.
- Switch the 15 iOS files to the protocol. Mechanical; iOS behaviour unchanged.
- Done when: iOS tests green, simulator smoke test of Gespräch + one story, Android unchanged.

## Phase 2: shared conversation logic (the big one)

- Split `ConversationEngine` into:
  - `ConversationSession` (core): turn flow (correction → reply), hints, say-it, repair, the
    summary, spaced re-encounter, streaks. Depends only on `TutorGenerating`, a small
    `ConversationStoring` protocol (append, update, save) and a `TutorSettings` struct (the
    values it reads from `modelManager` today).
  - The iOS shell: SwiftData storage, speech recognition, TTS autoplay, settings.
- Tests first: a scripted fake engine in core, so the conversation flow is tested on the Mac
  with no model. Move the logic parts of StammtischTests / LebenslaufTests / ClassLoopPrereqTests
  onto it.
- Android: replace `GespraechView`'s flow with `ConversationSession` (in-memory storage first,
  then saved history). Stammtisch comes almost free after that.
- Then the other features, one commit each, same pattern (prompt + parse in core, storage/UI
  outside): Lebenslauf (Resume), stories (StoryStudyService, KasusStoryGenerator), PaperStudy,
  Schreiben check, phrase/review decks, word inspector, worksheet check, handout translation.

## Phase 3: one model catalog

- Extend `MLXModel` with each format's file: MLX repo, GGUF repo + file name + bytes + SHA-256,
  minimum RAM, chat-template family, which quant. Delete Android's `TutorModelFile` table.
  (Renaming `MLXModel` to `TutorModel` is cosmetic; later, if at all.)
- Android downloads from Hugging Face with resume and a SHA-256 check, in Settings ▸ Tutor Model.
- A remote catalog (new tutors without an app update): not yet; worth it around a fifth model.
- Needs: the GGUFs on Hugging Face (needs the HF login on the Mac mini).

## Phase 4: one release pipeline

- `training/scripts/release_model.sh <bf16 master>`: MLX 4-bit + GGUF (Q4_K_M, Q4_0), both
  evaluated with the app guard, fails if a format is clearly worse than the other, writes the
  scores into `MODEL_SCOREBOARD.md`, uploads both, prints the catalog entry (sizes, hashes).
- Re-run it once for the four current tutors from their private masters (today's GGUFs come
  from the dequantized 4-bit MLX weights; tested equal, but not the clean path).

## Order

0 → 1 → 2 (Gespräch first, then feature by feature) → 3 and 4 when the HF login is done.
Every step lands with iOS tests green, the core tests green and an Android emulator check.
