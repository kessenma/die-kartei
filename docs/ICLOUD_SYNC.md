# iCloud Sync

A learner's progress and content follow them across their own iPhone and iPad. Everything is
stored in their **private CloudKit database**: no server of ours, and no cost to us (it counts
against their iCloud storage). There's no sign-in; sync uses the Apple Account the device is
signed into. Settings ▸ Account ▸ iCloud Sync shows the status.

## Why CKSyncEngine, not SwiftData's built-in CloudKit mirroring

`ModelConfiguration(cloudKitDatabase: .automatic)` looks like one line, but it doesn't fit this app:

- **Last writer wins, per whole record.** StudyDay (the streak, XP and daily-goal source), the
  per-word stats and the SRS fields are updated in place with `+=`. Two devices studying the same
  day would overwrite each other's reviews and XP.
- **Fetch-or-create singletons duplicate.** Each device creates its own LearnerProfile, today's
  StudyDay, the 2,825-card Wortschatz deck and the stat rows, and readers pick one with `.first`.
- **Schema rules.** 180 properties and 5 relationships break mirroring's optional/default rules.
  Once in Production, its CloudKit schema is add-only, with a manual deploy for every change.
- **It wipes local data** when the learner signs out of iCloud (Apple engineer, Dec 2025).

So `App/german_ai_flashcardsApp.swift` passes **`cloudKitDatabase: .none`**. That line is
load-bearing: the default `.automatic` would turn mirroring on as soon as the iCloud entitlement
exists, the store would fail to open, and the app would crash.

The same goes for **every** container: previews, tests, debug harnesses. The app has the
entitlement, so a plain `ModelConfiguration(isStoredInMemoryOnly: true)` or
`.modelContainer(for:inMemory:)` fails to load (the grammar tests did, right after the merge). Use
`ModelContainer.inMemory([...])` / `.inMemoryModelContainer(for: [...])` (`App/InMemoryStore.swift`),
or pass `cloudKitDatabase: .none` yourself.

## How it works

```
SwiftData store (cloudKitDatabase: .none)
  │ SwiftData history, author == nil only        UserDefaults + JSON files + pictures
  ▼                                              ▼ (compared every pass)
SyncChangeTracker ── SyncRecordState.needsUpload ◄── SyncDocuments
  ▼
CloudKitSyncTransport = CKSyncEngine (zone "Kartei", one record type "KarteiItem")
  └ fetched / conflict ──► SyncMerge (KarteiSyncCore) ──► SyncApplier (mainContext, author "sync")
```

| Piece | File |
|---|---|
| Pure merge engine (JSON payloads, PN counters, rules, UUIDv5, digest, fake server) | `Services/Sync/Core/` (also `KarteiSyncCore/`, see below) |
| One codec per `@Model` (fields ⇄ payload, merge rules) | `Services/Sync/Codecs/` |
| Non-SwiftData records: Progress, Journey, PlacementAttempts, File | `Services/Sync/SyncDocuments.swift` |
| History → "must upload" | `SyncChangeTracker.swift` |
| Server copies → store | `SyncApplier.swift` |
| Ties them together, Repair, forgetServer | `SyncCoordinator.swift` |
| CKSyncEngine | `CloudKitSyncTransport.swift` |
| On/off, account, zone deletion, lifecycle | `SyncManager.swift` |
| Singleton ids | `SyncCanonicalizer.swift`, `SyncSingletonDecks` in `Codecs/DeckCodecs.swift` |
| Screen | `Features/Settings/ICloudSyncSettingsView.swift` |

- **One generic record type** `KarteiItem` with fields `kind`, `payload` (JSON bytes),
  `payloadAsset` (payloads over 512 KB) and `file` (a picture or handout). Model changes only
  change the JSON, so the Production schema is deployed **once**.
- **Record names** are `<Kind>:<UUID>`. Rows keyed by a natural key (StudyDay by date, stats by
  word) derive the UUID from the key (`SyncRecordName(kind:naturalKey:)`); CloudKit names must be
  ASCII.

## Invariants (don't re-derive these)

1. **Counters are per-device PN maps**, never "last synced value + my delta". Each counter travels
   as `{replica: (p, n)}` merged by pointwise max; the model holds the sum. Anything that forgets
   the server copy (Delete iCloud Data, an account round trip, Debug↔TestFlight) would otherwise
   sum the same history twice. That's the conservation property the randomized tests check.
