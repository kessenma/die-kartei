# Cloud pictures (OpenRouter)

Flashcard pictures and story illustrations can be drawn in the cloud instead of on the phone, on
the learner's **own OpenRouter account**. The app holds no API keys of its own and runs no server:
the learner signs in (or pastes a key), and every picture is billed to them. On-device drawing
(CoreML Stable Diffusion, `ImageGenModel`) stays the default.

Why: the on-device models are slow (~100 s a picture) and weak. Better ones don't fit a phone yet
(see `training/MODEL_SCOREBOARD.md`). Cloud pictures take seconds, cost 1–4¢, and come back clean:
no stray lettering, and story characters that keep their look.

## Models

| Model | OpenRouter id | Cost | Typical wait | Output | References |
|---|---|---|---|---|---|
| Muse Image (Meta), the default | `meta/muse-image` | $0.01 | 10–24 s | WebP, 1600² with `aspect_ratio: "1:1"` | yes (verified) |
| Nano Banana (Google) | `google/gemini-2.5-flash-image` | ~$0.039 | 6–12 s | PNG, 1024² | up to 3 (verified) |

Both are in `Models/CloudImageModel.swift`. Muse needs a **one-time 18+ confirmation on the
learner's OpenRouter account**: open https://openrouter.ai/meta/muse-image, tick "I confirm that I
am 18 years of age or older", tap Confirm. Until then every Muse request fails with 403
`missing_attestation_types: ["age_18plus"]` → `OpenRouterError.needsAgeConfirmation`. Settings
shows the instructions until Muse has drawn once on this phone (`CloudImageModel.hasDrawnBefore`).

## The flow

- **Endpoint:** `POST https://openrouter.ai/api/v1/images` for both models. Muse is **not** served
  on chat completions (404). Body: `{model, prompt, aspect_ratio: "1:1", user, input_references?}`.
  Response: `{data: [{b64_json, media_type}], usage: {cost}}`. No streaming, so the progress bar
  runs on the clock (eases toward 90% over `typicalSeconds`).
- **Sign-in:** OAuth PKCE (`OpenRouterPKCE`). The app opens `openrouter.ai/auth` in SwiftUI's
  `WebAuthenticationSession`; OpenRouter only redirects to https or localhost, so the callback is
  a static page, `https://kessenma.github.io/kartei-openrouter-callback` (source:
  `kessenma.github.io/kartei-openrouter-callback.html`), which forwards the query to
  `kartei-openrouter://callback`. The session catches that scheme itself: **no URL scheme is
  registered**, so it can never reach `.onOpenURL`, which treats every URL as a deck import. The
  code is exchanged at `POST /api/v1/auth/keys` for a user-owned key.
- **Credit:** Settings links to https://openrouter.ai/settings/credits to add credit. The app
  can't show the account balance: `/credits` needs a management key. It shows the key's own
  spend and limit from `GET /key`.
- **Paste a key** is the fallback (openrouter.ai/keys). Both paths check the key with
  `GET /api/v1/key` before saving it.
- **Storage:** the key lives in the Keychain (`KeychainItem`,
  `AfterFirstUnlockThisDeviceOnly`), mirrored as `openrouter.hasKey` in UserDefaults for the
  nonisolated readiness gate, reconciled at launch.
- **Consent:** the first switch to the cloud shows `CloudPicturesConsentSheet` (what's sent, where
  it goes, who pays: App Store rule 5.1.2(i)). Nothing is sent before it's accepted.

## The seam

`StoryImageService.beginSession(unloading:)` → `PictureSession`, fixed to one source per run:

- **On-device:** unloads the tutor, loads the pipeline, `draw` calls the old `generateImage`,
  `end()` unloads.
- **Cloud:** no tutor unload, no pipeline. `draw` sends `PictureRequest.cloudPrompt` (+ references),
  decodes whatever comes back, shrinks it (`CloudPictureWriter`: 512 px cards, 768 px stories)
  and writes a PNG to the same path the on-device path would.

`PictureRequest` carries both halves: the SD keyword prompt + negative + seed + steps, and the
plain-English `cloudPrompt` (`CardIllustrationPrompts.cloudPrompt`,
`StoryIllustrationPrompts.cloudPrompt`). Callers: `DeckIllustrationService.illustrate` /
`illustrateDraft`, `StoryStudyService.illustrate`, `CardImageStyleSheet.drawSample`.

Every picture feature gates on `PictureEngine.isReady` (on-device: model downloaded; cloud: key
stored). `ImageGenModel.current.isDownloaded` is only for things that really are about the
downloaded files (Settings download/delete, storage, orphan sweep).

## Invariants

1. **One source per run.** `beginSession` snapshots `PictureSource.current`; switching in Settings
   applies to the next run. The source picker is disabled while a deck run is going.
