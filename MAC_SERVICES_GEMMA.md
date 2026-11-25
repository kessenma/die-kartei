# Mac Services on the Gemma tutor (E4B / E2B)

## Goal

Make the Mac Schreibhilfe (Services ▸ „Auf Deutsch (Sie)", „Auf Deutsch (du)", „Deutsch korrigieren",
and the Schreibhilfe panel) run on the fine-tuned Gemma tutor the learner has loaded, instead of
Apple's on-device model. Keep Apple Intelligence as the fallback when no tutor is ready.

**Mac only.** The iOS keyboard extension stays on Apple's model: an extension can't hold a
multi-GB model in memory (see the 3.7 MB footprint note at the top of `GermanWriter.swift`).

## Why

Apple's model is the weak link. Our own grammar test (Settings ▸ Model & Downloads): Apple
Intelligence 60% and 0/15 on da-/wo-compounds, against 75–90% for the tutors. In real use it got
2 of 3 simple emails wrong:

| English in | Apple's German | Problem |
|---|---|---|
| "…can convert this text from English to German" | „…von Deutsch ins Englische umwandeln kann" | direction flipped |
| "Hello Hans, can we meet tomorrow at 10?" | „Können wir morgen um 10 Uhr treffen?" | missing reflexive *uns* |
| "Hello Hans, thank you for your help yesterday." | „Hallo Hans, ich danke dir für deine Hilfe gestern." | correct |

Use these three as the first regression cases.

## Where things are (main)

- `german-ai-flashcards/Services/MacWritingServices.swift`: the `NSServices` provider. Synchronous:
  it starts a detached task, then spins the main run loop until the result or a **20 s** deadline.
  Anything that can't finish cleanly opens the panel and leaves the selection untouched.
- `german-ai-flashcards/Services/GermanWriter.swift`: `GermanWriting.perform(...)` (`@concurrent`,
  `nonisolated`), prompts in `instructions(for:address:)`, plus `clean`, `isGerman`,
  `isTruncated`. Currently hard-wired to `SystemLanguageModel` / `LanguageModelSession`.
  Compiled into the keyboard extension too (membership exception), so it must not reference MLX.
- `german-ai-flashcards/Services/MLXGenerationService.swift`: the Gemma runtime (MLX,
  `LLMModelFactory.loadContainer`), `loadedModel`, `generateText` / `generateStreamedText`.
  Main-actor isolated (project default `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`).
- `german-ai-flashcards/App/german_ai_flashcardsApp.swift`: sets `NSApp.servicesProvider`.
  The live `MLXGenerationService` is created in the SwiftUI environment, so the provider
  **has no reference to it today**.
- `Info-macOS.plist`: `NSServices` entries, `NSTimeout` 45000 ms, `NSUserData` = `translate.sie` /
  `translate.du` / `correct`.
- `german-ai-flashcards/Features/Settings/MacWritingHelperSettingsView.swift`: copy says "It runs on
  Apple Intelligence"; update it to match whatever we ship.

## Constraints to respect

1. **Deadlock.** The handler blocks the main thread spinning the run loop, and the header comment in
   `GermanWriter.swift` warns that a hidden hop to the main actor hung until timeout.
   `MLXGenerationService` is main-actor isolated, so calling it from the detached task is exactly
   that hop. Either prove that main-queue work drains while the run loop spins, or run Gemma
   generation off the main actor (a `nonisolated`/actor-isolated path to the `ModelContainer`).
2. **Model may not be loaded.** A cold launch for a service has no tutor in memory. Loading E4B
   inside the 20 s deadline / 45 s `NSTimeout` is unlikely. Decide: use Gemma only if already
   loaded, otherwise fall back to Apple (or open the panel and load there, with progress).
3. **Memory.** Don't load a second model on top of one that's already in use (see the comments in
   `loadModel`), and don't evict a tutor mid-conversation for a service call.
4. **Keep the extension building.** Gemma code goes in a Mac-only file (`#if os(macOS)`) that the
   keyboard target doesn't compile. `GermanWriting` stays the shared prompt/cleanup layer.
5. **Speed.** Measure time to first token and full reply for a ~3-sentence email on E4B and E2B on
   an M1 Max. In-place replacement must finish well under 20 s, or it falls back to the panel.

## Suggested shape (open to a better one)

- Add a backend protocol, e.g. `GermanWritingBackend { func perform(...) async -> Result<Outcome, Failure> }`,
  with `AppleBackend` (the current code) and, Mac-only, `GemmaBackend` (MLX).
- Give the services provider a way to reach the running `MLXGenerationService` / model container
  (register it at launch the way `servicesProvider` is set).
- Selection rule: loaded Gemma tutor → Gemma; otherwise Apple; neither → today's "unavailable" path.
- Reuse the same instructions, `clean`, `isGerman` and truncation checks so behaviour stays the same.

## Done when

- The three emails above come back correct via Services in Mail, with E4B loaded, in place.
- With no tutor loaded it still works through Apple Intelligence (no regression).
- No hang: a service call can never freeze the requesting app beyond the deadline.
- E2B also works (lower-RAM Macs). Note its timings next to E4B's.
- Settings copy says which model the Schreibhilfe uses.