2. **Pre-sync data** is credited at the first scan to a bootstrap slot:
   - natural-key and canonical rows use the store's UUID, so two devices' histories *sum*, and a
     restored copy of the same store lands in the same slot;
   - random-UUID rows use a shared `pre` slot (*max*), because the only way two devices share a
     random id is a `.kartei` Replace copy.
3. **Sync writes run on the main actor in `mainContext`**: flush the learner's edits, set author
   `"sync"`, apply, save, reset, with no `await` in between (`SyncWriter`). The tracker reads only
   `author == nil` history, which also skips Core Data's `com.apple.coredata.*` migrator.
4. **`needsUpload` is the source of truth.** The history token is saved in the same save as the
   flags it produced; the flag clears only on a successful send; everything owed is re-queued at
   launch and after an account change.
5. **Canonical ids.** The Wortschatz deck, the goethe / past-tense / grammar decks and their cards
   get UUIDv5 ids from (generatorRaw, topic) and (deck, German word), at creation in `DeckStore`
   and once for older rows (`SyncCanonicalizer`). Wortschatz syncs only reviewed cards; the bundle
   rebuilds the rest and owns their word content. LearnerProfile has a fixed record name.
6. **Older builds never clobber newer ones.** A local change is composed on the last copy
   (unknown fields survive); `_b` (breaking generation) above what a build knows is held back.
   Adding fields never needs `_b`.
7. **Never synced:** BatchJob, `pausedProgressData`, device prefs (models, voices, image model,
   memory tier, review throttle, What's New), migration flags, the memory log.
8. **Seeders refuse while sync runs**, and a seeded store refuses to enable sync. `.kartei`
   Replace is hidden while sync runs.

## Merge rules

| Record | Rule |
|---|---|
| StudyDay | every activity count and time bucket is a counter; `lastActivityAt` max; keyed by `yyyy-MM-dd` of `dayStart + 12 h` (safe across time zones) |
| SavedCard | schedule fields as one group from the later `lastReviewedAt`; `totalReviews`/`lapses` counters; `firstReviewedAt` min |
| Stats (matching / article / preposition) | seen/missed and wrong-pick tallies are counters; `firstTryStreak` from the later `lastSeenAt` |
| Round logs, QuizResult, story sessions/attempts, ChatMessage | append-only |
| LearnerProfile | grammar per focus (later `lastSeen`); vocab/slips as sets by id; `sessionCount` counter |
| Content (decks, stories, chats, papers, class notes, job posts, phrases) | field-wise three-way; lookups and saved words as sets; `bestScore` max; `durationSeconds`/`readingSeconds` counters |
| Progress (UserDefaults) | level last-writer-wins; badges earliest date; flags OR; celebrations union |
| Journey | one snapshot per ISO week; milestones deduped by (kind, title) |
| File | path + size + modified date; the bytes go as a CKAsset |

Field rules live in `Core/SyncMerge.swift` (`SyncFieldRule`). Every codec file ends with a
`// Field coverage:` block listing each stored property and where it goes. **Adding a stored
property to a synced model means adding it to its codec**, or it won't travel.

## Development vs. Production

- Xcode builds (simulator or device) talk to CloudKit **Development**; TestFlight and App Store
  builds talk to **Production**. The data never crosses, and the screen shows "Development" in
  DEBUG builds.
- Sync is **off by default in DEBUG** and on in TestFlight/App Store. `-sync.enable 1` and
  `-sync.disabled 1` override one launch.
- A Debug build and a TestFlight build on the same phone see different databases. Switching
  between them is safe (invariant 1), but they don't share data.

## Testing

- `scripts/sync_core_test.sh`: the merge engine, plus randomized 2–3-device simulations over the
  fake server that must converge and conserve every counter, including across zone resets and
  database switches. `KarteiSyncCore/Sources/KarteiSyncCore` is a symlink to
  `german-ai-flashcards/Services/Sync/Core`, so the app and the tests compile the same files. It
  uses Xcode's toolchain (the swiftly one on PATH can't link against the macOS 27 SDK).
