# Mac pictures: big drawing models on the Mac, and "Draw on my Mac"

On iPhone and iPad, pictures come from Core ML Stable Diffusion: BK-SDM Tiny or SD 2.1, at 512 px.
The Mac build adds two much better models, and lets a phone send a deck or story to the Mac to be
drawn there. Everything runs on the learner's own devices; requests and pictures travel through
the existing iCloud sync. There is no server.

Branch `mac-pictures` (worktree `../german-ai-flashcards-macpics`), off `macos`. Every edit to a
file that existed before carries the grep tag `MAC-PICTURES`.

## What the learner gets

- **On a Mac:** Settings ▸ Image generation lists **Z-Image Turbo** (best pictures) and
  **FLUX.2 klein** (about three times faster) next to the Core ML models. Download one, pick it, and
  every deck and story picture on that Mac uses it.
- **On a phone or iPad**, with iCloud Sync on and a Mac seen in the device list:
  - A deck screen shows **Draw on my Mac** or **Redraw on my Mac**.
  - A story with pictures has **Redraw Pictures on My Mac** in its toolbar.
  - The order says which style the phone wants. While it waits, the row shows "Waiting for your
    Mac" and offers Cancel.
- **The next time the Mac app opens**, a banner says "2 decks from your iPhone are waiting for
  pictures · Draw Now". A notification is posted too if the app isn't in front. Draw Now works
  through every order. The pictures sync back, and the phone shows them on the open card without
  reopening it. When the app is in the background, it posts "Your Mac drew the pictures".

Decisions made with Kyle (2026-10-02):
- Both models; the learner picks.
- Notify, then draw on tap. Nothing draws on its own.
- No login item, so the Mac only notices orders while the app is open.
- iOS keeps Core ML only.

## The engine

`KarteiDiffusion/` is a local Swift package at the repo root. It is a trimmed copy of turbo-mlx's
native engine (MIT): Z-Image Turbo and FLUX.2 klein 4B on MLX, with its own BPE tokenizer.
`KarteiDiffusion/VENDORED.md` has the upstream commit, what's kept, and every local change.

- **One MLX for the whole app.** The package builds against mlx-swift 0.31.x, the version
  mlx-swift-lm 3.31 pins for the tutors. turbo-mlx asks for 0.32, but the APIs it uses already
  exist in 0.31.6. Don't bump mlx-swift for this.
- **Mac only.** The product is linked with a macOS platform filter
  (`platformFilters = (macos, )`). The iOS build never compiles it; it shows up only when packages
  are resolved. All app code that uses it sits inside `#if os(macOS)`.
- **Checked against mflux.** `kartei-diffusion-probe` renders the bake-off prompts, and
  `training/imagegen/bakeoff/parity.py` compares the results with mflux 0.20 on the same seed:
  - Z-Image: 54 / 39 / 30 dB.
  - klein: 35 / 30 dB.
  - The 30 dB images are the same picture by eye.
- **Weights** are mflux checkpoints from `mflux-community`, both Apache 2.0:
  - `z-image-turbo-mflux-q4`: 5.9 GB.
  - `flux2-klein-4b-mflux-q4`: 4.6 GB.

  They download through the normal `ResumableModelDownloader` path, which uses a background
  URLSession (the bytes show up under `nsurlsessiond`, not the app).

### How it plugs in

- `ImageGenModel` has two more cases with `engine == .mlx`.
  - Its `allCases` lists only what this device can run, so every picker, storage row and orphan
    sweep already does the right thing.
  - The `current` getter falls back to BK-SDM when the stored pick isn't available on this
    device.
- `StoryImageService` hands over to `MacDiffusionService` in four marked places: `loadPipeline`,
  `unloadPipeline`, `generateImage(…saveTo:)` and `stopForMemoryPressure`. The deck and story
  illustrators don't know which engine drew.
- Negative prompts and step counts are ignored for MLX: both models are distilled and draw a fixed
  9 or 4 steps. The quality tier picks the **size** instead (`MacPictureSizing`):

  | Tier | Cards | Story pictures |
  |---|---|---|
  | Fast | 512 | 512 |
  | Balanced | 512 | 768 |
  | Best | 768 | 1024 |

  The style sheet's sample is always 512.
- `StoryImageService.cancelFlag` also stops the MLX run, so `requestStop` needed no change.

### Memory

Measured on an M1 Max with the vendored engine:

| Model | 512 | 768 | 1024 |
|---|---|---|---|
| Z-Image Turbo, prompt reader released | 33 s, 5.6 GB | 64 s, 5.6 GB | 122 s, 5.6 GB |
| Z-Image Turbo, prompt reader resident | 33 s, 7.6 GB | 65 s, 7.6 GB | — |
| FLUX.2 klein, prompt reader released | 13 s, 4.7 GB | 24 s, 7.1 GB | 44 s, 11.0 GB |
| FLUX.2 klein, prompt reader resident | 13 s, 6.3 GB | 24 s, 8.8 GB | 45 s, 12.7 GB |

