# Die Kartei — repo orientation

SwiftUI iOS app for learning German with on-device AI tutors. Solo developer; in-app copy is
German for identity words and headings, plain English for explanation.

## Other instruction files

- `training/CLAUDE.md` — the ML fine-tune subproject (data rounds, eval suites, GPU-pod lessons).
  Its rules apply under `training/` only.
- `docs/DEPLOY_SETUP.md` — how builds reach TestFlight and the App Store (`scripts/deploy.py`).
- `AppStore/README.md` — the product page: description and keywords (`scripts/metadata.py`),
  screenshots (`scripts/screenshots.py`), and where What's New fits.
- `docs/GAMIFICATION.md` — XP, pyramid, placement quiz, streaks; debug launch arguments live here.
- `docs/LEARNER_MEMORY.md` — the persistent learner profile and coaching memory.
- `docs/SHORT_STORIES.md` — story mode and on-device illustrations.
- `docs/CLOUD_PICTURES.md` — cloud pictures on the learner's own OpenRouter account (Muse Image,
  Nano Banana): sign-in, the picture-source seam, error policy, invariants, the probe, debug args.
- `docs/JOB_PREP.md` — job-posting capture and interview prep.
- `docs/CLASS_NOTES.md` — Deutschkurs: courses, class entries, handouts, homework, the per-course deck.
- `docs/DOCUMENT_DECKS.md` — flashcards from a document: the vocab-sheet pairer, phrase picking, decks on a course.
- `docs/WORTSCHATZ.md` — the Goethe word box: merged index, one SRS deck, sessions, status, debug args.
- `docs/KASUS.md` — the Grammatik case path: units, story format and targets, validator, exercises and right/wrong feedback, rich-text markup, Verlauf, GrammarRoute, coach rules, adding a story, tutor-written stories (planner, gate, fallback, Kasus Lab, Mac probe), tests, debug args.
- `docs/PREPOSITION_3D.md` — the 3D preposition scenes and die Figur.
- `docs/VERB_PREPOSITIONS.md` — Verben mit Präpositionen: 42 verb pairs in the preposition hub's
  second track (cards, drills, Die Falle), their data, the baked 3D scenes, and what is still open.
- `docs/theme-upgrade.md` — the AppTheme system and its invariants.
- `docs/MEMORY.md` — the memory budget, the one-heavy-resident invariant, Settings ▸ Speicher
  (crash/memory log), and how to measure on a device.
- `docs/ICLOUD_SYNC.md` — iCloud Sync on CKSyncEngine: why not SwiftData mirroring, the invariants
  (per-device counters, canonical ids, `cloudKitDatabase: .none`), merge rules, Development vs
  Production, the one-time schema deploy, and models being per device (`ModelHandoff`). Adding a field to a
  synced model means adding it to its codec.
- `docs/MACOS.md` — the Mac app: the same target compiled for macOS, `App/MacCompat.swift` stand-ins,
  Mac twins of the UIKit-wrapped views, what's hidden or different on the Mac. Wrap every
  `import UIKit` in `#if canImport(UIKit)`, and keep the iOS build green.
- `docs/MAC_PICTURES.md` — Mac-only picture models (Z-Image Turbo, FLUX.2 klein via the vendored
  `KarteiDiffusion` package; keep mlx-swift on the tutors' 0.31 pin) and "Draw on my Mac" (a phone
  orders pictures through iCloud sync, the Mac draws them). Has the merge map for cloud pictures.
- `docs/FUTURE_FEATURES.md` — ideas not yet built.

## What's New maintenance

Do this whenever you ship a change a learner would notice. The app shows release notes from
`german-ai-flashcards/Resources/whats_new.json` (Settings ▸ About ▸ What's New, and once at launch
after an update). Deploy stamps the file; you only ever add bullets.

**Hard cap: 4000 characters per version.** App Store Connect rejects more, and deploy stops.
Until a version is live on the App Store, every TestFlight build's `unreleased` bullets merge into
it, so all of them share one 4000-char budget. Keep a version to about 15 bullets (~2500 chars)
so later builds still fit. `python3 scripts/whats_new.py render <version>` prints the shipped text.

1. Open `german-ai-flashcards/Resources/whats_new.json`. If the first entry is not
   `"version": "unreleased"`, add one at the top: `{ "version": "unreleased", "highlights": [] }`.
2. One highlight per feature, not per change:
   `{ "title": "…", "detail": "…", "symbol": "<sf symbol>" }`
   - First look for a bullet on the same feature in `unreleased` and the newest version. A
     follow-up, fix or polish is not a new bullet: fold it into the `unreleased` bullet's
     `detail`, or skip it if the feature's bullet already has a version.
   - Learner-facing, one sentence of at most ~30 words, no jargon and no file names. Say what
     they can do now.
   - Titles read like the app's headings: a German identity word with its English, e.g.
     `"Lernpyramide · Learner pyramid"`, then plain English `detail`.
   - `detail` and `symbol` are optional. A symbol must be a real SF Symbol name.
3. Never write `version` or `date`, and never edit an entry that already has a version unless
   the user asks you to trim one that isn't on the App Store yet. `scripts/deploy.py` renames
   `unreleased` to the shipping version, merges later bullets into it across TestFlight builds,
   and sends the same text to TestFlight and the App Store.
4. Run `python3 scripts/whats_new.py check` before you finish. It fails when a version is over
   the cap, and warns when `unreleased` plus the newest version would be. Either one means
   consolidate, not add; tell the user if trimming needs an already-versioned entry.

Simulator: `-whatsNew.debugForce 1` raises the launch sheet (DEBUG only; one presenting launch
argument per launch).
