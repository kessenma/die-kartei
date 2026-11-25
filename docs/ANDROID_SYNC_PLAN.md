# Android sync: plan

How the Android app gets something like iCloud Sync, in three steps. The merge engine already
builds for Android (`Services/Sync/Core`: `SyncMerge`, `SyncRecordLogic`, `SyncCounter`,
`SyncNameUUID`, `FakeSyncServer`), so the work is a store that speaks the iOS record format, a
backup, and a transport. Read [ICLOUD_SYNC.md](ICLOUD_SYNC.md) first; its invariants hold here
too.

## Step 1: a sync-shaped Android store

Goal: the Android app keeps its progress as the same records iOS syncs, so any transport (and
later iPhone ↔ Android) is plumbing.

**Same ids as iOS.** iOS keeps one Wortschatz deck across A1–B1 (generator `goethe-srs`, topic
`DeckStore.wortschatzTopic` = "Goethe Vocabulary"), with ids
`SyncNameUUID.make("deck", "goethe-srs", topic)` and
`SyncSingletonDecks.cardID(deckID:germanWord:)` (exact word, never lowercased). Android keys
cards as `A1:word` today: switch to the iOS card id, keep the level only as a filter, and
migrate saved progress once (a word in two levels becomes one card, the later review wins).

**App-side moves (no behaviour change on iOS), so both platforms share one definition:**
- `SavedCardCodec.spec` and `scheduleFields` → `Services/Sync/Core/SyncSpecs.swift`;
  `SavedCardCodec` reads them from there.
- `SyncSingletonDecks.deckID` / `cardID` → the same Core file (they're pure; `isSingleton`
  stays with SwiftData).
- The replica id: iOS keeps it in the Keychain (`SyncRegistry.replicaID()`, this-device-only),
  so Android makes its own UUID and keeps it outside the backup (see step 2).

**The store** (`DieKarteiAndroid/Sources/DieKartei/Sync/`):
- One record per reviewed card: `SyncRecordCopies` (`server`, `pending`) plus the flat
  `CardProgress` the UI reads. Unreviewed cards aren't records (the bundle owns them, as on iOS).
- A local change goes through `SyncRecordLogic.noteLocal(known:spec:slot:now:)` with
  `known` built with the same field names as `SavedCardCodec.known` (id, deck, germanWord, …,
  the schedule fields, totalReviews, lapses, firstReviewedAt) and `slot` = this install's
  replica id. That makes the counters per-device PN maps from day one.
- Saved as one JSON file in the app's files directory (UserDefaults is the wrong place for
  ~3,000 records). Write-then-rename so a crash can't leave half a file.
- Later kinds, same pattern: `StudyDay` (streak/XP; Android doesn't track it yet), `QuizResult`.

**Tests** (DieKarteiCore, runs on the Mac):
- Two replicas review the same card offline and merge through `FakeSyncServer`:
  `totalReviews` sums, the schedule comes whole from the later review, `firstReviewedAt` is
  the min.
- An Android-composed payload decodes through the iOS rules: an iOS unit test feeds an
  Android-made fixture to `SavedCardCodec.update` and checks the card.

Effort: about a day.

## Step 2: Android Auto Backup

Goal: a new or reset phone gets its progress back. Backup and restore only, not live sync.

- `AndroidManifest.xml`: `android:allowBackup="true"` and `android:dataExtractionRules` (Android
  12+) plus `fullBackupContent` (older) that include the store file and shared prefs and leave
  out caches.
- **Leave the replica id out of the backup** (keep it in `noBackupFilesDir`). A restored phone
  must make a new id; two devices sharing one would lose counts under pointwise max. The
  restored records still carry their `pending`/`server` copies, so the old slots stay put
  (ICLOUD_SYNC.md invariant 2).
- Test on the emulator: `adb shell bmgr backupnow com.kessenma.diekartei`, uninstall,
  reinstall, `adb shell bmgr restore`; progress is back and the replica id is new.

Effort: an hour or two. The 25 MB backup limit is far above what this stores.

## Step 3: live sync through Google Drive's app folder

Goal: Android ↔ Android sync with no server of ours, the way iCloud works on iOS. Data lives in
the learner's own Drive (`appDataFolder`, hidden from them, deleted with the app's access).

**Layout: each device writes only its own file.**
- `appDataFolder/kartei-<replicaID>.json`: that device's current copy of every record it holds
  (state-based; tombstones for deletes). Split per kind (`kartei-<replica>-SavedCard.json`) if
  it outgrows a few MB, gzip later.
- A pass: list the folder (Drive `changes.list` with a saved page token), download the other
  devices' files that changed, merge each record into the local copy with `SyncMerge.merge` /
  `SyncRecordLogic.receive`, then upload this device's file if anything is pending
  (`didSave` on success).
- No device ever overwrites another's file, so there are no write conflicts to resolve. The
  merge rules are commutative and idempotent, so reading files in any order, or twice, gives
  the same result. That's why we don't need CKSyncEngine's change tags.

**Code split:**
- Drive REST calls (list, download, upload) in shared Swift with `URLSession`, so iOS could use
  them later.
- Sign-in only in Kotlin: a small transpiled module like `GermanVoice`, using Google Identity
  Services' `AuthorizationClient` for the `drive.appdata` scope, handing the access token to
  Swift.
- A settings row on Android: Google account, last sync, "Sync now", "Remove synced data".

**Tests:**
- A fake Drive (in-memory files) in DieKarteiCore: three replicas doing random reviews and
  passes in random order converge, and counters conserve (the property the iOS randomized sync
  tests check).
- Then two emulators signed into the same test Google account.

**Needs Kyle:**
- A Google Cloud project with the Drive API on, an OAuth consent screen, and an Android OAuth
  client for package `com.kessenma.diekartei` plus the signing certificate's SHA-1 (debug key
  first, release key before shipping).
- Check how Google classifies `drive.appdata` for verification before a public release.

Effort: 2–4 days after the Google setup.

## Later: iPhone ↔ Android

Not part of steps 1–3, but step 1 keeps it open. Two routes:
- **CloudKit Web Services from Android:** iCloud stays the one source of truth; the learner signs
  in with their Apple Account once on Android. The REST zone-changes and record-modify calls map
  onto `SyncTransport` (record change tag as the stamp). Confirm Apple's current support for
  private-database web access first.
- **The Drive transport on iOS as well:** reuses step 3's Swift REST code; needs a Google
  sign-in on iOS.

## Order of work

0. Merge this branch's `german-ai-flashcards/` moves into main, so the shared-file split doesn't
   drift.
1. Step 1 (store + Core moves + tests), then push.
2. Step 2 (backup), verified on the emulator.
3. Kyle sets up the Google Cloud project and OAuth client; then step 3.