- **The drawing budget** is `min(Metal's recommendedMaxWorkingSetSize, ¾ RAM) − 2 GB`
  (`MacPictureSizing.budgetMB`). That's about 8.7 GB on a 16 GB Mac and 22 GB on a 32 GB Mac. It is
  separate from `MemoryBudget`'s RAM/2 Mac fallback, which still gates the tutors.
- **A size that doesn't fit steps down.** A model that can't fit 512 isn't offered. That's every
  8 GB Mac; on 16 GB, Z-Image fits every size and klein fits up to 768.
- **The prompt reader** (Qwen3 4B, 2–4 GB) stays loaded only when the budget has room. Otherwise
  it's released after each prompt is encoded and read back from disk for the next picture, about a
  second each time. This is the `releasesPromptReader` local change in VENDORED.md.
- **Z-Image always decodes in tiles.** It costs nothing measurable and keeps 1024 px at the 512 px
  peak.
- **The MLX memory limit:** MemorySaver caps MLX at the tutors' budget. A drawing run raises the
  cap to the drawing budget, and `unload` restores it with `applyAllocatorLimits(for: nil)`.
- **Memory warnings:** a Mac `.warning` during a run only clears MLX's cache and stops previews.
  Only `.critical` stops the run (`MacMemoryPressure.lastEventWasCritical`).
- **One heavy model at a time:** every path still unloads the tutor first, and `isBusy` blocks a
  tutor from loading mid-run.

## "Draw on my Mac": the hand-off

### Data

`SavedDeck` and `StudyStory` each get two JSON fields, `macPictureRequestData` and
`macPictureResultData`. Both are additive defaulted columns, synced through their codecs as
`macPictureRequest` and `macPictureResult` with plain LWW. No CloudKit schema change is needed:
it's still one `KarteiItem` with a JSON payload.

`MacPictureOrder` owns the rules:

- `Request` holds `id`, `requestedAt`, `styleRaw`/`detailRaw` (learner prefs don't sync, so the
  order carries its own), `redrawAll`, `cardCount` and `fromDevice`.
- `Result` holds `settles` (the request id), `outcome`, `drawn`, `finishedAt` and `byDevice`.
- **Pending ⇔ the result doesn't name the request's id.** The phone writes only the request. The
  Mac, or a cancel, writes only the result. So a merge can't lose an order:
  - Re-requesting while the Mac settles the old order writes a new id, which is still pending.
  - Cancelling while the Mac settles writes the same field, but both answers name the same id.
  - No clocks are compared.
- Outcomes:
  - `drawn` or `partial`.
  - `stopped`: a redraw that was stopped. A fill-in that was stopped stays pending, so the next
    Draw Now finishes it.
  - `cancelled`, `nothingToDraw`, `unsupported` (deleted cards, a Wortschatz deck).
- **The phone knows a Mac can draw** from the Device heartbeat's `macPictureModels` field (the
  downloaded MLX models), read through `SyncPeer.macPictureModels`. Phones never write the field.

### Lifecycle

1. **Phone:** `MacPictureHandoff.order` writes the request, saves, and syncs.
2. **Mac:** `MacPictureInbox.refresh` runs at launch, on every activation, and on remote
   SavedDeck/StudyStory changes (`SyncManager.observeRemoteChanges`, the new multi-listener next
   to `onRemoteChanges`). It lists pending orders from other devices, oldest first. New ones raise
   the banner, plus a notification when `!NSApp.isActive`.
3. **Draw Now:**
   - Picks the learner's MLX model, or the best one downloaded (`ImageGenModel.runOverride`).
   - Holds off idle sleep.
   - Runs each order:
     - **Decks** go through the unchanged `DeckIllustrationService.illustrate`, with the order's
       style (`CardImageStyle/CardImageDetail.runOverride`).
     - **Stories** go through `MacStoryRedrawer`: each saved `StoryImageRecord.prompt`, the
       story-id seed, a **new file name** per picture, and the old file deleted after the swap.
   - Settles each order.
   - If the phone saw more cards than have synced, it waits up to 10 minutes for the rest.
4. **Pictures sync back** as files (`FileSyncDocument`, CardImages/ and StoryImages/).
   - `FileSyncDocument.apply` now posts `.syncedFileLanded`.
   - `FlashCardView` and `StoryIllustrationView` reload when their file arrives after the record
     that names it.
   - `StoryDetailView`'s Umfluss cache is keyed on file names.
5. **Phone:** `MacPictureHandoffWatcher` posts "Your Mac drew the pictures" once per answered
   order, while backgrounded.

