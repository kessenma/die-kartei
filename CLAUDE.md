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
- `docs/JOB_PREP.md` — job-posting capture and interview prep.
- `docs/CLASS_NOTES.md` — Deutschkurs: courses, class entries, handouts, homework, the per-course deck.
- `docs/DOCUMENT_DECKS.md` — flashcards from a document: the vocab-sheet pairer, phrase picking, decks on a course.
- `docs/WORTSCHATZ.md` — the Goethe word box: merged index, one SRS deck, sessions, status, debug args.
- `docs/PREPOSITION_3D.md` — the 3D preposition scenes and die Figur.
- `docs/theme-upgrade.md` — the AppTheme system and its invariants.
- `docs/MEMORY.md` — the memory budget, the one-heavy-resident invariant, Settings ▸ Speicher
  (crash/memory log), and how to measure on a device.
- `docs/FUTURE_FEATURES.md` — ideas not yet built.

## What's New maintenance

Do this whenever you ship a change a learner would notice. The app shows release notes from
`german-ai-flashcards/Resources/whats_new.json` (Settings ▸ About ▸ What's New, and once at launch
after an update). Deploy stamps the file; you only ever add bullets.

1. Open `german-ai-flashcards/Resources/whats_new.json`. If the first entry is not
   `"version": "unreleased"`, add one at the top: `{ "version": "unreleased", "highlights": [] }`.
2. Append ONE highlight per change to that entry:
   `{ "title": "…", "detail": "…", "symbol": "<sf symbol>" }`
   - Learner-facing, one sentence, no jargon and no file names. Say what they can do now.
   - Titles read like the app's headings: a German identity word with its English, e.g.
     `"Lernpyramide · Learner pyramid"`, then plain English `detail`.
   - `detail` and `symbol` are optional. A symbol must be a real SF Symbol name.
3. Never write `version` or `date`, and never edit an entry that already has a version.
   `scripts/deploy.py` renames `unreleased` to the shipping version, merges later bullets into it
   across TestFlight builds, and sends the same text to TestFlight and the App Store.
4. Run `python3 scripts/whats_new.py check` before you finish.

Simulator: `-whatsNew.debugForce 1` raises the launch sheet (DEBUG only; one presenting launch
argument per launch).
