# Apple Intelligence flashcard generation — planned upgrade to `@Generable`

## Where we are (v1)

When the user picks the **Apple Intelligence** built-in model (`MLXModel.appleIntelligence`),
flashcard generation currently works like this:

1. `MLXGenerationService.generateCards(...)` builds the **same** JSON prompt it uses for the MLX
   models (`buildJSONPrompt`) and the same system prompt.
2. For the Apple case it calls `AppleIntelligenceService.generateCardsRaw(system:user:)`, which
   returns the model's **raw text** (expected to be JSON).
3. That raw text flows through the service's existing, very tolerant
   `parseVocabCards(from:)` pipeline: `extractJSON` → `salvageCards` (brace-matched per-object
   decode, conjugation-stripping retry) → `extractCardsWithRegex` → `repairTruncatedJSON`.

We chose this for v1 because:

- `buildJSONPrompt` and `parseVocabCards` are **private** to `MLXGenerationService`, and reusing
  them in place means **zero duplication and zero extraction refactor**.
- The salvage pipeline was built for far weaker small MLX models, so Apple's instruction-tuned
  on-device model (cleaner output) is comfortably within its tolerance.

## The goal (v2)

Switch `generateCardsRaw` to **schema-guided generation** using the FoundationModels `@Generable`
macro and `session.respond(to:generating:)`. Guided generation constrains decoding to the exact
card schema, which is the single biggest reliability lever on a small on-device model — it removes
the "did the model emit valid JSON?" failure mode entirely.

The change is **fully contained to `AppleIntelligenceService`** — `MLXGenerationService`,
`GenerationCoordinator`, and the UI do not change. Sketch:

```swift
@Generable
struct GenCard {
    @Guide(description: "The German word, including its article for nouns is handled separately")
    let germanWord: String
    let englishTranslation: String
    let wordType: String?          // noun / verb / adjective / ...
    let article: String?           // der / die / das, nouns only
    let exampleSentence: String?
    let conjugations: [GenConj]?   // verbs only
}

@Generable
struct GenConj {
    let tense: String              // e.g. "Präsens", "Perfekt"
    let ich: String
    let du: String
    let erSieEs: String
    let wir: String
    let ihr: String
    let sieSie: String
}
```

Then map `GenCard`/`GenConj` → the app's `VocabCard`/`Conjugation`.

## The catch to handle when doing v2

`CodableVocabCard`/`CodableConjugation` in `MLXGenerationService.swift` currently accept **three**
conjugation shapes (a `[Conjugation]` array, a dict keyed by tense, and a flat form) and strip
pronoun prefixes (e.g. "ich unterrichte" → "unterrichte"). A `@Generable` path bypasses
`parseVocabCards`, so re-encode that pronoun/tense normalization when converting `GenConj` →
`Conjugation`. The German pronoun keys are `ich / du / erSieEs / wir / ihr / sieSie`.

Note: even on the guided path, `GenerationCoordinator`'s post-processing (article/example/conjugation
cleanup and dedup, ~L212–230) still runs, so only the parse step is replaced.

## Verify v2 on-device

Guided generation requires the on-device model, which only runs on Apple-Intelligence-eligible
hardware (and a Simulator with the model pack). Validate card shape and German quality on a real
device on iOS 26.2+/iOS 27 before removing the JSON-reuse path.