### Limits

- **No server, no login item.** A Mac whose app is closed notices orders the next time it opens.
  CloudKit can't reliably wake a closed Mac app.
- **Two Macs** could both draw one order (no claim field yet).
- **Stories need pictures to redraw.** A story drawn without pictures has no prompts. Drawing it
  fresh needs the tutor's scene pass, which isn't wired.
- **Wortschatz decks are excluded:** their cards never take content from a payload.

## Debug launch arguments (DEBUG only)

| Argument | Does |
|---|---|
| `-macPictures.debugModel zimage\|klein` | Selects that model (Mac). |
| `-macPictures.debugDownload 1` | Downloads the selected model if it's missing. |
| `-macPictures.debugFakeOrder 1` | An order "from iPhone" on a dedicated three-card deck, „Küche · Mac-Bilder test“. Never one of the learner's decks. |
| `-macPictures.debugFakeOrderDelay 20` | The same, 20 s after launch; switch apps to see the notification. |
| `-macPictures.debugFakeStoryOrder 1` | The same for a two-picture test story, „Die Taube · Mac-Bilder test“. |
| `-macPictures.debugDrawNow 1` | Then draws, and prints `[macPictures.verify]` lines. |
| `-macPictures.debugCleanUp 1` | Deletes the test deck and story and their pictures. |
| `-macPictures.debugFakeMac 1` | iOS: shows the phone row and story button without a real Mac peer. |

Sync is off in Debug by default, so none of this reaches iCloud. Launch the built binary from a
shell to read the verify lines, for example:

```
"…/Die Kartei.app/Contents/MacOS/Die Kartei" -macPictures.debugModel klein \
  -macPictures.debugDownload 1 -macPictures.debugFakeOrder 1 -macPictures.debugDrawNow 1
```

## Verification

Done on 2026-10-03 (M1 Max, 32 GB):

- **Builds:** Mac Debug and iOS simulator are green. The iOS build log names KarteiDiffusion only
  when resolving packages.
- **Unit tests:** `german-ai-flashcardsTests/MacPictureTests.swift`, 14 tests. They cover the
  pending rule, the real `SyncMerge` on re-request-vs-settle and cancel-vs-settle, the
  sizing/budget table for 8/16/24/32 GB Macs, iOS never listing a Mac model, and renders of the
  phone row's three states.
- **Package test:** `KarteiDiffusion/Tests`, tokenizer ids against Hugging Face's.
- **End to end in the Mac app**, through the debug arguments:

  | Model | Download | Order | Result |
  |---|---|---|---|
  | klein | 291 s | 3-card fill-in | drawn in 48 s |
  | Z-Image | 369 s | 3-card redraw-all | drawn in 104 s |
  | Z-Image | (already there) | 2-picture story redraw at 768 px | drawn in 134 s, new file names |

  Every order was answered and every file was on disk. The banner was checked in a window
  capture.

**Not done yet:**
- A two-device run on CloudKit Development (Mac Debug and iPhone Debug with `-sync.enable 1`).
- The phone notification.
- A 16 GB Mac.
- A Gemma tutor chat right after a drawing run (the MLX limit is restored, but unchecked).

## Every touched spot

New files:
- `KarteiDiffusion/`
- `Models/MacPictureOrder.swift`, `Models/MacPictureSizing.swift`
- `Services/MacDiffusionService.swift`, `MacPictureHandoff.swift`, `MacPictureInbox.swift`,
  `MacStoryRedrawer.swift`
- `App/MacPictureInboxBanner.swift`
- `Features/Cards/CardDeck/MacPictureHandoffRow.swift`, `Features/Stories/MacStoryRedrawButton.swift`
- `german-ai-flashcardsTests/MacPictureTests.swift`

Changed files (each marked `MAC-PICTURES`):

