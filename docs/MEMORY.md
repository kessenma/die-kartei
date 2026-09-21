# Memory — how the app stays inside its budget

Die Kartei runs multi-gigabyte language models on phones. iOS kills an app that crosses its
per-process memory limit ("jetsam"), and that limit is far below physical RAM even with the
`com.apple.developer.kernel.increased-memory-limit` entitlement the app ships. This document is
the map of everything that keeps the app under that line, and how to see what it's holding.

## The budget

| Device | App budget (approx.) | E4B ordinary peak | Left for everything else |
|---|---|---|---|
| iPhone 17 Pro, 12 GB | ~7–8 GB | 4.33 GB | ~3 GB |
| iPad, 8 GB | ~4.5–5.5 GB | 4.33 GB | **~0.2–1 GB** |

(E4B: 4.20 GB weights, 4.33 GB on an ordinary turn, 4.99 GB under a very long context —
`MLXModel+Descriptors.swift`, `measuredPeakMB`.)

On the iPad the hero model alone is nearly the whole budget. Every crash seen there was the app
briefly holding **two** heavy things — a second model, the drawing model beside a tutor, a second
set of decoded pictures — or a leak that had quietly eaten the headroom over a session.

Read the real number for a device from the memory log: the `Loading …` row's detail names the
budget (`MemoryBudget.totalMB`, which is `os_proc_available_memory()` + `phys_footprint`).

## The invariant: one heavy resident at a time

The language model and the Stable Diffusion pipeline are never in memory together, and the app
never holds two language models. Enforced in both directions:

- **Tutor before pictures.** Every illustrate path (`StoryStudyService.illustrate`,
  `DeckIllustrationService.illustrate` / `illustrateDraft`, the style sample in
  `CardImageStyleSheet`) calls `mlxService.unloadModel()` before `StoryImageService.loadPipeline()`,
  with `defer { unloadPipeline() }`.
- **No tutor while pictures are being drawn.** `MLXGenerationService.loadModel` refuses (with a
  `loadError` the caller shows) while `StoryImageService.shared.isBusy`.
- **No second tutor mid-generation.** `loadModel` refuses a *different* model while
  `activeGenerations > 0`. Every generation path binds the container to a local, so nil-ing the
  property frees nothing until the run ends — a second load would have stacked.
- **The live budget gates every load.** `loadModel` refuses a model that `MemoryBudget.isOverBudget`
  unless `MemorySaver.allowsOversizedModels` ("Use it anyway" in Settings ▸ Model & Downloads).
  Seventeen call sites auto-load without asking; the gate lives below all of them.
- **MLX's allocator is always capped.** `MemorySaver.applyAllocatorLimits` sets `Memory.memoryLimit`
  to `totalMB − reserveMB` on every load and unload. MLX's own default is 1.5× the GPU's
  recommended working set, which on iOS is above the jetsam line.
- **Never touch `Memory.*` before `MemorySaver.mlxRuntimeReady`.** Any MLX memory call — a
  reading, a cache clear, a limit — constructs MLX's Metal device on first use, which aborts the
  process in the simulator (no Metal) and is wasted work before a model has loaded. `loadModel`
  opens the gate on a real device; `releaseCaches`, `applyAllocatorLimits` and
  `MemoryReading.now()` are no-ops / zero before that. Route new MLX calls through those helpers.

## Who owns what

| Piece | Owns |
|---|---|
| `MemoryBudget` (`Models/`) | The live numbers: footprint, available, total, `fits` / `isOverBudget` / `hasSlimHeadroom`, the pressure floors. |
| `MemorySaver` (`Services/MemorySaver.swift`) | The governors for a model that barely fits: token cap, KV-cache cap and quantization, allocator limits. Auto-active when over budget or slim headroom. |
| `MemoryPressureMonitor` (same file) | System memory warnings → `MLXGenerationService.releaseMemory(.pressure)` (drops the weights) and `StoryImageService.stopForMemoryPressure()` (winds down a picture run). Mid-run sampling → the banner. |
| `MLXGenerationService.releaseMemory(reason:)` | Background eviction on slim-headroom devices; `evictedModel` lets the owning screen reload. Never mid-load or mid-generation. |
| `MemoryDiagnostics` (`Services/`) | Readings, the breakdown registry, the screen context, the session marker, the heartbeat, the text export. |
| `MemoryEventStore` (`Services/`) | The on-disk log (`Application Support/Diagnostics/memory-events.json`, cap 600, chatty kinds trimmed first). |
| `MetricKitSubscriber` (`Services/`) | iOS's own exit counts and crash diagnostics, filed into the log. |
| `MemorySettingsView` (`Features/Settings/`) | Settings ▸ Speicher: live rows, the logging toggle, the log with Copy / Share / Clear, the live readout overlay (testing builds). |

## Settings ▸ Speicher

- **Jetzt · Right now** — footprint, free, budget, then the breakdown: every heavy owner
  registered with `MemoryDiagnostics.register` (tutor via `Memory.activeMemory`, drawing model,
  story pictures, generation previews), MLX's reuse cache, and "Everything else".
- **Log when memory runs short** (`memoryLog.verbose`) — default on for DEBUG and TestFlight,
  off for the App Store. Gates the opt-in kinds: pressure samples, model and pipeline loads and
  unloads, evictions, and a 60 s heartbeat while the app is in front. Crashes, memory warnings,
  interrupted loads and app updates are always recorded.