- `-sync.debugVerify 1` (DEBUG) syncs two temporary SQLite stores through the fake server with the
  real tracker, applier and coordinator, and prints `[sync.verify]` lines. It covers first sync,
  concurrent study, a zone reset, delete propagation, and both devices building the Wortschatz box
  offline. Documents are left out there: both "devices" share one app's UserDefaults.
- The simulator can't receive CloudKit pushes and its iCloud sign-in is flaky. Test real sync on
  two devices signed into the same Apple Account: Debug builds first, then TestFlight.

## Shipping

Before the **first** TestFlight build with sync:
1. Build to a device once from Xcode (automatic signing registers the iCloud container
   `iCloud.kyle-essenmacher.german-ai-flashcards` and the push capability on the App ID).
2. On that device (signed in to iCloud), launch once with `-sync.debugSeedSchema 1`. It saves one
   record that sets every `KarteiItem` field (`payloadAsset` and `file` otherwise exist only after a
   big payload or a picture was saved), then deletes it; the fields stay in the schema.
3. CloudKit Console ▸ the container ▸ Schema ▸ **Deploy Schema Changes** to Production (or
   `xcrun cktool`). TestFlight uses Production; without this, sync fails there.

The Mac ("Designed for iPad") and visionOS builds share the container, so they become sync devices
too.

## Drift and database switches

- **Heartbeats.** Each device writes a `Device` record: model, app version, last sync, pending and
  stuck counts, and a digest per kind of the server copies it holds. The screen lists them under
  "Your devices" and flags a different app version.
- **Drift check.** Two settled devices with different digests trigger one automatic Repair Sync a
  day; a lasting difference is shown on the screen.
- **Zone fingerprint.** A `Meta` record holds a random id for the zone. A different id, or a full
  fetch that finds none, means a different database: Debug vs TestFlight, a recreated zone, or
  another account. The device then forgets its server copies and sends everything; per-device
  counters keep that from doubling anything.
- **Open screens.** A delete from another device waits while its deck is being studied or its chat
  is open (`SyncInUse`), and a paused session is cleared when the deck's cards change under it.
- **New device.** The onboarding wizard waits up to 10 s for the first fetch and is skipped if the
  learner already onboarded on another device.

## Models are per device

Content syncs; downloads don't. A chat or paper made with the E4B tutor on the Mac arrives on an
iPhone that may hold only E2B, or no tutor at all. Reading never needs a model: transcripts,
reports, saved words, stories and pictures are plain synced data. Only new AI work does.

- **`ModelHandoff` (`Models/ModelHandoff.swift`) picks who continues:** the original if it is on
  disk and fits → the learner's own pick if ready → the best downloaded tutor → Apple Intelligence.
  A tutor chat never drops to an Apple Intelligence pick while a tutor is on disk. When nothing is
  ready it names a download that fits (original, else pick, else the best tutor that fits).
  Chats (`ChatConversation.makeConfig`), papers (`PaperDetailView.followUpModel`) and the report's
  card builder (`ReviewDeckView`) use it; stories, handouts and job posts already had
  `StoryStudyService.followUpModel`, which follows the same idea.
- **Never write the resolved model back.** `modelRaw` syncs, so saving the iPhone's E2B into the
  chat would switch the Mac's copy to a model the Mac may lack, and the two would bounce it back
  and forth. `modelRaw` means "made with"; each device resolves at open time. `ConversationView`
  compares the chat's `modelRaw` with the config's model to show the "Started with … carries on
  from here" notice, plus a "Get <original>" button when the original would fit here.
- Switching tutors mid-chat is safe because a chat holds no model state: the history is plain
  role/content turns cut to a trailing window (`ChatTurnNormalizer`).
- The load prompt says "Download … (~size)" whenever the model isn't on disk yet. It used to say
  "loaded into memory" and then start a multi-GB download.
- Simulator: `-screenshots.debugFill 1 -onboarding.debugTier apple` seeds chats made with E4B
  (not on the sim) and makes Apple Intelligence count as ready, so opening one shows the notice.
  `-screenshots.debugRestore 1` removes the seeded data afterwards.

## Not yet

- Learner preferences (theme, reminders, chat settings) don't sync. The plan is
  NSUbiquitousKeyValueStore with an allowlist, plus a reload path in `MLXModelManager`, which caches
  its settings at launch.
- The same word saved to a story/job/class deck on two devices while both are offline gives two
  cards (the deck itself is one record).