| File | Change |
|---|---|
| `german-ai-flashcards.xcodeproj/project.pbxproj` | Local package ref + product dependency + Frameworks build file with `platformFilters = (macos, )` |
| `Models/ImageGenModel.swift` | Two cases, `engine`, filtered `allCases`, `macModels`, `runOverride`, MLX repo/patterns/resources |
| `Models/ImageGenModel+Descriptors.swift` | Copy, logos (SF Symbols), themes for the two models |
| `Models/ImageGenQuality.swift` | MLX caption (sizes + this Mac's timing) |
| `Models/CardImageStyle.swift` | `runOverride` on both style enums |
| `Models/SavedDeck.swift`, `Models/StudyStory.swift` | The two order fields (+ deck accessors) |
| `Services/StoryImageService.swift` | Four `#if os(macOS)` hand-offs |
| `Services/Sync/Codecs/DeckCodecs.swift`, `StoryCodecs.swift` | The order fields + field coverage |
| `Services/Sync/SyncHealth.swift` | Heartbeat `macPictureModels`, `SyncPeer.macPictureModels` |
| `Services/Sync/SyncManager.swift` | `observeRemoteChanges` multi-listener |
| `Services/Sync/SyncDocuments.swift` | `.syncedFileLanded` post + `Notification.Name` |
| `App/MacCompat.swift` | `MacMemoryPressure.lastEventWasCritical` |
| `App/MacSidebarShell.swift` | Banner as a top safe-area inset |
| `App/german_ai_flashcardsApp.swift` | Starts the inbox (Mac) / watcher (iOS); refresh on `.active` |
| `Features/Cards/CardDeck/CardDeckView+Setup.swift` | One line after `illustrateDeckRow` |
| `Features/Cards/FlashCardView.swift`, `Features/Stories/StoryIllustrationView.swift` | Reload when the file lands |
| `Features/Stories/StoryDetailView.swift` | Toolbar button; Umfluss cache keyed on file names |
| `Features/Settings/SourcesView.swift` | Mac-only credit: turbo-mlx (MIT), Z-Image Turbo and FLUX.2 klein (Apache 2.0) |

## Merge map: cloud pictures (uncommitted on main)

Main's working tree holds the cloud-pictures work (OpenRouter Muse / Nano Banana,
`docs/CLOUD_PICTURES.md`). This branch was made from `macos` without it, so the order is: commit
the cloud work on main → merge `macos` → merge `mac-pictures`. These files are changed on both
sides. Main's numbers are from `git diff HEAD` on 2026-10-03.

| File | This branch | Cloud work on main | Expected | How to resolve |
|---|---|---|---|---|
| `Services/StoryImageService.swift` | Inserts at the top of `loadPipeline`, `unloadPipeline`, `stopForMemoryPressure`, the core `generateImage` | Adds `cloudRequests` (~L71) and a loop in `requestStop` (+7/−1) | Separate hunks, should merge clean | Keep both. Cloud's `beginSession(.onDevice)` calls `loadPipeline`, and `PictureSession.draw(.onDevice)` calls `generateImage(…saveTo:…)`, so the Mac engine is reached with no extra work |
| `Features/Cards/CardDeck/CardDeckView+Setup.swift` | One line after `illustrateDeckRow` (L52) | Run-report banner at the top (L27), `PictureEngine.isReady` gate (L108), caption (L141) | Separate hunks | Keep both. Our row stays outside the `PictureEngine.isReady` check on purpose |
| `Features/Stories/StoryDetailView.swift` | Toolbar item (~L112), Umfluss task id (~L180) | Run-report banner (~L236) | Separate hunks | Keep both |
| `german-ai-flashcards.xcodeproj/project.pbxproj` | 6 package objects (IDs `8AD1F001…`) | Release blocks reformatted, `CURRENT_PROJECT_VERSION` 5→6 | Possible conflict in the Release blocks only | Take main's Release blocks, keep our package objects (or re-add with Xcode ▸ Add Local Package, macOS filter) |
| `Resources/whats_new.json` | One bullet in `unreleased` | Its own `unreleased` bullets | Certain | One `unreleased` list holding all bullets; run `python3 scripts/whats_new.py check` |
| `CLAUDE.md` | Pointer line to this doc | Two adjacent edits (CLOUD_PICTURES pointer) | Likely | Keep every line |
| `docs/ICLOUD_SYNC.md` | Order fields + heartbeat note | A section (+26) | Probably separate hunks | Keep both |

After the merge:
- On a Mac, `PictureSource.onDevice` means the MLX models. Its label ("On this phone") should
  read `ThisDevice.name`.
- Inbox runs should pin the source to on-device: an order asks for the Mac's model, not
  OpenRouter.
- Cloud shrinks pictures to `PictureRequest.maxPixel` (512 cards, 768 stories) before saving,
  because every file syncs. MLX pictures at Best are 768 / 1024; decide whether to shrink them the
  same way.
- `PictureRequest.cloudPrompt` (plain English) suits a model that reads prompts with a language
  model. Try it for the MLX models against the CLIP-style `sdPrompt` on the bake-off prompts.

## Follow-ups

- Encode a whole deck's prompts first and release the reader once (`encode` / `promptsEncoded`),
  instead of once per card on tight Macs.
- HEIC or JPEG for synced card pictures (about 4× smaller than PNG).
- A claim field so two Macs can't draw the same order.
- Mirror the weights to `kessenma/` and pin revisions (the downloader supports `revision`;
  `isDownloaded` checks `refs/main`).
- Longer scene prompts for the MLX models (no 77-token CLIP limit).
- An anime style as a LoRA: the engine supports LoRA upstream but it isn't vendored. Candidate data
  is neonforestmist's Apache-2.0 storybook-anime set (GPT-generated; check the provenance before
  shipping).
