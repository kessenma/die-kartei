# Add OpenAI/ChatGPT Backend with OAuth Sign-In

## Status: Post-launch — pending OpenAI client_id approval

The seamless "Sign in with ChatGPT" UX requires OpenAI to provision a `client_id` for the app.
Apply at https://developers.openai.com/apps-sdk after the app is live on the App Store — having
a published listing makes the application stronger. The Litter app's `ChatGPTOAuth.swift` is a
near-complete blueprint for the implementation once approved.

Reference implementation: `/Users/ke/ws/example-swift-llm/litter/apps/ios/Sources/Litter/Models/ChatGPTOAuth.swift`

---

## Context

The app currently only supports local on-device inference via MLX models (downloaded from HuggingFace).
This plan adds OpenAI's ChatGPT API as a cloud backend option so users can generate flashcards without
downloading large local models.

### OpenAI OAuth — Registration Directions

OpenAI OAuth (`auth.openai.com`) is **not publicly self-service**. The Litter app's client ID
(`app_EMoamEEZ73f0CkXaXp7hrann`) was provisioned directly by OpenAI — there is no public developer
portal to register an app the way you would with Google or GitHub.

**Steps to unlock OAuth:**
1. Publish the app on the App Store
2. Apply at https://developers.openai.com/apps-sdk
3. OpenAI provisions a `client_id` for your app (timeline is unpredictable)
4. Implement PKCE OAuth with `ASWebAuthenticationSession` (see Litter reference above)
5. Scopes needed: `openid profile email offline_access`

**Interim option (API key):** Users paste an API key from https://platform.openai.com/api-keys.
Store it in iOS Keychain. Same generation functionality, but requires users to have an API key.

---

## Files to Create

### `german-ai-flashcards/Services/OpenAIKeyStore.swift`
Stores the API key (or OAuth tokens later) securely in iOS Keychain — never UserDefaults.
- `save(apiKey:)`, `apiKey() -> String?`, `clear()`
- Uses `Security.framework` (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`, `SecItemUpdate`)
- `@Observable` wrapper: `isConnected: Bool`, `maskedKey: String` (shows `sk-...XXXX`)
- Swap internals for OAuth tokens when client_id is available — no other files change

### `german-ai-flashcards/Services/OpenAIGenerationService.swift`
`@Observable @MainActor` class calling the OpenAI Chat Completions API.
- Same signature as MLXGenerationService: `generateCards(...) async throws -> [VocabCard]`
- Reuse the JSON prompt structure and parsing fallback chain from `MLXGenerationService`
  (extract shared logic into `FlashcardPromptBuilder.swift` / `FlashcardJSONParser.swift`)
- `isGenerating: Bool`, `generationError: String?` observable state

---

## Files to Modify

### `german-ai-flashcards/Models/ModelConfiguration.swift`
1. Add `.openai` case to `ModelProvider` enum
2. Add `OpenAIModel` enum (`gpt4o`, `gpt4_turbo`, `gpt35_turbo`) with:
   - `apiModelID: String` (e.g. `"gpt-4o"`)
   - `description`, `contextWindow`, cost-per-1K-tokens info strings
   - `logoName` → add OpenAI logo PNG to `Assets.xcassets`

### `german-ai-flashcards/Services/MLXModelManager.swift`
Add:
- `activeProvider: ModelProvider` (default `.mlx`, persisted to UserDefaults)
- `selectedOpenAIModel: OpenAIModel` (default `.gpt4o`, persisted)
- All existing MLX properties unchanged

### `german-ai-flashcards/Services/GenerationCoordinator.swift`
Branch on provider in `generateVocab(...)`:
```swift
switch modelManager.activeProvider {
case .mlx:   await generateWithMLX(...)
case .openai: await generateWithOpenAI(...)
}
```

### `german-ai-flashcards/Features/Settings/SettingsView.swift`
Add two new sections above the existing MLX Model section:

**"AI Provider"** — Segmented picker `.mlx` / `.openai`

**"OpenAI"** (visible only when `.openai` active):
- Connected status row (masked key or "Not connected")
- "Connect OpenAI" button → SecureField sheet to paste API key (or OAuth sheet once approved)
- "Disconnect" button (destructive, when connected)
- Model picker: `OpenAIModel` list with description captions
- Link to https://platform.openai.com/api-keys for onboarding

### `german-ai-flashcards/App/german_ai_flashcardsApp.swift`
Instantiate `OpenAIKeyStore` and `OpenAIGenerationService` as `@State` objects and inject
into `ContentView` → `SettingsView` and `GenerationCoordinator`.

---

## Shared Prompt Logic (Refactor)
Extract JSON prompt-building and response parsing from `MLXGenerationService` (~lines 200–600)
into `FlashcardPromptBuilder.swift` and `FlashcardJSONParser.swift` so both services share
the same format without duplication.

---

## Assets Needed
- `logo-openai` PNG in `Assets.xcassets`

---

## Verification
1. Build and run on simulator
2. Settings → switch provider to "OpenAI" → connect API key
3. Home tab → enter topic → Generate → cards appear via OpenAI API
4. Disconnect key → generate button disabled with clear message
5. Switch back to MLX → full MLX workflow still works unchanged