2. **Cloud drawing never counts as `isBusy`.** It holds no memory a tutor needs, so it must not
   block `MLXGenerationService.loadModel` or trigger `stopForMemoryPressure`.
3. **Failures split by `OpenRouterError.stopsRun`.** No key, revoked key (401, which also
   disconnects), no credit (402) and the missing 18+ confirmation stop the run with a message
   (`DeckIllustrationService.lastError`, `StoryStudyService.illustrationError` → Settings). A
   refused prompt, no image or a provider hiccup skips that one picture.
4. **Pictures land at display size.** Card and story folders sync to iCloud file by file; a
   1.9 MB original per card would make an illustrated deck hundreds of MB.
5. **Square.** Both models get `aspect_ratio: "1:1"`; left alone, Muse drew a story scene at
   1920×1280, and the reader's placeholder reserves a square.
6. **Parallel only in the cloud.** One request per picture (each card has its own prompt), but
   `PictureSession.cloudParallelism` (8) are in flight at once; on-device it's 1. Stories draw
   picture 1 alone (it's the reference), then the rest at once. 429/5xx retry up to twice,
   honoring `Retry-After`, so a burst that outruns a model's per-minute limit backs off instead of
   dropping pictures.
7. **The key never leaves the phone except to OpenRouter.** Never log it, never put it in launch
   arguments, never copy it into fixtures.

## When a run comes up short

Every deck and story run files a `PictureRunReport` (`Models/PictureRunReport.swift`) under the
deck or story id: pictures drawn of the total, pictures skipped (declined or failed after retries),
and why it stopped if it stopped on its own, with the one fix. `PictureRunReports` keeps them per
device in UserDefaults; a clean run clears the old one, and the banner's ✕ dismisses it.

- **Where it shows:** `PictureRunReportBanner` at the top of the deck's start screen (above the
  Illustrate row, and not gated on being connected: a revoked key disconnects, and that's when it
  matters) and in the story's header.
- **Fix buttons:** no credit → "Add credit on OpenRouter" (openrouter.ai/settings/credits); key
  limit → openrouter.ai/keys; Muse 18+ → the Muse page; revoked key / not connected →
  "Reconnect OpenRouter", which opens `CloudAccountSheet` in place (a deck is full screen, out of
  reach of Settings).
- **Create flow:** the draft run (`CardImageTiming.everyCard`) has no deck yet, so
  `GenerationCoordinator.draftPictureReport` is carried onto the deck when it's saved, and a draft
  run that stopped on credit/key doesn't launch a second run into the same wall.
- **Batch queue:** a picture job fails with the report's reason ("Drew 5 of 20 pictures, then
  stopped. Your OpenRouter credit ran out.") instead of a generic line.
- **Notifications:** a background deck run that stops on credit/key/Muse posts "Pictures stopped";
  a story's "ready" notification says when its pictures stopped.
- **Report wording:** `OpenRouterError.reportReason` states what happened; the button is the fix,
  so the reason doesn't repeat the instructions that `errorDescription` spells out.

## The probe

`scripts/openrouter_image_probe.py [out_dir] [model-filter]` hits both models through `/images`
with a flashcard prompt, a story prompt, and the story's next picture with the first as a
reference, plus `GET /key` and a bad-key call. Key from `$OPENROUTER_API_KEY` or the main
checkout's gitignored `.env`. About $0.15 a full run. Results (2026-10-01): both models keep a cast
consistent from one reference picture; both draw a "membership card" without lettering, the case
the on-device models always got wrong.

## Debug launch arguments (DEBUG)

- `-pictures.debugSource cloud|onDevice`: pick the source without the picker or the consent sheet.
- `-openrouter.debugOpen 1`: open Settings ▸ Model.
- `-pictures.debugReport addCredit|raiseKeyLimit|confirmAge|reconnect|skipped`: file a sample
  report on every deck and story, to see the banners without running an account dry.
- `-openrouter.debugCallback <url>`: use another callback page, e.g. a copy served from the Mac
  (`python3 -m http.server 8791` in the Pages repo, then
  `http://localhost:8791/kartei-openrouter-callback.html`), so the sign-in can be tried before the
  real page is published. OpenRouter accepts localhost callbacks.

Simulator traps: `simctl pbcopy` doesn't reach this simulator's pasteboard, so "Paste a key" was
tested by typing the key with `agent-device type "$(…)"` (it isn't logged). Signing in needs a
real OpenRouter login in the auth sheet.

## Tests

`german-ai-flashcardsTests/OpenRouterTests.swift`: PKCE (RFC 7636 vector), request bodies,
every response shape from the probe mapped to a picture or an error, the writer, the cloud
prompts, and `PictureEngine.isReady`.

## Before an App Store release

Not needed for personal or TestFlight testing: add `PrivacyInfo.xcprivacy` and update the App
Store privacy label (data sent to a third party for app functionality).