- **Abstürze & Ereignisse** — newest first; tap for the breakdown. Copy = the whole log as text
  (`MemoryDiagnostics.exportText`); Share = JSON (`MemoryLogExport`, schema
  `die-kartei.memory-log`); Clear asks first.
- The memory pressure banner links here ("See what's using memory") via `SettingsRoute.memory`.

### How a crash is noticed

1. **Session marker** (`Diagnostics/session.json`): written at launch, refreshed on every recorded
   event and scene change, closed in `applicationWillTerminate`. Still open at the next launch →
   an `unexpectedTermination` row carrying the last reading, breakdown and screen context.
   Labelled by the app state it was last seen in: *Closed while in use* (out of memory or a crash)
   vs *Closed in the background* (iOS reclaimed it, or the app switcher — normal). A changed app or
   OS version becomes `appUpdated` instead.
2. **MetricKit**: `applicationExitMetrics` → `systemExitCounts` (foreground memory-limit exits are
   the number that matters); `crashDiagnostics` → `crashReport` with reason, signal and the first
   frames. Arrives at most daily. In DEBUG: Xcode ▸ Debug ▸ Simulate MetricKit Payload.

### Screen context

Heavy screens name themselves with `.memoryContext("…")`: the story reader (with its layout),
the read-aloud player, story generation, card creation, chat, deck study. Every event records the
context in force, so a termination row says where the app was.

## Measuring on a device

Instruments (Allocations + Leaks + VM Tracker) on the iPad, four scripted scenarios:

1. Open an illustrated story → toggle Kompakt / Ganz / Umfluss five times fast.
2. Generate a deck with E4B.
3. Illustrate a deck.
4. Open a chat → background → foreground.

Note peak `phys_footprint` per scenario. Or skip Instruments: turn on the live readout in
Settings ▸ Speicher (testing builds) and watch the corner while running the same four.

**Numbers to fill in** (first pass shipped 2026-09-17, not yet measured on the iPad):

| Scenario | Before | After |
|---|---|---|
| Layout toggle with E4B loaded | — | — |
| Deck generation | — | — |
| Deck illustration | — | — |
| Chat background/foreground | — | — |

## What the first pass fixed (2026-09-17)

- `StoryImageCache.load` filed bitmaps after a purge (a detached decode ignores cancellation),
  and rapid layout toggling stacked unbounded full-set decodes. Now: a generation counter,
  cancellation checks, one decode in flight.
- `StoryIllustrationView` keyed its decode on the file only, so the header kept a banner-size
  decode when the fit changed; and `.id(layout)` rebuilt every paragraph and picture on any
  change — now only crossing into or out of Umfluss rebuilds.
- Per-render SwiftData fetches and JSON decodes in the reader and the read-aloud player
  (`savedWords`, `lookedUpWords`, `story.images`) are cached in `@State`.
- `StoryStudyService` kept up to four full-size preview bitmaps until the *next* run.
- A repeating `Timer` in the flashcard generating animation leaked on every run.
- `StoryBackgroundGenerator.pendingJobs` could hold a job's closure (story service, model context,
  view state) forever; a 30 s grace period now runs an unlaunched job inline.
- `generateCards` had no idle watchdog, so a token-less stall pinned `activeGenerations` and
  blocked eviction permanently. It now shares the chat path's watchdog.
- `WordInspectorModel` keeps its lookup task and tears it down with the screen.
- `GenerationCoordinator.generateVocab` guards re-entry (a double tap ran two batches).
- The live-preview decode now skips at *elevated* pressure, not only critical.

## Second pass (same day)

- **Card pictures decode through ImageIO** like story pictures: `DownsampledImage`
  (`Services/ImageDecoding.swift`) is the one decoder both stores call.
  `DraftCardThumbnail` now decodes at 48 pt × scale off the main actor and releases on
  disappear; `FlashCardView` decodes off the main actor and releases on disappear. The full-screen
  viewer deliberately shares the card's bitmap — the card already holds the file's full 512 px,
  so a second decode would only cost more.
- **SwiftData**: `CardDeckView+Pause.fetchDeck` is a registered-object lookup
  (`modelContext.model(for:)`) instead of fetch-everything-then-filter. `StudyStory`'s blob
  accessors cache their decoded arrays, keyed on the bytes they came from, so a stale cache is
  impossible by construction and every reader of `questions` / `glossary` / `images` / `lookups`
  pays for one decode per change rather than one per render.

## Still deferred

- The style-sheet sample picture (`CardImageStyleSheet`) still decodes with `UIImage(contentsOfFile:)`:
  one image, shown at the file's own size, so there is nothing to downsample.
- `ConversationEngine`'s unstructured tasks are left running on purpose: cancelling a reply
  mid-stream strands the turn (the exact defect `ChatTurnNormalizer` exists for). The engine
  lives until the reply lands or the stall watchdog fires, which is bounded.
- Home/Progress `@Query` fan-out (CPU and row cost, not the multi-hundred-MB class).
- RealityKit's internal asset cache is not purgeable from the app.
- `minimumRAMGB` tiers, once the iPad's real budget is known: E4B is offered to every 8 GB device
  today, and an 8 GB iPad is at the very edge.
